class_name KickDataSanitizer
extends RefCounted

const SECRET_FIELDS: PackedStringArray = [
	"access_token",
	"authorization",
	"broker_session",
	"client_secret",
	"code_verifier",
	"refresh_token",
	"session_credential",
	"stream_key",
	"token",
]


static func sanitize(value: Variant, parent_key: String = "") -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key_value: Variant in value:
			var key: String = str(key_value)
			var normalized: String = key.to_lower()
			if normalized in SECRET_FIELDS:
				continue
			# Kick's channel stream object currently includes RTMP credentials. They
			# remain broker-side even when the upstream schema returns them.
			if parent_key == "stream" and normalized in ["key", "url"]:
				continue
			result[key_value] = sanitize(value[key_value], normalized)
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(sanitize(item, parent_key))
		return result
	return value
