extends Node
class_name HostMigrationManager

signal migration_announced(info: Dictionary)
signal migration_needed

var last_announced: Dictionary = {}

func announce_new_host(new_host_ip: String, new_host_port: int, new_host_peer_id: int) -> NetPacket:
	last_announced = {
		"ip": new_host_ip,
		"port": new_host_port,
		"peer_id": new_host_peer_id,
	}
	emit_signal("migration_announced", last_announced)
	return NetPacket.new(PacketType.Type.HOST_MIGRATION, last_announced)

func handle_packet(packet: NetPacket) -> void:
	if packet.type != PacketType.Type.HOST_MIGRATION:
		return
	last_announced = {
		"ip": str(packet.payload.get("ip", "")),
		"port": int(packet.payload.get("port", 0)),
		"peer_id": int(packet.payload.get("peer_id", 0)),
	}
	emit_signal("migration_announced", last_announced)

func on_host_disconnected() -> void:
	emit_signal("migration_needed")
