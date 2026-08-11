extends SceneTree

const MAX_FRAMES: int = 500

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()
var _server: TCPServer = null
var _peers: Array[Dictionary] = []
var _path_counts: Dictionary = {}
var _release_delayed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_server = TCPServer.new()
	var listen_error: Error = _server.listen(0, "127.0.0.1")
	_check(listen_error == OK, "loopback HTTP harness binds IPv4")
	if listen_error != OK:
		_finish()
		return

	var transport: KickHttpTransport = KickHttpTransport.new()
	transport.max_concurrent_requests = 2
	transport.max_retries = 1
	transport.retry_base_delay_msec = 1
	transport.timeout_seconds = 1.0
	transport.response_body_limit_bytes = 1024
	root.add_child(transport)

	await _test_success_and_redaction(transport)
	await _test_retry_policy(transport)
	await _test_concurrency(transport)
	await _test_cancellation(transport)
	await _test_limits(transport)

	transport.queue_free()
	_close_server()
	await process_frame
	_finish()


func _test_success_and_redaction(transport: KickHttpTransport) -> void:
	var started_urls: PackedStringArray = PackedStringArray()
	var capture: Callable = func(_ticket_id: int, redacted_url: String, _attempt: int) -> void: started_urls.append(redacted_url)
	transport.request_started.connect(capture)
	var secret: String = "fixture-broker-secret"
	var ticket: KickHttpTicket = transport.request(_url("/ok?token=" + secret.uri_encode()))
	await _drive_until_completed([ticket])
	transport.request_started.disconnect(capture)
	_check(ticket.response != null and ticket.response.is_success(), "bounded transport completes a JSON request")
	_check(ticket.response.parsed_json is Dictionary and ticket.response.parsed_json.ok, "successful response parses JSON")
	_check(ticket.response.header("x-ratelimit-remaining") == "9", "response exposes rate-limit metadata")
	_check(started_urls.size() == 1 and not started_urls[0].contains(secret) and started_urls[0].contains("[REDACTED]"), "transport diagnostics redact broker-like URL values")


func _test_retry_policy(transport: KickHttpTransport) -> void:
	var retries: Array[int] = []
	var capture: Callable = func(_ticket_id: int, attempt: int, _delay: int) -> void: retries.append(attempt)
	transport.request_retried.connect(capture)
	var safe: KickHttpTicket = transport.request(_url("/retry"))
	await _drive_until_completed([safe])
	_check(safe.response != null and safe.response.is_success() and safe.response.attempt_count == 2, "safe GET retries one transient 503")
	_check(int(_path_counts.get("/retry", 0)) == 2 and retries == [2], "safe retry is bounded and observable")
	var unsafe: KickHttpTicket = transport.request(_url("/write-retry"), PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, "{}".to_utf8_buffer(), null, false)
	await _drive_until_completed([unsafe])
	_check(unsafe.response != null and unsafe.response.status_code == 503 and unsafe.response.attempt_count == 1, "write request is never retried without explicit safety")
	_check(int(_path_counts.get("/write-retry", 0)) == 1, "server observes one unsafe write attempt")
	transport.request_retried.disconnect(capture)


func _test_concurrency(transport: KickHttpTransport) -> void:
	_release_delayed = false
	var tickets: Array[KickHttpTicket] = [
		transport.request(_url("/delayed/one")),
		transport.request(_url("/delayed/two")),
		transport.request(_url("/delayed/three")),
	]
	for _frame: int in 20:
		_service_server()
		await process_frame
	_check(transport.active_count() == 2 and transport.queued_count() == 1, "transport enforces concurrency and queue bounds")
	_release_delayed = true
	await _drive_until_completed(tickets)
	_check(tickets.all(func(ticket: KickHttpTicket) -> bool: return ticket.response != null and ticket.response.is_success()), "queued requests finish after a slot opens")


func _test_cancellation(transport: KickHttpTransport) -> void:
	var cancellation: KickCancellationToken = KickCancellationToken.new()
	var ticket: KickHttpTicket = transport.request(_url("/slow"), PackedStringArray(), HTTPClient.METHOD_GET, PackedByteArray(), cancellation)
	for _frame: int in 10:
		_service_server()
		await process_frame
	cancellation.cancel("fixture stop")
	await _drive_until_completed([ticket])
	_check(ticket.is_cancelled and ticket.cancellation_reason == "fixture stop", "active request cancellation is typed and preserves a safe reason")
	_check(ticket.response != null and ticket.response.error != null and ticket.response.error.category == "cancelled", "cancelled request returns a typed error")
	_check(transport.active_count() == 0, "cancelled request releases its transport slot")


func _test_limits(transport: KickHttpTransport) -> void:
	var oversized: KickHttpTicket = transport.request(_url("/oversized"))
	await _drive_until_completed([oversized])
	_check(oversized.response != null and oversized.response.request_result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, "oversized response is rejected by the engine body limit")
	var insecure: KickHttpTicket = transport.request("http://example.com/unsafe")
	_check(insecure.is_completed and insecure.response.error != null, "non-loopback plaintext HTTP is rejected before network access")
	var large_body: PackedByteArray = PackedByteArray()
	large_body.resize(transport.request_body_limit_bytes + 1)
	var body_ticket: KickHttpTicket = transport.request(_url("/ok"), PackedStringArray(), HTTPClient.METHOD_POST, large_body)
	_check(body_ticket.is_completed and body_ticket.response.error != null, "oversized request body is rejected before network access")


func _drive_until_completed(tickets: Array, max_frames: int = MAX_FRAMES) -> void:
	for _frame: int in max_frames:
		_service_server()
		var complete: bool = true
		for ticket: KickHttpTicket in tickets:
			if not ticket.is_completed:
				complete = false
				break
		if complete:
			return
		await process_frame
	_failures.append("timed out waiting for HTTP tickets")


func _service_server() -> void:
	while _server != null and _server.is_connection_available():
		_peers.append({"peer": _server.take_connection(), "request": "", "responded": false, "path": ""})
	for item: Dictionary in _peers:
		if bool(item.responded):
			continue
		var peer: StreamPeerTCP = item.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var available: int = peer.get_available_bytes()
		if available > 0:
			item.request = str(item.request) + peer.get_utf8_string(available)
		if not str(item.request).contains("\r\n\r\n"):
			continue
		if str(item.path).is_empty():
			var first_line: String = str(item.request).split("\r\n", false)[0]
			var parts: PackedStringArray = first_line.split(" ", false)
			var target: String = parts[1] if parts.size() >= 2 else "/invalid"
			item.path = target.split("?", false)[0]
			_path_counts[item.path] = int(_path_counts.get(item.path, 0)) + 1
		var path: String = item.path
		if path == "/slow" or (path.begins_with("/delayed/") and not _release_delayed):
			continue
		if path == "/retry" and int(_path_counts[path]) == 1:
			_send_json(peer, 503, {"error": {"message": "fixture transient"}})
		elif path == "/write-retry":
			_send_json(peer, 503, {"error": {"message": "do not retry write"}})
		elif path == "/oversized":
			var body: PackedByteArray = PackedByteArray()
			body.resize(2048)
			body.fill(65)
			_send_bytes(peer, 200, "application/octet-stream", body)
		else:
			_send_json(peer, 200, {"ok": true, "path": path})
		item.responded = true


func _send_json(peer: StreamPeerTCP, status: int, payload: Dictionary) -> void:
	_send_bytes(peer, status, "application/json", JSON.stringify(payload).to_utf8_buffer())


func _send_bytes(peer: StreamPeerTCP, status: int, content_type: String, body: PackedByteArray) -> void:
	var reason: String = "OK" if status == 200 else "Service Unavailable"
	var header: String = (
		"HTTP/1.1 %d %s\r\n" % [status, reason] +
		"Content-Type: %s\r\n" % content_type +
		"Content-Length: %d\r\n" % body.size() +
		"X-RateLimit-Remaining: 9\r\n" +
		"Connection: close\r\n\r\n"
	)
	peer.put_data(header.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()


func _url(path: String) -> String:
	return "http://127.0.0.1:%d%s" % [_server.get_local_port(), path]


func _close_server() -> void:
	for item: Dictionary in _peers:
		var peer: StreamPeerTCP = item.peer
		if peer != null:
			peer.disconnect_from_host()
	_peers.clear()
	if _server != null:
		_server.stop()
	_server = null


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("REDOT KICKER HTTP TRANSPORT SUITE PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("REDOT KICKER HTTP TRANSPORT SUITE FAIL: " + failure)
	print("REDOT KICKER HTTP TRANSPORT SUITE FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
