class_name KickCredentialProtocol
extends RefCounted

## Adapted from redot-tuber's RTCH/1 credential protocol at commit
## 029c22d7d5a5a68abacd8d12aabfea0b8e6536d8 (MIT).
const HEADER: String = "RKCH/1"
const MAX_TARGET_BYTES: int = 512
const MAX_SECRET_BYTES: int = 4096
const VALID_COMMANDS: Array[String] = ["ping", "store", "read", "delete"]


func encode_request(command: String, target: String = "", secret: String = "") -> String:
	if not VALID_COMMANDS.has(command):
		return ""
	var target_bytes: PackedByteArray = target.to_utf8_buffer()
	var secret_bytes: PackedByteArray = secret.to_utf8_buffer()
	if target_bytes.size() > MAX_TARGET_BYTES or secret_bytes.size() > MAX_SECRET_BYTES:
		return ""
	return "%s\n%s\n%s\n%s\n" % [
		HEADER,
		command,
		_encode_base64(target_bytes),
		_encode_base64(secret_bytes),
	]


func decode_response(wire: String) -> KickCredentialResult:
	var result: KickCredentialResult = KickCredentialResult.new()
	var lines: PackedStringArray = wire.replace("\r", "").split("\n", true)
	if lines.size() < 4 or lines[0] != HEADER:
		result.status = "protocol_error"
		result.error = KickApiError.from_transport(ERR_INVALID_DATA, "Credential helper protocol mismatch")
		return result
	result.status = lines[1].to_lower()
	result.detail = lines[3]
	if result.status == "ok" and not lines[2].is_empty():
		var decoded: PackedByteArray = Marshalls.base64_to_raw(lines[2])
		if decoded.size() > MAX_SECRET_BYTES:
			result.status = "protocol_error"
			result.error = KickApiError.from_transport(ERR_OUT_OF_MEMORY, "Credential helper response exceeds the secret limit")
			return result
		result.secret = decoded.get_string_from_utf8()
	elif result.status not in ["ok", "not_found", "unavailable", "locked", "denied"]:
		result.status = "protocol_error"
	if result.status != "ok" and result.status != "not_found":
		result.error = KickApiError.from_transport(ERR_CANT_ACQUIRE_RESOURCE, "OS credential store is %s" % result.status)
		result.error.category = result.status
	return result


func decode_request_for_test(wire: String) -> Dictionary:
	var lines: PackedStringArray = wire.replace("\r", "").split("\n", true)
	if lines.size() < 4 or lines[0] != HEADER:
		return {}
	return {
		"version": 1,
		"command": lines[1],
		"target": Marshalls.base64_to_raw(lines[2]).get_string_from_utf8(),
		"secret": Marshalls.base64_to_raw(lines[3]).get_string_from_utf8(),
	}


func _encode_base64(bytes: PackedByteArray) -> String:
	return "" if bytes.is_empty() else Marshalls.raw_to_base64(bytes)
