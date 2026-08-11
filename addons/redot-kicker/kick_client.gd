class_name KickClient
extends Node

const AuthManagerClass = preload("res://addons/redot-kicker/auth/kick_auth_manager.gd")
const HttpTransportClass = preload("res://addons/redot-kicker/transport/kick_http_transport.gd")
const RelayEventSourceClass = preload("res://addons/redot-kicker/transport/kick_relay_event_source.gd")
const ApiClientClass = preload("res://addons/redot-kicker/services/kick_api_client.gd")
const MediaCacheClass = preload("res://addons/redot-kicker/media/kick_media_cache.gd")

signal connection_state_changed(previous: String, current: String, reason: String)
signal authorization_url_ready(url: String)
signal account_connected(descriptor: KickSessionDescriptor, restored: bool)
signal account_disconnected()
signal capability_mode_changed(mode: String)
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
signal rate_limit_observed(operation_id: String, remaining: int, reset_unix: int, retry_after_seconds: float)
signal error_occurred(error: KickApiError)

var connection_state: String = "unconfigured"
var capability_mode: String = "DISCONNECTED"
var connected_descriptor: KickSessionDescriptor = null

var identity: KickIdentityService = null
var channels: KickChannelService = null
var categories: KickCategoryService = null
var livestreams: KickLivestreamService = null
var chat: KickChatService = null
var subscriptions: KickSubscriptionService = null
var rewards: KickRewardService = null
var moderation: KickModerationService = null
var kicks: KickKicksService = null
var media: KickMediaCache = null

var _config: KickClientConfig = null
var _requested_capabilities: PackedStringArray = PackedStringArray()
var _auth: KickAuthManager = null
var _transport: KickHttpTransport = null
var _gate: KickCapabilityGate = KickCapabilityGate.new()
var _api: KickApiClient = null
var _events: KickRelayEventSource = null
var _reconnect_generation: int = 0
var _reconnect_attempt: int = 0


func configure(
	config: KickClientConfig,
	capabilities: PackedStringArray,
	session_slot: String,
	credential_client: Variant = null,
	descriptor_store: Variant = null
) -> KickApiError:
	if _config != null:
		return KickApiError.invalid("KickClient is already configured")
	_transport = HttpTransportClass.new()
	_transport.name = "KickHttpTransport"
	add_child(_transport)
	_auth = AuthManagerClass.new()
	_auth.name = "KickAuthManager"
	add_child(_auth)
	var auth_error: KickApiError = _auth.configure(config, capabilities, session_slot, _transport, credential_client, descriptor_store)
	if auth_error != null:
		_auth.queue_free()
		_transport.queue_free()
		_auth = null
		_transport = null
		return auth_error
	_config = config
	_requested_capabilities = capabilities.duplicate()
	_api = ApiClientClass.new()
	_api.configure(_auth, _gate)
	_build_services()
	_events = RelayEventSourceClass.new()
	_events.name = "KickRelayEventSource"
	add_child(_events)
	_connect_signals()
	_set_state("configured", "configuration_valid")
	return null


func connect_account() -> KickAuthResult:
	if _auth == null:
		return _auth_failure("Configure KickClient before connecting an account")
	return await _auth.authorize_interactive()


func begin_account_authorization(open_system_browser: bool = true) -> KickAuthorizationRequest:
	if _auth == null:
		var unavailable: KickAuthorizationRequest = KickAuthorizationRequest.new()
		unavailable.error = KickApiError.invalid("Configure KickClient before connecting an account")
		return unavailable
	return await _auth.begin_authorization(open_system_browser)


func wait_for_account_authorization() -> KickAuthResult:
	if _auth == null:
		return _auth_failure("Configure KickClient before connecting an account")
	return await _auth.wait_for_authorization()


func restore_account() -> KickAuthResult:
	if _auth == null:
		return _auth_failure("Configure KickClient before restoring an account")
	return await _auth.restore()


func rotate_broker_session() -> KickAuthResult:
	if _auth == null:
		return _auth_failure("Configure KickClient before rotating a broker session")
	return await _auth.rotate()


func cancel_account_authorization() -> void:
	if _auth != null:
		_auth.cancel_authorization()


func disconnect_account(revoke: bool = true) -> KickApiError:
	if _auth == null:
		return null
	_reconnect_generation += 1
	_reconnect_attempt = 0
	if _events != null:
		_events.clear()
	var first_error: KickApiError = null
	if revoke:
		first_error = await _auth.revoke_and_disconnect()
	else:
		first_error = await _auth.clear_local_data()
	if media != null:
		var media_error: KickApiError = media.clear_data()
		if first_error == null:
			first_error = media_error
	return first_error


func clear_local_data(revoke: bool = false) -> KickApiError:
	return await disconnect_account(revoke)


func connect_relay() -> KickApiError:
	if _auth == null or connected_descriptor == null:
		return KickApiError.custom("authorization", "Connect a Kick account before connecting the relay")
	if not _requested_capabilities.has("events.receive"):
		return KickApiError.custom("capability_missing", "The events.receive capability was not requested")
	_set_state("relay_connecting", "requesting_ticket")
	var ticket: KickEventTicket = await _auth.create_event_ticket()
	if ticket.error != null:
		_on_error(ticket.error)
		_set_mode("REST_ONLY")
		_set_state("degraded", "event_ticket_failed")
		return ticket.error
	var connect_error: KickApiError = _events.connect_with_ticket(ticket, connected_descriptor)
	if connect_error != null:
		_on_error(connect_error)
		_set_mode("REST_ONLY")
		_set_state("degraded", "relay_connect_failed")
	return connect_error


func disconnect_relay(reason: String = "requested") -> void:
	_reconnect_generation += 1
	_reconnect_attempt = 0
	if _events != null:
		_events.disconnect_relay(reason)
	if connected_descriptor != null:
		_set_mode("REST_ONLY")


func invoke(
	operation_id: String,
	query: Dictionary = {},
	path_parameters: Dictionary = {},
	body: Dictionary = {},
	confirmed: bool = false,
	idempotency_key: String = "",
	cancellation: KickCancellationToken = null
) -> KickApiResult:
	if _api == null:
		var unavailable: KickApiResult = KickApiResult.new()
		unavailable.error = KickApiError.invalid("Configure KickClient before invoking an operation")
		return unavailable
	return await _api.invoke(operation_id, query, path_parameters, body, confirmed, idempotency_key, cancellation)


func _build_services() -> void:
	identity = KickIdentityService.new(_api)
	channels = KickChannelService.new(_api)
	categories = KickCategoryService.new(_api)
	livestreams = KickLivestreamService.new(_api)
	chat = KickChatService.new(_api)
	subscriptions = KickSubscriptionService.new(_api)
	rewards = KickRewardService.new(_api)
	moderation = KickModerationService.new(_api)
	kicks = KickKicksService.new(_api)
	media = MediaCacheClass.new(_transport)
	media.name = "KickMediaCache"
	add_child(media)


func _connect_signals() -> void:
	_auth.state_changed.connect(_on_auth_state_changed)
	_auth.authorization_url_ready.connect(authorization_url_ready.emit)
	_auth.connected.connect(_on_account_connected)
	_auth.disconnected.connect(_on_account_disconnected)
	_auth.error_occurred.connect(_on_error)
	_api.rate_limit_observed.connect(rate_limit_observed.emit)
	_events.state_changed.connect(_on_relay_state_changed)
	_events.event_received.connect(event_received.emit)
	_events.chat_message_received.connect(chat_message_received.emit)
	_events.channel_followed.connect(channel_followed.emit)
	_events.subscription_event_received.connect(subscription_event_received.emit)
	_events.reward_redemption_updated.connect(reward_redemption_updated.emit)
	_events.livestream_updated.connect(livestream_updated.emit)
	_events.moderation_event_received.connect(moderation_event_received.emit)
	_events.kicks_gifted.connect(kicks_gifted.emit)
	_events.unknown_event_received.connect(unknown_event_received.emit)
	_events.queue_pressure.connect(queue_pressure.emit)
	_events.error_occurred.connect(_on_error)


func _on_auth_state_changed(_previous: String, current: String) -> void:
	if current in ["authorizing", "restoring"]:
		_set_state(current, "authentication_state")


func _on_account_connected(value: KickSessionDescriptor, restored: bool) -> void:
	connected_descriptor = value
	_gate.configure(value.granted_capabilities, value.granted_scopes, true, true)
	_set_mode("REST_ONLY")
	_set_state("rest_only", "account_restored" if restored else "account_authorized")
	account_connected.emit(value, restored)
	if value.granted_capabilities.has("events.receive"):
		connect_relay()


func _on_account_disconnected() -> void:
	connected_descriptor = null
	_gate.clear()
	_set_mode("DISCONNECTED")
	_set_state("disconnected", "account_disconnected")
	account_disconnected.emit()


func _on_relay_state_changed(_previous: String, current: String, reason: String) -> void:
	match current:
		"connecting":
			_set_state("relay_connecting", reason)
		"connected":
			_reconnect_attempt = 0
			_set_mode("RELAY_CONNECTED")
			_set_state("relay_connected", reason)
		"degraded":
			_set_mode("REST_ONLY")
			_set_state("degraded", reason)
		"disconnected":
			if connected_descriptor != null:
				_set_mode("REST_ONLY")
				_set_state("degraded", reason)
				if not _events.was_intentional_close():
					_schedule_reconnect()


func _schedule_reconnect() -> void:
	_reconnect_attempt += 1
	var generation: int = _reconnect_generation
	var delay_seconds: float = float(mini(30, 1 << mini(_reconnect_attempt - 1, 5)))
	await get_tree().create_timer(delay_seconds).timeout
	if generation == _reconnect_generation and connected_descriptor != null:
		connect_relay()


func _on_error(error: KickApiError) -> void:
	error_occurred.emit(error)


func _auth_failure(message: String) -> KickAuthResult:
	var result: KickAuthResult = KickAuthResult.new()
	result.error = KickApiError.invalid(message)
	return result


func _set_mode(value: String) -> void:
	if capability_mode == value:
		return
	capability_mode = value
	capability_mode_changed.emit(capability_mode)


func _set_state(value: String, reason: String) -> void:
	if connection_state == value:
		return
	var previous: String = connection_state
	connection_state = value
	connection_state_changed.emit(previous, connection_state, reason)


func _exit_tree() -> void:
	_reconnect_generation += 1
	if _events != null:
		_events.disconnect_relay("client_freed")
	if _transport != null:
		_transport.cancel_all("KickClient freed")
