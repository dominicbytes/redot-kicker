extends SceneTree

var _checks: int = 0
var _failures: Array[String] = []

class TicketProvider extends KickAuthManager:
	var calls: int = 0
	var failures: Array[KickApiError] = []
	var cancel_client: KickClient = null

	func create_event_ticket(_cancellation: KickCancellationToken = null) -> KickEventTicket:
		calls += 1
		var ticket: KickEventTicket = KickEventTicket.new()
		if cancel_client != null:
			cancel_client.disconnect_relay()
		if not failures.is_empty():
			ticket.error = failures.pop_front()
		else:
			ticket.socket_url = "ws://127.0.0.1:9876/v1/events/socket"
			ticket.ticket = "fixture-ticket"
			ticket.subscription_ids = PackedStringArray(["new-subscription"])
		return ticket

class EventSource extends KickRelayEventSource:
	var calls: int = 0
	var failures: Array[KickApiError] = []

	func connect_with_ticket(_ticket: KickEventTicket, _descriptor: KickSessionDescriptor) -> KickApiError:
		calls += 1
		if not failures.is_empty():
			return failures.pop_front()
		state_changed.emit("connecting", "connected", "fixture_connected")
		return null

func _init() -> void:
	call_deferred("_run")

func _client() -> KickClient:
	var client: KickClient = KickClient.new()
	root.add_child(client)
	client._auth = TicketProvider.new()
	client.add_child(client._auth)
	client._events = EventSource.new()
	client.add_child(client._events)
	client._events.state_changed.connect(client._on_relay_state_changed)
	client.connected_descriptor = KickSessionDescriptor.new()
	client._requested_capabilities = PackedStringArray(["events.receive"])
	return client

func _run() -> void:
	await process_frame
	var peer: WebSocketPeer = WebSocketPeer.new()
	var heartbeat_available: bool = false
	for property: Dictionary in peer.get_property_list():
		if str(property.name) == "heartbeat_interval":
			heartbeat_available = true
	_check(heartbeat_available, "installed Redot supports WebSocketPeer heartbeat_interval")
	var retry_errors: Array[KickApiError] = [
		KickApiError.from_transport(ERR_CANT_CONNECT, "fixture transport"),
		KickApiError.from_http(503, {}),
		KickApiError.from_http(501, {}),
		KickApiError.from_http(429, {}),
		KickApiError.from_http(409, {"error": {"code": "subscription_degraded"}}),
	]
	for retry_error: KickApiError in retry_errors:
		var client: KickClient = _client()
		var provider: TicketProvider = client._auth as TicketProvider
		provider.failures = [retry_error, retry_error]
		await client.connect_relay()
		await create_timer(3.3).timeout
		_check(provider.calls == 3 and client.connection_state == "relay_connected", "ticket failure retries twice then reconnects: %d/%s" % [retry_error.http_status, retry_error.category])
		client.queue_free()
		await process_frame
	var socket_client: KickClient = _client()
	var source: EventSource = socket_client._events as EventSource
	source.failures = [KickApiError.from_transport(ERR_CANT_CONNECT, "fixture socket")]
	await socket_client.connect_relay()
	await create_timer(1.2).timeout
	_check(source.calls == 2 and socket_client.connection_state == "relay_connected", "immediate socket failure retries")
	socket_client.queue_free()
	await process_frame
	for permanent: KickApiError in [KickApiError.from_http(401, {}), KickApiError.invalid("fixture invalid")]:
		var client: KickClient = _client()
		var provider: TicketProvider = client._auth as TicketProvider
		provider.failures = [permanent]
		await client.connect_relay()
		await create_timer(1.2).timeout
		_check(provider.calls == 1, "permanent failure does not reconnect")
		client.queue_free()
		await process_frame
	var cancelled: KickClient = _client()
	var cancelled_provider: TicketProvider = cancelled._auth as TicketProvider
	cancelled_provider.failures = [retry_errors[0]]
	cancelled_provider.cancel_client = cancelled
	await cancelled.connect_relay()
	await create_timer(1.2).timeout
	_check(cancelled_provider.calls == 1, "disconnect during ticket request prevents retry")
	cancelled.queue_free()
	await process_frame
	var pending: KickClient = _client()
	var pending_provider: TicketProvider = pending._auth as TicketProvider
	pending_provider.failures = [retry_errors[0]]
	await pending.connect_relay()
	pending.disconnect_relay()
	await create_timer(1.2).timeout
	_check(pending_provider.calls == 1, "disconnect cancels the queued backoff retry")
	pending.queue_free()
	await process_frame
	var changed: KickClient = _client()
	var changed_provider: TicketProvider = changed._auth as TicketProvider
	changed._on_relay_state_changed("connected", "disconnected", "subscriptions_changed")
	await create_timer(1.2).timeout
	_check(changed_provider.calls == 1 and changed.connection_state == "relay_connected", "subscription change close reconnects with a fresh ticket")
	changed.queue_free()
	await process_frame
	for failure: String in _failures:
		push_error("RECONNECT FAIL: " + failure)
	print("RECONNECT %s: %d checks, %d failures" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
