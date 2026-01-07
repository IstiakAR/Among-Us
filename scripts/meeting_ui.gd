extends Control

signal closed

@onready var dimbg: ColorRect = $DimBG
@onready var vote_panel: Control = $Container/VotePanel
@onready var players_vbox: VBoxContainer = $Container/VotePanel/VoteVBox/PlayersScroll/PlayersVBox
@onready var skip_btn: Button = $Container/VotePanel/VoteVBox/Skip
@onready var chat_log: RichTextLabel = $Container/ChatPanel/ChatVBox/ChatLog
@onready var chat_input: LineEdit = $Container/ChatPanel/ChatVBox/ChatInputRow/ChatInput
@onready var send_btn: Button = $Container/ChatPanel/ChatVBox/ChatInputRow/Send

var _peer_index: Array[int] = []
var _font: FontFile = preload("res://assets/VCR_OSD_MONO_1.001.ttf")
var _has_voted: bool = false
var _vote_btns: Array[Button] = []

func _ready() -> void:
	visible = false
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	if dimbg:
		dimbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Wire UI
	skip_btn.pressed.connect(_on_skip_vote)
	send_btn.pressed.connect(_on_send)
	chat_input.text_submitted.connect(_on_text_submitted)
	# Listen for incoming chat/vote packets
	Net.packet_received.connect(_on_tcp_packet)

func open_meeting() -> void:
	_refresh_players()
	_has_voted = false
	skip_btn.disabled = false
	visible = true
	if PlayerRef.player_instance != null:
		PlayerRef.player_instance.set_physics_process(false)
		PlayerRef.player_instance.set_process_input(false)
	chat_input.grab_focus()

func close_meeting() -> void:
	visible = false
	if PlayerRef.player_instance != null:
		PlayerRef.player_instance.set_physics_process(true)
		PlayerRef.player_instance.set_process_input(true)
	closed.emit()

func _refresh_players() -> void:
	_peer_index.clear()
	_vote_btns.clear()
	# Clear existing rows
	for child in players_vbox.get_children():
		child.queue_free()
	# Build player list with per-row vote buttons
	for k in Net.players.keys():
		var pid := int(k)
		var d: Dictionary = Net.players[pid]
		var pname := str(d.get("name", "Player"))
		var color: Color = _player_color(pid)
		var banner := ColorRect.new()
		banner.color = color
		banner.custom_minimum_size = Vector2(0, 42)
		banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var pad := HBoxContainer.new()
		pad.anchors_preset = Control.PRESET_FULL_RECT
		pad.anchor_left = 0
		pad.anchor_right = 1
		pad.anchor_top = 0
		pad.anchor_bottom = 1
		pad.offset_left = 12
		pad.offset_right = -12
		pad.offset_top = 6
		pad.offset_bottom = -6
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var name_label := Label.new()
		name_label.text = pname
		name_label.add_theme_font_override("font", _font)
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", _contrast_text_color(color))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var vote_btn := Button.new()
		vote_btn.text = "Vote"
		vote_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		vote_btn.pressed.connect(func(): _send_vote(pid))
		_vote_btns.append(vote_btn)

		pad.add_child(name_label)
		pad.add_child(vote_btn)
		banner.add_child(pad)
		players_vbox.add_child(banner)
		_peer_index.append(pid)

func _my_peer_id() -> int:
	if Net.mode == "client":
		return Net.my_peer_id
	return 1

func _on_send() -> void:
	var txt := chat_input.text.strip_edges()
	if txt == "":
		return
	chat_input.text = ""
	var pkt := NetPacket.new(PacketType.Type.CHAT_MESSAGE, {
		"from_id": _my_peer_id(),
		"text": txt,
	})
	Net.send(pkt)
	# Also show immediately for the sender
	_append_chat(_display_name(_my_peer_id()), txt)

func _on_text_submitted(_t: String) -> void:
	_on_send()

func _send_vote(target_id: int) -> void:
	if _has_voted:
		return
	var pkt := NetPacket.new(PacketType.Type.VOTE, {
		"from_id": _my_peer_id(),
		"target_id": target_id,
		"skip": false,
	})
	Net.send(pkt)
	_append_chat("System", "%s voted for %s" % [_display_name(_my_peer_id()), _display_name(target_id)])
	_lock_voting_controls()

func _player_color(peer_id: int) -> Color:
	if Net.players.has(peer_id):
		var d: Dictionary = Net.players[peer_id]
		var c: Variant = d.get("color", null)
		if typeof(c) == TYPE_COLOR:
			return c as Color
	return Color(0.5,0.5,0.5)

func _contrast_text_color(bg: Color) -> Color:
	var luminance := (0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b)
	return Color(0,0,0,1) if luminance > 0.6 else Color(1,1,1,1)

func _on_skip_vote() -> void:
	if _has_voted:
		return
	var pkt := NetPacket.new(PacketType.Type.VOTE, {
		"from_id": _my_peer_id(),
		"target_id": -1,
		"skip": true,
	})
	Net.send(pkt)
	_append_chat("System", "%s skipped" % _display_name(_my_peer_id()))
	_lock_voting_controls()

func _lock_voting_controls() -> void:
	_has_voted = true
	skip_btn.disabled = true
	for b in _vote_btns:
		b.disabled = true

func _on_close() -> void:
	close_meeting()

func _on_tcp_packet(_from_peer_id: int, packet: NetPacket) -> void:
	match packet.type:
		PacketType.Type.MEETING_START:
			# Ensure everyone opens the meeting UI when broadcast is received.
			if not visible:
				open_meeting()
		PacketType.Type.CHAT_MESSAGE:
			var from_id := int(packet.payload.get("from_id", 0))
			var text := str(packet.payload.get("text", ""))
			if from_id != _my_peer_id():
				_append_chat(_display_name(from_id), text)
		PacketType.Type.VOTE:
			var from_id := int(packet.payload.get("from_id", 0))
			var target_id := int(packet.payload.get("target_id", -1))
			var skip := bool(packet.payload.get("skip", false))
			if skip:
				_append_chat("System", "%s skipped" % _display_name(from_id))
			else:
				_append_chat("System", "%s voted for %s" % [_display_name(from_id), _display_name(target_id)])
		_:
			pass

func _display_name(peer_id: int) -> String:
	if Net.players.has(peer_id):
		var d: Dictionary = Net.players[peer_id]
		return str(d.get("name", "Player"))
	return "Player %d" % peer_id

func _append_chat(author: String, text: String) -> void:
	chat_log.append_text("[b]%s:[/b] %s\n" % [author, text])
	chat_log.scroll_to_line(chat_log.get_line_count())
