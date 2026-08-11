class_name KickIdentityService
extends RefCounted

var _api: KickApiClient


func _init(api: KickApiClient) -> void:
	_api = api


func get_current(cancellation: KickCancellationToken = null) -> KickApiResult:
	return KickModelMapper.map_result(await _api.invoke("users.get", {}, {}, {}, false, "", cancellation), "user")


func get_users(user_ids: PackedStringArray, cancellation: KickCancellationToken = null) -> KickApiResult:
	if user_ids.is_empty() or user_ids.size() > 50:
		return _failed("Provide between 1 and 50 Kick user IDs")
	return KickModelMapper.map_result(await _api.invoke("users.get", {"id": Array(user_ids)}, {}, {}, false, "", cancellation), "user")


func introspect(cancellation: KickCancellationToken = null) -> KickApiResult:
	return await _api.invoke("token.introspect", {}, {}, {}, false, "", cancellation)


func _failed(message: String) -> KickApiResult:
	var result: KickApiResult = KickApiResult.new()
	result.error = KickApiError.invalid(message)
	return result
