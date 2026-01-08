extends Node2D

@export var send_rate_hz: float = 25.0
@export var kill_range: float = 250.0

@onready var local_player: CharacterBody2D = $Player
var _player_scene: PackedScene = preload("res://scenes/Player.tscn")

@onready var _kill_button: TextureRect = $UI/HUD/KillButton
@onready var _use_button: TextureRect = $UI/HUD/UseButton
var _kill_cd_label: Label = null
@onready var _report_button: TextureRect = $UI/HUD/ReportButton
@onready var _meeting_ui: Control = $UI/MeetingUI
@onready var _meeting_button: TextureRect = $MeetingButton
@onready var _debug_label: Label = $UI/HUD/DebugLabel

var _avatars: Dictionary = {} # peer_id -> player node
var _accum: float = 0.0
var _my_peer_id: int = 0

var _kill_cooldown_seconds: float = 30.0
var _kill_cooldown_remaining: float = 0.0
var _result_shown: bool = false

func _ready() -> void:
	# Role is assigned in the lobby (host selects, everyone receives).
	if Globals.is_imposter:
		print("ROLE: IMPOSTER")
	else:
		print("ROLE: CREWMATE")

	# Role-based HUD buttons
	if is_instance_valid(_kill_button):
		_kill_button.visible = Globals.is_imposter
		_kill_button.mouse_filter = Control.MOUSE_FILTER_STOP
		_kill_button.gui_input.connect(_on_kill_button_input)
		# Create cooldown overlay label for visual countdown.
		if Globals.is_imposter:
			_kill_cd_label = Label.new()
			_kill_cd_label.name = "CooldownLabel"
			_kill_cd_label.text = ""
			_kill_cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_kill_cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_kill_cd_label.add_theme_font_size_override("font_size", 16)
			_kill_cd_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			_kill_cd_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			_kill_cd_label.visible = false
			_kill_button.add_child(_kill_cd_label)
	if is_instance_valid(_use_button):
		_use_button.visible = not Globals.is_imposter
		_use_button.mouse_filter = Control.MOUSE_FILTER_STOP
		_use_button.gui_input.connect(_on_use_button_input)

	Net.packet_received.connect(_on_tcp_packet)
	Net.udp_packet_received.connect(_on_udp_packet)
	Net.peer_disconnected.connect(_on_peer_disconnected)
	Net.connected.connect(_on_net_connected)
	# Meeting: wire report button to open the meeting UI
	if is_instance_valid(_report_button):
		_report_button.mouse_filter = Control.MOUSE_FILTER_STOP
		_report_button.gui_input.connect(_on_report_button_input)
	# Emergency meeting button in cafeteria
	if is_instance_valid(_meeting_button):
		_meeting_button.mouse_filter = Control.MOUSE_FILTER_STOP
		_meeting_button.gui_input.connect(_on_meeting_button_input)

	# Ensure HUD doesn't swallow clicks over fullscreen tasks.
	var hud := get_node_or_null("UI/HUD")
	if hud != null and hud is Control:
		(hud as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

	if Net.mode == "host":
		_my_peer_id = 1
		_setup_local_player()
		_sync_from_net_players()
		return

	if Net.my_peer_id > 0:
		_my_peer_id = Net.my_peer_id
		_setup_local_player()
		_sync_from_net_players()

func _on_net_connected() -> void:
	_my_peer_id = Net.my_peer_id
	_setup_local_player()
	_sync_from_net_players()

func _sync_from_net_players() -> void:
	if _my_peer_id <= 0:
		return
	for k in Net.players.keys():
		var peer_id := int(k)
		var d: Variant = Net.players[peer_id]
		if typeof(d) != TYPE_DICTIONARY:
			continue
		_handle_player_join(NetPacket.new(PacketType.Type.PLAYER_JOIN, {"player": d}))
	# Safety: in LAN client mode ensure host (peer_id=1) is spawned if present.
	if Net.mode == "client" and Net.players.has(1) and not _avatars.has(1):
		var d1: Variant = Net.players[1]
		if typeof(d1) == TYPE_DICTIONARY:
			_handle_player_join(NetPacket.new(PacketType.Type.PLAYER_JOIN, {"player": d1}))

func _setup_local_player() -> void:
	if local_player == null:
		return
	if local_player.has_method("set_is_local"):
		local_player.call("set_is_local", true)
	elif "is_local" in local_player:
		local_player.set("is_local", true)
	_avatars[_my_peer_id] = local_player

func _physics_process(delta: float) -> void:
	# Update kill cooldown UI and timing for imposters.
	if Globals.is_imposter:
		if _kill_cooldown_remaining > 0.0:
			_kill_cooldown_remaining = maxf(0.0, _kill_cooldown_remaining - delta)
		if is_instance_valid(_kill_button):
			var cooling := _kill_cooldown_remaining > 0.0
			# Dim button when cooling down, show countdown.
			_kill_button.modulate = Color(1,1,1, 0.55 if cooling else 1.0)
			if _kill_cd_label != null:
				_kill_cd_label.visible = cooling
				_kill_cd_label.text = str(int(ceil(_kill_cooldown_remaining))) if cooling else ""

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

func _process(_delta: float) -> void:
	_update_debug_label()


func _on_kill_button_input(event: InputEvent) -> void:
	if not Globals.is_imposter:
		return
	# Prevent killing if local player is dead.
	if local_player != null and "is_dead" in local_player and local_player.is_dead:
		return
	if Net.players.has(_my_peer_id):
		var pd: Dictionary = Net.players[_my_peer_id]
		var alive := bool(pd.get("is_alive", true))
		if not alive:
			return
	if _kill_cooldown_remaining > 0.0:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var target := _find_nearest_target(kill_range)
			if target == null:
				return
			# Move imposter to killed player's position.
			if local_player != null and target is Node2D:
				local_player.global_position = (target as Node2D).global_position
			# Execute player dead animation and freeze the target.
			if target.has_method("kill_player"):
				target.call("kill_player")
			# Identify victim peer_id to replicate over network and send kill event.
			var victim_peer_id := -1
			for k in _avatars.keys():
				if _avatars[k] == target:
					victim_peer_id = int(k)
					break
			if victim_peer_id > 0:
				var pos := local_player.global_position
				var pkt := NetPacket.new(PacketType.Type.PLAYER_KILL, {
					"killer_id": _my_peer_id,
					"victim_id": victim_peer_id,
					"x": pos.x,
					"y": pos.y,
				})
				Net.send(pkt)
			# Start cooldown
			_kill_cooldown_remaining = _kill_cooldown_seconds

func _on_use_button_input(event: InputEvent) -> void:
	if Globals.is_imposter:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if local_player != null and local_player.has_method("use_interact"):
				local_player.call("use_interact")

func _find_nearest_target(max_dist: float) -> Node:
	# Find nearest non-local, non-dead avatar.
	var nearest: Node = null
	var nearest_dist: float = INF
	for peer_id in _avatars.keys():
		if int(peer_id) == _my_peer_id:
			continue
		var node: Node = _avatars[peer_id]
		if not is_instance_valid(node):
			continue
		# Skip already dead players if property exists.
		var dead := false
		if "is_dead" in node:
			dead = node.get("is_dead")
		if dead:
			continue
		if node is Node2D and local_player is Node2D:
			var d := ((node as Node2D).global_position - (local_player as Node2D).global_position).length()
			if d < nearest_dist:
				nearest_dist = d
				nearest = node
	if nearest_dist <= max_dist:
		return nearest
	return null

func _on_tcp_packet(_from_peer_id: int, packet: NetPacket) -> void:
	match packet.type:
		PacketType.Type.PLAYER_JOIN:
			_handle_player_join(packet)
		PacketType.Type.PLAYER_LEAVE:
			_handle_player_leave(packet)
		PacketType.Type.PLAYER_KILL:
			_handle_player_kill(packet)
		PacketType.Type.TASK_COMPLETE:
			_check_end_conditions()
		PacketType.Type.END_GAME:
			_handle_end_game(packet)
		_:
			pass

func _update_debug_label() -> void:
	if not is_instance_valid(_debug_label):
		return
	var mode := Net.mode
	var players := int(Net.players.size())
	var text := "Mode: %s | Players: %d" % [mode, players]
	if mode == "client" and Net.client != null and Net.client.has_method("get_metrics"):
		var m: Dictionary = Net.client.call("get_metrics")
		var tcp_rtt := float(m.get("tcp_rtt_ms", -1.0))
		var tcp_jit := float(m.get("tcp_jitter_ms", 0.0))
		var udp_rtt := float(m.get("udp_rtt_ms", -1.0))
		var udp_jit := float(m.get("udp_jitter_ms", 0.0))
		var udp_ready := bool(m.get("udp_ready", false))
		var tcp_rtt_str := (String.num(tcp_rtt, 1) if tcp_rtt >= 0.0 else "n/a")
		var udp_rtt_str := (String.num(udp_rtt, 1) if udp_rtt >= 0.0 else "n/a")
		var udp_ready_str := ("ready" if udp_ready else "n/a")
		text += "\nTCP RTT: %s ms | Jit: %s ms" % [tcp_rtt_str, String.num(tcp_jit, 1)]
		text += "\nUDP: %s | RTT: %s ms | Jit: %s ms" % [udp_ready_str, udp_rtt_str, String.num(udp_jit, 1)]
	else:
		text += "\nHosting on port %d" % Net.tcp_port
	_debug_label.text = text

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
		# Apply host-assigned color/name to local avatar.
		var local_sprite := local_player.get_node_or_null("AnimatedSprite2D")
		if local_sprite != null and local_sprite is AnimatedSprite2D:
			var anim_sprite := local_sprite as AnimatedSprite2D
			if anim_sprite.material != null and anim_sprite.material is ShaderMaterial:
				# Ensure per-instance material
				anim_sprite.material = (anim_sprite.material as ShaderMaterial).duplicate(true)
				var sm := anim_sprite.material as ShaderMaterial
				sm.set_shader_parameter("tint_color", ps.color)
			else:
				anim_sprite.modulate = ps.color
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

	# Apply color/name.
	var remote_sprite := node.get_node_or_null("AnimatedSprite2D")
	if remote_sprite != null and remote_sprite is AnimatedSprite2D:
		var anim_sprite := remote_sprite as AnimatedSprite2D
		if anim_sprite.material != null and anim_sprite.material is ShaderMaterial:
			# Ensure per-instance material for remote avatar
			anim_sprite.material = (anim_sprite.material as ShaderMaterial).duplicate(true)
			var sm := anim_sprite.material as ShaderMaterial
			sm.set_shader_parameter("tint_color", ps.color)
		else:
			anim_sprite.modulate = ps.color
	if node.has_method("set_display_name"):
		node.call("set_display_name", ps.name)

func _handle_player_leave(packet: NetPacket) -> void:
	var peer_id := int(packet.payload.get("peer_id", 0))
	_remove_avatar(peer_id)
	# If an imposter leaves, crewmates win.
	if Net.players.has(peer_id):
		var pd: Dictionary = Net.players[peer_id]
		var was_imposter := bool(pd.get("is_imposter", false))
		Net.players.erase(peer_id)
		if was_imposter:
			_broadcast_end_game(false)
			return
	_check_end_conditions()

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

func _on_report_button_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# Broadcast meeting start so all clients enter the meeting.
			var pkt := NetPacket.new(PacketType.Type.MEETING_START, {"from_id": _my_peer_id})
			Net.send(pkt)
			# Open locally immediately for responsiveness.
			if is_instance_valid(_meeting_ui) and _meeting_ui.has_method("open_meeting"):
				_meeting_ui.call("open_meeting")

func _unhandled_input(event: InputEvent) -> void:
	# Keyboard shortcut: press E to call a meeting.
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_F:
			var pkt := NetPacket.new(PacketType.Type.MEETING_START, {"from_id": _my_peer_id})
			Net.send(pkt)
			if is_instance_valid(_meeting_ui) and _meeting_ui.has_method("open_meeting"):
				_meeting_ui.call("open_meeting")

func _handle_player_kill(packet: NetPacket) -> void:
	var killer_id := int(packet.payload.get("killer_id", 0))
	var victim_id := int(packet.payload.get("victim_id", 0))
	var x := float(packet.payload.get("x", 0.0))
	var y := float(packet.payload.get("y", 0.0))
	var killer_pos := Vector2(x, y)

	# Apply victim death
	if victim_id == _my_peer_id:
		if local_player != null and local_player.has_method("kill_player"):
			local_player.call("kill_player")
			# Hide/disable kill UI for dead local player.
			if is_instance_valid(_kill_button):
				_kill_button.visible = false
				_kill_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif _avatars.has(victim_id):
		var v: Node = _avatars[victim_id]
		if v != null and v.has_method("kill_player"):
			v.call("kill_player")

	# Mark victim not alive in players dictionary
	if Net.players.has(victim_id):
		var pd: Dictionary = Net.players[victim_id]
		pd["is_alive"] = false
		Net.players[victim_id] = pd
	print("kill: victim=", victim_id, " imp=", (Net.players.has(victim_id) and bool(Net.players[victim_id].get("is_imposter", false))), " killer=", killer_id)

	# Move killer to victim position if killer is known on this client
	if killer_id == _my_peer_id:
		if local_player is Node2D:
			(local_player as Node2D).global_position = killer_pos
	elif _avatars.has(killer_id):
		var k: Node = _avatars[killer_id]
		if k is Node2D:
			(k as Node2D).global_position = killer_pos

	_check_end_conditions()

func _on_meeting_button_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var pkt := NetPacket.new(PacketType.Type.MEETING_START, {"from_id": _my_peer_id})
			Net.send(pkt)
			if is_instance_valid(_meeting_ui) and _meeting_ui.has_method("open_meeting"):
				_meeting_ui.call("open_meeting")

func _check_end_conditions() -> void:
	# Compute alive counts
	var alive_imposters := 0
	var alive_crewmates := 0
	for k in Net.players.keys():
		var pd: Dictionary = Net.players[int(k)]
		var alive := bool(pd.get("is_alive", true))
		if not alive:
			continue
		if bool(pd.get("is_imposter", false)):
			alive_imposters += 1
		else:
			alive_crewmates += 1
	print("status: alive_crewmates=", alive_crewmates, " alive_imposters=", alive_imposters)

	# If no alive imposters, crewmates win
	if alive_imposters <= 0:
		_broadcast_end_game(false)
		return
	# If alive crewmates <= alive imposters, imposters win
	if alive_crewmates <= alive_imposters:
		_broadcast_end_game(true)
		return

	# Check team tasks completion: every crewmate completed all required tasks
	var required_tasks: Array[String] = ["download", "keypad", "circuit_match"]
	var all_crewmates_done := true
	for k in Net.players.keys():
		var pd: Dictionary = Net.players[int(k)]
		var is_imp := bool(pd.get("is_imposter", false))
		if is_imp:
			continue
		var tasks: Array = pd.get("completed_tasks", [])
		for t in required_tasks:
			if t not in tasks:
				all_crewmates_done = false
				break
		if not all_crewmates_done:
			break
	if all_crewmates_done:
		_broadcast_end_game(false)

func _broadcast_end_game(imposter_won: bool) -> void:
	# Only one source should broadcast; prefer host or dedicated decision-maker
	var should_broadcast := (Net.mode == "host") or (Net.mode == "client" and not Net.players.has(1))
	var pkt := NetPacket.new(PacketType.Type.END_GAME, {"imposter_won": imposter_won})
	if should_broadcast:
		Net.send(pkt)
	# Always show locally; guard to avoid duplicate UI when relay arrives.
	_handle_end_game(pkt)

func _handle_end_game(packet: NetPacket) -> void:
	if _result_shown:
		return
	var imposter_won := bool(packet.payload.get("imposter_won", false))
	var result_scene: PackedScene = load("res://scenes/Result.tscn")
	if result_scene != null:
		var inst := result_scene.instantiate()
		if inst is Control:
			# Prefer attaching under UI canvas to ensure visibility.
			var ui := get_node_or_null("UI")
			if ui != null and ui is Node:
				(ui as Node).add_child(inst)
			else:
				add_child(inst)
			var ctrl := inst as Control
			ctrl.z_index = 1000
			ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
			ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
			ctrl.anchor_left = 0
			ctrl.anchor_right = 1
			ctrl.anchor_top = 0
			ctrl.anchor_bottom = 1
			ctrl.offset_left = 0
			ctrl.offset_right = 0
			ctrl.offset_top = 0
			ctrl.offset_bottom = 0
			if ctrl.has_method("set_imposter_won"):
				ctrl.call("set_imposter_won", imposter_won)
			_result_shown = true
