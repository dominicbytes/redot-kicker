class_name KickRedemption
extends RefCounted

var id: String = ""
var status: String = ""
var user_input: String = ""
var redeemed_at: String = ""
var redeemer: KickUser = null
var reward: KickReward = null


static func from_dictionary(source: Dictionary, reward_value: KickReward = null) -> KickRedemption:
	var value: KickRedemption = KickRedemption.new()
	value.id = str(source.get("id", ""))
	value.status = str(source.get("status", ""))
	value.user_input = str(source.get("user_input", ""))
	value.redeemed_at = str(source.get("redeemed_at", ""))
	var redeemer_value: Variant = source.get("redeemer", {})
	value.redeemer = KickUser.from_dictionary(redeemer_value) if redeemer_value is Dictionary else null
	value.reward = reward_value
	return value
