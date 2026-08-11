class_name KickRelayResult
extends RefCounted

var status: String = "rejected"
var code: String = "unknown"
var message: String = "Relay event was rejected"
var envelope: Dictionary = {}


func is_accepted() -> bool:
	return status == "accepted" or status == "unknown_event"


func is_unknown_event() -> bool:
	return status == "unknown_event"


static func reject(reason_code: String, safe_message: String) -> KickRelayResult:
	var result: KickRelayResult = KickRelayResult.new()
	result.code = reason_code
	result.message = safe_message
	return result


static func accept(value: Dictionary, unknown: bool = false) -> KickRelayResult:
	var result: KickRelayResult = KickRelayResult.new()
	result.status = "unknown_event" if unknown else "accepted"
	result.code = "unknown_event" if unknown else "accepted"
	result.message = "Authenticated event uses an unknown type or version" if unknown else "Authenticated event accepted"
	result.envelope = value
	return result
