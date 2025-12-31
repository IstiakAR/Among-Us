extends Control

@onready var bar: ProgressBar = $ProgressBar
@onready var label: Label = $Label

const DOWNLOAD_TIME := 3.0

var elapsed := 0.0
var downloading := false

func start_task() -> void:
	visible = true
	elapsed = 0.0
	downloading = true
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 0
	label.text = "Downloading..."

func _process(delta: float) -> void:
	if not downloading:
		return

	elapsed += delta

	var t: float = clamp(elapsed / DOWNLOAD_TIME, 0.0, 1.0)
	bar.value = lerp(0.0, 100.0, t)

	var dots := int(elapsed * 2.0) % 4
	label.text = "Downloading" + ".".repeat(dots)

	if elapsed >= DOWNLOAD_TIME:
		downloading = false
		complete_task()

func complete_task() -> void:
	label.text = "Complete"

	# Optionally give a short delay so player sees "Complete"
	await get_tree().create_timer(0.5).timeout

	_close_self()

func _close_self() -> void:
	visible = false

	TaskManager.complete_task()
