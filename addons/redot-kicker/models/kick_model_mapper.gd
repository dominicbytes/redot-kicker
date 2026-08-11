class_name KickModelMapper
extends RefCounted


static func map_result(result: KickApiResult, kind: String) -> KickApiResult:
	if result == null or result.error != null:
		return result
	match kind:
		"user":
			result.data = _map_array_or_single(result.data, KickUser.from_dictionary)
		"channel":
			result.data = _map_array_or_single(result.data, KickChannel.from_dictionary)
		"category":
			result.data = _map_array_or_single(result.data, KickCategory.from_dictionary)
		"livestream":
			result.data = _map_array_or_single(result.data, KickLivestream.from_dictionary)
		"reward":
			result.data = _map_array_or_single(result.data, KickReward.from_dictionary)
		"redemption_page":
			result.data = _map_redemption_groups(result.data)
		"event_subscription":
			result.data = _map_array_or_single(result.data, KickEventSubscription.from_dictionary)
		"chat_receipt":
			result.data = KickChatReceipt.from_dictionary(result.data) if result.data is Dictionary else null
		"kicks_leaderboard":
			result.data = KickKicksLeaderboard.from_dictionary(result.data) if result.data is Dictionary else null
	return result


static func to_page(result: KickApiResult) -> KickApiPage:
	var page: KickApiPage = KickApiPage.new()
	if result == null:
		page.error = KickApiError.custom("transport", "Kick request returned no result", true)
		return page
	page.error = result.error
	page.http_status = result.http_status
	page.request_id = result.request_id
	page.items = result.data if result.data is Array else ([] if result.data == null else [result.data])
	page.next_cursor = str(result.pagination.get("next_cursor", result.pagination.get("cursor", "")))
	return page


static func _map_array_or_single(source: Variant, mapper: Callable) -> Variant:
	if source is Array:
		var result: Array = []
		for item: Variant in source:
			if item is Dictionary:
				result.append(mapper.call(item))
		return result
	if source is Dictionary:
		return mapper.call(source)
	return source


static func _map_redemption_groups(source: Variant) -> Variant:
	if not source is Array:
		return source
	var redemptions: Array[KickRedemption] = []
	for group_value: Variant in source:
		if not group_value is Dictionary:
			continue
		var reward_value: Variant = group_value.get("reward", {})
		var reward: KickReward = KickReward.from_dictionary(reward_value) if reward_value is Dictionary else null
		var items_value: Variant = group_value.get("redemptions", [])
		if items_value is Array:
			for item: Variant in items_value:
				if item is Dictionary:
					redemptions.append(KickRedemption.from_dictionary(item, reward))
	return redemptions
