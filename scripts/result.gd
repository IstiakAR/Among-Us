extends Control

@export var imposter_won: bool = false

@onready var _bg: ColorRect = $ColorRect
@onready var _label: Label = $Label

func _ready() -> void:
	_apply_result_style()

func set_imposter_won(v: bool) -> void:
	imposter_won = v
	_apply_result_style()

func _apply_result_style() -> void:
	if _label == null or _bg == null:
		return
	if imposter_won:
		_label.text = "IMPOSTER WINS"
		_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
		_bg.color = Color(0.15, 0.0, 0.0, 1.0)
	else:
		_label.text = "CREWMATES SURVIVED"
		_label.add_theme_color_override("font_color", Color(0.3, 0.6, 1.0, 1.0))
		_bg.color = Color(0.0, 0.08, 0.16, 1.0)
