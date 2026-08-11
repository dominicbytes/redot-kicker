class_name KickLivestreamService
extends RefCounted

var _api: KickApiClient


func _init(api: KickApiClient) -> void:
	_api = api


func list(
	category_ids: PackedStringArray = PackedStringArray(),
	language_codes: PackedStringArray = PackedStringArray(),
	limit: int = 100,
	cursor: String = "",
	cancellation: KickCancellationToken = null
) -> KickApiPage:
	if category_ids.size() > 25 or language_codes.size() > 25 or limit < 1 or limit > 1000:
		return _failed_page("Livestream filters exceed Kick's documented limits")
	var query: Dictionary = {"limit": limit}
	if not category_ids.is_empty(): query["category_id"] = Array(category_ids)
	if not language_codes.is_empty(): query["language_code"] = Array(language_codes)
	if not cursor.is_empty(): query["cursor"] = cursor
	var result: KickApiResult = KickModelMapper.map_result(await _api.invoke("livestreams.list.v2", query, {}, {}, false, "", cancellation), "livestream")
	return KickModelMapper.to_page(result)


func get_by_user_ids(user_ids: PackedStringArray, cancellation: KickCancellationToken = null) -> KickApiResult:
	if user_ids.is_empty() or user_ids.size() > 100:
		return _failed("Provide between 1 and 100 broadcaster user IDs")
	return KickModelMapper.map_result(await _api.invoke("livestreams.by_users", {"user_id": Array(user_ids)}, {}, {}, false, "", cancellation), "livestream")


func stats(cancellation: KickCancellationToken = null) -> KickApiResult:
	return await _api.invoke("livestreams.stats", {}, {}, {}, false, "", cancellation)


func list_deprecated(filters: Dictionary = {}, cancellation: KickCancellationToken = null) -> KickApiResult:
	return KickModelMapper.map_result(await _api.invoke("livestreams.list.v1", filters, {}, {}, false, "", cancellation), "livestream")


func _failed(message: String) -> KickApiResult:
	var result: KickApiResult = KickApiResult.new()
	result.error = KickApiError.invalid(message)
	return result


func _failed_page(message: String) -> KickApiPage:
	var page: KickApiPage = KickApiPage.new()
	page.error = KickApiError.invalid(message)
	return page
