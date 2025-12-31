extends Control

@onready var switch_node: TextureRect = $switch

var is_connected := false   # circuit state

func _ready():
	visible = false
	switch_node.mouse_filter = Control.MOUSE_FILTER_STOP
	switch_node.gui_input.connect(_on_switch_gui_input)

	# IMPORTANT: pivot center ঠিক করা
	await get_tree().process_frame
	switch_node.pivot_offset = switch_node.size / 2

	# start vertical
	_set_vertical()

# -------------------------
# CALLED BY TaskUI
# -------------------------
func start_task() -> void:
	visible = true
	is_connected = false
	_set_vertical()

# -------------------------
# SWITCH CLICK
# -------------------------
func _on_switch_gui_input(event):
	if event is InputEventMouseButton and event.pressed:
		if not is_connected:
			flip_to_horizontal()

# -------------------------
# SWITCH STATES
# -------------------------
func _set_vertical():
	switch_node.rotation = deg_to_rad(0)   # vertical

func flip_to_horizontal():
	is_connected = true

	# smooth rotation (optional but recommended)
	var tween := create_tween()
	tween.tween_property(
		switch_node,
		"rotation",
		deg_to_rad(90),   # horizontal
		0.15
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tween.finished.connect(complete_circuit)

# -------------------------
# CIRCUIT COMPLETE
# -------------------------
func complete_circuit():
	print("✅ Circuit Completed")
	await get_tree().create_timer(0.4).timeout
	_close_self()

func _close_self():
	visible = false
	TaskManager.complete_task()
