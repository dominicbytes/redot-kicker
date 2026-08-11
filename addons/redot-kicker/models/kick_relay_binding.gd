class_name KickRelayBinding
extends RefCounted

var tenant_id: String = ""
var application_id: String = ""
var channel_id: String = ""
var subscription_id: String = ""
var session_id: String = ""


func validate() -> String:
	for value: String in [tenant_id, application_id, channel_id, subscription_id, session_id]:
		if value.is_empty() or value.length() > 128:
			return "Relay binding fields must contain 1 to 128 characters"
		for character: String in value:
			if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(character):
				return "Relay binding fields contain an unsupported character"
	return ""


func to_dictionary() -> Dictionary:
	return {
		"tenant_id": tenant_id,
		"application_id": application_id,
		"channel_id": channel_id,
		"subscription_id": subscription_id,
		"session_id": session_id,
	}
