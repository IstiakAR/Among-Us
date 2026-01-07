extends SceneTree

# TCP newline-JSON matchmaker server (GDScript).
#
# Protocol matches services/matchmaker_server.py and network/MatchmakerClient.gd.
#
# Run (using a Godot executable):
#   godot4 --headless --script res://services_gd/matchmaker_server.gd -- --host=0.0.0.0 --port=5000
#
# Notes:
# - This is a long-running script; it will keep the process alive.

class Conn:
	var id: int
	var peer: StreamPeerTCP
	var buffer: PackedByteArray = PackedByteArray()
	var is_agent: bool = false
	var region: String = ""
	var public_ip: String = ""

	func _init(p_peer: StreamPeerTCP) -> void:
		peer = p_peer
		id = peer.get_instance_id()

class PendingAlloc:
	var alloc_id: int
	var client_conn_id: int
	var request_id: int
	var op: String
	var region: String

	func _init(p_alloc_id: int, p_client_conn_id: int, p_request_id: int, p_op: String, p_region: String) -> void:
		alloc_id = p_alloc_id
		client_conn_id = p_client_conn_id
		request_id = p_request_id
		op = p_op
		region = p_region

var _host: String = "0.0.0.0"
var _port: int = 5000

var _tcp := TCPServer.new()
var _conns: Dictionary = {} # int(conn_id) -> Conn
var _agents_by_region: Dictionary = {} # String -> Array[int] (conn_ids)

var _next_alloc_id: int = 1
var _pending_alloc: Dictionary = {} # int(alloc_id) -> PendingAlloc
var _pending_list: Dictionary = {} # int(request_id) -> Dictionary {client_conn_id, region}

var _code_map: Dictionary = {} # String -> Dictionary {ip, port, region}

var _rng := RandomNumberGenerator.new()

func _initialize() -> void:
	_rng.randomize()
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	_parse_args(args)
	var err := _tcp.listen(_port, _host)
	if err != OK:
		push_error("matchmaker listen failed: %s" % error_string(err))
		quit(1)
		return
	print("matchmaker listening on %s:%d" % [_host, _port])

func _process(_delta: float) -> bool:
	_accept_new()
	_poll_conns()
	return false

func _finalize() -> void:
	_tcp.stop()

func _parse_args(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--host="):
			_host = a.substr("--host=".length())
		elif a.begins_with("--port="):
			_port = int(a.substr("--port=".length()))

func _accept_new() -> void:
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		if peer == null:
			return
		var c := Conn.new(peer)
		_conns[c.id] = c

func _poll_conns() -> void:
	var to_remove: Array[int] = []
	for k in _conns.keys():
		var conn_id := int(k)
		var c: Conn = _conns[conn_id]
		c.peer.poll()
		var status := c.peer.get_status()
		if status != StreamPeerTCP.STATUS_CONNECTED:
			to_remove.append(conn_id)
			continue
		var avail := c.peer.get_available_bytes()
		if avail <= 0:
			continue
		var got := c.peer.get_partial_data(avail)
		var err: int = got[0]
		var chunk: PackedByteArray = got[1]
		if err != OK:
			to_remove.append(conn_id)
			continue
		c.buffer.append_array(chunk)
		_drain_lines(c)

	for conn_id in to_remove:
		_drop_conn(conn_id)

func _drop_conn(conn_id: int) -> void:
	if not _conns.has(conn_id):
		return
	var c: Conn = _conns[conn_id]
	if c.is_agent:
		_remove_agent(conn_id, c.region)
	_conns.erase(conn_id)

func _remove_agent(conn_id: int, region: String) -> void:
	if region == "":
		return
	if not _agents_by_region.has(region):
		return
	var arr: Array = _agents_by_region[region]
	arr.erase(conn_id)
	if arr.is_empty():
		_agents_by_region.erase(region)

func _drain_lines(c: Conn) -> void:
	while true:
		var idx := c.buffer.find(10) # '\n'
		if idx == -1:
			return
		var line_bytes := c.buffer.slice(0, idx)
		c.buffer = c.buffer.slice(idx + 1, c.buffer.size())
		var line := line_bytes.get_string_from_utf8().strip_edges()
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
			_send(c, {"ok": false, "error": "bad_json"})
			continue
		_handle_message(c, parsed as Dictionary)

func _handle_message(c: Conn, msg: Dictionary) -> void:
	var op := str(msg.get("op", ""))

	# Region agent registration.
	if op == "register_region":
		var region := str(msg.get("region", "")).strip_edges().to_lower()
		var public_ip := str(msg.get("public_ip", "")).strip_edges()
		if region == "" or public_ip == "":
			_send(c, {"ok": false, "op": op, "error": "region/public_ip required"})
			return
		c.is_agent = true
		c.region = region
		c.public_ip = public_ip
		if not _agents_by_region.has(region):
			_agents_by_region[region] = []
		var arr: Array = _agents_by_region[region]
		if not arr.has(c.id):
			arr.append(c.id)
		_send(c, {"ok": true, "op": op})
		return

	# Agent allocation responses.
	if op == "alloc_room_result":
		_handle_alloc_result(msg)
		return

	# Agent list responses.
	if op == "list_rooms_result":
		var req_id := int(msg.get("request_id", 0))
		if req_id == 0 or not _pending_list.has(req_id):
			return
		var pend: Dictionary = _pending_list[req_id]
		_pending_list.erase(req_id)
		var client_id := int(pend.get("client_conn_id", 0))
		var region := str(pend.get("region", ""))
		if not _conns.has(client_id):
			return
		var ip := str(msg.get("ip", ""))
		var ports: Array = msg.get("ports", [])
		var rooms: Array = []
		for p in ports:
			rooms.append({"ip": ip, "port": int(p), "region": region})
		_send(_conns[client_id], {"request_id": req_id, "ok": true, "rooms": rooms})
		return

	# Client ops.
	var request_id := int(msg.get("request_id", 0))

	if op == "join_code":
		var code := str(msg.get("code", "")).strip_edges().to_upper()
		if code == "" or not _code_map.has(code):
			_send(c, {"request_id": request_id, "ok": false, "error": "unknown_code"})
			return
		var m: Dictionary = _code_map[code]
		_send(c, {
			"request_id": request_id,
			"ok": true,
			"ip": str(m.get("ip", "")),
			"port": int(m.get("port", 0)),
			"region": str(m.get("region", "")),
			"code": code,
		})
		return

	if op == "find_match" or op == "create_private":
		var region_req := str(msg.get("region", "auto")).strip_edges().to_lower()
		var alloc := _request_alloc(c, request_id, op, region_req)
		if not alloc:
			_send(c, {"request_id": request_id, "ok": false, "error": "no_region_server"})
		return

	if op == "list_rooms":
		var region_req := str(msg.get("region", "auto")).strip_edges().to_lower()
		var agent_conn_id := _pick_agent_conn_id(region_req)
		if agent_conn_id == 0:
			_send(c, {"request_id": request_id, "ok": false, "error": "no_region_server"})
			return
		var agent: Conn = _conns[agent_conn_id]
		_pending_list[request_id] = {"client_conn_id": c.id, "region": agent.region}
		_send(agent, {"op": "list_rooms", "request_id": request_id})
		return

	_send(c, {"request_id": request_id, "ok": false, "error": "unknown_op"})

func _pick_agent_conn_id(region_req: String) -> int:
	if region_req == "" or region_req == "auto":
		for r in ["na", "eu", "asia"]:
			var picked := _pick_agent_conn_id(r)
			if picked != 0:
				return picked
			# continue
		# fallback: any
		for k in _agents_by_region.keys():
			var arr: Array = _agents_by_region[str(k)]
			if not arr.is_empty():
				return int(arr[0])
		return 0

	if not _agents_by_region.has(region_req):
		return 0
	var a: Array = _agents_by_region[region_req]
	if a.is_empty():
		return 0
	return int(a[0])

func _request_alloc(c: Conn, request_id: int, op: String, region_req: String) -> bool:
	var agent_conn_id := _pick_agent_conn_id(region_req)
	if agent_conn_id == 0:
		return false
	if not _conns.has(agent_conn_id):
		return false
	var agent: Conn = _conns[agent_conn_id]
	if not agent.is_agent:
		return false

	var alloc_id := _next_alloc_id
	_next_alloc_id += 1
	_pending_alloc[alloc_id] = PendingAlloc.new(alloc_id, c.id, request_id, op, agent.region)
	_send(agent, {"op": "alloc_room", "alloc_id": alloc_id})
	return true

func _handle_alloc_result(msg: Dictionary) -> void:
	var alloc_id := int(msg.get("alloc_id", 0))
	if alloc_id <= 0:
		return
	if not _pending_alloc.has(alloc_id):
		return
	var p: PendingAlloc = _pending_alloc[alloc_id]
	_pending_alloc.erase(alloc_id)
	if not _conns.has(p.client_conn_id):
		return
	var c: Conn = _conns[p.client_conn_id]

	var ok := bool(msg.get("ok", false))
	if not ok:
		_send(c, {"request_id": p.request_id, "ok": false, "error": str(msg.get("error", "alloc_failed"))})
		return

	var ip := str(msg.get("ip", ""))
	var port := int(msg.get("port", 0))
	if ip == "" or port <= 0:
		_send(c, {"request_id": p.request_id, "ok": false, "error": "alloc_missing_ip_port"})
		return

	var resp: Dictionary = {
		"request_id": p.request_id,
		"ok": true,
		"ip": ip,
		"port": port,
		"region": p.region,
	}

	if p.op == "create_private":
		var code := _create_code(ip, port, p.region)
		resp["code"] = code

	_send(c, resp)

func _create_code(ip: String, port: int, region: String) -> String:
	for _i in range(1000):
		var code := _rand_code(6)
		if not _code_map.has(code):
			_code_map[code] = {"ip": ip, "port": port, "region": region}
			return code
	return "" # should never happen

func _rand_code(length: int) -> String:
	const alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var out := ""
	for _i in range(length):
		out += alphabet[_rng.randi_range(0, alphabet.length() - 1)]
	return out

func _send(c: Conn, obj: Dictionary) -> void:
	if c.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var line := JSON.stringify(obj) + "\n"
	c.peer.put_data(line.to_utf8_buffer())
