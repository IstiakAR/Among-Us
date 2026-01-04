extends Resource
class_name GameState

@export var started: bool = false
@export var phase: String = "lobby" # lobby|playing|meeting|ended
@export var seed: int = 0
@export var players: Dictionary = {} # peer_id -> Dictionary (PlayerState.to_dict())

func to_dict() -> Dictionary:
	return {
		"started": started,
		"phase": phase,
		"seed": seed,
		"players": players,
	}

static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.started = bool(d.get("started", false))
	s.phase = str(d.get("phase", "lobby"))
	s.seed = int(d.get("seed", 0))
	s.players = d.get("players", {})
	return s
