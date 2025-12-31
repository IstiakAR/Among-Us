extends Control

@onready var keypad_image = $TextureRect
@onready var input_label = $Label
@onready var secret_label = $Label2

var entered_code := ""
var max_length := 6

# 5 rows × 3 columns
const KEYS = [
	["",  "",  ""],      # display row (ignored)
	["1", "2", "3"],
	["4", "5", "6"],
	["7", "8", "9"],
	["X", "0", "OK"]
]

func _ready():
	randomize()
	generate_secret_key()
	input_label.text = ""
	keypad_image.mouse_filter = Control.MOUSE_FILTER_STOP
	keypad_image.gui_input.connect(_on_keypad_gui_input)
	visible = false
func _on_keypad_gui_input(event):
	if not visible:
		return

	if event is InputEventMouseButton and event.pressed:
		var local_pos = keypad_image.get_local_mouse_position()
		handle_keypad_click(local_pos)

# -------------------------
# RANDOM SECRET KEY
# -------------------------
func generate_secret_key():
	var key := ""
	for i in range(max_length):
		key += str(randi() % 10)
	secret_label.text = key
	# secret_label.visible = false

func start_task() -> void:
	visible = true
	clear_input()
	generate_secret_key()

# -------------------------
# KEY DETECTION (5×3)
# -------------------------
func handle_keypad_click(pos: Vector2):
	var size = keypad_image.size
	var cols = 3
	var rows = 5

	var cell_w = size.x / cols
	var cell_h = size.y / rows

	var col = int(pos.x / cell_w)
	var row = int(pos.y / cell_h)

	if row < 0 or row >= rows or col < 0 or col >= cols:
		return

	var key = KEYS[row][col]

	if key == "":
		return   # ignore display area

	match key:
		"X":
			clear_input()
		"OK":
			complete_task()
		_:
			press_number(key)

# -------------------------
# INPUT LOGIC
# -------------------------
func press_number(num: String):
	if entered_code.length() >= max_length:
		return
	entered_code += num
	input_label.text = entered_code

func clear_input():
	entered_code = ""
	input_label.text = ""

func complete_task() -> void:
	if entered_code == secret_label.text:
		input_label.text = "OK"
	else:
		input_label.text = "ERR"
	await get_tree().create_timer(0.5).timeout
	_close_self()

func _close_self() -> void:
	visible = false
	TaskManager.complete_task()
	
