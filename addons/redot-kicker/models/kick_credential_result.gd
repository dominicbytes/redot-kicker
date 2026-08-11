class_name KickCredentialResult
extends RefCounted

var status: String = "protocol_error"
var secret: String = ""
var detail: String = ""
var error: KickApiError = null


func is_success() -> bool:
	return status == "ok" and error == null


func clear_secret() -> void:
	secret = ""
