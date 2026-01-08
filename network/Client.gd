extends Node
class_name GameClient

signal connected
signal disconnected
signal packet_received(packet: NetPacket)
signal udp_packet_received(packet: NetPacket)

@export var connect_timeout_sec: float = 5.0
@export var ping_interval_sec: float = 1.0

var _peer := StreamPeerTCP.new()
var _buffer := PackedByteArray()
var _connected_at_msec: int = 0
var _tcp_ping_accum: float = 0.0
var _udp_ping_accum: float = 0.0
var _last_tcp_rtt_ms: float = -1.0
var _last_udp_rtt_ms: float = -1.0

var _udp := PacketPeerUDP.new()
var _udp_ready: bool = false

var server_ip: String = ""
var server_port: int = 0
var my_peer_id: int = 0
var server_peer_id: int = 1

# Lightweight runtime metrics for debug display
var _metrics: Dictionary = {
	"connected": false,
	"server_ip": "",
	"server_port": 0,
	"udp_ready": false,
	"tcp_rtt_ms": -1.0,
	"tcp_jitter_ms": 0.0,
	"udp_rtt_ms": -1.0,
	"udp_jitter_ms": 0.0,
	"tcp_sent": 0,
	"tcp_recv": 0,
	"udp_sent": 0,
	"udp_recv": 0,
}

func connect_to(ip: String, port: int) -> Error:
	disconnect_from_server()
	# Ensure the TCP peer is back to STATUS_NONE before reconnecting.
	_peer = StreamPeerTCP.new()
	server_ip = ip
	server_port = port
	_buffer = PackedByteArray()
	my_peer_id = 0
	server_peer_id = 1
	_connected_at_msec = Time.get_ticks_msec()
	_tcp_ping_accum = 0.0
	_udp_ping_accum = 0.0
	_last_tcp_rtt_ms = -1.0
	_last_udp_rtt_ms = -1.0
	_metrics["connected"] = false
	_metrics["server_ip"] = server_ip
	_metrics["server_port"] = server_port
	_metrics["udp_ready"] = false
	_metrics["tcp_rtt_ms"] = -1.0
	_metrics["udp_rtt_ms"] = -1.0
	_metrics["tcp_jitter_ms"] = 0.0
	_metrics["udp_jitter_ms"] = 0.0
	_metrics["tcp_sent"] = 0
	_metrics["tcp_recv"] = 0
	_metrics["udp_sent"] = 0
	_metrics["udp_recv"] = 0
	return _peer.connect_to_host(server_ip, server_port)

func disconnect_from_server() -> void:
	if _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED or _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		_peer.disconnect_from_host()
	_buffer = PackedByteArray()
	my_peer_id = 0
	_udp_ready = false
	_udp.close()
	_metrics["connected"] = false
	_metrics["udp_ready"] = false

func is_server_connected() -> bool:
	return _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED

func send(packet: NetPacket) -> void:
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	var frame := NetPacket.pack_frame(packet.to_bytes())
	_peer.put_data(frame)
	_metrics["tcp_sent"] = int(_metrics["tcp_sent"]) + 1

func send_udp(packet: NetPacket) -> void:
	# UDP is used for main game traffic; must be connected to server endpoint.
	if not _udp_ready:
		return
	_udp.put_packet(packet.to_bytes())
	_metrics["udp_sent"] = int(_metrics["udp_sent"]) + 1

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
		_metrics["connected"] = true
		_metrics["server_ip"] = server_ip
		_metrics["server_port"] = server_port
		_metrics["udp_ready"] = _udp_ready

	var avail := _peer.get_available_bytes()
	if avail > 0:
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
				_send_tcp_hello()
				_send_udp_hello()
			elif packet.type == PacketType.Type.PONG:
				var ts := int(packet.payload.get("ts", 0))
				var now_ms := Time.get_ticks_msec()
				if ts > 0:
					var rtt := float(now_ms - ts)
					_metrics["tcp_rtt_ms"] = rtt
					# Exponential moving average for jitter estimate
					if _last_tcp_rtt_ms >= 0.0:
						var delta: float = abs(rtt - _last_tcp_rtt_ms)
						_metrics["tcp_jitter_ms"] = (0.9 * float(_metrics["tcp_jitter_ms"])) + (0.1 * delta)
					_last_tcp_rtt_ms = rtt
			emit_signal("packet_received", packet)
			_metrics["tcp_recv"] = int(_metrics["tcp_recv"]) + 1

	# Always poll UDP while connected.
	_poll_udp()

	# Periodic pings for RTT/jitter metrics
	if my_peer_id > 0:
		_tcp_ping_accum += _delta
		_udp_ping_accum += _delta
		if _tcp_ping_accum >= maxf(ping_interval_sec, 0.1):
			_tcp_ping_accum = 0.0
			var t := Time.get_ticks_msec()
			var tp := NetPacket.new(PacketType.Type.PING, {"peer_id": my_peer_id, "ts": t, "transport": "tcp"})
			send(tp)
		if _udp_ready and _udp_ping_accum >= maxf(ping_interval_sec, 0.1):
			_udp_ping_accum = 0.0
			var tu := Time.get_ticks_msec()
			var up := NetPacket.new(PacketType.Type.PING, {"peer_id": my_peer_id, "ts": tu, "transport": "udp"})
			send_udp(up)

func _setup_udp() -> void:
	_udp.close()
	_udp_ready = false
	# Bind to ephemeral local port.
	var err := _udp.bind(0, "0.0.0.0")
	if err != OK:
		return
	_udp.connect_to_host(server_ip, server_port)
	_udp_ready = true
	_metrics["udp_ready"] = true

func _send_udp_hello() -> void:
	if my_peer_id <= 0:
		return
	# Announce UDP endpoint to server so it can send datagrams back.
	var hello := NetPacket.new(PacketType.Type.HELLO, {"peer_id": my_peer_id, "transport": "udp"})
	send_udp(hello)

func _send_tcp_hello() -> void:
	if my_peer_id <= 0:
		return
	# Announce desired identity; host may override.
	var player_name := "Player"
	var color := Color.WHITE
	if Engine.has_singleton("Globals"):
		player_name = str(Globals.player_name)
		color = Globals.player_color
	var hello := NetPacket.new(PacketType.Type.HELLO, {"peer_id": my_peer_id, "name": player_name, "color": color})
	send(hello)

func _poll_udp() -> void:
	while _udp.get_available_packet_count() > 0:
		var bytes := _udp.get_packet()
		var packet := NetPacket.from_bytes(bytes)
		if packet.type == PacketType.Type.PONG:
			var ts := int(packet.payload.get("ts", 0))
			var now_ms := Time.get_ticks_msec()
			if ts > 0:
				var rtt := float(now_ms - ts)
				_metrics["udp_rtt_ms"] = rtt
				if _last_udp_rtt_ms >= 0.0:
					var delta: float = abs(rtt - _last_udp_rtt_ms)
					_metrics["udp_jitter_ms"] = (0.9 * float(_metrics["udp_jitter_ms"])) + (0.1 * delta)
				_last_udp_rtt_ms = rtt
		emit_signal("udp_packet_received", packet)
		_metrics["udp_recv"] = int(_metrics["udp_recv"]) + 1

func get_metrics() -> Dictionary:
	return _metrics.duplicate(true)
