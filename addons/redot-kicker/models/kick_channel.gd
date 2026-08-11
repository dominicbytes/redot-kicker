class_name KickChannel
extends RefCounted

var broadcaster_user_id: String = ""
var slug: String = ""
var description: String = ""
var stream_title: String = ""
var banner_picture_url: String = ""
var category: KickCategory = null
var stream: KickLivestream = null
var active_subscribers_count: int = 0
var active_gifted_subscribers_count: int = 0
var canceled_subscribers_count: int = 0


static func from_dictionary(source: Dictionary) -> KickChannel:
	var value: KickChannel = KickChannel.new()
	var user_id: Variant = source.get("broadcaster_user_id", "")
	value.broadcaster_user_id = str(int(user_id)) if user_id is float else str(user_id)
	value.slug = str(source.get("slug", ""))
	value.description = str(source.get("channel_description", ""))
	value.stream_title = str(source.get("stream_title", ""))
	value.banner_picture_url = str(source.get("banner_picture", ""))
	value.active_subscribers_count = int(source.get("active_subscribers_count", 0))
	value.active_gifted_subscribers_count = int(source.get("active_gifted_subscribers_count", 0))
	value.canceled_subscribers_count = int(source.get("canceled_subscribers_count", 0))
	var category_value: Variant = source.get("category", {})
	value.category = KickCategory.from_dictionary(category_value) if category_value is Dictionary else null
	var stream_value: Variant = source.get("stream", {})
	if stream_value is Dictionary and not stream_value.is_empty():
		value.stream = KickLivestream.from_dictionary(stream_value)
		value.stream.broadcaster_user_id = value.broadcaster_user_id
		value.stream.channel_slug = value.slug
	return value
