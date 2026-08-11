class_name KickChannelService
extends RefCounted

const UPDATE_FIELDS: PackedStringArray = ["category_id", "custom_tags", "stream_title"]
var _api: KickApiClient


func _init(api: KickApiClient) -> void:
	_api = api


func get_current(cancellation: KickCancellationToken = null) -> KickApiResult:
	return KickModelMapper.map_result(await _api.invoke("channels.get", {}, {}, {}, false, "", cancellation), "channel")


func get_by_user_ids(user_ids: PackedStringArray, cancellation: KickCancellationToken = null) -> KickApiResult:
	if user_ids.is_empty() or user_ids.size() > 50:
		return _failed("Provide between 1 and 50 broadcaster user IDs")
	return KickModelMapper.map_result(await _api.invoke("channels.get", {"broadcaster_user_id": Array(user_ids)}, {}, {}, false, "", cancellation), "channel")


func get_by_slugs(slugs: PackedStringArray, cancellation: KickCancellationToken = null) -> KickApiResult:
	if slugs.is_empty() or slugs.size() > 50:
		return _failed("Provide between 1 and 50 channel slugs")
	for slug: String in slugs:
		if slug.is_empty() or slug.length() > 25:
			return _failed("Kick channel slugs must contain between 1 and 25 characters")
	return KickModelMapper.map_result(await _api.invoke("channels.get", {"slug": Array(slugs)}, {}, {}, false, "", cancellation), "channel")


func update(metadata: Dictionary, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	if metadata.is_empty():
		return _failed("At least one channel metadata field is required")
	for key: Variant in metadata:
		if str(key) not in UPDATE_FIELDS:
			return _failed("Unsupported channel metadata field: %s" % str(key))
	return await _api.invoke("channels.update", {}, {}, metadata, confirmed, "", cancellation)


func _failed(message: String) -> KickApiResult:
	var result: KickApiResult = KickApiResult.new()
	result.error = KickApiError.invalid(message)
	return result
