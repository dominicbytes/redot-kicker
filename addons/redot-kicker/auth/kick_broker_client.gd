class_name KickBrokerClient
extends RefCounted

const AuthorizationRequestClass = preload("res://addons/redot-kicker/models/kick_authorization_request.gd")
const AuthResultClass = preload("res://addons/redot-kicker/models/kick_auth_result.gd")
const ApiResultClass = preload("res://addons/redot-kicker/models/kick_api_result.gd")
const EventTicketClass = preload("res://addons/redot-kicker/models/kick_event_ticket.gd")
const SanitizerClass = preload("res://addons/redot-kicker/diagnostics/kick_data_sanitizer.gd")

var _config: KickClientConfig = null
var _transport: KickHttpTransport = null


func configure(config: KickClientConfig, transport: KickHttpTransport) -> KickApiError:
	if config == null or transport == null:
		return KickApiError.invalid("Kick broker configuration and transport are required")
	var validation: KickApiError = config.validate()
	if validation != null:
		return validation
	_config = config
	_transport = transport
	return null


func begin_authorization(capabilities: PackedStringArray, session_slot: String, proof_hash: String, cancellation: KickCancellationToken = null) -> KickAuthorizationRequest:
	var result: KickAuthorizationRequest = AuthorizationRequestClass.new()
	var response: KickHttpResponse = await _request_json(
		"/v1/auth/requests",
		HTTPClient.METHOD_POST,
		{
			"schema_version": 1,
			"publisher_id": _config.publisher_id,
			"application_id": _config.application_id,
			"session_slot": session_slot,
			"capabilities": Array(capabilities),
			"proof_sha256": proof_hash,
		},
		PackedStringArray(),
		cancellation,
		false
	)
	if not _success(response):
		result.error = _response_error(response)
		return result
	var body: Dictionary = response.parsed_json if response.parsed_json is Dictionary else {}
	result.request_id = str(body.get("request_id", ""))
	result.authorization_url = str(body.get("authorization_url", ""))
	result.expires_at_unix = int(body.get("expires_at_unix", 0))
	result.poll_interval_msec = clampi(int(body.get("poll_interval_msec", 1000)), 250, 10000)
	if result.request_id.is_empty() or not _config.is_safe_relay_url(result.authorization_url):
		result.error = KickApiError.custom("broker_protocol", "Kick broker returned an invalid authorization request")
	return result


func poll_authorization(request_id: String, proof: String, cancellation: KickCancellationToken = null) -> KickAuthResult:
	var headers: PackedStringArray = PackedStringArray(["X-Redot-Kicker-Proof: " + proof])
	var response: KickHttpResponse = await _request_json(
		"/v1/auth/requests/" + request_id.uri_encode(),
		HTTPClient.METHOD_GET,
		{},
		headers,
		cancellation,
		true,
		false
	)
	return _auth_result_from_response(response, false)


func restore(broker_session: String, session_slot: String, cancellation: KickCancellationToken = null) -> KickAuthResult:
	var response: KickHttpResponse = await _authenticated_json(
		"/v1/sessions/restore",
		HTTPClient.METHOD_POST,
		broker_session,
		{"schema_version": 1, "session_slot": session_slot},
		cancellation,
		false
	)
	return _auth_result_from_response(response, true)


func rotate(broker_session: String, cancellation: KickCancellationToken = null) -> KickAuthResult:
	var response: KickHttpResponse = await _authenticated_json(
		"/v1/sessions/rotate",
		HTTPClient.METHOD_POST,
		broker_session,
		{"schema_version": 1},
		cancellation,
		false
	)
	return _auth_result_from_response(response, true)


func revoke(broker_session: String, cancellation: KickCancellationToken = null) -> KickApiResult:
	var response: KickHttpResponse = await _authenticated_json(
		"/v1/sessions/revoke",
		HTTPClient.METHOD_POST,
		broker_session,
		{"schema_version": 1, "revoke_kick_authorization": true, "delete_token_state": true},
		cancellation,
		false
	)
	return _api_result_from_response(response)


func invoke(
	broker_session: String,
	operation_id: String,
	query: Dictionary = {},
	path_parameters: Dictionary = {},
	body: Dictionary = {},
	confirmed: bool = false,
	idempotency_key: String = "",
	cancellation: KickCancellationToken = null,
	retry_safe: bool = false
) -> KickApiResult:
	if KickCapabilityRegistry.operation_info(operation_id) == null:
		var unknown: KickApiResult = ApiResultClass.new()
		unknown.error = KickApiError.invalid("Unknown Kick operation: %s" % operation_id)
		return unknown
	var payload: Dictionary = {
		"schema_version": 1,
		"query": query,
		"path_parameters": path_parameters,
		"body": body,
		"confirmed": confirmed,
	}
	if not idempotency_key.is_empty():
		payload["idempotency_key"] = idempotency_key
	var response: KickHttpResponse = await _authenticated_json(
		"/v1/kick/actions/" + operation_id.uri_encode(),
		HTTPClient.METHOD_POST,
		broker_session,
		payload,
		cancellation,
		retry_safe
	)
	return _api_result_from_response(response)


func create_event_ticket(broker_session: String, cancellation: KickCancellationToken = null) -> KickEventTicket:
	var result: KickEventTicket = EventTicketClass.new()
	var response: KickHttpResponse = await _authenticated_json(
		"/v1/events/tickets",
		HTTPClient.METHOD_POST,
		broker_session,
		{"schema_version": 1},
		cancellation,
		false
	)
	if not _success(response):
		result.error = _response_error(response)
		return result
	var body: Dictionary = response.parsed_json if response.parsed_json is Dictionary else {}
	result.socket_url = str(body.get("socket_url", ""))
	result.ticket = str(body.get("ticket", ""))
	result.expires_at_unix = int(body.get("expires_at_unix", 0))
	var subscriptions_value: Variant = body.get("subscription_ids", [])
	if subscriptions_value is Array:
		for subscription_id: Variant in subscriptions_value:
			if not str(subscription_id).is_empty():
				result.subscription_ids.append(str(subscription_id))
	if not _valid_socket_url(result.socket_url) or result.ticket.is_empty() or result.subscription_ids.is_empty():
		result.clear_ticket()
		result.error = KickApiError.custom("subscription_degraded", "Kick broker has no healthy event subscriptions for this session")
	return result


func health(cancellation: KickCancellationToken = null) -> KickApiResult:
	var response: KickHttpResponse = await _request_json(
		"/v1/health", HTTPClient.METHOD_GET, {}, PackedStringArray(), cancellation, true, false
	)
	return _api_result_from_response(response)


func _authenticated_json(path: String, method: int, broker_session: String, body: Dictionary, cancellation: KickCancellationToken, retry_safe: bool) -> KickHttpResponse:
	if broker_session.is_empty():
		var missing: KickHttpResponse = KickHttpResponse.new()
		missing.request_result = HTTPRequest.RESULT_REQUEST_FAILED
		missing.error = KickApiError.custom("authorization", "A broker session is required")
		return missing
	return await _request_json(
		path,
		method,
		body,
		PackedStringArray(["Authorization: Broker " + broker_session]),
		cancellation,
		retry_safe
	)


func _request_json(path: String, method: int, body: Dictionary, extra_headers: PackedStringArray, cancellation: KickCancellationToken, retry_safe: bool, include_body: bool = true) -> KickHttpResponse:
	if _config == null or _transport == null:
		var unavailable: KickHttpResponse = KickHttpResponse.new()
		unavailable.request_result = HTTPRequest.RESULT_REQUEST_FAILED
		unavailable.error = KickApiError.invalid("Kick broker client is not configured")
		return unavailable
	var headers: PackedStringArray = PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	for header: String in extra_headers:
		headers.append(header)
	var bytes: PackedByteArray = JSON.stringify(body).to_utf8_buffer() if include_body else PackedByteArray()
	var ticket: KickHttpTicket = _transport.request(_config.endpoint(path), headers, method, bytes, cancellation, retry_safe)
	return await ticket.wait_for_response()


func _auth_result_from_response(response: KickHttpResponse, restored: bool) -> KickAuthResult:
	var result: KickAuthResult = AuthResultClass.new()
	result.restored = restored
	if response != null and response.status_code == 202:
		result.pending = true
		return result
	if not _success(response):
		result.error = _response_error(response)
		return result
	var body: Dictionary = response.parsed_json if response.parsed_json is Dictionary else {}
	result.broker_session = str(body.get("broker_session", ""))
	var descriptor_source: Variant = body.get("session", body.get("descriptor", {}))
	if descriptor_source is Dictionary:
		result.descriptor = KickSessionDescriptor.from_dictionary(descriptor_source)
	if result.descriptor == null or result.broker_session.is_empty():
		result.clear_broker_session()
		result.error = KickApiError.custom("broker_protocol", "Kick broker returned an invalid session")
	return result


func _api_result_from_response(response: KickHttpResponse) -> KickApiResult:
	var result: KickApiResult = ApiResultClass.new()
	if response == null:
		result.error = KickApiError.custom("transport", "Kick broker returned no response", true)
		return result
	result.http_status = response.status_code
	result.request_id = response.header("x-request-id")
	result.retry_after_seconds = response.retry_after_seconds()
	var remaining: String = response.header("x-ratelimit-remaining")
	result.rate_limit_remaining = int(remaining) if remaining.is_valid_int() else -1
	var reset: String = response.header("x-ratelimit-reset")
	result.rate_limit_reset_unix = int(reset) if reset.is_valid_int() else 0
	if not response.is_success():
		result.error = _response_error(response)
		return result
	var payload: Variant = response.parsed_json
	if payload is Dictionary:
		result.message = str(payload.get("message", ""))
		var pagination_value: Variant = payload.get("pagination", {})
		result.pagination = (pagination_value as Dictionary).duplicate(true) if pagination_value is Dictionary else {}
		result.data = SanitizerClass.sanitize(payload.get("data", payload))
	else:
		result.data = SanitizerClass.sanitize(payload)
	return result


func _response_error(response: KickHttpResponse) -> KickApiError:
	if response == null:
		return KickApiError.custom("transport", "Kick broker returned no response", true)
	if response.error != null:
		return response.error
	return KickApiError.custom("broker_protocol", "Kick broker response was not successful")


func _success(response: KickHttpResponse) -> bool:
	return response != null and response.is_success()


func _valid_socket_url(url: String) -> bool:
	if url.begins_with("wss://"):
		return true
	return url.begins_with("ws://127.0.0.1:") or url.begins_with("ws://localhost:")
