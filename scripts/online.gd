extends TextureButton

func _ready() -> void:
	if not is_connected("pressed", Callable(self, "_on_texture_button_pressed")):
		connect("pressed", Callable(self, "_on_texture_button_pressed"))

func _on_texture_button_pressed():
	Globals.playing_online = 1
	get_tree().change_scene_to_file("res://scenes/GameSelection.tscn")
