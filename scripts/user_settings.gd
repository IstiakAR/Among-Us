extends Control

@onready var name_edit: LineEdit = $LineEdit
@onready var color_grid: GridContainer = $ColorGrid

var _selected_swatch: ColorRect
var _selection_mark: Label


func _ready() -> void:
	_setup_selection_mark()
	_setup_name()
	_setup_swatches()
	_select_initial_swatch()


func _setup_selection_mark() -> void:
	_selection_mark = Label.new()
	_selection_mark.text = "✓"
	_selection_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selection_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_selection_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_mark.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _setup_name() -> void:
	if name_edit:
		name_edit.text = Globals.player_name
		name_edit.text_changed.connect(_on_name_changed)


func _setup_swatches() -> void:
	for child in color_grid.get_children():
		if child is ColorRect:
			var swatch := child as ColorRect
			swatch.mouse_filter = Control.MOUSE_FILTER_STOP
			swatch.gui_input.connect(_on_swatch_gui_input.bind(swatch))


func _select_initial_swatch() -> void:
	var target := Globals.player_color
	for child in color_grid.get_children():
		if child is ColorRect:
			var swatch := child as ColorRect
			if swatch.color.is_equal_approx(target):
				_select_swatch(swatch)
				return

	# Fallback: select the first swatch
	for child in color_grid.get_children():
		if child is ColorRect:
			_select_swatch(child as ColorRect)
			return


func _on_name_changed(new_text: String) -> void:
	Globals.player_name = new_text


func _on_swatch_gui_input(event: InputEvent, swatch: ColorRect) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_select_swatch(swatch)


func _select_swatch(swatch: ColorRect) -> void:
	_selected_swatch = swatch
	Globals.player_color = swatch.color

	if _selection_mark.get_parent():
		_selection_mark.get_parent().remove_child(_selection_mark)

	swatch.add_child(_selection_mark)
	_selection_mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selection_mark.offset_left = 0
	_selection_mark.offset_top = 0
	_selection_mark.offset_right = 0
	_selection_mark.offset_bottom = 0

	# Pick a readable checkmark color
	var c := swatch.color
	var luminance := (0.2126 * c.r) + (0.7152 * c.g) + (0.0722 * c.b)
	_selection_mark.add_theme_color_override("font_color", Color.BLACK if luminance > 0.6 else Color.WHITE)
