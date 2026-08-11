extends Control

@export var relay_base_url: String = ""
@export var publisher_id: String = ""
@export var application_id: String = ""
@export var session_slot: String = "primary"

@onready var kick_client: KickClient = $KickClient
@onready var connection_panel: KickConnectionPanel = $Margin/ConnectionPanel


func _ready() -> void:
	connection_panel.bind_client(kick_client)
	if relay_base_url.is_empty() or publisher_id.is_empty() or application_id.is_empty():
		print("Redot Kicker example: set the non-secret relay, publisher, and application identifiers in the inspector.")
		return
	var config: KickClientConfig = KickClientConfig.new()
	config.relay_base_url = relay_base_url
	config.publisher_id = publisher_id
	config.application_id = application_id
	var error: KickApiError = kick_client.configure(config, PackedStringArray([
		"identity.read",
		"channel.read",
		"livestreams.read",
		"chat.write",
		"events.receive",
		"events.manage",
	]), session_slot)
	if error != null:
		push_error("Redot Kicker example configuration failed: %s" % error.message)
		return
	kick_client.chat_message_received.connect(_on_chat_message)


func send_example_message(content: String) -> KickApiResult:
	if kick_client.connected_descriptor == null:
		var result: KickApiResult = KickApiResult.new()
		result.error = KickApiError.custom("authorization", "Connect a Kick account first")
		return result
	return await kick_client.chat.send_message(content, "user", kick_client.connected_descriptor.channel_id)


func _on_chat_message(event: KickEvent) -> void:
	var sender: String = event.actor.username if event.actor != null else "anonymous"
	print("Kick chat [%s]: %s" % [sender, event.content])
