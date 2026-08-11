class_name KickLivestream
extends RefCounted

var id: String = ""
var broadcaster: KickUser = null
var broadcaster_user_id: String = ""
var channel_slug: String = ""
var category: KickCategory = null
var title: String = ""
var language_code: String = ""
var thumbnail_url: String = ""
var viewer_count: int = 0
var started_at: String = ""
var has_mature_content: bool = false
var is_live: bool = true
var tags: PackedStringArray = PackedStringArray()


static func from_dictionary(source: Dictionary) -> KickLivestream:
	var value: KickLivestream = KickLivestream.new()
	value.id = _identifier(source.get("id", source.get("channel_id", "")))
	var broadcaster_value: Variant = source.get("broadcaster_user", {})
	if broadcaster_value is Dictionary:
		value.broadcaster = KickUser.from_dictionary(broadcaster_value)
		value.broadcaster_user_id = value.broadcaster.id
	value.broadcaster_user_id = _identifier(source.get("broadcaster_user_id", value.broadcaster_user_id))
	var channel_value: Variant = source.get("channel", {})
	value.channel_slug = str(channel_value.get("slug", "")) if channel_value is Dictionary else str(source.get("slug", ""))
	var category_value: Variant = source.get("category", {})
	value.category = KickCategory.from_dictionary(category_value) if category_value is Dictionary else null
	value.title = str(source.get("title", source.get("stream_title", "")))
	value.language_code = str(source.get("language_code", source.get("language", "")))
	value.thumbnail_url = str(source.get("thumbnail", ""))
	value.viewer_count = int(source.get("viewer_count", 0))
	value.started_at = str(source.get("started_at", source.get("start_time", "")))
	value.has_mature_content = bool(source.get("has_mature_content", source.get("is_mature", false)))
	value.is_live = bool(source.get("is_live", true))
	var tags_value: Variant = source.get("tags", source.get("custom_tags", []))
	if tags_value is Array:
		for tag: Variant in tags_value:
			value.tags.append(str(tag))
	return value


static func _identifier(value: Variant) -> String:
	return str(int(value)) if value is float else str(value)
