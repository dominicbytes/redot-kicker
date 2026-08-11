class_name KickChatService
extends RefCounted

var _api: KickApiClient


func _init(api: KickApiClient) -> void:
	_api = api


func send_message(
	content: String,
	message_type: String = "user",
	broadcaster_user_id: String = "",
	reply_to_message_id: String = "",
	cancellation: KickCancellationToken = null
) -> KickApiResult:
	if content.is_empty() or content.length() > 500:
		return _failed("Kick chat content must contain between 1 and 500 characters")
	if message_type not in ["user", "bot"]:
		return _failed("Kick chat message type must be user or bot")
	if message_type == "user" and broadcaster_user_id.is_empty():
		return _failed("A broadcaster user ID is required when sending chat as a user")
	var body: Dictionary = {"content": content, "type": message_type}
	if not broadcaster_user_id.is_empty(): body["broadcaster_user_id"] = broadcaster_user_id
	if not reply_to_message_id.is_empty(): body["reply_to_message_id"] = reply_to_message_id
	return KickModelMapper.map_result(await _api.invoke("chat.send", {}, {}, body, false, "", cancellation), "chat_receipt")


func delete_message(message_id: String, confirmed: bool, cancellation: KickCancellationToken = null) -> KickApiResult:
	if message_id.is_empty():
		return _failed("Kick chat message ID is required")
	return await _api.invoke("chat.delete", {}, {"message_id": message_id}, {}, confirmed, "", cancellation)


func _failed(message: String) -> KickApiResult:
	var result: KickApiResult = KickApiResult.new()
	result.error = KickApiError.invalid(message)
	return result
