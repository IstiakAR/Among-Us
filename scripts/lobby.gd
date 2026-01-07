extends Control

@export var send_rate_hz: float = 25
@export var start_countdown_seconds: float = 5.0

@onready var local_player: CharacterBody2D = $Player
@onready var start_button: TextureRect = $UI/HUD/StartButton
@onready var countdown_label: Label = $UI/HUD/CountdownLabel
var _player_scene: PackedScene = preload("res://scenes/Player.tscn")

# peer_id -> player node
var _avatars: Dictionary = {}
var _accum: float = 0.0
var _my_peer_id: int = 0

var _countdown_left: float = -1.0
var _game_starting: bool = false
var _imposter_peer_id: int = 0

func _ready() -> void:
	Net.packet_received.connect(_on_tcp_packet)
	Net.udp_packet_received.connect(_on_udp_packet)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.connected.connect(_on_net_connected)

	if is_instance_valid(start_button):
		start_button.gui_input.connect(_on_start_button_gui_input)
		# Only host can start the game.
		if Net.mode != "host":
			start_button.visible = false

	# Host has an immediate peer id; clients must wait for WELCOME.
	if Net.mode == "host":
		_my_peer_id = 1
		_setup_local_player()
		_sync_from_net_players()
		return

	# If the client already has a peer id (scene loaded late), sync now.
	if Net.my_peer_id > 0:
		_my_peer_id = Net.my_peer_id
		_setup_local_player()
		_sync_from_net_players()

func _on_net_connected() -> void:
	# Client receives peer id after WELCOME.
	_my_peer_id = Net.my_peer_id
	_setup_local_player()
	_sync_from_net_players()

func _sync_from_net_players() -> void:
	if _my_peer_id <= 0:
		return
	# Net caches PLAYER_JOIN packets; spawn anything we're missing.
	for k in Net.players.keys():
		var peer_id := int(k)
		var d: Variant = Net.players[peer_id]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		_handle_player_join(NetPacket.new(PacketType.Type.PLAYER_JOIN, {"player": d}))

func _setup_local_player() -> void:
	if local_player == null:
		return
	# If we spawned an avatar for ourselves before we knew the peer id, remove it.
	if _my_peer_id > 0 and _avatars.has(_my_peer_id) and _avatars[_my_peer_id] != local_player:
		var old_node: Node = _avatars[_my_peer_id]
		if is_instance_valid(old_node):
			old_node.queue_free()
		_avatars.erase(_my_peer_id)
	if local_player.has_method("set_is_local"):
		local_player.call("set_is_local", true)
	elif "is_local" in local_player:
		local_player.set("is_local", true)

	_avatars[_my_peer_id] = local_player

func _physics_process(delta: float) -> void:
	if _my_peer_id <= 0:
		return
	_accum += delta
	var interval: float = 1.0 / maxf(send_rate_hz, 1.0)
	if _accum < interval:
		return
	_accum = 0.0

	# Send local position as UDP PLAYER_STATE.
	var pos := local_player.global_position
	var pkt := NetPacket.new(PacketType.Type.PLAYER_STATE, {
		"peer_id": _my_peer_id,
		"x": pos.x,
		"y": pos.y,
	})
	Net.send_udp(pkt)

func _process(delta: float) -> void:
	if not _game_starting:
		return
	_countdown_left -= delta
	var secs_left := int(ceili(maxf(_countdown_left, 0.0)))
	if is_instance_valid(countdown_label):
		countdown_label.text = "Starting in %d" % secs_left
	if _countdown_left <= 0.0:
		_game_starting = false
		get_tree().change_scene_to_file("res://scenes/Main_Game.tscn")

func _on_tcp_packet(_from_peer_id: int, packet: NetPacket) -> void:
	match packet.type:
		PacketType.Type.PLAYER_JOIN:
			_handle_player_join(packet)
		PacketType.Type.PLAYER_LEAVE:
			_handle_player_leave(packet)
		PacketType.Type.START_GAME:
			_handle_start_game(packet)
		_:
			pass

func _on_start_button_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MouseButton.MOUSE_BUTTON_LEFT:
		return
	if Net.mode != "host":
		return
	if _game_starting:
		return

	_imposter_peer_id = _pick_random_imposter_peer_id()
	var pkt := NetPacket.new(PacketType.Type.START_GAME, {
		"countdown": start_countdown_seconds,
		"imposter_peer_id": _imposter_peer_id,
	})
	Net.send(pkt)
	_begin_countdown(start_countdown_seconds, _imposter_peer_id)
	if is_instance_valid(start_button):
		start_button.visible = false

func _handle_start_game(packet: NetPacket) -> void:
	# Host already started locally; clients start when receiving this.
	var seconds := float(packet.payload.get("countdown", start_countdown_seconds))
	var imposter_id := int(packet.payload.get("imposter_peer_id", 0))
	if imposter_id <= 0:
		imposter_id = _pick_random_imposter_peer_id()
	_imposter_peer_id = imposter_id
	_begin_countdown(seconds, imposter_id)
	if is_instance_valid(start_button):
		start_button.visible = false

func _begin_countdown(seconds: float, imposter_id: int) -> void:
	_game_starting = true
	_countdown_left = maxf(seconds, 0.0)
	Globals.imposter_peer_id = imposter_id
	Globals.is_imposter = (_my_peer_id > 0 and _my_peer_id == imposter_id)
	if is_instance_valid(countdown_label):
		countdown_label.visible = true
		countdown_label.text = "Starting in %d" % int(ceili(_countdown_left))

func _pick_random_imposter_peer_id() -> int:
	# Select 1 imposter among all connected players.
	var ids: Array[int] = []
	for k in Net.players.keys():
		ids.append(int(k))
	if ids.is_empty():
		return _my_peer_id if _my_peer_id > 0 else 1
	return ids[randi() % ids.size()]

func _handle_player_join(packet: NetPacket) -> void:
	var pd: Variant = packet.payload.get("player", null)
	if typeof(pd) != TYPE_DICTIONARY:
		return
	var d := pd as Dictionary
	var peer_id := int(d.get("peer_id", 0))
	if peer_id <= 0:
		return
	var ps := PlayerState.from_dict(d)

	if peer_id == _my_peer_id:
		# Apply host-assigned color to local avatar.
		var sprite := local_player.get_node_or_null("AnimatedSprite2D")
		if sprite != null and sprite is AnimatedSprite2D:
			(sprite as AnimatedSprite2D).modulate = ps.color
		if local_player.has_method("set_display_name"):
			local_player.call("set_display_name", ps.name)
		return

	if _avatars.has(peer_id):
		return

	var node: Node = _player_scene.instantiate()
	add_child(node)
	_avatars[peer_id] = node
	if node is Node2D and local_player != null:
		(node as Node2D).global_position = local_player.global_position

	# Disable input/camera on remote players if supported.
	if node.has_method("set_is_local"):
		node.call("set_is_local", false)
	elif "is_local" in node:
		node.set("is_local", false)

	# Apply color.
	var remote_sprite := node.get_node_or_null("AnimatedSprite2D")
	if remote_sprite != null and remote_sprite is AnimatedSprite2D:
		(remote_sprite as AnimatedSprite2D).modulate = ps.color
	if node.has_method("set_display_name"):
		node.call("set_display_name", ps.name)

func _handle_player_leave(packet: NetPacket) -> void:
	var peer_id := int(packet.payload.get("peer_id", 0))
	_remove_avatar(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	_remove_avatar(peer_id)

func _remove_avatar(peer_id: int) -> void:
	if peer_id <= 0:
		return
	if peer_id == _my_peer_id:
		return
	if not _avatars.has(peer_id):
		return
	var node: Node = _avatars[peer_id]
	_avatars.erase(peer_id)
	if is_instance_valid(node):
		node.queue_free()

func _on_udp_packet(from_peer_id: int, packet: NetPacket) -> void:
	if packet.type != PacketType.Type.PLAYER_STATE:
		return
	var peer_id := int(packet.payload.get("peer_id", from_peer_id))
	if peer_id <= 0:
		return
	if peer_id == _my_peer_id:
		return
	if not _avatars.has(peer_id):
		return
	var node: Node = _avatars[peer_id]
	var x := float(packet.payload.get("x", 0.0))
	var y := float(packet.payload.get("y", 0.0))
	var pos := Vector2(x, y)
	if node.has_method("apply_network_position"):
		node.call("apply_network_position", pos)
	elif node is Node2D:
		(node as Node2D).global_position = pos
