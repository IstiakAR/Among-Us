extends Node

func _ready() -> void:
	pass

var playing_online = 0
var player_name: String = "Player"
var player_color: Color = Color.WHITE

# Set at game start (host-authoritative) and used by gameplay scenes.
var imposter_peer_id: int = 0
var is_imposter: bool = false
