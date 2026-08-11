class_name KickKicksLeaderboard
extends RefCounted

var week: Array[Dictionary] = []
var month: Array[Dictionary] = []
var lifetime: Array[Dictionary] = []


static func from_dictionary(source: Dictionary) -> KickKicksLeaderboard:
	var value: KickKicksLeaderboard = KickKicksLeaderboard.new()
	value.week = _entries(source.get("week", []))
	value.month = _entries(source.get("month", []))
	value.lifetime = _entries(source.get("lifetime", []))
	return value


static func _entries(source: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if source is Array:
		for item: Variant in source:
			if item is Dictionary:
				var user_id: Variant = item.get("user_id", "")
				result.append({
					"user_id": str(int(user_id)) if user_id is float else str(user_id),
					"username": str(item.get("username", "")),
					"rank": int(item.get("rank", 0)),
					"gifted_amount": int(item.get("gifted_amount", 0)),
				})
	return result
