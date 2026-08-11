class_name KickUser
extends RefCounted

var id: String = ""
var username: String = ""
var display_name: String = ""
var profile_picture_url: String = ""
var channel_slug: String = ""
var email: String = ""
var is_verified: bool = false
var is_anonymous: bool = false
var identity: Dictionary = {}


static func from_dictionary(source: Dictionary) -> KickUser:
	var value: KickUser = KickUser.new()
	value.id = _identifier(source.get("user_id", source.get("id", "")))
	value.username = str(source.get("username", source.get("name", "")))
	value.display_name = str(source.get("name", value.username))
	value.profile_picture_url = str(source.get("profile_picture", ""))
	value.channel_slug = str(source.get("channel_slug", ""))
	value.email = str(source.get("email", ""))
	value.is_verified = bool(source.get("is_verified", false))
	value.is_anonymous = bool(source.get("is_anonymous", false))
	var identity_value: Variant = source.get("identity", {})
	value.identity = (identity_value as Dictionary).duplicate(true) if identity_value is Dictionary else {}
	return value


static func _identifier(value: Variant) -> String:
	return str(int(value)) if value is float else str(value)
