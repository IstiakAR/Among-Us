extends TextureRect

@export var player: Node2D          # Player node Inspector থেকে assign করবে
@export var highlight_distance := 80.0
@export var border_color := Color(1, 1, 0) # yellow
@export var border_width := 3.0

var show_border := false

func _process(_delta):
	if player == null:
		return

	# TextureRect-এর center (screen/world-safe)
	var rect := get_global_rect()
	var task_center := rect.position + rect.size * 0.5

	# Player position (world)
	var player_pos := player.global_position

	# Distance check
	show_border = task_center.distance_to(player_pos) <= highlight_distance
	queue_redraw()

func _draw():
	if show_border:
		draw_rect(
			Rect2(Vector2.ZERO, size),
			border_color,
			false,
			border_width
		)
