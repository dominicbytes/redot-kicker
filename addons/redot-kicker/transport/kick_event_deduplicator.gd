class_name KickEventDeduplicator
extends RefCounted

## Bounded insertion-order map adapted from redot-tuber's
## YouTubeEventDeduplicator at commit 029c22d7d5a5a68abacd8d12aabfea0b8e6536d8 (MIT).
var _max_entries: int
var _ttl_seconds: int
var _seen_at: Dictionary = {}
var _insertion_order: Array[String] = []


func _init(max_entries: int = 5000, ttl_seconds: int = 600) -> void:
	_max_entries = maxi(1, max_entries)
	_ttl_seconds = maxi(1, ttl_seconds)


func check_and_remember(message_id: String, now_unix: int) -> String:
	_evict_expired(now_unix)
	if _seen_at.has(message_id):
		return "duplicate"
	if _seen_at.size() >= _max_entries:
		return "capacity_exhausted"
	_seen_at[message_id] = now_unix
	_insertion_order.append(message_id)
	return "new"


func has_seen(message_id: String, now_unix: int) -> bool:
	_evict_expired(now_unix)
	return _seen_at.has(message_id)


func clear() -> void:
	_seen_at.clear()
	_insertion_order.clear()


func size() -> int:
	return _seen_at.size()


func _evict_expired(now_unix: int) -> void:
	while not _insertion_order.is_empty():
		var oldest_id: String = _insertion_order[0]
		if now_unix - int(_seen_at.get(oldest_id, now_unix)) <= _ttl_seconds:
			break
		_insertion_order.pop_front()
		_seen_at.erase(oldest_id)
