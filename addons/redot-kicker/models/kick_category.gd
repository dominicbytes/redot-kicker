class_name KickCategory
extends RefCounted

var id: String = ""
var name: String = ""
var thumbnail_url: String = ""
var tags: PackedStringArray = PackedStringArray()
var viewer_count: int = 0


static func from_dictionary(source: Dictionary) -> KickCategory:
	var value: KickCategory = KickCategory.new()
	var id_value: Variant = source.get("id", "")
	value.id = str(int(id_value)) if id_value is float else str(id_value)
	value.name = str(source.get("name", ""))
	value.thumbnail_url = str(source.get("thumbnail", ""))
	value.viewer_count = int(source.get("viewer_count", 0))
	var tags_value: Variant = source.get("tags", [])
	if tags_value is Array:
		for tag: Variant in tags_value:
			value.tags.append(str(tag))
	return value
