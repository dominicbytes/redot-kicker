class_name KickReward
extends RefCounted

var id: String = ""
var title: String = ""
var description: String = ""
var cost: int = 0
var background_color: String = ""
var is_enabled: bool = false
var is_paused: bool = false
var is_user_input_required: bool = false
var skips_request_queue: bool = false


static func from_dictionary(source: Dictionary) -> KickReward:
	var value: KickReward = KickReward.new()
	value.id = str(source.get("id", ""))
	value.title = str(source.get("title", ""))
	value.description = str(source.get("description", ""))
	value.cost = int(source.get("cost", 0))
	value.background_color = str(source.get("background_color", ""))
	value.is_enabled = bool(source.get("is_enabled", false))
	value.is_paused = bool(source.get("is_paused", false))
	value.is_user_input_required = bool(source.get("is_user_input_required", false))
	value.skips_request_queue = bool(source.get("should_redemptions_skip_request_queue", false))
	return value
