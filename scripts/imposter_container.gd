extends HBoxContainer

var labels: Array[Label] = []
var default_color: Color = Color.WHITE
var selected_color: Color = Color.SEA_GREEN

func _ready():
	labels = [
		$imp1,
		$imp2,
		$imp3
	]
	for label in labels:
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		label.connect("gui_input", Callable(self, "_on_label_click").bind(label))

func _on_label_click(event: InputEvent, label: Label) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		for l in labels:
			l.modulate = default_color
		label.modulate = selected_color
		# Update imposters_count in Globals based on selected label.
		var idx := labels.find(label)
		if idx >= 0:
			# labels index 0..2 corresponds to 1..3 imposters
			Globals.imposters_count = idx + 1
