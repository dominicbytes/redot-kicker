class_name KickModerationService
extends RefCounted

var _api: KickApiClient


func _init(api: KickApiClient) -> void:
	_api = api


func ban(broadcaster_user_id: String, user_id: String, reason: String, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	return await _ban_or_timeout(broadcaster_user_id, user_id, reason, 0, confirmed, cancellation)


func timeout(broadcaster_user_id: String, user_id: String, duration_minutes: int, reason: String, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	if duration_minutes < 1 or duration_minutes > 10080:
		return _failed("Timeout duration must be between 1 and 10080 minutes")
	return await _ban_or_timeout(broadcaster_user_id, user_id, reason, duration_minutes, confirmed, cancellation)


func unban(broadcaster_user_id: String, user_id: String, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	if broadcaster_user_id.is_empty() or user_id.is_empty():
		return _failed("Broadcaster and target user IDs are required")
	return await _api.invoke("moderation.unban", {}, {}, {"broadcaster_user_id": broadcaster_user_id, "user_id": user_id}, confirmed, "", cancellation)


func _ban_or_timeout(broadcaster_user_id: String, user_id: String, reason: String, duration: int, confirmed: bool, cancellation: KickCancellationToken) -> KickApiResult:
	if broadcaster_user_id.is_empty() or user_id.is_empty() or reason.length() > 100:
		return _failed("Broadcaster and target IDs are required; reason must not exceed 100 characters")
	var body: Dictionary = {"broadcaster_user_id": broadcaster_user_id, "user_id": user_id}
	if not reason.is_empty(): body["reason"] = reason
	if duration > 0: body["duration"] = duration
	return await _api.invoke("moderation.ban", {}, {}, body, confirmed, "", cancellation)


func _failed(message: String) -> KickApiResult:
	var result: KickApiResult = KickApiResult.new()
	result.error = KickApiError.invalid(message)
	return result
