class_name KickEventTicket
extends RefCounted

var socket_url: String = ""
var ticket: String = ""
var expires_at_unix: int = 0
var subscription_ids: PackedStringArray = PackedStringArray()
var error: KickApiError = null


func is_success() -> bool:
	return error == null and not socket_url.is_empty() and not ticket.is_empty() and not subscription_ids.is_empty()


func clear_ticket() -> void:
	ticket = ""
