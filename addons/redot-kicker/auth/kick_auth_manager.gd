class_name KickAuthManager
extends Node

const BrokerClientClass = preload("res://addons/redot-kicker/auth/kick_broker_client.gd")
const CredentialClientClass = preload("res://addons/redot-kicker/auth/kick_credential_helper_client.gd")
const DescriptorStoreClass = preload("res://addons/redot-kicker/auth/kick_session_descriptor_store.gd")
const AuthResultClass = preload("res://addons/redot-kicker/models/kick_auth_result.gd")

signal state_changed(previous: String, current: String)
signal authorization_url_ready(url: String)
signal connected(descriptor: KickSessionDescriptor, restored: bool)
signal disconnected()
signal error_occurred(error: KickApiError)

var state: String = "unconfigured"
var session_slot: String = ""
var descriptor: KickSessionDescriptor = null

var _config: KickClientConfig = null
var _capabilities: PackedStringArray = PackedStringArray()
var _transport: KickHttpTransport = null
var _broker: Variant = null
var _credential_client: Variant = null
var _descriptor_store: Variant = null
var _broker_session: String = ""
var _pending_request_id: String = ""
var _pending_proof: String = ""
var _pending_deadline_msec: int = 0
var _pending_poll_interval_msec: int = 1000
var _slot_held: bool = false
var _cancellation: KickCancellationToken = null


func configure(
	config: KickClientConfig,
	capabilities: PackedStringArray,
	stable_session_slot: String,
	transport: KickHttpTransport,
	credential_client: Variant = null,
	descriptor_store: Variant = null,
	broker_client: Variant = null
) -> KickApiError:
	if _config != null:
		return KickApiError.invalid("Kick authentication is already configured for this client")
	if not _is_valid_slot(stable_session_slot):
		return KickApiError.invalid("Session slot may contain 1-64 letters, digits, dots, underscores, or hyphens")
	var config_error: KickApiError = config.validate() if config != null else KickApiError.invalid("Kick client configuration is required")
	if config_error != null:
		return config_error
	var capability_error: KickApiError = KickCapabilityRegistry.validate_capabilities(capabilities)
	if capability_error != null:
		return capability_error
	var qualified_slot: String = config.credential_target(stable_session_slot)
	var lease_error: KickApiError = KickSessionSlotRegistry.acquire(qualified_slot, self)
	if lease_error != null:
		return lease_error
	_slot_held = true
	_config = config
	_capabilities = capabilities.duplicate()
	_capabilities.sort()
	session_slot = stable_session_slot
	_transport = transport
	_broker = broker_client if broker_client != null else BrokerClientClass.new()
	if broker_client == null:
		var broker_error: KickApiError = _broker.configure(config, transport)
		if broker_error != null:
			_release_slot()
			return broker_error
	_credential_client = credential_client if credential_client != null else CredentialClientClass.new()
	if credential_client == null and not config.helper_path_override.is_empty():
		_credential_client.helper_path_override = config.helper_path_override
	_descriptor_store = descriptor_store if descriptor_store != null else DescriptorStoreClass.new()
	_set_state("configured")
	return null


func begin_authorization(open_system_browser: bool = true) -> KickAuthorizationRequest:
	var request: KickAuthorizationRequest = KickAuthorizationRequest.new()
	var readiness: KickApiError = _ensure_ready_slot()
	if readiness != null:
		request.error = readiness
		return request
	cancel_authorization("replaced")
	_cancellation = KickCancellationToken.new()
	var proof_bytes: PackedByteArray = Crypto.new().generate_random_bytes(32)
	_pending_proof = _base64_url(proof_bytes)
	var proof_hash: String = _base64_url(_sha256(proof_bytes))
	proof_bytes.clear()
	_set_state("authorizing")
	request = await _broker.begin_authorization(_capabilities, session_slot, proof_hash, _cancellation)
	proof_hash = ""
	if request.error != null:
		_clear_pending()
		_set_state("configured")
		error_occurred.emit(request.error)
		return request
	_pending_request_id = request.request_id
	_pending_deadline_msec = Time.get_ticks_msec() + mini(
		_config.authorization_timeout_msec,
		maxi(1000, (request.expires_at_unix - int(Time.get_unix_time_from_system())) * 1000)
	)
	_pending_poll_interval_msec = request.poll_interval_msec
	authorization_url_ready.emit(request.authorization_url)
	if open_system_browser:
		var browser_error: Error = OS.shell_open(request.authorization_url)
		if browser_error != OK:
			request.error = KickApiError.from_transport(browser_error, "Unable to open the system browser; use the safe authorization URL shown by the connection panel")
			error_occurred.emit(request.error)
	return request


func authorize_interactive() -> KickAuthResult:
	var request: KickAuthorizationRequest = await begin_authorization(true)
	if request.error != null and _pending_request_id.is_empty():
		return _failed(request.error)
	return await wait_for_authorization()


func wait_for_authorization() -> KickAuthResult:
	if _pending_request_id.is_empty() or _pending_proof.is_empty():
		return _failed(KickApiError.invalid("No Kick authorization request is pending"))
	while Time.get_ticks_msec() < _pending_deadline_msec:
		if _cancellation != null and _cancellation.is_cancelled():
			var cancelled_error: KickApiError = KickApiError.custom("cancelled", "Kick authorization was cancelled")
			_clear_pending()
			_set_state("configured")
			return _failed(cancelled_error)
		var polled: KickAuthResult = await _broker.poll_authorization(_pending_request_id, _pending_proof, _cancellation)
		if polled.pending:
			await get_tree().create_timer(float(_pending_poll_interval_msec) / 1000.0).timeout
			continue
		_clear_pending()
		if polled.error != null:
			_set_state("configured")
			error_occurred.emit(polled.error)
			return polled
		return await _accept_session(polled, false)
	var timeout_error: KickApiError = KickApiError.custom("timeout", "Kick authorization timed out", true)
	_clear_pending()
	_set_state("configured")
	error_occurred.emit(timeout_error)
	return _failed(timeout_error)


func restore() -> KickAuthResult:
	var readiness: KickApiError = _ensure_ready_slot()
	if readiness != null:
		return _failed(readiness)
	_set_state("restoring")
	var loaded: KickSessionDescriptorLoadResult = _descriptor_store.load_descriptor(session_slot)
	if loaded.error != null:
		_set_state("configured")
		return _failed(loaded.error)
	var expected_target: String = _config.credential_target(session_slot)
	if loaded.descriptor.credential_target != expected_target or loaded.descriptor.relay_base_url != _config.relay_base_url:
		_set_state("configured")
		return _failed(KickApiError.custom("descriptor_mismatch", "Saved Kick session does not match this relay application and slot"))
	var credential: KickCredentialResult = await _credential_client.read(expected_target)
	if not credential.is_success():
		_set_state("configured")
		return _failed(credential.error if credential.error != null else KickApiError.custom(credential.status, "Stored broker session is unavailable"))
	var secret: String = credential.secret
	credential.clear_secret()
	var restored: KickAuthResult = await _broker.restore(secret, session_slot)
	secret = ""
	if restored.error != null:
		_set_state("configured")
		error_occurred.emit(restored.error)
		return restored
	return await _accept_session(restored, true)


func rotate() -> KickAuthResult:
	if state != "connected" or _broker_session.is_empty():
		return _failed(KickApiError.custom("authorization", "No connected Kick broker session can be rotated"))
	var rotated: KickAuthResult = await _broker.rotate(_broker_session)
	if rotated.error != null:
		error_occurred.emit(rotated.error)
		return rotated
	return await _accept_session(rotated, true)


func invoke(
	operation_id: String,
	query: Dictionary = {},
	path_parameters: Dictionary = {},
	body: Dictionary = {},
	confirmed: bool = false,
	idempotency_key: String = "",
	cancellation: KickCancellationToken = null,
	retry_safe: bool = false
) -> KickApiResult:
	if state != "connected" or _broker_session.is_empty():
		var unavailable: KickApiResult = KickApiResult.new()
		unavailable.error = KickApiError.custom("authorization", "A connected Kick account is required")
		return unavailable
	return await _broker.invoke(_broker_session, operation_id, query, path_parameters, body, confirmed, idempotency_key, cancellation, retry_safe)


func create_event_ticket(cancellation: KickCancellationToken = null) -> KickEventTicket:
	if state != "connected" or _broker_session.is_empty():
		var unavailable: KickEventTicket = KickEventTicket.new()
		unavailable.error = KickApiError.custom("authorization", "A connected Kick account is required")
		return unavailable
	return await _broker.create_event_ticket(_broker_session, cancellation)


func revoke_and_disconnect() -> KickApiError:
	return await _disconnect_internal(true)


func clear_local_data() -> KickApiError:
	return await _disconnect_internal(false)


func cancel_authorization(reason: String = "cancelled") -> void:
	if _cancellation != null:
		_cancellation.cancel(reason)
	_clear_pending()
	if state == "authorizing":
		_set_state("configured")


func granted_capabilities() -> PackedStringArray:
	return descriptor.granted_capabilities.duplicate() if descriptor != null and state == "connected" else PackedStringArray()


func granted_scopes() -> PackedStringArray:
	return descriptor.granted_scopes.duplicate() if descriptor != null and state == "connected" else PackedStringArray()


func _accept_session(result: KickAuthResult, restored: bool) -> KickAuthResult:
	if not result.is_success() or result.broker_session.is_empty():
		return result
	var expected_target: String = _config.credential_target(session_slot)
	var value: KickSessionDescriptor = result.descriptor
	var descriptor_error: KickApiError = _validate_session_descriptor(value)
	if descriptor_error != null:
		await _broker.revoke(result.broker_session)
		result.clear_broker_session()
		return _failed(descriptor_error)
	value.credential_target = expected_target
	value.relay_base_url = _config.relay_base_url
	var stored: KickCredentialResult = await _credential_client.store(expected_target, result.broker_session)
	if not stored.is_success():
		await _broker.revoke(result.broker_session)
		result.clear_broker_session()
		return _failed(stored.error if stored.error != null else KickApiError.custom(stored.status, "Unable to persist the Kick broker session"))
	var save_error: KickApiError = _descriptor_store.save(value)
	if save_error != null:
		await _credential_client.delete(expected_target)
		await _broker.revoke(result.broker_session)
		result.clear_broker_session()
		return _failed(save_error)
	_broker_session = result.broker_session
	result.clear_broker_session()
	descriptor = value
	_set_state("connected")
	var public_result: KickAuthResult = AuthResultClass.new()
	public_result.descriptor = descriptor
	public_result.restored = restored
	connected.emit(descriptor, restored)
	return public_result


func _validate_session_descriptor(value: KickSessionDescriptor) -> KickApiError:
	if value == null:
		return KickApiError.custom("broker_protocol", "Kick broker session descriptor is missing")
	if value.session_slot != session_slot or value.application_id != _config.application_id:
		return KickApiError.custom("broker_protocol", "Kick broker session does not match this application and slot")
	if value.tenant_id.is_empty() or value.session_id.is_empty() or value.user_id.is_empty() or value.channel_id.is_empty():
		return KickApiError.custom("broker_protocol", "Kick broker session is missing a required identity binding")
	if value.broker_session_expires_at_unix <= int(Time.get_unix_time_from_system()):
		return KickApiError.custom("broker_protocol", "Kick broker session is already expired")
	if value.granted_capabilities.is_empty():
		return KickApiError.custom("broker_protocol", "Kick broker session grants no capabilities")
	for capability: String in value.granted_capabilities:
		if capability not in _capabilities:
			return KickApiError.custom("broker_protocol", "Kick broker granted an unrequested capability")
	return null


func _disconnect_internal(revoke: bool) -> KickApiError:
	if _config == null:
		return null
	cancel_authorization("disconnect")
	var first_error: KickApiError = null
	if revoke and not _broker_session.is_empty():
		var revoked: KickApiResult = await _broker.revoke(_broker_session)
		if revoked.error != null:
			first_error = revoked.error
	_broker_session = ""
	var target: String = _config.credential_target(session_slot)
	var deleted: KickCredentialResult = await _credential_client.delete(target)
	if not deleted.is_success() and deleted.status != "not_found" and first_error == null:
		first_error = deleted.error
	var descriptor_error: KickApiError = _descriptor_store.delete_descriptor(session_slot)
	if descriptor_error != null and first_error == null:
		first_error = descriptor_error
	descriptor = null
	_release_slot()
	_set_state("disconnected")
	disconnected.emit()
	return first_error


func _ensure_ready_slot() -> KickApiError:
	if _config == null or _broker == null:
		return KickApiError.invalid("Configure Kick authentication first")
	if not _slot_held:
		var lease_error: KickApiError = KickSessionSlotRegistry.acquire(_config.credential_target(session_slot), self)
		if lease_error != null:
			return lease_error
		_slot_held = true
	return null


func _release_slot() -> void:
	if _slot_held and _config != null:
		KickSessionSlotRegistry.release(_config.credential_target(session_slot), self)
	_slot_held = false


func _clear_pending() -> void:
	_pending_request_id = ""
	_pending_proof = ""
	_pending_deadline_msec = 0
	_pending_poll_interval_msec = 1000
	_cancellation = null


func _failed(error: KickApiError) -> KickAuthResult:
	var result: KickAuthResult = AuthResultClass.new()
	result.error = error
	return result


func _set_state(value: String) -> void:
	if state == value:
		return
	var previous: String = state
	state = value
	state_changed.emit(previous, state)


func _is_valid_slot(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(character):
			return false
	return true


func _sha256(bytes: PackedByteArray) -> PackedByteArray:
	var hashing: HashingContext = HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return PackedByteArray()
	if hashing.update(bytes) != OK:
		return PackedByteArray()
	return hashing.finish()


func _base64_url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").trim_suffix("=").trim_suffix("=")


func _exit_tree() -> void:
	cancel_authorization("client freed")
	_broker_session = ""
	_release_slot()
