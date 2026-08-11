extends SceneTree

const CONTRACT_PATH: String = "res://addons/redot-kicker/contracts/kick_api_contract.json"

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()


class MockCredentialClient extends RefCounted:
	var values: Dictionary = {}

	func store(target: String, secret: String, _cancellation: KickCancellationToken = null) -> KickCredentialResult:
		values[target] = secret
		return _result("ok")

	func read(target: String, _cancellation: KickCancellationToken = null) -> KickCredentialResult:
		if not values.has(target):
			return _result("not_found")
		var result: KickCredentialResult = _result("ok")
		result.secret = str(values[target])
		return result

	func delete(target: String, _cancellation: KickCancellationToken = null) -> KickCredentialResult:
		var existed: bool = values.erase(target)
		return _result("ok" if existed else "not_found")

	func _result(status: String) -> KickCredentialResult:
		var result: KickCredentialResult = KickCredentialResult.new()
		result.status = status
		return result


class MockDescriptorStore extends RefCounted:
	var values: Dictionary = {}

	func save(descriptor: KickSessionDescriptor) -> KickApiError:
		values[descriptor.session_slot] = KickSessionDescriptor.from_dictionary(descriptor.to_dictionary())
		return null

	func load_descriptor(slot: String) -> KickSessionDescriptorLoadResult:
		var result: KickSessionDescriptorLoadResult = KickSessionDescriptorLoadResult.new()
		if not values.has(slot):
			result.error = KickApiError.custom("not_found", "fixture descriptor missing")
			return result
		result.descriptor = KickSessionDescriptor.from_dictionary((values[slot] as KickSessionDescriptor).to_dictionary())
		return result

	func delete_descriptor(slot: String) -> KickApiError:
		values.erase(slot)
		return null


class MockBrokerClient extends RefCounted:
	var invoked: Array[String] = []
	var revoked: bool = false
	var session_slot: String = ""
	var capabilities: PackedStringArray = PackedStringArray()

	func begin_authorization(requested: PackedStringArray, slot: String, proof_hash: String, _cancellation: KickCancellationToken = null) -> KickAuthorizationRequest:
		capabilities = requested.duplicate()
		session_slot = slot
		var result: KickAuthorizationRequest = KickAuthorizationRequest.new()
		result.request_id = "fixture-request"
		result.authorization_url = "http://127.0.0.1:9876/authorize/fixture-request"
		result.expires_at_unix = int(Time.get_unix_time_from_system()) + 300
		result.poll_interval_msec = 250
		if proof_hash.is_empty():
			result.error = KickApiError.invalid("fixture proof hash missing")
		return result

	func poll_authorization(_request_id: String, proof: String, _cancellation: KickCancellationToken = null) -> KickAuthResult:
		return _session("fixture-broker-session", false) if not proof.is_empty() else _failed("fixture proof missing")

	func restore(_broker_session: String, slot: String, _cancellation: KickCancellationToken = null) -> KickAuthResult:
		session_slot = slot
		return _session("fixture-restored-session", true)

	func rotate(_broker_session: String, _cancellation: KickCancellationToken = null) -> KickAuthResult:
		return _session("fixture-rotated-session", true)

	func revoke(_broker_session: String, _cancellation: KickCancellationToken = null) -> KickApiResult:
		revoked = true
		return _api_result({"revoked": true})

	func invoke(_broker_session: String, operation_id: String, _query: Dictionary = {}, _path: Dictionary = {}, body: Dictionary = {}, _confirmed: bool = false, _idempotency_key: String = "", _cancellation: KickCancellationToken = null, _retry_safe: bool = false) -> KickApiResult:
		invoked.append(operation_id)
		if operation_id == "chat.send":
			return _api_result({"message_id": "fixture-message", "is_sent": not str(body.get("content", "")).is_empty()})
		if operation_id == "channels.get":
			return _api_result([{"broadcaster_user_id": 333.0, "slug": "fixture-channel", "stream_title": "Fixture"}])
		return _api_result({"operation_id": operation_id})

	func create_event_ticket(_broker_session: String, _cancellation: KickCancellationToken = null) -> KickEventTicket:
		var result: KickEventTicket = KickEventTicket.new()
		result.socket_url = "ws://127.0.0.1:9876/v1/events/socket"
		result.ticket = "fixture-ticket"
		result.expires_at_unix = int(Time.get_unix_time_from_system()) + 30
		result.subscription_ids = PackedStringArray(["fixture-subscription"])
		return result

	func _session(secret: String, restored: bool) -> KickAuthResult:
		var result: KickAuthResult = KickAuthResult.new()
		result.descriptor = _descriptor()
		result.broker_session = secret
		result.restored = restored
		return result

	func _descriptor() -> KickSessionDescriptor:
		var descriptor: KickSessionDescriptor = KickSessionDescriptor.new()
		descriptor.session_slot = session_slot
		descriptor.tenant_id = "fixture-tenant"
		descriptor.application_id = "fixture-app"
		descriptor.session_id = "fixture-session"
		descriptor.user_id = "111"
		descriptor.username = "fixture-user"
		descriptor.channel_id = "333"
		descriptor.channel_slug = "fixture-channel"
		descriptor.granted_capabilities = capabilities.duplicate()
		descriptor.granted_scopes = KickCapabilityRegistry.scopes_for(capabilities)
		descriptor.subscription_ids = PackedStringArray(["fixture-subscription"])
		descriptor.broker_session_expires_at_unix = int(Time.get_unix_time_from_system()) + 3600
		return descriptor

	func _api_result(data: Variant) -> KickApiResult:
		var result: KickApiResult = KickApiResult.new()
		result.http_status = 200
		result.data = data
		return result

	func _failed(message: String) -> KickAuthResult:
		var result: KickAuthResult = KickAuthResult.new()
		result.error = KickApiError.invalid(message)
		return result


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_test_contract_and_capabilities()
	_test_protocol_and_sanitization()
	_test_models_and_events()
	await _test_authorization_persistence_and_services()
	_finish()


func _test_contract_and_capabilities() -> void:
	var contract: Dictionary = _load_json(CONTRACT_PATH)
	var operations: Array = contract.get("endpoints", [])
	_check(operations.size() == 28, "frozen Kick contract contains 28 operations")
	_check(KickCapabilityRegistry.all_operation_info().size() == 28, "capability registry covers every frozen operation")
	_check(KickCapabilityRegistry.all_capabilities().size() == 14, "capability registry exposes the frozen capability set")
	var expected_scopes: PackedStringArray = KickCapabilityRegistry.scopes_for(PackedStringArray(["identity.read", "chat.write", "events.receive"]))
	_check(expected_scopes == PackedStringArray(["chat:write", "events:subscribe", "user:read"]), "minimum scopes are stable and sorted")
	var gate: KickCapabilityGate = KickCapabilityGate.new()
	gate.configure(PackedStringArray(["channel.manage", "streamkey.read"]), PackedStringArray(["channel:write", "streamkey:read"]), true, true)
	_check(gate.require_operation("channels.update", false).category == "confirmation_required", "destructive channel update requires confirmation")
	_check(gate.require_operation("channels.update", true) == null, "confirmed channel update passes capability gate")
	_check(gate.require_operation("stream_key.get", true).category == "unavailable", "declared stream-key scope remains explicitly unavailable")


func _test_protocol_and_sanitization() -> void:
	var protocol: KickCredentialProtocol = KickCredentialProtocol.new()
	var wire: String = protocol.encode_request("store", "publisher/app/slot", "fixture-secret")
	var decoded: Dictionary = protocol.decode_request_for_test(wire)
	_check(decoded.command == "store" and decoded.target == "publisher/app/slot" and decoded.secret == "fixture-secret", "RKCH/1 request round-trips UTF-8 fields")
	_check(protocol.decode_response("RTCH/1\nOK\n\nwrong\n").status == "protocol_error", "Tuber credential protocol is rejected")
	var safe: Variant = KickDataSanitizer.sanitize({
		"access_token": "forbidden",
		"stream": {"key": "forbidden", "url": "rtmps://forbidden", "is_live": true},
		"thumbnail": "https://safe.example/image.webp",
	})
	_check(not safe.has("access_token"), "API sanitizer removes OAuth tokens")
	_check(not safe.stream.has("key") and not safe.stream.has("url") and safe.stream.is_live, "API sanitizer strips stream key and RTMP URL")
	_check(safe.thumbnail == "https://safe.example/image.webp", "API sanitizer preserves public media URLs")


func _test_models_and_events() -> void:
	var channel: KickChannel = KickChannel.from_dictionary({"broadcaster_user_id": 333.0, "slug": "fixture", "stream": {"is_live": true, "viewer_count": 5}})
	_check(channel.broadcaster_user_id == "333" and channel.stream != null and channel.stream.is_live, "typed channel normalizes numeric IDs and livestream state")
	var normalizer: KickEventNormalizer = KickEventNormalizer.new()
	var event_types: PackedStringArray = KickSubscriptionService.SUPPORTED_EVENTS
	for event_type: String in event_types:
		var payload: Dictionary = _event_payload(event_type)
		var event: KickEvent = normalizer.normalize({
			"platform": "kick",
			"schema_version": 1,
			"tenant_id": "fixture-tenant",
			"application_id": "fixture-app",
			"session_id": "fixture-session",
			"subscription_id": "fixture-subscription",
			"source_message_id": "message-" + event_type,
			"event_type": event_type,
			"event_version": 1,
			"occurred_at": "2026-08-11T12:00:00Z",
			"received_at": "2026-08-11T12:00:01Z",
			"channel_id": "333",
			"supported": true,
			"payload": payload,
		})
		_check(event != null and event.event_type == event_type and event.broadcaster.id == "333", "typed event normalizes " + event_type)
	var unknown: KickEvent = normalizer.normalize({"platform":"kick","schema_version":1,"tenant_id":"t","application_id":"a","session_id":"s","subscription_id":"sub","source_message_id":"m","event_type":"future.event","event_version":2,"channel_id":"333","supported":false,"payload":{"broadcaster":{"user_id":333}}})
	_check(unknown != null and unknown.is_unknown, "future event uses the typed unknown path")


func _test_authorization_persistence_and_services() -> void:
	KickSessionSlotRegistry.clear_for_tests()
	var config: KickClientConfig = KickClientConfig.new()
	config.relay_base_url = "http://127.0.0.1:9876"
	config.publisher_id = "fixture-publisher"
	config.application_id = "fixture-app"
	var capabilities: PackedStringArray = KickCapabilityRegistry.all_capabilities()
	var credentials: MockCredentialClient = MockCredentialClient.new()
	var descriptors: MockDescriptorStore = MockDescriptorStore.new()
	var broker: MockBrokerClient = MockBrokerClient.new()
	var transport: KickHttpTransport = KickHttpTransport.new()
	root.add_child(transport)
	var auth: KickAuthManager = KickAuthManager.new()
	root.add_child(auth)
	_check(auth.configure(config, capabilities, "primary", transport, credentials, descriptors, broker) == null, "auth manager configures a stable isolated session slot")
	var request: KickAuthorizationRequest = await auth.begin_authorization(false)
	_check(request.is_success() and request.authorization_url.begins_with(config.relay_base_url), "broker authorization returns only a safe same-relay URL")
	var authorized: KickAuthResult = await auth.wait_for_authorization()
	_check(authorized.is_success() and auth.state == "connected", "broker authorization establishes a connected descriptor")
	var target: String = config.credential_target("primary")
	_check(credentials.values.has(target), "opaque broker session is persisted through the vault boundary")
	var saved_text: String = JSON.stringify((descriptors.values.primary as KickSessionDescriptor).to_dictionary())
	_check(not saved_text.contains("fixture-broker-session") and not saved_text.contains("access_token") and not saved_text.contains("refresh_token"), "user descriptor contains no broker or Kick token secret")

	var conflicting: KickAuthManager = KickAuthManager.new()
	root.add_child(conflicting)
	var conflict_error: KickApiError = conflicting.configure(config, capabilities, "primary", transport, credentials, descriptors, broker)
	_check(conflict_error != null, "two live clients cannot acquire the same session slot")
	conflicting.queue_free()
	auth.queue_free()
	await process_frame

	var restored_auth: KickAuthManager = KickAuthManager.new()
	root.add_child(restored_auth)
	_check(restored_auth.configure(config, capabilities, "primary", transport, credentials, descriptors, broker) == null, "released slot can be acquired after restart")
	var restored: KickAuthResult = await restored_auth.restore()
	_check(restored.is_success() and restored.restored and restored_auth.descriptor.channel_id == "333", "saved broker session restores the connected Kick identity")
	_check(str(credentials.values[target]) == "fixture-restored-session", "restore atomically replaces the stored broker session")
	var rotated: KickAuthResult = await restored_auth.rotate()
	_check(rotated.is_success() and str(credentials.values[target]) == "fixture-rotated-session", "broker-session rotation replaces the vault entry")

	var gate: KickCapabilityGate = KickCapabilityGate.new()
	gate.configure(restored_auth.granted_capabilities(), restored_auth.granted_scopes(), true, true)
	var api: KickApiClient = KickApiClient.new()
	api.configure(restored_auth, gate)
	var channels: KickChannelService = KickChannelService.new(api)
	var channel_result: KickApiResult = await channels.get_current()
	_check(channel_result.is_success() and channel_result.data is Array and (channel_result.data[0] as KickChannel).slug == "fixture-channel", "typed channel service traverses the broker allowlist")
	var chat: KickChatService = KickChatService.new(api)
	var invalid_chat: KickApiResult = await chat.send_message("", "user", "333")
	_check(invalid_chat.error != null and broker.invoked.count("chat.send") == 0, "invalid chat is rejected before broker invocation")
	var sent: KickApiResult = await chat.send_message("Hello from Redot", "user", "333")
	_check(sent.is_success() and sent.data is KickChatReceipt and sent.data.is_sent, "typed chat action uses the allowlisted broker operation")
	var ticket: KickEventTicket = await restored_auth.create_event_ticket()
	_check(ticket.is_success() and ticket.socket_url.begins_with("ws://127.0.0.1:"), "event ticket is short-lived and separate from the broker credential")
	var revoke_error: KickApiError = await restored_auth.revoke_and_disconnect()
	_check(revoke_error == null and broker.revoked, "revoke reaches the broker")
	_check(not credentials.values.has(target) and not descriptors.values.has("primary"), "revoke clears vault and non-secret descriptor state")
	restored_auth.queue_free()
	transport.queue_free()
	await process_frame


func _event_payload(event_type: String) -> Dictionary:
	var broadcaster: Dictionary = {"user_id": 333.0, "username": "fixture-channel", "channel_slug": "fixture-channel"}
	var actor: Dictionary = {"user_id": 444.0, "username": "fixture-actor"}
	var payload: Dictionary = {"broadcaster": broadcaster, "created_at": "2026-08-11T12:00:00Z"}
	match event_type:
		"chat.message.sent": payload.merge({"sender": actor, "message_id": "chat-1", "content": "hello"})
		"channel.followed": payload["follower"] = actor
		"channel.subscription.renewal", "channel.subscription.new": payload.merge({"subscriber": actor, "duration": 1})
		"channel.subscription.gifts": payload.merge({"gifter": actor, "giftees": [actor]})
		"channel.reward.redemption.updated": payload.merge({"redeemer": actor, "id": "redemption-1", "status": "pending", "reward": {"id": "reward-1", "title": "Fixture", "cost": 100}})
		"livestream.status.updated": payload.merge({"is_live": true, "title": "Fixture"})
		"livestream.metadata.updated": payload["metadata"] = {"title": "Fixture", "language": "en"}
		"moderation.banned": payload.merge({"moderator": actor, "banned_user": {"user_id": 555}, "metadata": {"reason": "fixture"}})
		"kicks.gifted": payload.merge({"sender": actor, "gift": {"amount": 500}})
	return payload


func _load_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("REDOT KICKER CORE SUITE PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("REDOT KICKER CORE SUITE FAIL: " + failure)
	print("REDOT KICKER CORE SUITE FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
