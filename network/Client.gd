extends Node
class_name GameClient

signal connected
signal disconnected
signal packet_received(packet: NetPacket)
signal udp_packet_received(packet: NetPacket)

@export var connect_timeout_sec: float = 5.0

var _peer := StreamPeerTCP.new()
var _buffer := PackedByteArray()
var _connected_at_msec: int = 0

var _udp := PacketPeerUDP.new()

var server_ip: String = ""
var server_port: int = 0
var my_peer_id: int = 0
var server_peer_id: int = 1

func connect_to(ip: String, port: int) -> Error:
	disconnect_from_server()
	server_ip = ip
	server_port = port
	_buffer = PackedByteArray()
	my_peer_id = 0
	server_peer_id = 1
	_connected_at_msec = Time.get_ticks_msec()
	return _peer.connect_to_host(server_ip, server_port)

func disconnect_from_server() -> void:
	if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED or _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		_peer.disconnect_from_host()
	_buffer = PackedByteArray()
	my_peer_id = 0
	_udp.close()

func is_server_connected() -> bool:
	return _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED

func send(packet: NetPacket) -> void:
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var frame := NetPacket.pack_frame(packet.to_bytes())
	_peer.put_data(frame)

func send_udp(packet: NetPacket) -> void:
	# UDP is used for main game traffic; must be connected to server endpoint.
	if _udp.get_socket() == null:
		return
	_udp.put_packet(packet.to_bytes())

func _process(_delta: float) -> void:
	_peer.poll()
	var status := _peer.get_status()

	if status == StreamPeerTCP.STATUS_CONNECTING:
		var elapsed := float(Time.get_ticks_msec() - _connected_at_msec) / 1000.0
		if elapsed >= connect_timeout_sec:
			disconnect_from_server()
			emit_signal("disconnected")
		return

	if status != StreamPeerTCP.STATUS_CONNECTED:
		return

	# Connected; emit once when we transition.
	# (Godot doesn't provide an explicit connect callback for StreamPeerTCP.)
	if _connected_at_msec != 0:
		_connected_at_msec = 0
		_setup_udp()
		emit_signal("connected")

	var avail := _peer.get_available_bytes()
	if avail <= 0:
		return
	var got := _peer.get_partial_data(avail)
	var err: int = got[0]
	var chunk: PackedByteArray = got[1]
	if err != OK:
		disconnect_from_server()
		emit_signal("disconnected")
		return

	_buffer.append_array(chunk)
	var unpacked := NetPacket.try_unpack_frames(_buffer)
	_buffer = unpacked["remaining"]
	for frame_bytes in unpacked["frames"]:
		var packet := NetPacket.from_bytes(frame_bytes)
		if packet.type == PacketType.Type.WELCOME:
			my_peer_id = int(packet.payload.get("peer_id", 0))
			server_peer_id = int(packet.payload.get("server_peer_id", 1))
			_send_udp_hello()
		emit_signal("packet_received", packet)

	_poll_udp()

func _setup_udp() -> void:
	_udp.close()
	# Bind to ephemeral local port.
	var err := _udp.bind(0, "0.0.0.0")
	if err != OK:
		return
	_udp.connect_to_host(server_ip, server_port)

func _send_udp_hello() -> void:
	if my_peer_id <= 0:
		return
	# Announce UDP endpoint to server so it can send datagrams back.
	var hello := NetPacket.new(PacketType.Type.HELLO, {"peer_id": my_peer_id, "transport": "udp"})
	send_udp(hello)

func _poll_udp() -> void:
	while _udp.get_available_packet_count() > 0:
		var bytes := _udp.get_packet()
		var packet := NetPacket.from_bytes(bytes)
		emit_signal("udp_packet_received", packet)
