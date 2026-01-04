extends TextureRect

@export var duration := 0.6

func _ready() -> void:
	pivot_offset = size / 2
	rotate_button()

func rotate_button() -> void:
	rotation_degrees = 0

	var tween := create_tween()
	tween.tween_property(self, "rotation_degrees", 360.0, duration)
	
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
	and event.pressed \
	and event.button_index == MOUSE_BUTTON_LEFT:
		rotate_button()
