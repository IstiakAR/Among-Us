extends HBoxContainer

@onready var value_label = $ValueLabel
var value: int = 10
var min_value: int = 1
var max_value: int = 15

func _ready():
	$DButton.pressed.connect(_on_decrease_pressed)
	$IButton.pressed.connect(_on_increase_pressed)
	_update()

func _on_decrease_pressed():
	value = max(min_value, value - 1)
	_update()

func _on_increase_pressed():
	value = min(max_value, value + 1)
	_update()

func _update():
	value_label.text = "%02d" % value
