class_name KickCapabilityInfo
extends RefCounted

var id: String = ""
var capability: String = ""
var method: String = "GET"
var path: String = ""
var scopes: PackedStringArray = PackedStringArray()
var scope_mode: String = "all"
var token_kinds: PackedStringArray = PackedStringArray()
var is_write: bool = false
var requires_confirmation: bool = false
var requires_relay: bool = false
var is_deprecated: bool = false
var availability: String = "supported"


static func from_definition(operation_id: String, source: Dictionary) -> KickCapabilityInfo:
	var value: KickCapabilityInfo = KickCapabilityInfo.new()
	value.id = operation_id
	value.capability = str(source.get("capability", ""))
	value.method = str(source.get("method", "GET"))
	value.path = str(source.get("path", ""))
	value.scopes = _to_strings(source.get("scopes", []))
	value.scope_mode = str(source.get("scope_mode", "all"))
	value.token_kinds = _to_strings(source.get("token_kinds", []))
	value.is_write = bool(source.get("write", false))
	value.requires_confirmation = bool(source.get("confirm", false))
	value.requires_relay = bool(source.get("relay", false))
	value.is_deprecated = bool(source.get("deprecated", false))
	value.availability = str(source.get("availability", "supported"))
	return value


static func _to_strings(source: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if source is Array:
		for item: Variant in source:
			result.append(str(item))
	return result
