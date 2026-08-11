class_name KickMockDownlink
extends RefCounted

const NormalizerClass = preload("res://addons/redot-kicker/transport/kick_event_normalizer.gd")
const DeduplicatorClass = preload("res://addons/redot-kicker/transport/kick_event_deduplicator.gd")

signal state_changed(state: String, reason: String)
signal event_received(event: KickEvent)
signal unknown_event_received(event: KickEvent)
signal degraded(code: String)

var max_queue_entries: int = 64
var _state: String = "disconnected"
var _binding: KickRelayBinding
var _expected_credential: PackedByteArray = PackedByteArray()
var _queue: Array[Dictionary] = []
var _deduplicator: KickEventDeduplicator = DeduplicatorClass.new(5000, 3600)
var _normalizer: KickEventNormalizer = NormalizerClass.new()
var _crypto: Crypto = Crypto.new()


func configure(binding: KickRelayBinding, expected_credential: String, queue_limit: int = 64) -> String:
	if binding == null or not binding.validate().is_empty() or expected_credential.is_empty():
		return "invalid_configuration"
	_binding = binding
	_expected_credential = expected_credential.to_utf8_buffer()
	max_queue_entries = clampi(queue_limit, 1, 4096)
	return "configured"


func connect_session(presented_credential: String) -> bool:
	var presented: PackedByteArray = presented_credential.to_utf8_buffer()
	if _expected_credential.is_empty() or not _crypto.constant_time_compare(_expected_credential, presented):
		_set_state("disconnected", "authentication_failed")
		return false
	_set_state("connected", "authenticated")
	return true


func receive(envelope: Dictionary) -> String:
	if _state != "connected" and _state != "degraded":
		return "relay_unavailable"
	if _binding == null:
		return "invalid_configuration"
	if String(envelope.get("tenant_id", "")) != _binding.tenant_id:
		return "tenant_mismatch"
	if String(envelope.get("application_id", "")) != _binding.application_id:
		return "application_mismatch"
	if String(envelope.get("session_id", "")) != _binding.session_id:
		return "session_mismatch"
	if String(envelope.get("channel_id", "")) != _binding.channel_id:
		return "channel_mismatch"
	if String(envelope.get("subscription_id", "")) != _binding.subscription_id:
		return "subscription_mismatch"
	var message_id: String = String(envelope.get("source_message_id", ""))
	if message_id.is_empty():
		return "message_id_missing"
	var now_unix: int = int(Time.get_unix_time_from_system())
	if _deduplicator.has_seen(message_id, now_unix):
		return "duplicate"
	if _queue.size() >= max_queue_entries:
		_set_state("degraded", "queue_overflow")
		degraded.emit("queue_overflow")
		return "queue_overflow"
	var replay_classification: String = _deduplicator.check_and_remember(message_id, now_unix)
	if replay_classification == "capacity_exhausted":
		_set_state("degraded", "deduplication_capacity")
		degraded.emit("deduplication_capacity")
		return "deduplication_capacity"
	_queue.append(envelope.duplicate(true))
	return "accepted"


func pump_one() -> String:
	if _queue.is_empty():
		return "empty"
	var envelope: Dictionary = _queue.pop_front()
	var event: KickEvent = _normalizer.normalize(envelope)
	if event == null:
		degraded.emit("invalid_envelope")
		return "invalid_envelope"
	if event.is_unknown:
		unknown_event_received.emit(event)
		return "unknown_event"
	event_received.emit(event)
	return "emitted"


func disconnect_relay(reason: String = "relay_loss") -> void:
	_queue.clear()
	_set_state("disconnected", reason)


func clear() -> void:
	disconnect_relay("cleared")
	_deduplicator.clear()
	_expected_credential.clear()
	_binding = null


func state() -> String:
	return _state


func queued_count() -> int:
	return _queue.size()


func _set_state(value: String, reason: String) -> void:
	_state = value
	state_changed.emit(_state, reason)
