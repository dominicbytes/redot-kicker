class_name KickApiResult
extends RefCounted

var data: Variant = null
var message: String = ""
var pagination: Dictionary = {}
var error: KickApiError = null
var http_status: int = 0
var request_id: String = ""
var rate_limit_remaining: int = -1
var rate_limit_reset_unix: int = 0
var retry_after_seconds: float = 0.0


func is_success() -> bool:
	return error == null and http_status >= 200 and http_status < 300
