class_name KickCategoryService
extends RefCounted

var _api: KickApiClient


func _init(api: KickApiClient) -> void:
	_api = api


func list(
	cursor: String = "",
	limit: int = 25,
	names: PackedStringArray = PackedStringArray(),
	tags: PackedStringArray = PackedStringArray(),
	ids: PackedStringArray = PackedStringArray(),
	cancellation: KickCancellationToken = null
) -> KickApiPage:
	if limit < 1 or limit > 1000:
		return _failed_page("Category page limit must be between 1 and 1000")
	var query: Dictionary = {"limit": limit}
	if not cursor.is_empty(): query["cursor"] = cursor
	if not names.is_empty(): query["name"] = Array(names)
	if not tags.is_empty(): query["tag"] = Array(tags)
	if not ids.is_empty(): query["id"] = Array(ids)
	var result: KickApiResult = KickModelMapper.map_result(await _api.invoke("categories.search.v2", query, {}, {}, false, "", cancellation), "category")
	return KickModelMapper.to_page(result)


func search_deprecated(query_text: String, page: int = 1, cancellation: KickCancellationToken = null) -> KickApiResult:
	if query_text.is_empty() or page < 1:
		return _failed("A category search query and positive page are required")
	return KickModelMapper.map_result(await _api.invoke("categories.search.v1", {"q": query_text, "page": page}, {}, {}, false, "", cancellation), "category")


func get_deprecated(category_id: String, cancellation: KickCancellationToken = null) -> KickApiResult:
	if category_id.is_empty():
		return _failed("Category ID is required")
	return KickModelMapper.map_result(await _api.invoke("categories.get.v1", {}, {"category_id": category_id}, {}, false, "", cancellation), "category")


func _failed(message: String) -> KickApiResult:
	var result: KickApiResult = KickApiResult.new()
	result.error = KickApiError.invalid(message)
	return result


func _failed_page(message: String) -> KickApiPage:
	var page: KickApiPage = KickApiPage.new()
	page.error = KickApiError.invalid(message)
	return page
