extends Control

@onready var items := [
	$diamond,
	$skull,
	$leaf,
	$crystal
]

func _ready():
	visible = false

# TaskUI থেকে call হবে
func start_task() -> void:
	visible = true
	set_process(true)

func _process(_delta):
	for item in items:
		if not item.attached:
			return
	_complete_task()

# -------------------------
# TASK COMPLETE
# -------------------------
func _complete_task():
	print("✅ Relocate task completed")
	set_process(false)
	await get_tree().create_timer(0.3).timeout
	_close_self()

func _close_self():
	visible = false
	TaskManager.complete_task()
