class_name KickSessionDescriptor
extends RefCounted

const SCHEMA_VERSION: int = 1

var session_slot: String = ""
var credential_target: String = ""
var relay_base_url: String = ""
var tenant_id: String = ""
var application_id: String = ""
var session_id: String = ""
var user_id: String = ""
var username: String = ""
var channel_id: String = ""
var channel_slug: String = ""
var granted_capabilities: PackedStringArray = PackedStringArray()
var granted_scopes: PackedStringArray = PackedStringArray()
var subscription_ids: PackedStringArray = PackedStringArray()
var broker_session_expires_at_unix: int = 0
var saved_at_unix: int = 0


func to_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"session_slot": session_slot,
		"credential_target": credential_target,
		"relay_base_url": relay_base_url,
		"tenant_id": tenant_id,
		"application_id": application_id,
		"session_id": session_id,
		"identity": {"user_id": user_id, "username": username},
		"channel": {"id": channel_id, "slug": channel_slug},
		"granted_capabilities": Array(granted_capabilities),
		"granted_scopes": Array(granted_scopes),
		"subscription_ids": Array(subscription_ids),
		"broker_session_expires_at_unix": broker_session_expires_at_unix,
		"saved_at_unix": saved_at_unix if saved_at_unix > 0 else int(Time.get_unix_time_from_system()),
	}


static func from_dictionary(source: Dictionary) -> KickSessionDescriptor:
	if int(source.get("schema_version", 0)) != SCHEMA_VERSION:
		return null
	var value: KickSessionDescriptor = KickSessionDescriptor.new()
	value.session_slot = str(source.get("session_slot", ""))
	value.credential_target = str(source.get("credential_target", ""))
	value.relay_base_url = str(source.get("relay_base_url", ""))
	value.tenant_id = str(source.get("tenant_id", ""))
	value.application_id = str(source.get("application_id", ""))
	value.session_id = str(source.get("session_id", ""))
	var identity: Variant = source.get("identity", {})
	if identity is Dictionary:
		value.user_id = str(identity.get("user_id", ""))
		value.username = str(identity.get("username", ""))
	var channel: Variant = source.get("channel", {})
	if channel is Dictionary:
		value.channel_id = str(channel.get("id", ""))
		value.channel_slug = str(channel.get("slug", ""))
	value.granted_capabilities = _to_strings(source.get("granted_capabilities", []))
	value.granted_scopes = _to_strings(source.get("granted_scopes", []))
	value.subscription_ids = _to_strings(source.get("subscription_ids", []))
	value.broker_session_expires_at_unix = int(source.get("broker_session_expires_at_unix", 0))
	value.saved_at_unix = int(source.get("saved_at_unix", 0))
	return value


static func _to_strings(source: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if source is Array:
		for item: Variant in source:
			result.append(str(item))
	return result
