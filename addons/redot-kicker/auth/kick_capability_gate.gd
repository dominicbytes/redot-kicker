class_name KickCapabilityGate
extends RefCounted

var _capabilities: PackedStringArray = PackedStringArray()
var _scopes: PackedStringArray = PackedStringArray()
var _authenticated: bool = false
var _relay_available: bool = false


func configure(capabilities: PackedStringArray, scopes: PackedStringArray, authenticated: bool, relay_available: bool) -> void:
	_capabilities = capabilities.duplicate()
	_scopes = scopes.duplicate()
	_authenticated = authenticated
	_relay_available = relay_available


func clear() -> void:
	_capabilities.clear()
	_scopes.clear()
	_authenticated = false
	_relay_available = false


func has_capability(capability: String) -> bool:
	return _capabilities.has(capability)


func require_operation(operation_id: String, confirmed: bool = false) -> KickApiError:
	var info: KickCapabilityInfo = KickCapabilityRegistry.operation_info(operation_id)
	if info == null:
		return KickApiError.invalid("Unknown Kick operation: %s" % operation_id)
	if info.availability != "supported":
		return KickApiError.custom("unavailable", "Kick operation is unavailable: %s" % info.availability)
	if not _authenticated and not info.token_kinds.has("none"):
		return KickApiError.custom("authorization", "A connected Kick account is required")
	if not info.capability.is_empty() and not _capabilities.has(info.capability):
		return KickApiError.custom("capability_missing", "Kick capability is not granted: %s" % info.capability)
	if info.requires_relay and not _relay_available:
		return KickApiError.custom("relay_unavailable", "This Kick operation requires a healthy relay")
	if not _has_required_scopes(info):
		return KickApiError.custom("scope_missing", "The connected Kick session lacks a required scope")
	if info.requires_confirmation and not confirmed:
		return KickApiError.custom("confirmation_required", "This Kick action requires explicit confirmation")
	return null


func capabilities() -> PackedStringArray:
	return _capabilities.duplicate()


func scopes() -> PackedStringArray:
	return _scopes.duplicate()


func _has_required_scopes(info: KickCapabilityInfo) -> bool:
	if info.scopes.is_empty():
		return true
	if info.scope_mode == "any":
		for scope: String in info.scopes:
			if _scopes.has(scope):
				return true
		return false
	for scope: String in info.scopes:
		if not _scopes.has(scope):
			return false
	return true
