class_name KickConnectionPanel
extends VBoxContainer

var _client: KickClient = null
var _status: Label = null
var _identity: Label = null
var _mode: Label = null
var _authorization_url: LineEdit = null
var _connect_button: Button = null
var _restore_button: Button = null
var _cancel_button: Button = null
var _relay_button: Button = null
var _disconnect_button: Button = null
var _clear_button: Button = null
var _confirm: ConfirmationDialog = null
var _pending_destructive_action: String = ""


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var heading: Label = Label.new()
	heading.text = "Kick connection"
	heading.add_theme_font_size_override("font_size", 20)
	add_child(heading)

	_status = Label.new()
	_status.text = "Status: not configured"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_mode = Label.new()
	_mode.text = "Capability mode: DISCONNECTED"
	add_child(_mode)
	_identity = Label.new()
	_identity.text = "Channel: none"
	add_child(_identity)

	var url_label: Label = Label.new()
	url_label.text = "Manual authorization URL"
	add_child(url_label)
	var url_row: HBoxContainer = HBoxContainer.new()
	add_child(url_row)
	_authorization_url = LineEdit.new()
	_authorization_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_authorization_url.placeholder_text = "A safe relay authorization URL appears here if needed"
	_authorization_url.editable = false
	url_row.add_child(_authorization_url)
	var copy_button: Button = _add_button(url_row, "Copy", _copy_authorization_url)
	copy_button.tooltip_text = "Copy the safe relay authorization URL"

	var actions: HFlowContainer = HFlowContainer.new()
	add_child(actions)
	_connect_button = _add_button(actions, "Connect", _connect)
	_restore_button = _add_button(actions, "Restore login", _restore)
	_cancel_button = _add_button(actions, "Cancel", _cancel)
	_relay_button = _add_button(actions, "Reconnect events", _connect_relay)
	_disconnect_button = _add_button(actions, "Revoke and disconnect", _request_revoke)
	_clear_button = _add_button(actions, "Clear local data", _request_clear)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(_confirm_destructive_action)
	add_child(_confirm)
	_refresh_identity()
	_refresh_buttons()


func bind_client(client: KickClient) -> void:
	if _client == client:
		if is_node_ready():
			_refresh_buttons()
		return
	_disconnect_client_signals()
	_client = client
	if not is_node_ready():
		return
	if _client != null:
		_client.connection_state_changed.connect(_on_state_changed)
		_client.capability_mode_changed.connect(_on_mode_changed)
		_client.authorization_url_ready.connect(_on_authorization_url)
		_client.account_connected.connect(_on_connected)
		_client.account_disconnected.connect(_on_disconnected)
		_client.error_occurred.connect(_on_error)
		_status.text = "Status: " + _client.connection_state
		_mode.text = "Capability mode: " + _client.capability_mode
	_refresh_identity()
	_refresh_buttons()


func _connect() -> void:
	if _client != null:
		_client.connect_account()


func _restore() -> void:
	if _client != null:
		_client.restore_account()


func _cancel() -> void:
	if _client != null:
		_client.cancel_account_authorization()


func _connect_relay() -> void:
	if _client != null:
		_client.connect_relay()


func _request_revoke() -> void:
	_pending_destructive_action = "revoke"
	_confirm.title = "Revoke Kick connection?"
	_confirm.dialog_text = "This invalidates the broker session, asks the relay to revoke/delete its Kick token state, and clears this device's saved session."
	_confirm.popup_centered()


func _request_clear() -> void:
	_pending_destructive_action = "clear"
	_confirm.title = "Clear local Kick data?"
	_confirm.dialog_text = "This deletes the operating-system vault entry and non-secret local descriptor. It does not revoke the remote Kick authorization."
	_confirm.popup_centered()


func _confirm_destructive_action() -> void:
	if _client == null:
		return
	if _pending_destructive_action == "revoke":
		_client.disconnect_account(true)
	elif _pending_destructive_action == "clear":
		_client.clear_local_data(false)
	_pending_destructive_action = ""


func _copy_authorization_url() -> void:
	if not _authorization_url.text.is_empty():
		DisplayServer.clipboard_set(_authorization_url.text)


func _on_state_changed(_previous: String, current: String, reason: String) -> void:
	_status.text = "Status: %s (%s)" % [current, reason]
	_refresh_buttons()


func _on_mode_changed(current: String) -> void:
	_mode.text = "Capability mode: " + current
	_refresh_buttons()


func _on_authorization_url(url: String) -> void:
	_authorization_url.text = url


func _on_connected(descriptor: KickSessionDescriptor, restored: bool) -> void:
	_identity.text = "Channel: %s%s" % [descriptor.channel_slug if not descriptor.channel_slug.is_empty() else descriptor.username, " (restored)" if restored else ""]
	_authorization_url.text = ""
	_refresh_buttons()


func _on_disconnected() -> void:
	_identity.text = "Channel: none"
	_authorization_url.text = ""
	_refresh_buttons()


func _on_error(error: KickApiError) -> void:
	_status.text = "Status: %s - %s" % [error.category, error.message]
	_refresh_buttons()


func _refresh_buttons() -> void:
	if _connect_button == null:
		return
	var available: bool = _client != null
	var current: String = _client.connection_state if available else "unconfigured"
	_connect_button.disabled = not available or current not in ["configured", "disconnected"]
	_restore_button.disabled = not available or current not in ["configured", "disconnected"]
	_cancel_button.disabled = not available or current != "authorizing"
	_relay_button.disabled = not available or _client.connected_descriptor == null or _client.capability_mode == "RELAY_CONNECTED"
	_disconnect_button.disabled = not available or _client.connected_descriptor == null
	_clear_button.disabled = not available


func _refresh_identity() -> void:
	if _identity == null:
		return
	if _client != null and _client.connected_descriptor != null:
		var descriptor: KickSessionDescriptor = _client.connected_descriptor
		_identity.text = "Channel: " + (descriptor.channel_slug if not descriptor.channel_slug.is_empty() else descriptor.username)
	else:
		_identity.text = "Channel: none"


func _disconnect_client_signals() -> void:
	if _client == null:
		return
	for pair: Array in [
		[_client.connection_state_changed, _on_state_changed],
		[_client.capability_mode_changed, _on_mode_changed],
		[_client.authorization_url_ready, _on_authorization_url],
		[_client.account_connected, _on_connected],
		[_client.account_disconnected, _on_disconnected],
		[_client.error_occurred, _on_error],
	]:
		var signal_value: Signal = pair[0]
		var callback: Callable = pair[1]
		if signal_value.is_connected(callback):
			signal_value.disconnect(callback)


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
