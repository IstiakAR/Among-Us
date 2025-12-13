extends CharacterBody2D

@export var speed := 200
@onready var sprite := $AnimatedSprite2D

func _physics_process(delta):
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
