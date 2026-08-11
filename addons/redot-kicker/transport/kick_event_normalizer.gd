class_name KickEventNormalizer
extends RefCounted

const EventClass = preload("res://addons/redot-kicker/models/kick_event.gd")


func normalize(envelope: Dictionary) -> KickEvent:
	if String(envelope.get("platform", "")) != "kick" or int(envelope.get("schema_version", 0)) != 1:
		return null
	var payload: Variant = envelope.get("payload", null)
	if not payload is Dictionary:
		return null
	var event: KickEvent = EventClass.new()
	event.id = String(envelope.get("source_message_id", ""))
	event.subscription_id = String(envelope.get("subscription_id", ""))
	event.event_type = String(envelope.get("event_type", ""))
	event.event_version = int(envelope.get("event_version", 0))
	event.occurred_at = String(envelope.get("occurred_at", ""))
	event.received_at = String(envelope.get("received_at", ""))
	event.channel_id = String(envelope.get("channel_id", ""))
	event.tenant_id = String(envelope.get("tenant_id", ""))
	event.application_id = String(envelope.get("application_id", ""))
	event.session_id = String(envelope.get("session_id", ""))
	event.payload = (payload as Dictionary).duplicate(true)
	event.is_unknown = not bool(envelope.get("supported", false))
	event.broadcaster = _user(payload.get("broadcaster", {}))
	event.created_at = str(payload.get("created_at", payload.get("redeemed_at", event.occurred_at)))
	_match_event_fields(event, payload)
	if event.id.is_empty() or event.channel_id.is_empty() or event.tenant_id.is_empty():
		return null
	return event


func _match_event_fields(event: KickEvent, payload: Dictionary) -> void:
	match event.event_type:
		"chat.message.sent":
			event.actor = _user(payload.get("sender", {}))
			event.message_id = str(payload.get("message_id", ""))
			event.content = str(payload.get("content", ""))
			event.metadata = {
				"replies_to": _dictionary(payload.get("replies_to", {})),
				"emotes": _array(payload.get("emotes", [])),
			}
		"channel.followed":
			event.actor = _user(payload.get("follower", {}))
		"channel.subscription.renewal", "channel.subscription.new":
			event.actor = _user(payload.get("subscriber", {}))
			event.duration = int(payload.get("duration", 0))
			event.expires_at = str(payload.get("expires_at", ""))
		"channel.subscription.gifts":
			event.actor = _user(payload.get("gifter", {}))
			event.expires_at = str(payload.get("expires_at", ""))
			var giftees: Variant = payload.get("giftees", [])
			if giftees is Array:
				for user_value: Variant in giftees:
					var user: KickUser = _user(user_value)
					if user != null:
						event.related_users.append(user)
		"channel.reward.redemption.updated":
			event.actor = _user(payload.get("redeemer", {}))
			var reward_value: Variant = payload.get("reward", {})
			event.reward = KickReward.from_dictionary(reward_value) if reward_value is Dictionary else null
			event.redemption = KickRedemption.from_dictionary(payload, event.reward)
		"livestream.status.updated":
			event.is_live = bool(payload.get("is_live", false))
			event.title = str(payload.get("title", ""))
			event.metadata = {"started_at": str(payload.get("started_at", "")), "ended_at": str(payload.get("ended_at", ""))}
		"livestream.metadata.updated":
			event.metadata = _dictionary(payload.get("metadata", {}))
			event.title = str(event.metadata.get("title", ""))
		"moderation.banned":
			event.actor = _user(payload.get("moderator", {}))
			var banned: KickUser = _user(payload.get("banned_user", {}))
			if banned != null:
				event.related_users.append(banned)
			event.metadata = _dictionary(payload.get("metadata", {}))
		"kicks.gifted":
			event.actor = _user(payload.get("sender", {}))
			event.gift = _dictionary(payload.get("gift", {}))


func _user(source: Variant) -> KickUser:
	return KickUser.from_dictionary(source) if source is Dictionary else null


func _dictionary(source: Variant) -> Dictionary:
	return (source as Dictionary).duplicate(true) if source is Dictionary else {}


func _array(source: Variant) -> Array:
	return (source as Array).duplicate(true) if source is Array else []
