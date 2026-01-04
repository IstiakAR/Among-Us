extends RefCounted
class_name NetPacket

const PROTOCOL_VERSION := 1

var type: int
var seq: int
var payload: Dictionary

func _init(p_type: int = 0, p_payload: Dictionary = {}, p_seq: int = 0) -> void:
	type = p_type
	payload = p_payload
	seq = p_seq

func to_bytes() -> PackedByteArray:
	# Only built-in Variant types. No Objects/Resources.
	var obj := {
		"v": PROTOCOL_VERSION,
		"t": type,
		"s": seq,
		"p": payload,
	}
	return var_to_bytes(obj)

static func from_bytes(data: PackedByteArray) -> NetPacket:
	var obj = bytes_to_var(data)
	if typeof(obj) != TYPE_DICTIONARY:
		return NetPacket.new(PacketType.Type.ERROR, {"reason": "decode_failed"})

	var v := int(obj.get("v", 0))
	if v != PROTOCOL_VERSION:
		return NetPacket.new(PacketType.Type.ERROR, {"reason": "bad_protocol", "v": v})

	var p := NetPacket.new()
	p.type = int(obj.get("t", 0))
	p.seq = int(obj.get("s", 0))
	p.payload = obj.get("p", {})
	return p

static func pack_frame(payload_bytes: PackedByteArray) -> PackedByteArray:
	# Big-endian u32 length prefix.
	var size := payload_bytes.size()
	var frame := PackedByteArray()
	frame.resize(4 + size)
	frame[0] = (size >> 24) & 0xFF
	frame[1] = (size >> 16) & 0xFF
	frame[2] = (size >> 8) & 0xFF
	frame[3] = size & 0xFF
	for i in range(size):
		frame[4 + i] = payload_bytes[i]
	return frame

static func try_unpack_frames(buffer: PackedByteArray) -> Dictionary:
	# Returns {"frames": Array[PackedByteArray], "remaining": PackedByteArray}
	var frames: Array[PackedByteArray] = []
	var offset := 0
	while buffer.size() - offset >= 4:
		var b0 := int(buffer[offset])
		var b1 := int(buffer[offset + 1])
		var b2 := int(buffer[offset + 2])
		var b3 := int(buffer[offset + 3])
		var size := (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
		if size < 0:
			break
		if buffer.size() - offset < 4 + size:
			break
		var start := offset + 4
		var end := start + size
		frames.append(buffer.slice(start, end))
		offset = end
	var remaining := buffer.slice(offset, buffer.size())
	return {"frames": frames, "remaining": remaining}
