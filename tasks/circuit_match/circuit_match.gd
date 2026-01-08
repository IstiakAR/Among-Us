extends Control

@onready var switch_node: TextureRect = $switch

var circuit_connected := false

func _ready():
	visible = false
	switch_node.mouse_filter = Control.MOUSE_FILTER_STOP
	switch_node.gui_input.connect(_on_switch_gui_input)

	if is_inside_tree() and get_tree() != null:
		await get_tree().process_frame
	switch_node.pivot_offset = switch_node.size / 2

	_set_vertical()

func start_task() -> void:
	visible = true
	circuit_connected = false
	_set_vertical()

func _on_switch_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if not circuit_connected:
			flip_to_horizontal()

func _set_vertical():
	switch_node.rotation = deg_to_rad(0)

func flip_to_horizontal():
	circuit_connected = true

	var tween := create_tween()
	tween.tween_property(
		switch_node,
		"rotation",
		deg_to_rad(90),
		0.15
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.finished.connect(complete_circuit)


func complete_circuit():
	if is_inside_tree() and get_tree() != null:
		await get_tree().create_timer(0.4).timeout
	_close_self()

func _close_self():
	visible = false
	TaskManager.complete_task()
