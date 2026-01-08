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
signal rooms_listed(rooms)

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
var matchmaker: MatchmakerClient

var mode: String = "offline"
var my_peer_id: int = 0

# peer_id -> PlayerState.to_dict()
var players: Dictionary = {}

var _color_palette: Array[Color] = []
var _rng := RandomNumberGenerator.new()
@export var empty_lobby_timeout_seconds: float = 30.0
var _empty_accum: float = 0.0

func _ready() -> void:
	server = GameServer.new()
	client = GameClient.new()
	lan = LanDiscovery.new()
	matchmaker = MatchmakerClient.new()
	_apply_cmdline_overrides()
	matchmaker.matchmaker_ip = matchmaker_ip
	matchmaker.matchmaker_port = matchmaker_port

	add_child(server)
	add_child(client)
	add_child(lan)
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
	matchmaker.list_rooms_result.connect(_on_matchmaker_list_rooms)

	_color_palette = _load_color_palette()
	_rng.randomize()

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

func _process(delta: float) -> void:
	# Auto-terminate dedicated/headless rooms that stay empty.
	if mode == "host" and (OS.has_feature("headless") or _has_cmdline_flag("--dedicated")):
		var active_players := players.size()
		if active_players <= 0:
			_empty_accum += delta
			if _empty_accum >= maxf(empty_lobby_timeout_seconds, 0.0):
				print("empty room timeout reached; shutting down dedicated room")
				lan.stop()
				server.stop()
				if is_inside_tree() and get_tree() != null:
					get_tree().quit()
		else:
			_empty_accum = 0.0

func host_lan() -> Error:
	disconnect_all()
	var start_result := _start_server_on_available_port(host_port_min, host_port_max)
	if start_result != OK:
		return start_result
	# Host is peer_id 1.
	mode = "host"
	my_peer_id = 1
	emit_signal("mode_changed", mode)
	_register_host_player()

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
	_register_host_player()
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
	# Check both full and user args; headless scripts may populate one or the other.
	var args := OS.get_cmdline_args()
	for a in args:
		if a == flag:
			return true
	var uargs := OS.get_cmdline_user_args()
	for a in uargs:
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
	var last_err: Error = ERR_CANT_CREATE
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

func list_rooms(region: String) -> void:
	matchmaker.matchmaker_ip = matchmaker_ip
	matchmaker.matchmaker_port = matchmaker_port
	matchmaker.request_list_rooms(region)

func join_by_code(code: String) -> void:
	matchmaker.matchmaker_ip = matchmaker_ip
	matchmaker.matchmaker_port = matchmaker_port
	matchmaker.request_join_code(code)

func disconnect_all() -> void:
	lan.stop()
	server.stop()
	client.disconnect_from_server()
	players.clear()
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
			# Ensure host-local listeners also process this event.
			emit_signal("packet_received", 1, packet)
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
	if players.has(peer_id):
		players.erase(peer_id)
		var left := NetPacket.new(PacketType.Type.PLAYER_LEAVE, {"peer_id": peer_id})
		server.broadcast(left)
		# Also notify local host listeners.
		emit_signal("packet_received", 1, left)
	emit_signal("peer_disconnected", peer_id)

func _on_server_packet_received(from_peer_id: int, packet: NetPacket) -> void:
	# Host can intercept/control certain packets.
	if mode == "host":
		if packet.type == PacketType.Type.HELLO:
			_handle_host_hello(from_peer_id, packet)
			# Still emit to allow gameplay scripts to react.
		elif packet.type == PacketType.Type.START_GAME:
			# Dedicated rooms don't have a local UI host; allow a client to initiate and relay.
			server.broadcast(packet)
		elif packet.type == PacketType.Type.PLAYER_KILL:
			# Relay kill events to all clients.
			server.broadcast(packet, from_peer_id)
		elif packet.type == PacketType.Type.MEETING_START:
			# Relay meeting start to all clients so everyone opens the meeting.
			server.broadcast(packet, from_peer_id)
		elif packet.type == PacketType.Type.MEETING_END:
			# Relay meeting end so clients can close meeting UI.
			server.broadcast(packet, from_peer_id)
		elif packet.type == PacketType.Type.END_GAME:
			# Relay game over so all clients see the result screen (dedicated rooms).
			server.broadcast(packet, from_peer_id)
		elif packet.type == PacketType.Type.CHAT_MESSAGE or packet.type == PacketType.Type.VOTE:
			# Relay chat and vote packets from a client to everyone else.
			server.broadcast(packet, from_peer_id)
		elif packet.type == PacketType.Type.TASK_COMPLETE:
			# Update host-side player record and relay to everyone else.
			var pid := int(packet.payload.get("from_id", from_peer_id))
			var task_id := str(packet.payload.get("task_id", ""))
			if pid > 0 and players.has(pid) and task_id != "":
				var pd: Dictionary = players[pid]
				var arr: Array = pd.get("completed_tasks", [])
				if task_id not in arr:
					arr.append(task_id)
					pd["completed_tasks"] = arr
					players[pid] = pd
			server.broadcast(packet, from_peer_id)
		emit_signal("packet_received", from_peer_id, packet)
		return
	emit_signal("packet_received", from_peer_id, packet)

func _handle_host_hello(from_peer_id: int, packet: NetPacket) -> void:
	# Client announces desired name/color.
	var p := PlayerState.new()
	p.peer_id = from_peer_id
	p.name = str(packet.payload.get("name", "Player"))
	var desired: Color = Color.WHITE
	var c: Variant = packet.payload.get("color", Color.WHITE)
	if typeof(c) == TYPE_COLOR:
		desired = c as Color

	var assigned := _assign_unique_color(desired)
	if assigned["ok"] == false:
		# No colors left.
		server.send_to(from_peer_id, NetPacket.new(PacketType.Type.ERROR, {"reason": "no_colors_available"}))
		server.kick(from_peer_id)
		return
	p.color = assigned["color"] as Color
	p.color_id = int(assigned["color_id"])
	players[from_peer_id] = p.to_dict()
	print("host_hello: registered player peer_id=%d name=%s color_id=%d" % [from_peer_id, p.name, p.color_id])

	# Send existing players to the newly joined peer.
	for k in players.keys():
		var pid := int(k)
		if pid == from_peer_id:
			continue
		# Never send a synthetic host player (peer_id=1) from dedicated/headless servers.
		if pid == 1 and (OS.has_feature("headless") or _has_cmdline_flag("--dedicated")):
			continue
		var existing := NetPacket.new(PacketType.Type.PLAYER_JOIN, {"player": players[pid]})
		server.send_to(from_peer_id, existing)

	# Redundant safety: ensure host (1) is sent if present and not dedicated/headless.
	if players.has(1) and not (OS.has_feature("headless") or _has_cmdline_flag("--dedicated")):
		var host_pkt := NetPacket.new(PacketType.Type.PLAYER_JOIN, {"player": players[1]})
		server.send_to(from_peer_id, host_pkt)

	# Broadcast the new player to everyone else and confirm to the new peer.
	var joined := NetPacket.new(PacketType.Type.PLAYER_JOIN, {"player": players[from_peer_id]})
	server.send_to(from_peer_id, joined)
	server.broadcast(joined, from_peer_id)
	# Host instance isn't a TCP peer; deliver locally so it can spawn avatars.
	print("host_hello: broadcast PLAYER_JOIN for peer_id=%d" % from_peer_id)
	emit_signal("packet_received", from_peer_id, joined)

func _load_color_palette() -> Array[Color]:
	# Read the swatches from scenes/User_Settings.tscn so we don't duplicate values.
	var out: Array[Color] = []
	var packed: PackedScene = load("res://scenes/User_Settings.tscn")
	if packed == null:
		return out
	var root := packed.instantiate()
	if root == null:
		return out
	var grid: Node = root.get_node_or_null("ColorGrid")
	if grid != null:
		for child in grid.get_children():
			if child is ColorRect:
				out.append((child as ColorRect).color)
	root.queue_free()
	return out

func _assign_unique_color(desired: Color) -> Dictionary:
	# Returns {"ok": bool, "color": Color, "color_id": int}
	if _color_palette.is_empty():
		# Fallback: allow any color if palette wasn't found.
		return {"ok": true, "color": desired, "color_id": -1}

	var used: Dictionary = {}
	for k in players.keys():
		var pid := int(k)
		var pd: Dictionary = players[pid]
		var v: Variant = pd.get("color", null)
		if typeof(v) == TYPE_COLOR:
			used[v as Color] = true

	# Prefer desired if it's in the palette and unused.
	for i in range(_color_palette.size()):
		var palette_color := _color_palette[i]
		if palette_color.is_equal_approx(desired) and not used.has(palette_color):
			return {"ok": true, "color": palette_color, "color_id": i}

	# Otherwise pick a random free palette color.
	var free_ids: Array[int] = []
	for i in range(_color_palette.size()):
		var palette_color := _color_palette[i]
		if not used.has(palette_color):
			free_ids.append(i)
	if free_ids.is_empty():
		return {"ok": false}
	var pick := free_ids[_rng.randi_range(0, free_ids.size() - 1)]
	return {"ok": true, "color": _color_palette[pick], "color_id": pick}

func _on_server_udp_packet_received(from_peer_id: int, packet: NetPacket) -> void:
	if mode == "host" and packet.type == PacketType.Type.PLAYER_STATE:
		# Relay client movement to all other clients.
		server.broadcast_udp(packet, from_peer_id)
	emit_signal("udp_packet_received", from_peer_id, packet)

func _on_client_connected() -> void:
	# Wait for WELCOME before emitting connected (we need my_peer_id set).
	pass

func _on_client_disconnected() -> void:
	my_peer_id = 0
	emit_signal("disconnected")

func _on_client_packet_received(packet: NetPacket) -> void:
	if packet.type == PacketType.Type.WELCOME:
		my_peer_id = client.my_peer_id
		emit_signal("connected")
	elif packet.type == PacketType.Type.PLAYER_JOIN:
		var pd: Variant = packet.payload.get("player", null)
		if typeof(pd) == TYPE_DICTIONARY:
			var peer_id := int((pd as Dictionary).get("peer_id", 0))
			print("client_packet: PLAYER_JOIN peer_id=%d my_peer_id=%d mode=%s" % [peer_id, my_peer_id, mode])
			if peer_id > 0:
				players[peer_id] = pd as Dictionary
			if peer_id == my_peer_id:
				var v: Variant = (pd as Dictionary).get("color", null)
				if typeof(v) == TYPE_COLOR and Engine.has_singleton("Globals"):
					Globals.player_color = v as Color
	elif packet.type == PacketType.Type.PLAYER_LEAVE:
		var peer_id := int(packet.payload.get("peer_id", 0))
		if peer_id > 0 and players.has(peer_id):
			players.erase(peer_id)
	elif packet.type == PacketType.Type.TASK_COMPLETE:
		var pid := int(packet.payload.get("from_id", 0))
		var task_id := str(packet.payload.get("task_id", ""))
		if pid > 0 and players.has(pid) and task_id != "":
			var pd: Dictionary = players[pid]
			var arr: Array = pd.get("completed_tasks", [])
			if task_id not in arr:
				arr.append(task_id)
				pd["completed_tasks"] = arr
				players[pid] = pd
	emit_signal("packet_received", client.server_peer_id, packet)

func _register_host_player() -> void:
	# Host isn't a TCP peer, so we register it explicitly.
	if mode != "host":
		return
	# Dedicated room servers should not appear as a player.
	if _has_cmdline_flag("--dedicated"):
		print("register_host_player: skipping (dedicated flag present)")
		return
	# Headless processes are dedicated servers; never add a local host player.
	if OS.has_feature("headless"):
		print("register_host_player: skipping (headless feature detected)")
		return
	if players.has(1):
		print("register_host_player: skipping (players already has peer_id=1)")
		return
	var host_name := "Player"
	var desired_color := Color.WHITE
	# If Globals autoload exists, use its configured name and color.
	if Engine.has_singleton("Globals"):
		host_name = str(Globals.player_name)
		desired_color = Globals.player_color
	print("register_host_player: adding local host player; name=%s" % host_name)
	var p := PlayerState.new()
	p.peer_id = 1
	p.name = host_name
	var assigned := _assign_unique_color(desired_color)
	if assigned.get("ok", false):
		p.color = assigned["color"] as Color
		p.color_id = int(assigned["color_id"])
		print("register_host_player: assigned color_id=%d" % p.color_id)
	players[1] = p.to_dict()
	# Notify local host scripts (Lobby spawner) that host exists.
	print("register_host_player: emitting PLAYER_JOIN for peer_id=1")
	emit_signal("packet_received", 1, NetPacket.new(PacketType.Type.PLAYER_JOIN, {"player": players[1]}))

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

func _on_matchmaker_list_rooms(ok: bool, resp: Dictionary) -> void:
	if not ok:
		emit_signal("rooms_listed", [])
		return
	var rooms: Array[Dictionary] = []
	var arr: Array = resp.get("rooms", [])
	for r in arr:
		var ip := str(r.get("ip", ""))
		var port := int(r.get("port", 0))
		var region := str(r.get("region", ""))
		if ip == "" or port <= 0:
			continue
		rooms.append({"ip": ip, "tcp_port": port, "region": region})
	emit_signal("rooms_listed", rooms)
