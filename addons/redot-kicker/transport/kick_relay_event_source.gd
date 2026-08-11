class_name KickRelayEventSource
extends Node

const NormalizerClass = preload("res://addons/redot-kicker/transport/kick_event_normalizer.gd")
const DeduplicatorClass = preload("res://addons/redot-kicker/transport/kick_event_deduplicator.gd")

signal state_changed(previous: String, current: String, reason: String)
signal event_received(event: KickEvent)
signal chat_message_received(event: KickEvent)
signal channel_followed(event: KickEvent)
signal subscription_event_received(event: KickEvent)
signal reward_redemption_updated(event: KickEvent)
signal livestream_updated(event: KickEvent)
signal moderation_event_received(event: KickEvent)
signal kicks_gifted(event: KickEvent)
signal unknown_event_received(event: KickEvent)
signal queue_pressure(queued: int, capacity: int)
signal error_occurred(error: KickApiError)

@export_range(1, 4096, 1) var max_queue_entries: int = 256
@export_range(1024, 1048576, 1024) var max_packet_bytes: int = 256 * 1024

var state: String = "disconnected"
var _peer: WebSocketPeer = null
var _descriptor: KickSessionDescriptor = null
var _allowed_subscription_ids: PackedStringArray = PackedStringArray()
var _queue: Array[Dictionary] = []
var _normalizer: KickEventNormalizer = NormalizerClass.new()
var _deduplicator: KickEventDeduplicator = DeduplicatorClass.new(5000, 3600)
var _intentional_close: bool = false


func connect_with_ticket(ticket: KickEventTicket, descriptor: KickSessionDescriptor) -> KickApiError:
	if ticket == null or not ticket.is_success() or descriptor == null:
		return KickApiError.invalid("A valid Kick event ticket and session descriptor are required")
	if not _valid_socket_url(ticket.socket_url):
		ticket.clear_ticket()
		return KickApiError.invalid("Kick event socket URL must use WSS")
	disconnect_relay("replaced")
	_descriptor = descriptor
	_allowed_subscription_ids = ticket.subscription_ids.duplicate()
	_intentional_close = false
	_peer = WebSocketPeer.new()
	_peer.handshake_headers = PackedStringArray(["Authorization: Ticket " + ticket.ticket])
	var socket_url: String = ticket.socket_url
	ticket.clear_ticket()
	var connect_error: Error = _peer.connect_to_url(socket_url)
	socket_url = ""
	if connect_error != OK:
		_peer = null
		return KickApiError.from_transport(connect_error, "Unable to start the Kick relay downlink")
	_set_state("connecting", "ticket_accepted")
	set_process(true)
	return null


func disconnect_relay(reason: String = "requested") -> void:
	_intentional_close = reason in ["requested", "replaced", "cleared", "account_disconnected", "client_freed"]
	if _peer != null:
		_peer.close(1000, reason.left(120))
	_peer = null
	_queue.clear()
	set_process(false)
	_set_state("disconnected", reason)


func clear() -> void:
	disconnect_relay("cleared")
	_deduplicator.clear()
	_descriptor = null
	_allowed_subscription_ids.clear()


func queued_count() -> int:
	return _queue.size()


func was_intentional_close() -> bool:
	return _intentional_close


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if _peer == null:
		set_process(false)
		return
	_peer.poll()
	var ready_state: int = _peer.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN:
		if state != "connected":
			_set_state("connected", "relay_authenticated")
		_receive_packets()
		_pump_one()
	elif ready_state == WebSocketPeer.STATE_CLOSING:
		_set_state("closing", "relay_closing")
	elif ready_state == WebSocketPeer.STATE_CLOSED:
		var reason: String = _peer.get_close_reason()
		_peer = null
		set_process(false)
		_set_state("disconnected", reason if not reason.is_empty() else "relay_closed")


func _receive_packets() -> void:
	while _peer != null and _peer.get_available_packet_count() > 0:
		var packet: PackedByteArray = _peer.get_packet()
		if packet.size() > max_packet_bytes:
			_fail("packet_too_large", "Kick relay packet exceeded the configured size limit")
			continue
		if not _peer.was_string_packet():
			_fail("packet_type", "Kick relay sent a non-text packet")
			continue
		var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
		packet.clear()
		if not parsed is Dictionary:
			_fail("malformed_envelope", "Kick relay sent malformed JSON")
			continue
		var envelope: Dictionary = parsed
		var validation: String = _validate_envelope(envelope)
		if not validation.is_empty():
			_fail(validation, "Kick relay envelope failed session binding")
			continue
		var message_id: String = str(envelope.get("source_message_id", ""))
		var now_unix: int = int(Time.get_unix_time_from_system())
		if _deduplicator.has_seen(message_id, now_unix):
			continue
		if _queue.size() >= max_queue_entries:
			_set_state("degraded", "queue_overflow")
			queue_pressure.emit(_queue.size(), max_queue_entries)
			continue
		var remembered: String = _deduplicator.check_and_remember(message_id, now_unix)
		if remembered != "accepted":
			_fail("deduplication_capacity", "Kick event replay cache is at capacity")
			continue
		_queue.append(envelope.duplicate(true))
		if _queue.size() * 4 >= max_queue_entries * 3:
			queue_pressure.emit(_queue.size(), max_queue_entries)


func _pump_one() -> void:
	if _queue.is_empty():
		return
	var event: KickEvent = _normalizer.normalize(_queue.pop_front())
	if event == null:
		_fail("invalid_envelope", "Kick event could not be normalized")
		return
	event_received.emit(event)
	if event.is_unknown:
		unknown_event_received.emit(event)
		return
	match event.event_type:
		"chat.message.sent": chat_message_received.emit(event)
		"channel.followed": channel_followed.emit(event)
		"channel.subscription.renewal", "channel.subscription.gifts", "channel.subscription.new": subscription_event_received.emit(event)
		"channel.reward.redemption.updated": reward_redemption_updated.emit(event)
		"livestream.status.updated", "livestream.metadata.updated": livestream_updated.emit(event)
		"moderation.banned": moderation_event_received.emit(event)
		"kicks.gifted": kicks_gifted.emit(event)
		_: unknown_event_received.emit(event)


func _validate_envelope(envelope: Dictionary) -> String:
	if str(envelope.get("platform", "")) != "kick" or int(envelope.get("schema_version", 0)) != 1:
		return "schema_mismatch"
	if _descriptor == null:
		return "session_missing"
	if str(envelope.get("tenant_id", "")) != _descriptor.tenant_id:
		return "tenant_mismatch"
	if str(envelope.get("application_id", "")) != _descriptor.application_id:
		return "application_mismatch"
	if str(envelope.get("session_id", "")) != _descriptor.session_id:
		return "session_mismatch"
	if str(envelope.get("channel_id", "")) != _descriptor.channel_id:
		return "channel_mismatch"
	var subscription_id: String = str(envelope.get("subscription_id", ""))
	if subscription_id.is_empty() or subscription_id not in _allowed_subscription_ids:
		return "subscription_mismatch"
	if str(envelope.get("source_message_id", "")).is_empty():
		return "message_id_missing"
	return ""


func _valid_socket_url(url: String) -> bool:
	return url.begins_with("wss://") or url.begins_with("ws://127.0.0.1:") or url.begins_with("ws://localhost:")


func _fail(category: String, message: String) -> void:
	var error: KickApiError = KickApiError.custom(category, message)
	error_occurred.emit(error)


func _set_state(value: String, reason: String) -> void:
	if state == value:
		return
	var previous: String = state
	state = value
	state_changed.emit(previous, state, reason)


func _exit_tree() -> void:
	disconnect_relay("client_freed")
