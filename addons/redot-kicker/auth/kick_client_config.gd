class_name KickClientConfig
extends RefCounted

var relay_base_url: String = ""
var application_id: String = ""
var publisher_id: String = ""
var authorization_timeout_msec: int = 300000
var helper_path_override: String = ""


func validate() -> KickApiError:
	if not _is_secure_endpoint(relay_base_url):
		return KickApiError.invalid("A developer-hosted HTTPS Kick relay URL is required")
	if not _is_safe_identifier(application_id) or not _is_safe_identifier(publisher_id):
		return KickApiError.invalid("Publisher and application IDs may contain only letters, digits, dot, underscore, and hyphen")
	if authorization_timeout_msec < 1000 or authorization_timeout_msec > 900000:
		return KickApiError.invalid("Authorization timeout must be between 1 second and 15 minutes")
	return null


func endpoint(path: String) -> String:
	return relay_base_url.trim_suffix("/") + "/" + path.trim_prefix("/")


func is_safe_relay_url(url: String) -> bool:
	var base: String = relay_base_url.trim_suffix("/")
	return url == base or url.begins_with(base + "/")


func credential_target(session_slot: String) -> String:
	return "redot-kicker/%s/%s/%s" % [publisher_id, application_id, session_slot]


func _is_secure_endpoint(endpoint_value: String) -> bool:
	return endpoint_value.begins_with("https://") or endpoint_value.begins_with("http://127.0.0.1:") or endpoint_value.begins_with("http://localhost:")


func _is_safe_identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(character):
			return false
	return true
