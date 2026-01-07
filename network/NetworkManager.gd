extends Node
class_name NetworkManager

signal mode_changed(mode: String) # offline|host|client
signal connected
signal disconnected
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal packet_received(from_peer_id: int, packet: NetPacket)
signal udp_packet_received(from_peer_id: int, packet: NetPacket)

signal match_found(info: Dictionary)
signal private_room_created(info: Dictionary)
signal matchmaker_error(message: String)
signal lan_host_found(host_info: Dictionary)
signal lan_host_lost(host_key: String)

@export var tcp_port: int = 8910
@export var discovery_port: int = 9999
@export var server_name: String = "AmongClone"

@export var matchmaker_ip: String = "127.0.0.1"
@export var matchmaker_port: int = 5000

@export var host_port_min: int = 8910
@export var host_port_max: int = 8920

# Used for ONLINE (global) selection-based join.
# Each entry: {"name": "NA", "ip": "1.2.3.4", "tcp_port": 24567}
@export var region_servers: Array[Dictionary] = []

var server: GameServer
var client: GameClient
var lan: LanDiscovery
var host_migration: HostMigrationManager
var matchmaker: MatchmakerClient

var mode: String = "offline"
var my_peer_id: int = 0

func _ready() -> void:
	server = GameServer.new()
	client = GameClient.new()
	lan = LanDiscovery.new()
	host_migration = HostMigrationManager.new()
	matchmaker = MatchmakerClient.new()
	_apply_cmdline_overrides()
	matchmaker.matchmaker_ip = matchmaker_ip
	matchmaker.matchmaker_port = matchmaker_port

	add_child(server)
	add_child(client)
	add_child(lan)
	add_child(host_migration)
	add_child(matchmaker)

	server.peer_connected.connect(_on_server_peer_connected)
	server.peer_disconnected.connect(_on_server_peer_disconnected)
	server.packet_received.connect(_on_server_packet_received)
	server.udp_packet_received.connect(_on_server_udp_packet_received)

	client.connected.connect(_on_client_connected)
	client.disconnected.connect(_on_client_disconnected)
	client.packet_received.connect(_on_client_packet_received)
	client.udp_packet_received.connect(_on_client_udp_packet_received)

	lan.host_found.connect(func(info: Dictionary): emit_signal("lan_host_found", info))
	lan.host_lost.connect(func(key: String): emit_signal("lan_host_lost", key))

	matchmaker.error.connect(func(message: String): emit_signal("matchmaker_error", message))
	matchmaker.find_match_result.connect(_on_matchmaker_find_match)
	matchmaker.join_code_result.connect(_on_matchmaker_join_code)
	matchmaker.create_private_result.connect(_on_matchmaker_create_private)

	# Optional dedicated server mode: run this exported binary headless and pass:
	#   --dedicated --port=30123
	# This starts TCP + UDP on the port and does not require any scene scripts.
	if _has_cmdline_flag("--dedicated"):
		var port := _get_cmdline_int("--port", tcp_port)
		if port > 0:
			tcp_port = port
		var err := host_internet()
		if err != OK:
			push_error("Dedicated server failed to start: %s" % error_string(err))

func host_lan() -> Error:
	disconnect_all()
	var start_result := _start_server_on_available_port(host_port_min, host_port_max)
	if start_result != OK:
		return start_result
	# Host is peer_id 1.
	mode = "host"
	my_peer_id = 1
	emit_signal("mode_changed", mode)

	lan.discovery_port = discovery_port
	var err := lan.start_advertising(server_name, tcp_port)
	return err

func host_internet() -> Error:
	# Minimal "global" hosting: start TCP server only.
	# Real internet play will still require port forwarding / relay / dedicated server.
	disconnect_all()
	var err := server.start(tcp_port)
	if err != OK:
		return err
	mode = "host"
	my_peer_id = 1
	emit_signal("mode_changed", mode)
	return OK

func _apply_cmdline_overrides() -> void:
	# Allow overriding matchmaker endpoint and default TCP port from CLI.
	# We skip this in-editor unless explicitly requested.
	if OS.has_feature("editor") and not _has_cmdline_flag("--dedicated"):
		return
	var mm_ip := _get_cmdline_string("--matchmaker_ip", "")
	if mm_ip != "":
		matchmaker_ip = mm_ip
	var mm_port := _get_cmdline_int("--matchmaker_port", -1)
	if mm_port > 0:
		matchmaker_port = mm_port
	var port := _get_cmdline_int("--port", -1)
	if port > 0:
		tcp_port = port

func _has_cmdline_flag(flag: String) -> bool:
	var args := OS.get_cmdline_args()
	for a in args:
		if a == flag:
			return true
	return false

func _get_cmdline_string(key: String, default_value: String) -> String:
	# Supports: --key=value
	var args := OS.get_cmdline_args()
	var prefix := key + "="
	for a in args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return default_value

func _get_cmdline_int(key: String, default_value: int) -> int:
	var s := _get_cmdline_string(key, "")
	if s == "":
		return default_value
	return int(s)

func _start_server_on_available_port(min_port: int, max_port: int) -> Error:
	# Picks the first available port in [min_port, max_port] and updates tcp_port.
	# Returns OK on success, or the last error if none worked.
	if min_port <= 0 or max_port <= 0 or max_port < min_port:
		return ERR_INVALID_PARAMETER
	var last_err: int = ERR_CANT_CREATE
	for p in range(min_port, max_port + 1):
		last_err = server.start(p)
		if last_err == OK:
			tcp_port = p
			return OK
	return last_err

func start_lan_browser() -> Error:
	# Listen for hosts (client or host can do this).
	lan.discovery_port = discovery_port
	return lan.start_listening()

func join(ip: String, port: int = -1) -> Error:
	disconnect_all()
	mode = "client"
	emit_signal("mode_changed", mode)
	if port <= 0:
		port = tcp_port
	return client.connect_to(ip, port)

func connect_global(region_ip: String, region_port: int) -> Error:
	# Same as join, just semantically different.
	return join(region_ip, region_port)

func find_match(region: String) -> void:
	matchmaker.matchmaker_ip = matchmaker_ip
	matchmaker.matchmaker_port = matchmaker_port
	matchmaker.request_find_match(region)

func create_private_room(region: String = "auto") -> void:
	matchmaker.matchmaker_ip = matchmaker_ip
	matchmaker.matchmaker_port = matchmaker_port
	matchmaker.request_create_private(region)

func join_by_code(code: String) -> void:
	matchmaker.matchmaker_ip = matchmaker_ip
	matchmaker.matchmaker_port = matchmaker_port
	matchmaker.request_join_code(code)

func disconnect_all() -> void:
	lan.stop()
	server.stop()
	client.disconnect_from_server()
	mode = "offline"
	my_peer_id = 0
	emit_signal("mode_changed", mode)

func send(packet: NetPacket, to_peer_id: int = -1) -> void:
	# Host sends via server, clients send via TCP client.
	if mode == "host":
		if to_peer_id > 0:
			server.send_to(to_peer_id, packet)
		else:
			server.broadcast(packet)
	elif mode == "client":
		client.send(packet)

func send_udp(packet: NetPacket, to_peer_id: int = -1) -> void:
	if mode == "host":
		if to_peer_id > 0:
			server.send_udp_to(to_peer_id, packet)
		else:
			server.broadcast_udp(packet)
	elif mode == "client":
		client.send_udp(packet)

func get_lan_hosts() -> Array[Dictionary]:
	return lan.get_hosts()

func get_region_servers() -> Array[Dictionary]:
	return region_servers

func _on_server_peer_connected(peer_id: int) -> void:
	emit_signal("peer_connected", peer_id)

func _on_server_peer_disconnected(peer_id: int) -> void:
	emit_signal("peer_disconnected", peer_id)

func _on_server_packet_received(from_peer_id: int, packet: NetPacket) -> void:
	host_migration.handle_packet(packet)
	emit_signal("packet_received", from_peer_id, packet)

func _on_server_udp_packet_received(from_peer_id: int, packet: NetPacket) -> void:
	emit_signal("udp_packet_received", from_peer_id, packet)

func _on_client_connected() -> void:
	my_peer_id = client.my_peer_id
	emit_signal("connected")

func _on_client_disconnected() -> void:
	my_peer_id = 0
	host_migration.on_host_disconnected()
	emit_signal("disconnected")

func _on_client_packet_received(packet: NetPacket) -> void:
	if packet.type == PacketType.Type.WELCOME:
		my_peer_id = client.my_peer_id
	host_migration.handle_packet(packet)
	emit_signal("packet_received", client.server_peer_id, packet)

func _on_client_udp_packet_received(packet: NetPacket) -> void:
	emit_signal("udp_packet_received", client.server_peer_id, packet)

func _on_matchmaker_find_match(ok: bool, resp: Dictionary) -> void:
	if not ok:
		return
	var ip := str(resp.get("ip", ""))
	var port := int(resp.get("port", 0))
	if ip == "" or port <= 0:
		emit_signal("matchmaker_error", "bad_match_response")
		return
	var info := {"ip": ip, "tcp_port": port, "code": str(resp.get("code", "")), "region": str(resp.get("region", ""))}
	emit_signal("match_found", info)
	join(ip, port)

func _on_matchmaker_join_code(ok: bool, resp: Dictionary) -> void:
	if not ok:
		return
	var ip := str(resp.get("ip", ""))
	var port := int(resp.get("port", 0))
	if ip == "" or port <= 0:
		emit_signal("matchmaker_error", "bad_code_response")
		return
	join(ip, port)

func _on_matchmaker_create_private(ok: bool, resp: Dictionary) -> void:
	if not ok:
		return
	var ip := str(resp.get("ip", ""))
	var port := int(resp.get("port", 0))
	if ip == "" or port <= 0:
		emit_signal("matchmaker_error", "bad_create_response")
		return
	var info := {"ip": ip, "tcp_port": port, "code": str(resp.get("code", "")), "region": str(resp.get("region", ""))}
	emit_signal("private_room_created", info)
	join(ip, port)
