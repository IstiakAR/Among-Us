extends Node

signal task_started(task_id: String)
signal task_completed

var player: Node
var task_ui: Control
var current_task := ""
@onready var TaskUI = $"/root/MainGame/UI/TaskUI"

func start_task(task_id: String):
	if current_task != "":
		return
	current_task = task_id
	PlayerRef.player_instance.set_physics_process(false)
	TaskUI.open_task(task_id)
	task_started.emit(task_id)

func complete_task():
	if current_task == "":
		return

	TaskUI.close_task()
	PlayerRef.player_instance.set_physics_process(true)
	current_task = ""
	task_completed.emit()
