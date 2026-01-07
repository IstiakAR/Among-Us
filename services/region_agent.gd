extends SceneTree

# Region VM agent (GDScript).
# - Connects to matchmaker over TCP newline JSON.
# - Registers a region + public IP.
# - On alloc_room, picks a free port and spawns a dedicated room server process:
#     Networking.x86_64 --headless --dedicated --port=PORT
#
# Run (using a Godot executable):
#   godot4 --headless --script res://services_gd/region_agent.gd -- \
#     --matchmaker-ip=127.0.0.1 --matchmaker-port=5000 \
#     --region=na --public-ip=127.0.0.1 \
#     --room-port-min=8910 --room-port-max=8920 \
#     --server-binary=./Networking.x86_64

class Room:
	var port: int
	var pid: int

	func _init(p_port: int, p_pid: int) -> void:
		port = p_port
		pid = p_pid

var _matchmaker_ip: String = "127.0.0.1"
var _matchmaker_port: int = 5000
var _region: String = "na"
var _public_ip: String = "127.0.0.1"
var _room_port_min: int = 8910
var _room_port_max: int = 8920
var _server_binary: String = "./Networking.x86_64"

var _peer := StreamPeerTCP.new()
var _buffer := PackedByteArray()

var _free_ports: Array[int] = []
var _rooms: Dictionary = {} # int(port) -> Room

var _reap_accum: float = 0.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	_parse_args(args)
	for p in range(_room_port_min, _room_port_max + 1):
		_free_ports.append(p)
	var err := _peer.connect_to_host(_matchmaker_ip, _matchmaker_port)
	if err != OK:
		push_error("region agent connect failed: %s" % error_string(err))
		quit(1)
		return
	print("region agent connecting to %s:%d region=%s public_ip=%s" % [_matchmaker_ip, _matchmaker_port, _region, _public_ip])

func _process(delta: float) -> bool:
	_peer.poll()
	var status := _peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return false
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return false

	# Send registration once.
	if _buffer.size() == 0 and _rooms.is_empty() and _free_ports.size() == (_room_port_max - _room_port_min + 1):
		_send({"op": "register_region", "region": _region, "public_ip": _public_ip})

	var avail := _peer.get_available_bytes()
	if avail > 0:
		var got := _peer.get_partial_data(avail)
		var err: int = got[0]
		var chunk: PackedByteArray = got[1]
		if err == OK:
			_buffer.append_array(chunk)
			_drain_lines()

	_reap_accum += delta
	if _reap_accum >= 1.0:
		_reap_accum = 0.0
		_reap_rooms()

	return false

func _parse_args(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--matchmaker-ip="):
			_matchmaker_ip = a.substr("--matchmaker-ip=".length())
		elif a.begins_with("--matchmaker-port="):
			_matchmaker_port = int(a.substr("--matchmaker-port=".length()))
		elif a.begins_with("--region="):
			_region = a.substr("--region=".length()).strip_edges().to_lower()
		elif a.begins_with("--public-ip="):
			_public_ip = a.substr("--public-ip=".length()).strip_edges()
		elif a.begins_with("--room-port-min="):
			_room_port_min = int(a.substr("--room-port-min=".length()))
		elif a.begins_with("--room-port-max="):
			_room_port_max = int(a.substr("--room-port-max=".length()))
		elif a.begins_with("--server-binary="):
			_server_binary = a.substr("--server-binary=".length()).strip_edges()

func _drain_lines() -> void:
	while true:
		var idx := _buffer.find(10)
		if idx == -1:
			return
		var line_bytes := _buffer.slice(0, idx)
		_buffer = _buffer.slice(idx + 1, _buffer.size())
		var line := line_bytes.get_string_from_utf8().strip_edges()
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
			continue
		_handle_message(parsed as Dictionary)

func _handle_message(msg: Dictionary) -> void:
	var op := str(msg.get("op", ""))
	if op == "alloc_room":
		var alloc_id := int(msg.get("alloc_id", 0))
		if alloc_id <= 0:
			return
		try_alloc_room(alloc_id)
		return

	if op == "list_rooms":
		var request_id := int(msg.get("request_id", 0))
		var ports: Array[int] = []
		for k in _rooms.keys():
			ports.append(int(k))
		_send({
			"op": "list_rooms_result",
			"request_id": request_id,
			"ok": true,
			"ip": _public_ip,
			"ports": ports,
		})
		return

func try_alloc_room(alloc_id: int) -> void:
	if _free_ports.is_empty():
		_send({"op": "alloc_room_result", "alloc_id": alloc_id, "ok": false, "error": "no_free_ports"})
		return
	var port := int(_free_ports[0])
	_free_ports.remove_at(0)

	var args: PackedStringArray = PackedStringArray([
		"--headless",
		"--dedicated",
		"--port=%d" % port,
	])

	var pid := OS.create_process(_server_binary, args, false)
	if pid <= 0:
		_free_ports.append(port)
		_send({"op": "alloc_room_result", "alloc_id": alloc_id, "ok": false, "error": "spawn_failed"})
		return

	_rooms[port] = Room.new(port, pid)
	print("spawned room port=%d pid=%d" % [port, pid])
	_send({"op": "alloc_room_result", "alloc_id": alloc_id, "ok": true, "ip": _public_ip, "port": port})

func _reap_rooms() -> void:
	for k in _rooms.keys():
		var port := int(k)
		var r: Room = _rooms[port]
		if not OS.is_process_running(r.pid):
			_rooms.erase(port)
			_free_ports.append(port)
			print("room exited port=%d pid=%d" % [port, r.pid])

func _send(obj: Dictionary) -> void:
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var line := JSON.stringify(obj) + "\n"
	_peer.put_data(line.to_utf8_buffer())
