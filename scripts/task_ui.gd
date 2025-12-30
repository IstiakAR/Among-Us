extends Control

@onready var download_task: Control = $download
# @onready var wires_task: Control = $WiresTask

var active_task: Control = null

func _ready() -> void:
	visible = false
	_hide_all_tasks()

func _process(_delta: float) -> void:
	_align_to_camera()
	
func _align_to_camera() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var top_left: Vector2 = cam.global_position - viewport_size * 0.5
	global_position = top_left
	size = viewport_size


func _hide_all_tasks() -> void:
	download_task.visible = false
	# wires_task.visible = false

func open_task(task_id: String) -> void:
	_hide_all_tasks()
	active_task = null

	match task_id:
		"download":
			active_task = download_task
		# "wires":
		#     active_task = wires_task
		_:
			push_error("TaskUI: Unknown task '%s'" % task_id)
			return

	visible = true

	if active_task.has_method("start_task"):
		active_task.start_task()
	else:
		active_task.visible = true

func close_task() -> void:
	_hide_all_tasks()
	active_task = null
	visible = false
