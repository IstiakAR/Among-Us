extends Control

@onready var create_panel = $BoxArea/CreatePanel
@onready var join_panel   = $BoxArea/JoinPanel
@onready var code_panel   = $BoxArea/CodePanel

@onready var label_create = $create
@onready var label_join   = $join
@onready var label_code   = $code

func _ready():
	for label in [label_create, label_join, label_code]:
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.connect("gui_input", Callable(self, "_on_label_click").bind(label))
	
	_show_panel(join_panel)

func _on_label_click(event: InputEvent, label) -> void:  # no type
	if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		match label:
			label_create:
				_show_panel(create_panel)
			label_join:
				_show_panel(join_panel)
			label_code:
				_show_panel(code_panel)


func _show_panel(panel_to_show: Control) -> void:
	for panel in [create_panel, join_panel, code_panel]:
		panel.visible = panel == panel_to_show
