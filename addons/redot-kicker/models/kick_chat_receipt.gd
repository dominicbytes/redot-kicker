class_name KickChatReceipt
extends RefCounted

var message_id: String = ""
var is_sent: bool = false


static func from_dictionary(source: Dictionary) -> KickChatReceipt:
	var value: KickChatReceipt = KickChatReceipt.new()
	value.message_id = str(source.get("message_id", ""))
	value.is_sent = bool(source.get("is_sent", false))
	return value
