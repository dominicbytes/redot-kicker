class_name KickAuthorizationRequest
extends RefCounted

var request_id: String = ""
var authorization_url: String = ""
var expires_at_unix: int = 0
var poll_interval_msec: int = 1000
var error: KickApiError = null


func is_success() -> bool:
	return error == null and not request_id.is_empty() and not authorization_url.is_empty()
