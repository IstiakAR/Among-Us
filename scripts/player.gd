extends CharacterBody2D

@export var speed := 200
@onready var sprite := $AnimatedSprite2D

func _ready():
	PlayerRef.player_instance = self

func _physics_process(_delta):
	var input_vector = Vector2.ZERO

	# Input
	if Input.is_action_pressed("ui_right"):
		input_vector.x += 1
	if Input.is_action_pressed("ui_left"):
		input_vector.x -= 1
	if Input.is_action_pressed("ui_down"):
		input_vector.y += 1
	if Input.is_action_pressed("ui_up"):
		input_vector.y -= 1

	# Normalize to prevent faster diagonal movement
	input_vector = input_vector.normalized()
	velocity = input_vector * speed
	move_and_slide()

	# Animate
	if input_vector != Vector2.ZERO:
		sprite.play("walk")
		sprite.flip_h = input_vector.x < 0   # Flip sprite left/right
	else:
		sprite.play("stand")
		

var current_task_area = null

func _input(event: InputEvent) -> void:
	# Interact action
	if event.is_action_pressed("interact") and current_task_area:
		TaskManager.start_task(current_task_area.task_id)

	# Press L key to start "download" task
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		TaskManager.start_task("download")
