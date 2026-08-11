class_name KickSessionSlotRegistry
extends RefCounted

## Adapted from redot-tuber's weak owner registry at commit
## 029c22d7d5a5a68abacd8d12aabfea0b8e6536d8 (MIT).
static var _owners: Dictionary = {}


static func acquire(qualified_slot: String, owner: Object) -> KickApiError:
	_cleanup()
	if qualified_slot.is_empty() or owner == null:
		return KickApiError.invalid("A qualified Kick session slot and owner are required")
	if _owners.has(qualified_slot):
		var existing: Object = (_owners[qualified_slot] as WeakRef).get_ref()
		if existing != null and existing != owner:
			return KickApiError.invalid("Kick session slot is already active in another KickClient")
	_owners[qualified_slot] = weakref(owner)
	return null


static func release(qualified_slot: String, owner: Object) -> void:
	if not _owners.has(qualified_slot):
		return
	var existing: Object = (_owners[qualified_slot] as WeakRef).get_ref()
	if existing == null or existing == owner:
		_owners.erase(qualified_slot)


static func clear_for_tests() -> void:
	_owners.clear()


static func _cleanup() -> void:
	var expired: PackedStringArray = PackedStringArray()
	for slot: Variant in _owners:
		if (_owners[slot] as WeakRef).get_ref() == null:
			expired.append(str(slot))
	for slot: String in expired:
		_owners.erase(slot)
