extends TextureButton

func _ready() -> void:
	if not is_connected("pressed", Callable(self, "_on_texture_button_pressed")):
		connect("pressed", Callable(self, "_on_texture_button_pressed"))

func _on_texture_button_pressed() -> void:
	Globals.playing_online = 0
	if is_inside_tree() and get_tree() != null:
		get_tree().change_scene_to_file("res://scenes/User_Settings.tscn")
