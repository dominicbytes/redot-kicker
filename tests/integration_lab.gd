extends Control

const BindingClass = preload("res://addons/redot-kicker/models/kick_relay_binding.gd")
const ValidatorClass = preload("res://addons/redot-kicker/transport/kick_webhook_validator.gd")
const DownlinkClass = preload("res://addons/redot-kicker/transport/kick_mock_downlink.gd")

var _status: Label


func _ready() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("111827")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var title: Label = Label.new()
	title.text = "Redot Kicker — Relay Contract Lab"
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)

	var description: Label = Label.new()
	description.text = "Runs a lawful synthetic RSA-signed Kick webhook through signature-before-parse validation, relay binding, and an authenticated bounded downlink."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.y = 70
	column.add_child(description)

	var run_button: Button = Button.new()
	run_button.text = "Run deterministic relay check"
	run_button.custom_minimum_size = Vector2(320, 52)
	run_button.pressed.connect(_run_check)
	column.add_child(run_button)

	_status = Label.new()
	_status.text = "Ready"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)


func _run_check() -> void:
	var crypto: Crypto = Crypto.new()
	var private_key: CryptoKey = crypto.generate_rsa(2048)
	if private_key == null:
		_status.text = "FAIL — Redot could not generate the synthetic RSA fixture key."
		return
	var public_key: CryptoKey = CryptoKey.new()
	if public_key.load_from_string(private_key.save_to_string(true), true) != OK:
		_status.text = "FAIL — Redot could not load the public fixture key."
		return
	var body: PackedByteArray = FileAccess.get_file_as_bytes("res://tests/fixtures/ms001/chat_message.json")
	var timestamp: String = "2026-08-11T12:00:00Z"
	var message_id: String = "01J5KICKERLABMESSAGE00000001"
	var signed_bytes: PackedByteArray = (message_id + "." + timestamp + ".").to_utf8_buffer()
	signed_bytes.append_array(body)
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(signed_bytes)
	var signature: PackedByteArray = crypto.sign(HashingContext.HASH_SHA256, hashing.finish(), private_key)

	var binding: Variant = BindingClass.new()
	binding.tenant_id = "fixture-tenant"
	binding.application_id = "fixture-app"
	binding.channel_id = "123456789"
	binding.subscription_id = "01J5KICKERSUBSCRIPTION000001"
	binding.session_id = "fixture-session"
	var headers: Dictionary = {
		"Kick-Event-Message-Id": message_id,
		"Kick-Event-Subscription-Id": binding.subscription_id,
		"Kick-Event-Signature": Marshalls.raw_to_base64(signature),
		"Kick-Event-Message-Timestamp": timestamp,
		"Kick-Event-Type": "chat.message.sent",
		"Kick-Event-Version": "1",
	}
	var now_unix: int = int(Time.get_unix_time_from_datetime_string(timestamp))
	var result: Variant = ValidatorClass.new().validate_and_transform(body, headers, public_key, binding, now_unix)
	if not result.is_accepted():
		_status.text = "FAIL — Ingress rejected the lawful fixture: %s" % result.code
		return
	var downlink: Variant = DownlinkClass.new()
	downlink.configure(binding, "synthetic-broker-session", 2)
	if not downlink.connect_session("synthetic-broker-session") or downlink.receive(result.envelope) != "accepted":
		_status.text = "FAIL — Authenticated mock downlink rejected the verified envelope."
		return
	var emitted: Array[int] = [0]
	downlink.event_received.connect(func(_event: Variant) -> void: emitted[0] += 1)
	var outcome: String = downlink.pump_one()
	_status.text = "PASS — %s; %d typed event emitted; raw body discarded after transformation." % [outcome, emitted[0]]
