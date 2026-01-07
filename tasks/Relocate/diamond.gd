extends TextureRect

@export var target_position: Vector2   # GLOBAL position
@export var snap_distance := 40.0

var dragging := false
var drag_offset := Vector2.ZERO
var start_global_pos := Vector2.ZERO
var attached := false

func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	start_global_pos = global_position

func _gui_input(event):
	if attached:
		return

	if event is InputEventMouseButton:
		if event.pressed:
			dragging = true
			drag_offset = get_global_mouse_position() - global_position
			start_global_pos = global_position
		else:
			if dragging:
				dragging = false
				_try_attach()

func _process(_delta):
	if dragging:
		global_position = get_global_mouse_position() - drag_offset

func _try_attach():
	if global_position.distance_to(target_position) <= snap_distance:
		global_position = target_position
		attached = true
		set_process(false)   # permanently fixed
	else:
		global_position = start_global_pos
