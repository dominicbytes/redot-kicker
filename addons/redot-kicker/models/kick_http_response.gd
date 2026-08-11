class_name KickHttpResponse
extends RefCounted

var request_result: int = HTTPRequest.RESULT_SUCCESS
var status_code: int = 0
var headers: PackedStringArray = PackedStringArray()
var body: PackedByteArray = PackedByteArray()
var parsed_json: Variant = null
var attempt_count: int = 0
var elapsed_msec: int = 0
var error: KickApiError = null


func is_success() -> bool:
	return request_result == HTTPRequest.RESULT_SUCCESS and status_code >= 200 and status_code < 300 and error == null


func body_text() -> String:
	return body.get_string_from_utf8()


func header(name: String) -> String:
	var expected: String = name.to_lower()
	for line: String in headers:
		var separator: int = line.find(":")
		if separator > 0 and line.substr(0, separator).strip_edges().to_lower() == expected:
			return line.substr(separator + 1).strip_edges()
	return ""


func retry_after_seconds() -> float:
	var value: String = header("retry-after")
	return float(value) if value.is_valid_float() else 0.0


func clear_body() -> void:
	body.clear()
	parsed_json = null
