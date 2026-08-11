class_name KickApiError
extends RefCounted

var category: String = "unknown"
var message: String = "Unknown Kick integration error"
var http_status: int = 0
var transport_error: int = OK
var request_id: String = ""
var reasons: PackedStringArray = PackedStringArray()
var is_retryable: bool = false


static func from_transport(error_code: int, error_message: String) -> KickApiError:
	var value: KickApiError = KickApiError.new()
	value.category = "cancelled" if error_code == ERR_SKIP else "transport"
	value.message = error_message
	value.transport_error = error_code
	value.is_retryable = error_code not in [OK, ERR_SKIP, ERR_INVALID_PARAMETER, ERR_OUT_OF_MEMORY]
	return value


static func from_http(status_code: int, payload: Variant, response_request_id: String = "") -> KickApiError:
	var value: KickApiError = KickApiError.new()
	value.http_status = status_code
	value.request_id = response_request_id
	var source: Dictionary = payload if payload is Dictionary else {}
	var error_value: Variant = source.get("error", source)
	if error_value is Dictionary:
		source = error_value
	value.message = str(source.get("message", "Kick broker request failed with HTTP %d" % status_code))
	var errors_value: Variant = source.get("errors", source.get("data", []))
	if errors_value is Array:
		for item: Variant in errors_value:
			var reason: String = str(item.get("code", item.get("reason", ""))) if item is Dictionary else str(item)
			if not reason.is_empty() and not value.reasons.has(reason):
				value.reasons.append(reason)
	elif errors_value is Dictionary:
		for key: Variant in errors_value:
			value.reasons.append(str(key))
	value.category = _category_for(status_code)
	value.is_retryable = status_code in [408, 425, 429, 500, 502, 503, 504]
	return value


static func invalid(message_text: String) -> KickApiError:
	var value: KickApiError = KickApiError.new()
	value.category = "invalid_request"
	value.message = message_text
	value.transport_error = ERR_INVALID_PARAMETER
	return value


static func custom(category_name: String, message_text: String, retryable: bool = false) -> KickApiError:
	var value: KickApiError = KickApiError.new()
	value.category = category_name
	value.message = message_text
	value.is_retryable = retryable
	return value


static func _category_for(status_code: int) -> String:
	match status_code:
		400, 422:
			return "invalid_request"
		401:
			return "authorization"
		403:
			return "denied"
		404:
			return "not_found"
		408:
			return "timeout"
		409:
			return "conflict"
		425, 429:
			return "rate_limited"
		_:
			return "server_error" if status_code >= 500 else "unknown"
