extends TextureButton

func _ready() -> void:
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)

func _on_pressed() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.change_scene_to_file("res://scenes/Main_Menu.tscn")
