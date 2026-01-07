extends Control

@onready var create_panel = $BoxArea/CreatePanel
@onready var join_panel   = $BoxArea/JoinPanel
@onready var code_panel   = $BoxArea/CodePanel

@onready var create_button: Button = $BoxArea/CreatePanel/Panel/CreateButton
@onready var join_list: ItemList = $BoxArea/JoinPanel/HostList
@onready var refresh_button: TextureRect = $BoxArea/JoinPanel/RefreshButton

@onready var code_text: TextEdit = $BoxArea/CodePanel/Panel/TextEdit
@onready var code_join_button: TextureButton = $BoxArea/CodePanel/JoinButton

@onready var label_create = $create
@onready var label_join   = $join
@onready var label_code   = $code

func _ready():
	create_button.pressed.connect(_on_create_pressed)
	join_list.item_clicked.connect(_on_join_list_item_clicked)
	join_list.item_activated.connect(_on_join_list_item_activated)
	refresh_button.gui_input.connect(_on_refresh_gui_input)
	code_join_button.pressed.connect(_on_code_join_pressed)

	# Avoid duplicate connections when revisiting this scene.
	if not Net.matchmaker_error.is_connected(_on_matchmaker_error):
		Net.matchmaker_error.connect(_on_matchmaker_error)

	# Refresh list when LAN discovery finds/loses hosts.
	Net.lan_host_found.connect(func(_info: Dictionary): _refresh_join_list())
	Net.lan_host_lost.connect(func(_key: String): _refresh_join_list())

	# Online rooms listing results.
	if not Net.rooms_listed.is_connected(_on_rooms_listed):
		Net.rooms_listed.connect(_on_rooms_listed)

	for label in [label_create, label_join, label_code]:
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.connect("gui_input", Callable(self, "_on_label_click").bind(label))
	
	_show_panel(join_panel)

func _on_label_click(event: InputEvent, label) -> void:  # no type
	if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		match label:
			label_create:
				_show_panel(create_panel)
			label_join:
				_show_panel(join_panel)
			label_code:
				_show_panel(code_panel)


func _show_panel(panel_to_show: Control) -> void:
	for panel in [create_panel, join_panel, code_panel]:
		panel.visible = panel == panel_to_show

	if panel_to_show == join_panel:
		_enter_discovery_mode()
	else:
		_exit_discovery_mode()

func _on_create_pressed() -> void:
	# LOCAL => LAN host. ONLINE => ask matchmaker for a private room (code).
	if Globals.playing_online == 0:
		var err := Net.host_lan()
		if err != OK:
			push_error("Failed to host: %s" % error_string(err))
			return
		get_tree().change_scene_to_file("res://scenes/Lobby.tscn")
		return

	if not Net.private_room_created.is_connected(_on_private_room_created):
		Net.private_room_created.connect(_on_private_room_created, CONNECT_ONE_SHOT)
	# Use selected region from Globals to create the private room.
	var mm_map := {"Asia": "asia", "Europe": "eu", "NA": "na"}
	var mm_region := str(mm_map.get(Globals.region, "auto"))
	Net.create_private_room(mm_region)

var _discovery_active := false

func _enter_discovery_mode() -> void:
	if _discovery_active:
		return
	_discovery_active = true
	_refresh_join_list()

	# LOCAL => start UDP LAN discovery.
	if Globals.playing_online == 0:
		var err := Net.start_lan_browser()
		if err != OK:
			push_error("LAN discovery failed: %s" % error_string(err))
			return
	# Always refresh visible list.
	_refresh_join_list()

func _exit_discovery_mode() -> void:
	_discovery_active = false

func _refresh_join_list() -> void:
	if not _discovery_active:
		return

	join_list.clear()

	if Globals.playing_online == 0:
		var entries := Net.get_lan_hosts()
		for info in entries:
			var server_name := str(info.get("name", ""))
			var ip := str(info.get("ip", ""))
			var port := int(info.get("tcp_port", 0))
			var label := "%s %s:%d" % [server_name, ip, port]
			var idx := join_list.add_item(label)
			join_list.set_item_metadata(idx, {"ip": ip, "tcp_port": port})
		return

	# ONLINE: request rooms list for the selected region via matchmaker.
	var mm_map := {"Asia": "asia", "Europe": "eu", "NA": "na"}
	var mm_region := str(mm_map.get(Globals.region, "auto"))
	Net.list_rooms(mm_region)

func _on_rooms_listed(rooms) -> void:
	# Populate join_list with room entries returned by matchmaker.
	join_list.clear()
	for r in rooms:
		var ip := str(r.get("ip", ""))
		var port := int(r.get("tcp_port", 0))
		if ip == "" or port <= 0:
			continue
		var label := "%s:%d" % [ip, port]
		var idx := join_list.add_item(label)
		join_list.set_item_metadata(idx, {"ip": ip, "tcp_port": port})

func _try_join_index(index: int) -> void:
	var meta = join_list.get_item_metadata(index)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	# Join by IP/port for both LOCAL and ONLINE items.
	var ip := str(meta.get("ip", ""))
	var port := int(meta.get("tcp_port", 0))
	if ip == "" or port <= 0:
		return
	var err := Net.join(ip, port)
	if err != OK:
		push_error("Failed to join: %s" % error_string(err))
		return
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _on_join_list_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MouseButton.MOUSE_BUTTON_LEFT:
		return
	_try_join_index(index)

func _on_join_list_item_activated(index: int) -> void:
	# Keyboard / double-click activation.
	_try_join_index(index)

func _on_refresh_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		_refresh_discovery()

func _refresh_discovery() -> void:
	if not _discovery_active:
		return
	# LOCAL => restart UDP LAN discovery (clears and re-binds).
	if Globals.playing_online == 0:
		var err := Net.start_lan_browser()
		if err != OK:
			push_error("LAN discovery failed: %s" % error_string(err))
			return
	# ONLINE => just refresh list from region servers.
	_refresh_join_list()

func _on_code_join_pressed() -> void:
	if Globals.playing_online == 0:
		return
	var code := code_text.text.strip_edges()
	if code == "":
		return
	if not Net.connected.is_connected(_on_net_connected_go_lobby):
		Net.connected.connect(_on_net_connected_go_lobby, CONNECT_ONE_SHOT)
	Net.join_by_code(code)

func _on_match_found(_info: Dictionary) -> void:
	# Net.join() is called internally; wait for TCP connect then go lobby.
	if not Net.connected.is_connected(_on_net_connected_go_lobby):
		Net.connected.connect(_on_net_connected_go_lobby, CONNECT_ONE_SHOT)

func _on_private_room_created(_info: Dictionary) -> void:
	if not Net.connected.is_connected(_on_net_connected_go_lobby):
		Net.connected.connect(_on_net_connected_go_lobby, CONNECT_ONE_SHOT)

func _on_net_connected_go_lobby() -> void:
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _on_matchmaker_error(message: String) -> void:
	push_error("Matchmaker: %s" % message)
