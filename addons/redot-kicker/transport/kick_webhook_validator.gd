class_name KickWebhookValidator
extends RefCounted

const BindingClass = preload("res://addons/redot-kicker/models/kick_relay_binding.gd")
const ResultClass = preload("res://addons/redot-kicker/models/kick_relay_result.gd")
const DeduplicatorClass = preload("res://addons/redot-kicker/transport/kick_event_deduplicator.gd")

const REQUIRED_HEADERS: Array[String] = [
	"kick-event-message-id",
	"kick-event-subscription-id",
	"kick-event-signature",
	"kick-event-message-timestamp",
	"kick-event-type",
	"kick-event-version",
]
const SUPPORTED_EVENTS: Dictionary = {
	"chat.message.sent": 1,
	"channel.followed": 1,
	"channel.subscription.renewal": 1,
	"channel.subscription.gifts": 1,
	"channel.subscription.new": 1,
	"channel.reward.redemption.updated": 1,
	"livestream.status.updated": 1,
	"livestream.metadata.updated": 1,
	"moderation.banned": 1,
	"kicks.gifted": 1,
}

var max_body_bytes: int = 256 * 1024
var max_timestamp_skew_seconds: int = 300
var _crypto: Crypto = Crypto.new()
var _deduplicator: KickEventDeduplicator


func _init(deduplication_entries: int = 5000, deduplication_ttl_seconds: int = 600) -> void:
	_deduplicator = DeduplicatorClass.new(deduplication_entries, deduplication_ttl_seconds)


func validate_and_transform(
	raw_body: PackedByteArray,
	headers: Dictionary,
	public_key: CryptoKey,
	binding: KickRelayBinding,
	now_unix: int = -1
) -> KickRelayResult:
	if raw_body.is_empty():
		return ResultClass.reject("empty_body", "Webhook body is empty")
	if raw_body.size() > max_body_bytes:
		return ResultClass.reject("body_too_large", "Webhook body exceeds the configured limit")
	if public_key == null:
		return ResultClass.reject("public_key_missing", "Kick public key is unavailable")
	if binding == null or not binding.validate().is_empty():
		return ResultClass.reject("binding_invalid", "Relay binding is invalid")

	var normalized_headers: Dictionary = _normalize_headers(headers)
	for required_header: String in REQUIRED_HEADERS:
		if String(normalized_headers.get(required_header, "")).is_empty():
			return ResultClass.reject("header_missing", "A required Kick webhook header is missing")

	var message_id: String = String(normalized_headers["kick-event-message-id"])
	var subscription_id: String = String(normalized_headers["kick-event-subscription-id"])
	var signature_text: String = String(normalized_headers["kick-event-signature"])
	var timestamp: String = String(normalized_headers["kick-event-message-timestamp"])
	var event_type: String = String(normalized_headers["kick-event-type"])
	var version_text: String = String(normalized_headers["kick-event-version"])
	if not _valid_header_identifier(message_id) or not _valid_header_identifier(subscription_id):
		return ResultClass.reject("header_invalid", "Kick message or subscription identity is invalid")
	if subscription_id != binding.subscription_id:
		return ResultClass.reject("subscription_mismatch", "Webhook subscription is not authorized for this relay binding")
	if event_type.length() > 128 or version_text.length() > 16 or signature_text.length() > 8192:
		return ResultClass.reject("header_invalid", "Kick webhook header exceeds the configured limit")

	var message_unix: int = _timestamp_to_unix(timestamp)
	if message_unix < 0:
		return ResultClass.reject("timestamp_invalid", "Kick webhook timestamp is invalid")
	var effective_now: int = int(Time.get_unix_time_from_system()) if now_unix < 0 else now_unix
	if absi(effective_now - message_unix) > max_timestamp_skew_seconds:
		return ResultClass.reject("timestamp_stale", "Kick webhook timestamp is outside the accepted freshness window")

	var signature: PackedByteArray = Marshalls.base64_to_raw(signature_text)
	if signature.is_empty():
		return ResultClass.reject("signature_invalid", "Kick webhook signature is invalid")
	var signed_bytes: PackedByteArray = (message_id + "." + timestamp + ".").to_utf8_buffer()
	signed_bytes.append_array(raw_body)
	var digest: PackedByteArray = _sha256(signed_bytes)
	if digest.is_empty() or not _crypto.verify(HashingContext.HASH_SHA256, digest, signature, public_key):
		return ResultClass.reject("signature_invalid", "Kick webhook signature is invalid")

	var replay_classification: String = _deduplicator.check_and_remember(message_id, effective_now)
	if replay_classification == "duplicate":
		return ResultClass.reject("duplicate", "Kick webhook message was already processed")
	if replay_classification == "capacity_exhausted":
		return ResultClass.reject("replay_capacity", "Webhook replay protection is at capacity")

	var parser: JSON = JSON.new()
	if parser.parse(raw_body.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return ResultClass.reject("malformed_payload", "Authenticated webhook payload is not a JSON object")
	var payload: Dictionary = (parser.data as Dictionary).duplicate(true)
	var channel_id: String = _extract_channel_id(payload)
	if channel_id.is_empty():
		return ResultClass.reject("channel_missing", "Authenticated webhook payload has no broadcaster identity")
	if channel_id != binding.channel_id:
		return ResultClass.reject("channel_mismatch", "Webhook broadcaster is not authorized for this relay binding")

	var event_version: int = int(version_text) if version_text.is_valid_int() else -1
	if event_version < 1:
		return ResultClass.reject("event_version_invalid", "Kick webhook event version is invalid")
	var is_supported: bool = SUPPORTED_EVENTS.has(event_type) and int(SUPPORTED_EVENTS[event_type]) == event_version
	var envelope: Dictionary = {
		"platform": "kick",
		"schema_version": 1,
		"tenant_id": binding.tenant_id,
		"application_id": binding.application_id,
		"session_id": binding.session_id,
		"subscription_id": subscription_id,
		"source_message_id": message_id,
		"event_type": event_type,
		"event_version": event_version,
		"occurred_at": String(payload.get("created_at", timestamp)),
		"received_at": Time.get_datetime_string_from_unix_time(effective_now) + "Z",
		"channel_id": channel_id,
		"supported": is_supported,
		"payload": payload,
	}
	return ResultClass.accept(envelope, not is_supported)


func clear_replay_state() -> void:
	_deduplicator.clear()


func replay_entry_count() -> int:
	return _deduplicator.size()


func _normalize_headers(headers: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in headers:
		result[String(key).to_lower()] = String(headers[key]).strip_edges()
	return result


func _timestamp_to_unix(value: String) -> int:
	var pattern: RegEx = RegEx.new()
	if pattern.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?(?:Z|[+-]\\d{2}:\\d{2})$") != OK:
		return -1
	if pattern.search(value) == null:
		return -1
	return int(Time.get_unix_time_from_datetime_string(value))


func _valid_header_identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(character):
			return false
	return true


func _sha256(value: PackedByteArray) -> PackedByteArray:
	var hashing: HashingContext = HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if hashing.update(value) != OK:
		return PackedByteArray()
	return hashing.finish()


func _extract_channel_id(payload: Dictionary) -> String:
	var broadcaster: Variant = payload.get("broadcaster", {})
	if broadcaster is Dictionary:
		var user_id: Variant = (broadcaster as Dictionary).get("user_id", "")
		if user_id is float:
			return str(int(user_id))
		return str(user_id)
	return ""
