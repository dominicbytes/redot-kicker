class_name KickRedactor
extends RefCounted

## Adapted from redot-tuber's YouTubeRedactor at commit
## 029c22d7d5a5a68abacd8d12aabfea0b8e6536d8 (MIT).
const REDACTED: String = "[REDACTED]"
const OMITTED: String = "[OMITTED]"
const SECRET_KEYS: Array[String] = [
	"access_token",
	"authorization",
	"broker_session",
	"client_secret",
	"code",
	"code_verifier",
	"credential",
	"kick-event-signature",
	"refresh_token",
	"session_credential",
	"signature",
	"state",
	"token",
]
const PRIVATE_DATA_KEYS: Array[String] = [
	"body",
	"chat_message",
	"content",
	"payload",
	"raw_body",
	"user_input",
]


func redact_text(value: String) -> String:
	var result: String = value
	var bearer: RegEx = RegEx.new()
	bearer.compile("(?i)(authorization\\s*:\\s*bearer\\s+)[^\\s&]+")
	result = bearer.sub(result, "$1" + REDACTED, true)
	for key: String in SECRET_KEYS:
		var expression: RegEx = RegEx.new()
		expression.compile("(?i)([?&\\s]" + key + "\\s*[=:]\\s*)[^&\\s]+")
		result = expression.sub(result, "$1" + REDACTED, true)
	return result


func redact_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_value: Variant in source:
		var key: String = String(key_value)
		var value: Variant = source[key_value]
		if _matches_key(key, SECRET_KEYS):
			result[key_value] = REDACTED
		elif _matches_key(key, PRIVATE_DATA_KEYS):
			result[key_value] = OMITTED
		elif value is Dictionary:
			result[key_value] = redact_dictionary(value)
		elif value is Array:
			result[key_value] = _redact_array(value)
		else:
			result[key_value] = value
	return result


func _redact_array(source: Array) -> Array:
	var result: Array = []
	for value: Variant in source:
		if value is Dictionary:
			result.append(redact_dictionary(value))
		elif value is Array:
			result.append(_redact_array(value))
		else:
			result.append(value)
	return result


func _matches_key(key: String, candidates: Array[String]) -> bool:
	var normalized: String = key.to_lower()
	for candidate: String in candidates:
		if normalized == candidate or normalized.ends_with("_" + candidate):
			return true
	return false
