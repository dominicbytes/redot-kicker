class_name KickEvent
extends RefCounted

var id: String = ""
var subscription_id: String = ""
var event_type: String = ""
var event_version: int = 0
var occurred_at: String = ""
var received_at: String = ""
var channel_id: String = ""
var tenant_id: String = ""
var application_id: String = ""
var session_id: String = ""
var broadcaster: KickUser = null
var actor: KickUser = null
var related_users: Array[KickUser] = []
var message_id: String = ""
var content: String = ""
var created_at: String = ""
var expires_at: String = ""
var duration: int = 0
var is_live: bool = false
var title: String = ""
var metadata: Dictionary = {}
var gift: Dictionary = {}
var reward: KickReward = null
var redemption: KickRedemption = null
var payload: Dictionary = {}
var is_unknown: bool = false


func clear_payload() -> void:
	payload.clear()
	metadata.clear()
	gift.clear()
