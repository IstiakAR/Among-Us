extends Control

@onready var download_task: Control = $download
@onready var keypad_task: Control = $keypad
@onready var dimbg: Control = $DimBG
@onready var circuit_match_task: Control = $CircuitMatch
# @onready var wires_task: Control = $WiresTask

var active_task: Control = null

func _ready() -> void:
	visible = false
	_hide_all_tasks()
	# Register with the TaskManager autoload (avoids hard-coded scene paths).
	if Engine.is_editor_hint() == false:
		TaskManager.set_task_ui(self)
	# Ensure TaskUI and background dim don't block clicks on tasks.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dimbg != null:
		dimbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Draw TaskUI above other HUD elements for both visuals and picking.
	z_index = 100

func _process(_delta: float) -> void:
	_align_to_camera()
	
func _align_to_camera() -> void:
	# UI is under a CanvasLayer; it already ignores camera transforms.
	# Just ensure it fills the viewport.
	var viewport_size: Vector2 = get_viewport_rect().size
	global_position = Vector2.ZERO
	size = viewport_size


func _hide_all_tasks() -> void:
	download_task.visible = false
	keypad_task.visible = false
	circuit_match_task.visible = false
	# wires_task.visible = false

func open_task(task_id: String) -> void:
	_hide_all_tasks()
	active_task = null
	print(task_id)

	match task_id:
		"download":
			active_task = download_task
		"keypad":
			active_task = keypad_task
		"circuit_match":
			active_task = circuit_match_task	
		# "wires":
		#     active_task = wires_task
		_:
			push_error("TaskUI: Unknown task '%s'" % task_id)
			return
	print(active_task)

	visible = true
	dimbg.visible = true
	if active_task != null:
		active_task.z_index = 1
		active_task.visible = true
	if active_task.has_method("start_task"):
		active_task.start_task()
		print("Started task:", active_task.name)


func close_task() -> void:
	_hide_all_tasks()
	active_task = null
	visible = false
	dimbg.visible = false
