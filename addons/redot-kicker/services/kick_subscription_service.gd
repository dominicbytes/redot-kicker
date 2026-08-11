class_name KickSubscriptionService
extends RefCounted

const SUPPORTED_EVENTS: PackedStringArray = [
	"chat.message.sent",
	"channel.followed",
	"channel.subscription.renewal",
	"channel.subscription.gifts",
	"channel.subscription.new",
	"channel.reward.redemption.updated",
	"livestream.status.updated",
	"livestream.metadata.updated",
	"moderation.banned",
	"kicks.gifted",
]

var _api: KickApiClient


func _init(api: KickApiClient) -> void:
	_api = api


func list(broadcaster_user_id: String = "", cancellation: KickCancellationToken = null) -> KickApiResult:
	var query: Dictionary = {}
	if not broadcaster_user_id.is_empty(): query["broadcaster_user_id"] = broadcaster_user_id
	return KickModelMapper.map_result(await _api.invoke("subscriptions.list", query, {}, {}, false, "", cancellation), "event_subscription")


func create(event_types: PackedStringArray, broadcaster_user_id: String = "", cancellation: KickCancellationToken = null) -> KickApiResult:
	if event_types.is_empty():
		return _failed("At least one Kick event type is required")
	var events: Array[Dictionary] = []
	for event_type: String in event_types:
		if event_type not in SUPPORTED_EVENTS:
			return _failed("Unsupported Kick event type: %s" % event_type)
		events.append({"name": event_type, "version": 1})
	var body: Dictionary = {"events": events, "method": "webhook"}
	if not broadcaster_user_id.is_empty(): body["broadcaster_user_id"] = broadcaster_user_id
	return KickModelMapper.map_result(await _api.invoke("subscriptions.create", {}, {}, body, false, "", cancellation), "event_subscription")


func delete(subscription_ids: PackedStringArray, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	if subscription_ids.is_empty():
		return _failed("At least one Kick event subscription ID is required")
	return await _api.invoke("subscriptions.delete", {"id": Array(subscription_ids)}, {}, {}, confirmed, "", cancellation)


func _failed(message: String) -> KickApiResult:
	var result: KickApiResult = KickApiResult.new()
	result.error = KickApiError.invalid(message)
	return result
