extends Node

signal task_started(task_id: String)
signal task_completed

var current_task := ""

var _task_ui: Control = null

func set_task_ui(ui: Control) -> void:
	_task_ui = ui

func _resolve_task_ui() -> Control:
	if is_instance_valid(_task_ui):
		return _task_ui
	if not is_inside_tree() or get_tree() == null:
		return null
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var n := scene.get_node_or_null("UI/TaskUI")
	if n == null:
		n = scene.find_child("TaskUI", true, false)
	if n != null and n is Control:
		_task_ui = n
		return _task_ui
	return null

func start_task(task_id: String):
	if current_task != "":
		return
	current_task = task_id
	if PlayerRef.player_instance != null:
		PlayerRef.player_instance.set_physics_process(false)
	var ui := _resolve_task_ui()
	if ui == null:
		push_error("TaskManager: TaskUI not found (are you in MainGame?)")
		current_task = ""
		return
	ui.open_task(task_id)
	task_started.emit(task_id)

func complete_task():
	if current_task == "":
		return
	var ui := _resolve_task_ui()
	if ui != null:
		ui.close_task()
	if PlayerRef.player_instance != null:
		PlayerRef.player_instance.set_physics_process(true)
	# Broadcast task completion to host/peers
	var my_id := 1 if Net.mode == "host" else Net.my_peer_id
	if my_id > 0:
		var pkt := NetPacket.new(PacketType.Type.TASK_COMPLETE, {
			"from_id": my_id,
			"task_id": current_task,
		})
		Net.send(pkt)
	current_task = ""
	task_completed.emit()
