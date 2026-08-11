class_name KickAuthResult
extends RefCounted

var descriptor: KickSessionDescriptor = null
var broker_session: String = ""
var restored: bool = false
var pending: bool = false
var error: KickApiError = null


func is_success() -> bool:
	return error == null and not pending and descriptor != null


func clear_broker_session() -> void:
	broker_session = ""
