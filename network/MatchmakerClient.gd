extends Node
class_name MatchmakerClient

signal connected
signal disconnected
signal error(message: String)

signal find_match_result(ok: bool, result: Dictionary)
signal join_code_result(ok: bool, result: Dictionary)
signal create_private_result(ok: bool, result: Dictionary)
signal list_rooms_result(ok: bool, result: Dictionary)

@export var matchmaker_ip: String = "127.0.0.1"
@export var matchmaker_port: int = 5000
@export var connect_timeout_sec: float = 5.0

var _peer := StreamPeerTCP.new()
var _buffer := PackedByteArray()
var _connecting_started_msec: int = 0

var _outbox: Array[Dictionary] = []

var _next_request_id: int = 1
# request_id -> op
var _pending: Dictionary = {}

func connect_to_matchmaker(ip: String = "", port: int = -1) -> Error:
	if ip != "":
		matchmaker_ip = ip
	if port > 0:
		matchmaker_port = port
	disconnect_from_matchmaker()
	# Ensure the peer is back to STATUS_NONE before reconnecting.
	_peer = StreamPeerTCP.new()
	_buffer = PackedByteArray()
	_pending.clear()
	_next_request_id = 1
	_outbox.clear()
	_connecting_started_msec = Time.get_ticks_msec()
	return _peer.connect_to_host(matchmaker_ip, matchmaker_port)

func disconnect_from_matchmaker() -> void:
	if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED or _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		_peer.disconnect_from_host()
	_buffer = PackedByteArray()
	_pending.clear()
	_outbox.clear()
	_connecting_started_msec = 0

func is_connected_to_matchmaker() -> bool:
	return _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED

func request_find_match(region: String) -> void:
	_send_request({"op": "find_match", "region": region})

func request_join_code(code: String) -> void:
	_send_request({"op": "join_code", "code": code.strip_edges()})

func request_create_private(region: String = "auto") -> void:
	_send_request({"op": "create_private", "region": region})

func request_list_rooms(region: String) -> void:
	_send_request({"op": "list_rooms", "region": region})

func _send_request(payload: Dictionary) -> void:
	# If not connected yet, connect once and queue requests until the socket is ready.
	var status := _peer.get_status()
	if status != StreamPeerTCP.STATUS_CONNECTED:
		if status == StreamPeerTCP.STATUS_NONE:
			var err := connect_to_matchmaker(matchmaker_ip, matchmaker_port)
			if err != OK:
				emit_signal("error", "matchmaker_connect_failed: %s" % error_string(err))
				return
		# STATUS_CONNECTING (or transient): queue request for later.
		_outbox.append(payload.duplicate(true))
		return

	_send_payload_now(payload)

func _send_payload_now(payload: Dictionary) -> void:
	var request_id := _next_request_id
	_next_request_id += 1
	payload["request_id"] = request_id
	_pending[request_id] = str(payload.get("op", ""))

	var json_line := JSON.stringify(payload) + "\n"
	var err := _peer.put_data(json_line.to_utf8_buffer())
	if err != OK:
		disconnect_from_matchmaker()
		emit_signal("error", "matchmaker_write_failed: %s" % error_string(err))
		emit_signal("disconnected")

func _process(_delta: float) -> void:
	_peer.poll()
	var status := _peer.get_status()

	if status == StreamPeerTCP.STATUS_CONNECTING:
		if _connecting_started_msec != 0:
			var elapsed := float(Time.get_ticks_msec() - _connecting_started_msec) / 1000.0
			if elapsed >= connect_timeout_sec:
				disconnect_from_matchmaker()
				emit_signal("error", "matchmaker_connect_timeout")
				emit_signal("disconnected")
		return

	if status != StreamPeerTCP.STATUS_CONNECTED:
		return

	# Transition to connected.
	if _connecting_started_msec != 0:
		_connecting_started_msec = 0
		emit_signal("connected")
		_flush_outbox()
	elif not _outbox.is_empty():
		_flush_outbox()

	var avail := _peer.get_available_bytes()
	if avail <= 0:
		return

	var got := _peer.get_partial_data(avail)
	var err: int = got[0]
	var chunk: PackedByteArray = got[1]
	if err != OK:
		disconnect_from_matchmaker()
		emit_signal("error", "matchmaker_read_failed: %s" % error_string(err))
		emit_signal("disconnected")
		return

	_buffer.append_array(chunk)
	_drain_lines()

func _flush_outbox() -> void:
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	# Send queued requests in FIFO order.
	while not _outbox.is_empty():
		var payload: Dictionary = _outbox.pop_front() as Dictionary
		_send_payload_now(payload)

func _drain_lines() -> void:
	# Parse newline-delimited JSON.
	while true:
		var idx := _buffer.find(10) # '\n'
		if idx == -1:
			return
		var line_bytes := _buffer.slice(0, idx)
		_buffer = _buffer.slice(idx + 1, _buffer.size())
		var line := line_bytes.get_string_from_utf8().strip_edges()
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
			emit_signal("error", "matchmaker_bad_json")
			continue
		_handle_response(parsed as Dictionary)

func _handle_response(resp: Dictionary) -> void:
	var request_id := int(resp.get("request_id", 0))
	var ok := bool(resp.get("ok", false))
	var op := ""
	if request_id != 0 and _pending.has(request_id):
		op = str(_pending[request_id])
		_pending.erase(request_id)

	if not ok:
		var msg := str(resp.get("error", "matchmaker_error"))
		emit_signal("error", msg)

	match op:
		"find_match":
			emit_signal("find_match_result", ok, resp)
		"join_code":
			emit_signal("join_code_result", ok, resp)
		"create_private":
			emit_signal("create_private_result", ok, resp)
		"list_rooms":
			emit_signal("list_rooms_result", ok, resp)
		_:
			# Unknown/untracked op; ignore but surface errors above.
			pass
