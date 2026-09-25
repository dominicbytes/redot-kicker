extends SceneTree

const SourceClass = preload("res://addons/redot-kicker/transport/kick_relay_event_source.gd")
const DeduplicatorClass = preload("res://addons/redot-kicker/transport/kick_event_deduplicator.gd")

var _checks: int = 0
var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if OS.get_cmdline_user_args().has("--dedupe-baseline"):
		_benchmark_original_deduplication()
		quit(0)
		return
	if not OS.get_cmdline_user_args().has("--bench-only"):
		_test_deduplication_policy()
	await _test_actual_receiver()
	_finish()


func _benchmark_original_deduplication() -> void:
	var cache: KickEventDeduplicator = DeduplicatorClass.new(5000, 3600)
	var accepted: int = 0
	var refused: int = 0
	var started: int = Time.get_ticks_msec()
	for index: int in 6000:
		var result: String = cache.check_and_remember("event-%d" % index, 100)
		if result == "new":
			accepted += 1
		elif result == "capacity_exhausted":
			refused += 1
	print("BENCH original_dedupe_6000_ms=%d accepted=%d refused=%d retained=%d" % [Time.get_ticks_msec() - started, accepted, refused, cache.size()])


func _test_deduplication_policy() -> void:
	var webhook_cache: KickEventDeduplicator = DeduplicatorClass.new(1, 3600)
	_check(webhook_cache.check_and_remember("signed-1", 100) == "new", "webhook replay cache accepts first ID")
	_check(webhook_cache.check_and_remember("signed-2", 100) == "capacity_exhausted", "webhook replay cache still fails closed")
	_check(webhook_cache.check_and_remember("signed-1", 100) == "duplicate", "webhook replay cache retains first ID")
	var dedupe_script: Variant = DeduplicatorClass
	var downlink_cache: KickEventDeduplicator = dedupe_script.new(5000, 3600, true)
	var started: int = Time.get_ticks_msec()
	for index: int in 6000:
		var result: String = downlink_cache.check_and_remember("event-%d" % index, 100)
		if result != "new":
			_failures.append("downlink cache refused fresh ID %d: %s" % [index, result])
			break
	print("BENCH dedupe_6000_ms=%d retained=%d" % [Time.get_ticks_msec() - started, downlink_cache.size()])
	_check(downlink_cache.size() == 5000, "downlink dedupe memory stays at 5000 IDs")
	_check(downlink_cache.check_and_remember("event-5999", 100) == "duplicate", "recent downlink replay is suppressed")
	_check(downlink_cache.check_and_remember("event-0", 100) == "new", "oldest downlink ID rolls out explicitly")


func _test_actual_receiver() -> void:
	var server: TCPServer = TCPServer.new()
	var listen_error: Error = server.listen(0, "127.0.0.1")
	_check(listen_error == OK, "loopback WebSocket server binds")
	if listen_error != OK:
		return
	var port: int = server.get_local_port()
	var descriptor: KickSessionDescriptor = KickSessionDescriptor.new()
	descriptor.tenant_id = "tenant"
	descriptor.application_id = "app"
	descriptor.session_id = "session"
	descriptor.channel_id = "channel"
	var ticket: KickEventTicket = KickEventTicket.new()
	ticket.socket_url = "ws://127.0.0.1:%d" % port
	ticket.ticket = "test-ticket"
	ticket.subscription_ids = PackedStringArray(["subscription"])
	var source: KickRelayEventSource = SourceClass.new()
	root.add_child(source)
	var received: Array[String] = []
	var errors: Array[String] = []
	source.event_received.connect(func(event: KickEvent) -> void: received.append(event.id))
	source.error_occurred.connect(func(error: KickApiError) -> void: errors.append(error.category))
	_check(source.connect_with_ticket(ticket, descriptor) == null, "receiver accepts loopback ticket")
	var peer: WebSocketPeer = null
	for _frame: int in 180:
		if peer == null and server.is_connection_available():
			peer = WebSocketPeer.new()
			_check(peer.accept_stream(server.take_connection()) == OK, "server accepts WebSocket stream")
		if peer != null:
			peer.poll()
		if peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN and source.state == "connected":
			break
		await process_frame
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN or source.state != "connected":
		_failures.append("actual WebSocket did not open")
		source.queue_free()
		server.stop()
		return
	_check(source._peer.max_queued_packets <= 1024, "engine WebSocket packet queue is capped")

	peer.send_text(JSON.stringify(_envelope("first")))
	peer.send_text(JSON.stringify(_envelope("first")))
	for _frame: int in 180:
		peer.poll()
		if received.size() > 0:
			break
		await process_frame
	_check(received == ["first"], "actual receiver emits first valid event once")
	_check(errors.is_empty(), "valid first event raises no deduplication error")

	var started: int = Time.get_ticks_msec()
	for index: int in 512:
		peer.send_text(JSON.stringify(_envelope("burst-%d" % index)))
	var frames: int = 0
	var max_delivered_in_frame: int = 0
	for _frame: int in 600:
		peer.poll()
		var before_frame: int = received.size()
		await process_frame
		max_delivered_in_frame = maxi(max_delivered_in_frame, received.size() - before_frame)
		if received.size() >= 513:
			break
		frames += 1
	print("BENCH websocket_512_frames=%d elapsed_ms=%d total_delivered=%d queue=%d" % [frames, Time.get_ticks_msec() - started, received.size(), source.queued_count()])
	_check(received.size() == 513, "512-event burst reaches actual receiver")
	_check(source.queued_count() <= source.max_queue_entries, "game queue remains bounded")
	_check(max_delivered_in_frame <= 64, "game signals obey default per-frame delivery budget")
	_check(frames <= 64, "512-event burst drains within 64 frames")
	_check(errors.is_empty(), "burst produces no validation errors")
	peer.send_text(JSON.stringify(_envelope("burst-511")))
	for _frame: int in 5:
		peer.poll()
		await process_frame
	_check(received.size() == 513, "recent burst replay is suppressed")

	source.max_queue_entries = 2
	var pressure: Array[int] = []
	source.queue_pressure.connect(func(queued: int, _capacity: int) -> void: pressure.append(queued))
	for index: int in 8:
		peer.send_text(JSON.stringify(_envelope("overflow-%d" % index)))
	for _frame: int in 20:
		peer.poll()
		await process_frame
	_check(received.size() == 515 and not pressure.is_empty(), "overflow drops excess events and reports pressure")
	_check(source.queued_count() <= 2, "overloaded game queue stays within configured bound")
	peer.send_text(JSON.stringify(_envelope("overflow-7")))
	for _frame: int in 20:
		peer.poll()
		if received.has("overflow-7"):
			break
		await process_frame
	_check(received.has("overflow-7"), "overflowed ID is not remembered and can be retried")
	peer.close()
	source.queue_free()
	server.stop()
	await process_frame


func _envelope(message_id: String) -> Dictionary:
	return {
		"platform": "kick", "schema_version": 1,
		"tenant_id": "tenant", "application_id": "app", "session_id": "session",
		"channel_id": "channel", "subscription_id": "subscription",
		"source_message_id": message_id, "event_type": "chat.message.sent",
		"event_version": 1, "supported": true, "payload": {},
	}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	for failure: String in _failures:
		push_error("STREAMING REPAIR FAIL: " + failure)
	print("STREAMING REPAIR %s: %d checks, %d failures" % ["PASS" if _failures.is_empty() else "FAIL", _checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
