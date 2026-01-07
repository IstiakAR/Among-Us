extends TextureRect

var regions = ["Asia", "Europe", "NA"]

func _ready() -> void:
	if Globals.playing_online == 1:
		visible = true
	else:
		visible = false

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_region()

func _toggle_region() -> void:
	# Simply cycle through regions
	var current_index = regions.find(Globals.region)
	var next_index = (current_index + 1) % regions.size()
	Globals.region = regions[next_index]
	print("Region switched to: ", Globals.region)
