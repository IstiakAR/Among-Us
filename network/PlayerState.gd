extends Resource
class_name PlayerState

@export var peer_id: int = 0
@export var name: String = ""
@export var color_id: int = 0
@export var color: Color = Color.WHITE
@export var is_imposter: bool = false
@export var is_alive: bool = true
@export var position: Vector2 = Vector2.ZERO

func to_dict() -> Dictionary:
	return {
		"peer_id": peer_id,
		"name": name,
		"color_id": color_id,
		"color": color,
		"is_imposter": is_imposter,
		"is_alive": is_alive,
		"x": position.x,
		"y": position.y,
	}

static func from_dict(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.peer_id = int(d.get("peer_id", 0))
	p.name = str(d.get("name", ""))
	p.color_id = int(d.get("color_id", 0))
	var c: Variant = d.get("color", null)
	if typeof(c) == TYPE_COLOR:
		p.color = c as Color
	p.is_imposter = bool(d.get("is_imposter", false))
	p.is_alive = bool(d.get("is_alive", true))
	p.position = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
	return p
