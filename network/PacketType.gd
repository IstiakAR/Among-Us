extends Node
class_name PacketType

# Keep values stable once clients ship.
enum Type {
	HELLO = 1,
	WELCOME = 2,
	PING = 3,
	PONG = 4,
	PLAYER_JOIN = 10,
	PLAYER_LEAVE = 11,
	PLAYER_STATE = 12,
		PLAYER_KILL = 13,
	MEETING_START = 23,
	MEETING_END = 24,
		CHAT_MESSAGE = 40,
		VOTE = 41,
		TASK_COMPLETE = 42,
	GAME_STATE = 20,
	START_GAME = 21,
	END_GAME = 22,
	HOST_MIGRATION = 30,
	ERROR = 255,
}
