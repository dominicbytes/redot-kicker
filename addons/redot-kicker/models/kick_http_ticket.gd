class_name KickHttpTicket
extends RefCounted

signal completed(response: KickHttpResponse)
signal cancelled(reason: String)

var id: int = 0
var redacted_url: String = ""
var response: KickHttpResponse = null
var is_completed: bool = false
var is_cancelled: bool = false
var cancellation_reason: String = ""


func wait_for_response() -> KickHttpResponse:
	if not is_completed:
		await completed
	return response


func _mark_cancelled(reason: String) -> void:
	if is_cancelled:
		return
	is_cancelled = true
	cancellation_reason = reason
	cancelled.emit(reason)


func _complete(value: KickHttpResponse) -> void:
	if is_completed:
		return
	response = value
	is_completed = true
	completed.emit(value)
