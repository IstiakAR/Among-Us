extends Area2D
class_name TaskArea

@export var task_id: String = "download" # e.g. "download", "keypad", "circuit_match"

func _ready() -> void:
	monitoring = true
	set_process(true)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	# When the local player enters, mark this as the active task area.
	if body is CharacterBody2D and ("is_local" in body) and body.get("is_local"):
		if ("is_dead" in body) and body.get("is_dead"):
			return
		body.set("current_task_area", self)

func _on_body_exited(body: Node) -> void:
	# Clear the active task area when the player leaves.
	if body is CharacterBody2D and ("is_local" in body) and body.get("is_local"):
		if body.get("current_task_area") == self:
			body.set("current_task_area", null)
