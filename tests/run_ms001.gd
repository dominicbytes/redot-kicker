extends SceneTree

const ROOT: String = "res://addons/redot-kicker"
const FIXTURE_PATH: String = "res://tests/fixtures/ms001/chat_message.json"
const SOURCE_PIN: String = "7f7afe7ace9424f722c8e6b06e32421099c8e7f6"

const BindingClass = preload("res://addons/redot-kicker/models/kick_relay_binding.gd")
const ValidatorClass = preload("res://addons/redot-kicker/transport/kick_webhook_validator.gd")
const DownlinkClass = preload("res://addons/redot-kicker/transport/kick_mock_downlink.gd")
const RedactorClass = preload("res://addons/redot-kicker/diagnostics/kick_redactor.gd")

var _failures: PackedStringArray = []
var _checks: int = 0
var _crypto: Crypto = Crypto.new()
var _private_key: CryptoKey
var _public_key: CryptoKey
var _binding: KickRelayBinding
var _fixture_body: PackedByteArray
var _fixture_timestamp: String = "2026-08-11T12:00:00Z"
var _fixture_now: int = 0


func _init() -> void:
	call_deferred(&"_run")


func _run() -> void:
	await process_frame
	_test_contract_files()
	if not _prepare_crypto_and_fixture():
		_finish()
		return
	_test_signature_and_ingress()
	_test_identity_and_forward_compatibility()
	_test_downlink_reliability()
	_test_redaction()
	_finish()


func _test_contract_files() -> void:
	for path: String in [
		ROOT + "/contracts/kick_api_contract.json",
		ROOT + "/contracts/relay_ingress.schema.json",
		ROOT + "/contracts/relay_downlink.schema.json",
		ROOT + "/contracts/broker_contract.json",
		ROOT + "/contracts/fixture_ledger.json",
	]:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_check(parsed is Dictionary, "contract parses: %s" % path)
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/contracts/kick_api_contract.json"))
	_check(String(contract.get("source", {}).get("documentation_commit", "")) == SOURCE_PIN, "official documentation pin is frozen")
	_check((contract.get("scopes", []) as Array).size() == 11, "all current official OAuth scopes are classified")
	_check((contract.get("events", []) as Array).size() == 10, "all current official webhook event types are classified")


func _prepare_crypto_and_fixture() -> bool:
	_private_key = _crypto.generate_rsa(2048)
	_check(_private_key != null, "ephemeral RSA-2048 fixture key is generated")
	if _private_key == null:
		return false
	_public_key = CryptoKey.new()
	var public_load_error: Error = _public_key.load_from_string(_private_key.save_to_string(true), true)
	_check(public_load_error == OK and _public_key.is_public_only(), "fixture verifier uses public-only key material")
	_fixture_body = FileAccess.get_file_as_bytes(FIXTURE_PATH)
	_check(not _fixture_body.is_empty(), "raw webhook fixture loads as exact bytes")
	_fixture_now = int(Time.get_unix_time_from_datetime_string(_fixture_timestamp))
	_check(_fixture_now > 0, "fixture RFC3339 timestamp parses")
	_binding = BindingClass.new()
	_binding.tenant_id = "fixture-tenant"
	_binding.application_id = "fixture-app"
	_binding.channel_id = "123456789"
	_binding.subscription_id = "01J5KICKERSUBSCRIPTION000001"
	_binding.session_id = "fixture-session"
	_check(_binding.validate().is_empty(), "relay binding is valid")
	return public_load_error == OK and not _fixture_body.is_empty()


func _test_signature_and_ingress() -> void:
	var validator: KickWebhookValidator = ValidatorClass.new(16, 600)
	var message_id: String = "01J5KICKERMESSAGE0000000001"
	var headers: Dictionary = _signed_headers(message_id, _fixture_timestamp, "chat.message.sent", "1", _fixture_body)
	var valid: KickRelayResult = validator.validate_and_transform(_fixture_body, headers, _public_key, _binding, _fixture_now)
	_check(valid.is_accepted() and not valid.is_unknown_event(), "valid signature and binding are accepted (got %s/%s)" % [valid.status, valid.code])
	_check(valid.envelope.get("source_message_id", "") == message_id, "source message identity is preserved")
	_check(not valid.envelope.has("signature"), "downlink envelope excludes signing material")

	var mutated_body: PackedByteArray = _fixture_body.duplicate()
	mutated_body[mutated_body.size() - 2] = 32
	var mutated: KickRelayResult = validator.validate_and_transform(mutated_body, headers, _public_key, _binding, _fixture_now)
	_check(mutated.code == "signature_invalid", "body mutation invalidates the signature")

	var bad_headers: Dictionary = headers.duplicate()
	bad_headers["Kick-Event-Signature"] = Marshalls.raw_to_base64(PackedByteArray([1, 2, 3, 4]))
	var bad_signature: KickRelayResult = validator.validate_and_transform(_fixture_body, bad_headers, _public_key, _binding, _fixture_now)
	_check(bad_signature.code == "signature_invalid", "invalid signature is rejected")

	var malformed: PackedByteArray = "{not-json".to_utf8_buffer()
	var malformed_bad_headers: Dictionary = _signed_headers("01J5KICKERMESSAGE0000000002", _fixture_timestamp, "chat.message.sent", "1", malformed)
	malformed_bad_headers["Kick-Event-Signature"] = Marshalls.raw_to_base64(PackedByteArray([9, 9, 9]))
	var precedence: KickRelayResult = validator.validate_and_transform(malformed, malformed_bad_headers, _public_key, _binding, _fixture_now)
	_check(precedence.code == "signature_invalid", "signature rejection occurs before payload parsing")

	var signed_malformed_headers: Dictionary = _signed_headers("01J5KICKERMESSAGE0000000003", _fixture_timestamp, "chat.message.sent", "1", malformed)
	var signed_malformed: KickRelayResult = validator.validate_and_transform(malformed, signed_malformed_headers, _public_key, _binding, _fixture_now)
	_check(signed_malformed.code == "malformed_payload", "authenticated malformed JSON is explicitly rejected")

	var stale_timestamp: String = "2026-08-11T11:00:00Z"
	var stale_headers: Dictionary = _signed_headers("01J5KICKERMESSAGE0000000004", stale_timestamp, "chat.message.sent", "1", _fixture_body)
	var stale: KickRelayResult = validator.validate_and_transform(_fixture_body, stale_headers, _public_key, _binding, _fixture_now)
	_check(stale.code == "timestamp_stale", "stale signed timestamp is rejected")

	var replay: KickRelayResult = validator.validate_and_transform(_fixture_body, headers, _public_key, _binding, _fixture_now)
	_check(replay.code == "duplicate", "replayed message identity is rejected")
	_check(validator.replay_entry_count() <= 16, "replay cache remains bounded")
	var capacity_validator: KickWebhookValidator = ValidatorClass.new(1, 600)
	var capacity_first_headers: Dictionary = _signed_headers("01J5KICKERCAPACITY000000001", _fixture_timestamp, "chat.message.sent", "1", _fixture_body)
	var capacity_second_headers: Dictionary = _signed_headers("01J5KICKERCAPACITY000000002", _fixture_timestamp, "chat.message.sent", "1", _fixture_body)
	_check(capacity_validator.validate_and_transform(_fixture_body, capacity_first_headers, _public_key, _binding, _fixture_now).is_accepted(), "replay cache accepts within capacity")
	var at_capacity: KickRelayResult = capacity_validator.validate_and_transform(_fixture_body, capacity_second_headers, _public_key, _binding, _fixture_now)
	_check(at_capacity.code == "replay_capacity" and capacity_validator.replay_entry_count() == 1, "replay cache fails closed without evicting a fresh identity")

	var small_validator: KickWebhookValidator = ValidatorClass.new()
	small_validator.max_body_bytes = 64
	var oversized: KickRelayResult = small_validator.validate_and_transform(_fixture_body, headers, _public_key, _binding, _fixture_now)
	_check(oversized.code == "body_too_large", "oversized body is rejected before cryptographic or parse work")


func _test_identity_and_forward_compatibility() -> void:
	var validator: KickWebhookValidator = ValidatorClass.new()
	var wrong_subscription: Dictionary = _signed_headers("01J5KICKERMESSAGE0000000005", _fixture_timestamp, "chat.message.sent", "1", _fixture_body)
	wrong_subscription["Kick-Event-Subscription-Id"] = "01J5KICKERWRONGSUBSCRIPTION01"
	var subscription_result: KickRelayResult = validator.validate_and_transform(_fixture_body, wrong_subscription, _public_key, _binding, _fixture_now)
	_check(subscription_result.code == "subscription_mismatch", "subscription mismatch is rejected")

	var wrong_channel_payload: Dictionary = JSON.parse_string(_fixture_body.get_string_from_utf8())
	wrong_channel_payload["broadcaster"]["user_id"] = 222222222
	var wrong_channel_body: PackedByteArray = (JSON.stringify(wrong_channel_payload) + "\n").to_utf8_buffer()
	var wrong_channel_headers: Dictionary = _signed_headers("01J5KICKERMESSAGE0000000006", _fixture_timestamp, "chat.message.sent", "1", wrong_channel_body)
	var channel_result: KickRelayResult = validator.validate_and_transform(wrong_channel_body, wrong_channel_headers, _public_key, _binding, _fixture_now)
	_check(channel_result.code == "channel_mismatch", "broadcaster mismatch is rejected")

	var unknown_type_headers: Dictionary = _signed_headers("01J5KICKERMESSAGE0000000007", _fixture_timestamp, "future.event.created", "1", _fixture_body)
	var unknown_type: KickRelayResult = validator.validate_and_transform(_fixture_body, unknown_type_headers, _public_key, _binding, _fixture_now)
	_check(unknown_type.is_unknown_event() and not bool(unknown_type.envelope.get("supported", true)), "unknown event type uses forward-compatible path (got %s/%s)" % [unknown_type.status, unknown_type.code])

	var unknown_version_headers: Dictionary = _signed_headers("01J5KICKERMESSAGE0000000008", _fixture_timestamp, "chat.message.sent", "99", _fixture_body)
	var unknown_version: KickRelayResult = validator.validate_and_transform(_fixture_body, unknown_version_headers, _public_key, _binding, _fixture_now)
	_check(unknown_version.is_unknown_event(), "unknown event version uses forward-compatible path (got %s/%s)" % [unknown_version.status, unknown_version.code])


func _test_downlink_reliability() -> void:
	var validator: KickWebhookValidator = ValidatorClass.new()
	var headers: Dictionary = _signed_headers("01J5KICKERMESSAGE0000000009", _fixture_timestamp, "chat.message.sent", "1", _fixture_body)
	var accepted: KickRelayResult = validator.validate_and_transform(_fixture_body, headers, _public_key, _binding, _fixture_now)
	_check(accepted.is_accepted(), "downlink fixture passes ingress (got %s/%s)" % [accepted.status, accepted.code])

	var downlink: KickMockDownlink = DownlinkClass.new()
	_check(downlink.configure(_binding, "fixture-broker-credential", 1) == "configured", "mock downlink configures")
	_check(not downlink.connect_session("wrong-credential"), "wrong broker session is rejected")
	_check(downlink.connect_session("fixture-broker-credential"), "opaque broker session authenticates")
	var event_count: Array[int] = [0]
	downlink.event_received.connect(func(_event: KickEvent) -> void: event_count[0] += 1)
	_check(downlink.receive(accepted.envelope) == "accepted", "authorized envelope enters bounded queue")
	_check(downlink.pump_one() == "emitted", "authorized envelope emits one typed event")
	_check(event_count[0] == 1, "typed event emitted exactly once")
	_check(downlink.receive(accepted.envelope) == "duplicate", "downlink suppresses duplicate source identity")

	downlink.disconnect_relay("relay_loss")
	_check(downlink.state() == "disconnected", "relay loss is visible")
	_check(downlink.connect_session("fixture-broker-credential"), "downlink reconnects with valid session")
	_check(downlink.receive(accepted.envelope) == "duplicate", "reconnect replay does not emit twice")
	_check(event_count[0] == 1, "reconnect preserves exactly-once game emission")

	var other_tenant: Dictionary = accepted.envelope.duplicate(true)
	other_tenant["tenant_id"] = "other-tenant"
	other_tenant["source_message_id"] = "01J5KICKERMESSAGE0000000010"
	_check(downlink.receive(other_tenant) == "tenant_mismatch", "cross-tenant envelope is rejected")

	var overflow: KickMockDownlink = DownlinkClass.new()
	overflow.configure(_binding, "fixture-broker-credential", 1)
	overflow.connect_session("fixture-broker-credential")
	var first: Dictionary = accepted.envelope.duplicate(true)
	first["source_message_id"] = "01J5KICKERMESSAGE0000000011"
	var second: Dictionary = accepted.envelope.duplicate(true)
	second["source_message_id"] = "01J5KICKERMESSAGE0000000012"
	_check(overflow.receive(first) == "accepted", "first queued event is accepted")
	_check(overflow.receive(second) == "queue_overflow", "queue overflow is explicit")
	_check(overflow.state() == "degraded" and overflow.queued_count() == 1, "overflow preserves bound and visible degraded state")
	_check(overflow.pump_one() == "emitted", "overflow queue can drain without losing its accepted event")
	_check(overflow.receive(second) == "accepted", "an event rejected for overflow can be retried after pressure clears")

	var unknown_headers: Dictionary = _signed_headers("01J5KICKERMESSAGE0000000013", _fixture_timestamp, "future.event.created", "7", _fixture_body)
	var unknown_result: KickRelayResult = ValidatorClass.new().validate_and_transform(_fixture_body, unknown_headers, _public_key, _binding, _fixture_now)
	var unknown_downlink: KickMockDownlink = DownlinkClass.new()
	unknown_downlink.configure(_binding, "fixture-broker-credential", 2)
	unknown_downlink.connect_session("fixture-broker-credential")
	var unknown_count: Array[int] = [0]
	unknown_downlink.unknown_event_received.connect(func(_event: KickEvent) -> void: unknown_count[0] += 1)
	_check(unknown_downlink.receive(unknown_result.envelope) == "accepted", "unknown authenticated envelope keeps downlink connected")
	_check(unknown_downlink.pump_one() == "unknown_event" and unknown_count[0] == 1, "unknown envelope emits typed forward-compatible event")


func _test_redaction() -> void:
	var redactor: KickRedactor = RedactorClass.new()
	var safe: Dictionary = redactor.redact_dictionary({
		"authorization": "Bearer fixture-secret",
		"broker_session": "fixture-broker-credential",
		"payload": {"content": "private chat"},
		"code": "fixture-code",
		"status": "rejected",
	})
	_check(safe.get("authorization", "") == KickRedactor.REDACTED, "authorization is redacted")
	_check(safe.get("broker_session", "") == KickRedactor.REDACTED, "broker credential is redacted")
	_check(safe.get("payload", "") == KickRedactor.OMITTED, "raw event payload is omitted from diagnostics")
	var text: String = redactor.redact_text("Authorization: Bearer fixture-secret token=fixture-token")
	_check(not text.contains("fixture-secret") and not text.contains("fixture-token"), "text diagnostics redact bearer and token values")


func _signed_headers(message_id: String, timestamp: String, event_type: String, version: String, body: PackedByteArray) -> Dictionary:
	var signed_bytes: PackedByteArray = (message_id + "." + timestamp + ".").to_utf8_buffer()
	signed_bytes.append_array(body)
	var hashing: HashingContext = HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(signed_bytes) != OK:
		return {}
	var signature: PackedByteArray = _crypto.sign(HashingContext.HASH_SHA256, hashing.finish(), _private_key)
	return {
		"Kick-Event-Message-Id": message_id,
		"Kick-Event-Subscription-Id": _binding.subscription_id,
		"Kick-Event-Signature": Marshalls.raw_to_base64(signature),
		"Kick-Event-Message-Timestamp": timestamp,
		"Kick-Event-Type": event_type,
		"Kick-Event-Version": version,
	}


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _finish() -> void:
	var output: Dictionary = {
		"suite": "MS-001",
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"checks": _checks,
		"failures": Array(_failures),
		"source_pin": SOURCE_PIN,
		"redot_version": String(Engine.get_version_info().get("string", "unknown")),
	}
	var file: FileAccess = FileAccess.open("res://.test-output/ms001/latest.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(output, "  ") + "\n")
		file.close()
	if _failures.is_empty():
		print("MS-001 PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("MS-001 FAIL: %s" % failure)
	print("MS-001 FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
