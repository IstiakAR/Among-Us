extends Node
class_name LanDiscovery

signal host_found(host_info: Dictionary)
signal host_lost(host_key: String)

@export var discovery_port: int = 9999
@export var advertise_interval_sec: float = 1.0
@export var host_ttl_sec: float = 3.0

var _udp := PacketPeerUDP.new()
var _udp_send := PacketPeerUDP.new()
var _is_advertising := false
var _advertise_name: String = "AmongClone"
var _advertise_tcp_port: int = 24567

# key(ip:tcp_port) -> {info, last_seen_msec}
var _hosts: Dictionary = {}
var _accum: float = 0.0

func start_listening() -> Error:
	stop()
	var err := _udp.bind(discovery_port, "0.0.0.0")
	if err != OK:
		return err
	_udp.set_broadcast_enabled(true)
	return OK

func start_advertising(server_name: String, tcp_port: int) -> Error:
	stop()
	var err := _udp_send.bind(0, "0.0.0.0")
	if err != OK:
		return err
	_udp_send.set_broadcast_enabled(true)
	_is_advertising = true
	_advertise_name = server_name
	_advertise_tcp_port = tcp_port
	_accum = 0.0
	return OK

func stop() -> void:
	_is_advertising = false
	_hosts.clear()
	_udp.close()
	_udp_send.close()

func get_hosts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in _hosts.keys():
		out.append(_hosts[k]["info"])
	return out

func _process(delta: float) -> void:
	_poll_incoming()
	_expire_hosts()
	if _is_advertising:
		_accum += delta
		if _accum >= advertise_interval_sec:
			_accum = 0.0
			_send_advertisement()

func _send_advertisement() -> void:
	var payload := {
		"name": _advertise_name,
		"tcp_port": _advertise_tcp_port,
		"v": NetPacket.PROTOCOL_VERSION,
		"t": Time.get_unix_time_from_system(),
	}
	var bytes := var_to_bytes(payload)
	_udp_send.set_dest_address("255.255.255.255", discovery_port)
	_udp_send.put_packet(bytes)

func _poll_incoming() -> void:
	while _udp.get_available_packet_count() > 0:
		var pkt := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var obj = bytes_to_var(pkt)
		if typeof(obj) != TYPE_DICTIONARY:
			continue
		if int(obj.get("v", 0)) != NetPacket.PROTOCOL_VERSION:
			continue
		var tcp_port := int(obj.get("tcp_port", 0))
		if tcp_port <= 0:
			continue
		var key := "%s:%d" % [ip, tcp_port]

		var info := {
			"ip": ip,
			"tcp_port": tcp_port,
			"name": str(obj.get("name", "")),
		}

		var now := Time.get_ticks_msec()
		var is_new := not _hosts.has(key)
		_hosts[key] = {"info": info, "last_seen_msec": now}
		if is_new:
			emit_signal("host_found", info)

func _expire_hosts() -> void:
	var now := Time.get_ticks_msec()
	var to_remove: Array[String] = []
	for k in _hosts.keys():
		var last_seen := int(_hosts[k]["last_seen_msec"])
		var age_sec := float(now - last_seen) / 1000.0
		if age_sec >= host_ttl_sec:
			to_remove.append(str(k))
	for k in to_remove:
		_hosts.erase(k)
		emit_signal("host_lost", k)
