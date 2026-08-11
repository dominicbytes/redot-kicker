class_name KickEventSubscription
extends RefCounted

var id: String = ""
var event_type: String = ""
var version: int = 0
var method: String = "webhook"
var broadcaster_user_id: String = ""
var application_id: String = ""
var created_at: String = ""
var updated_at: String = ""
var error_message: String = ""


static func from_dictionary(source: Dictionary) -> KickEventSubscription:
	var value: KickEventSubscription = KickEventSubscription.new()
	value.id = str(source.get("id", source.get("subscription_id", "")))
	value.event_type = str(source.get("event", source.get("name", "")))
	value.version = int(source.get("version", 0))
	value.method = str(source.get("method", "webhook"))
	var user_id: Variant = source.get("broadcaster_user_id", "")
	value.broadcaster_user_id = str(int(user_id)) if user_id is float else str(user_id)
	value.application_id = str(source.get("app_id", ""))
	value.created_at = str(source.get("created_at", ""))
	value.updated_at = str(source.get("updated_at", ""))
	value.error_message = str(source.get("error", ""))
	return value
