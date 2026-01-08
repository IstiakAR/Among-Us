extends Node

func _ready() -> void:
	pass

var playing_online = 0
var player_name: String = "Player"
var player_color: Color = Color.WHITE

var region: String = "Asia"

var imposter_peer_id: int = 0
var is_imposter: bool = false
var imposters_count: int = 1
var room_code: String = ""
var imposter_peer_ids: Array[int] = []
