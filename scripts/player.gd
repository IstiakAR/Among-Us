extends CharacterBody2D

@export var speed := 200
@export var is_local: bool = true
@onready var sprite := $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D
@onready var collider: CollisionShape2D = $CollisionShape2D
@onready var name_label: Label = $NameLabel

var _last_network_pos: Vector2 = Vector2.INF
var _net_target_pos: Vector2 = Vector2.ZERO
var _net_has_target: bool = false
var _net_anim_state: StringName = &"stand"

@export var net_smooth_speed: float = 18.0

var _default_collision_layer: int = 0
var _default_collision_mask: int = 0

func _ready():
	_default_collision_layer = collision_layer
	_default_collision_mask = collision_mask
	_apply_locality()
	# Local color (in online play, the host should confirm via PLAYER_JOIN).
	if is_local and sprite:
		sprite.modulate = Globals.player_color
	if is_local:
		set_display_name(Globals.player_name)
	if is_local:
		PlayerRef.player_instance = self

func set_display_name(player_name: String) -> void:
	if name_label:
		name_label.text = player_name

func set_is_local(v: bool) -> void:
	is_local = v
	_apply_locality()

func _apply_locality() -> void:
	set_process_input(is_local)
	set_physics_process(true)
	set_process(true)
	if camera:
		camera.enabled = is_local
	if not is_local:
		# Remote avatars should never block/push the local player.
		collision_layer = 0
		collision_mask = 0
		if collider:
			collider.disabled = true
		velocity = Vector2.ZERO
		_last_network_pos = Vector2.INF
		_net_has_target = false
		_net_anim_state = &"stand"
	else:
		collision_layer = _default_collision_layer
		collision_mask = _default_collision_mask
		if collider:
			collider.disabled = false

func _physics_process(_delta):
	if not is_local:
		return
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


func _process(delta: float) -> void:
	if is_local:
		return
	if not _net_has_target:
		return
	# Smoothly move toward target.
	var t := clampf(net_smooth_speed * delta, 0.0, 1.0)
	var prev := global_position
	global_position = prev.lerp(_net_target_pos, t)
	var moved := (global_position - prev)
	if sprite == null:
		return
	# Animate based on smoothed motion.
	var moving := moved.length() > 0.1
	var desired_state: StringName = &"walk" if moving else &"stand"
	if desired_state != _net_anim_state:
		_net_anim_state = desired_state
		sprite.play(_net_anim_state)
	if absf(moved.x) > 0.01:
		sprite.flip_h = moved.x < 0.0


func apply_network_position(pos: Vector2) -> void:
	# Called by networking code for remote players.
	if is_local:
		return
	if _last_network_pos == Vector2.INF:
		_last_network_pos = pos
		global_position = pos
		_net_target_pos = pos
		_net_has_target = true
		if sprite:
			_net_anim_state = &"stand"
			sprite.play("stand")
		return
	var delta := pos - _last_network_pos
	_last_network_pos = pos
	_net_target_pos = pos
	_net_has_target = true
	# Flip direction immediately based on network delta.
	if sprite != null and absf(delta.x) > 0.01:
		sprite.flip_h = delta.x < 0.0
		

var current_task_area = null

func _input(event: InputEvent) -> void:
	# Interact action
	if event.is_action_pressed("interact") and current_task_area:
		TaskManager.start_task(current_task_area.task_id)

	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		TaskManager.start_task("download")
	if event is InputEventKey and event.pressed and event.keycode == KEY_K:
		TaskManager.start_task("keypad")
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		TaskManager.start_task("circuit_match")
		
