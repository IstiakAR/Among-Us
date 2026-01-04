extends Node
class_name GameServer

signal started(port: int)
signal stopped
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal packet_received(peer_id: int, packet: NetPacket)

@export var listen_port: int = 24567

var _server := TCPServer.new()
var _next_peer_id := 2 # 1 reserved for host/server

# peer_id -> { "peer": StreamPeerTCP, "buffer": PackedByteArray, "seq": int }
var _peers: Dictionary = {}

func start(port: int = -1) -> Error:
	if port > 0:
		listen_port = port
	stop()
	var err := _server.listen(listen_port)
	if err == OK:
		emit_signal("started", listen_port)
	return err

func stop() -> void:
	for peer_id in _peers.keys():
		_disconnect_peer(int(peer_id))
	_peers.clear()
	if _server.is_listening():
		_server.stop()
		emit_signal("stopped")

func is_running() -> bool:
	return _server.is_listening()

func get_peer_ids() -> PackedInt32Array:
	var ids := PackedInt32Array()
	for k in _peers.keys():
		ids.append(int(k))
	return ids

func send_to(peer_id: int, packet: NetPacket) -> void:
	if not _peers.has(peer_id):
		return
	var peer: StreamPeerTCP = _peers[peer_id]["peer"]
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var bytes := packet.to_bytes()
	var frame := NetPacket.pack_frame(bytes)
	peer.put_data(frame)

func broadcast(packet: NetPacket, except_peer_id: int = -1) -> void:
	for k in _peers.keys():
		var pid := int(k)
		if pid == except_peer_id:
			continue
		send_to(pid, packet)

func _process(_delta: float) -> void:
	if not _server.is_listening():
		return
	_accept_new_peers()
	_poll_peers()

func _accept_new_peers() -> void:
	while _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			break
		peer.set_no_delay(true)
		var peer_id := _next_peer_id
		_next_peer_id += 1
		_peers[peer_id] = {
			"peer": peer,
			"buffer": PackedByteArray(),
			"seq": 0,
		}
		emit_signal("peer_connected", peer_id)

		# Tell the client its assigned peer_id.
		var welcome := NetPacket.new(PacketType.Type.WELCOME, {"peer_id": peer_id, "server_peer_id": 1})
		send_to(peer_id, welcome)

func _poll_peers() -> void:
	var to_drop: Array[int] = []
	for k in _peers.keys():
		var peer_id := int(k)
		var peer: StreamPeerTCP = _peers[peer_id]["peer"]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			to_drop.append(peer_id)
			continue

		var avail := peer.get_available_bytes()
		if avail > 0:
			var got := peer.get_partial_data(avail)
			var err: int = got[0]
			var chunk: PackedByteArray = got[1]
			if err != OK:
				to_drop.append(peer_id)
				continue
			var buffer: PackedByteArray = _peers[peer_id]["buffer"]
			buffer.append_array(chunk)
			var unpacked := NetPacket.try_unpack_frames(buffer)
			_peers[peer_id]["buffer"] = unpacked["remaining"]
			for frame_bytes in unpacked["frames"]:
				var packet := NetPacket.from_bytes(frame_bytes)
				emit_signal("packet_received", peer_id, packet)

	for peer_id in to_drop:
		_disconnect_peer(peer_id)

func _disconnect_peer(peer_id: int) -> void:
	if not _peers.has(peer_id):
		return
	var peer: StreamPeerTCP = _peers[peer_id]["peer"]
	peer.disconnect_from_host()
	_peers.erase(peer_id)
	emit_signal("peer_disconnected", peer_id)
