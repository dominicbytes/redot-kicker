class_name KickRewardService
extends RefCounted

const CREATE_FIELDS: PackedStringArray = ["background_color", "cost", "description", "is_enabled", "is_user_input_required", "should_redemptions_skip_request_queue", "title"]
const UPDATE_FIELDS: PackedStringArray = ["background_color", "cost", "description", "is_enabled", "is_paused", "is_user_input_required", "should_redemptions_skip_request_queue", "title"]

var _api: KickApiClient


func _init(api: KickApiClient) -> void:
	_api = api


func list(cancellation: KickCancellationToken = null) -> KickApiResult:
	return KickModelMapper.map_result(await _api.invoke("rewards.list", {}, {}, {}, false, "", cancellation), "reward")


func create(reward: Dictionary, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	var validation: KickApiError = _validate_fields(reward, CREATE_FIELDS, true)
	if validation != null: return _failed(validation)
	return KickModelMapper.map_result(await _api.invoke("rewards.create", {}, {}, reward, confirmed, "", cancellation), "reward")


func update(reward_id: String, changes: Dictionary, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	if reward_id.is_empty(): return _failed(KickApiError.invalid("Reward ID is required"))
	var validation: KickApiError = _validate_fields(changes, UPDATE_FIELDS, false)
	if validation != null: return _failed(validation)
	return KickModelMapper.map_result(await _api.invoke("rewards.update", {}, {"id": reward_id}, changes, confirmed, "", cancellation), "reward")


func delete(reward_id: String, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	if reward_id.is_empty(): return _failed(KickApiError.invalid("Reward ID is required"))
	return await _api.invoke("rewards.delete", {}, {"id": reward_id}, {}, confirmed, "", cancellation)


func list_redemptions(reward_id: String = "", status: String = "pending", ids: PackedStringArray = PackedStringArray(), cursor: String = "", cancellation: KickCancellationToken = null) -> KickApiPage:
	if status not in ["pending", "accepted", "rejected"]:
		return _failed_page("Redemption status must be pending, accepted, or rejected")
	if not ids.is_empty() and (not reward_id.is_empty() or status != "pending" or not cursor.is_empty()):
		return _failed_page("Redemption ID filtering cannot be combined with other filters")
	var query: Dictionary = {}
	if not ids.is_empty(): query["id"] = Array(ids)
	else:
		if not reward_id.is_empty(): query["reward_id"] = reward_id
		query["status"] = status
		if not cursor.is_empty(): query["cursor"] = cursor
	var result: KickApiResult = KickModelMapper.map_result(await _api.invoke("redemptions.list", query, {}, {}, false, "", cancellation), "redemption_page")
	return KickModelMapper.to_page(result)


func accept(redemption_ids: PackedStringArray, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	return await _change_redemptions("redemptions.accept", redemption_ids, confirmed, cancellation)


func reject(redemption_ids: PackedStringArray, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	return await _change_redemptions("redemptions.reject", redemption_ids, confirmed, cancellation)


func _change_redemptions(operation_id: String, ids: PackedStringArray, confirmed: bool, cancellation: KickCancellationToken) -> KickApiResult:
	if ids.is_empty() or ids.size() > 25:
		return _failed(KickApiError.invalid("Provide between 1 and 25 unique redemption IDs"))
	var unique: Dictionary = {}
	for id_value: String in ids:
		if id_value.is_empty() or unique.has(id_value):
			return _failed(KickApiError.invalid("Redemption IDs must be non-empty and unique"))
		unique[id_value] = true
	return await _api.invoke(operation_id, {}, {}, {"ids": Array(ids)}, confirmed, "", cancellation)


func _validate_fields(value: Dictionary, allowed: PackedStringArray, require_title_cost: bool) -> KickApiError:
	if value.is_empty(): return KickApiError.invalid("Reward data is required")
	for key: Variant in value:
		if str(key) not in allowed: return KickApiError.invalid("Unsupported reward field: %s" % str(key))
	if require_title_cost and (str(value.get("title", "")).is_empty() or int(value.get("cost", 0)) < 1):
		return KickApiError.invalid("Reward title and positive cost are required")
	return null


func _failed(error: KickApiError) -> KickApiResult:
	var result: KickApiResult = KickApiResult.new()
	result.error = error
	return result


func _failed_page(message: String) -> KickApiPage:
	var page: KickApiPage = KickApiPage.new()
	page.error = KickApiError.invalid(message)
	return page
