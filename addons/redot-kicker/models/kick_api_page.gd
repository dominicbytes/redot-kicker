class_name KickApiPage
extends RefCounted

var items: Array = []
var next_cursor: String = ""
var error: KickApiError = null
var http_status: int = 0
var request_id: String = ""


func is_success() -> bool:
	return error == null and http_status >= 200 and http_status < 300
