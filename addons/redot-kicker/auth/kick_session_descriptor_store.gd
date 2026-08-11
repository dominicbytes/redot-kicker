class_name KickSessionDescriptorStore
extends RefCounted

## Adapted from redot-tuber's non-secret descriptor store at commit
## 029c22d7d5a5a68abacd8d12aabfea0b8e6536d8 (MIT).
const DEFAULT_DIRECTORY: String = "user://redot-kicker/sessions"

var _base_directory: String


func _init(base_directory: String = DEFAULT_DIRECTORY) -> void:
	_base_directory = base_directory.trim_suffix("/")


func path_for_slot(session_slot: String) -> String:
	return "%s/%s.json" % [_base_directory, session_slot] if _is_valid_slot(session_slot) else ""


func save(descriptor: KickSessionDescriptor) -> KickApiError:
	if descriptor == null:
		return KickApiError.invalid("Session descriptor is required")
	var path: String = path_for_slot(descriptor.session_slot)
	if path.is_empty() or descriptor.credential_target.is_empty():
		return KickApiError.invalid("Session slot and credential target are required")
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_base_directory))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return KickApiError.from_transport(directory_error, "Unable to create the Kick session descriptor directory")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return KickApiError.from_transport(FileAccess.get_open_error(), "Unable to write the non-secret Kick session descriptor")
	file.store_string(JSON.stringify(descriptor.to_dictionary(), "  ") + "\n")
	file.close()
	return null


func load_descriptor(session_slot: String) -> KickSessionDescriptorLoadResult:
	var result: KickSessionDescriptorLoadResult = KickSessionDescriptorLoadResult.new()
	var path: String = path_for_slot(session_slot)
	if path.is_empty():
		result.error = KickApiError.invalid("Invalid session slot")
		return result
	if not FileAccess.file_exists(path):
		result.error = KickApiError.custom("not_found", "No saved Kick session exists for this slot")
		return result
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		result.error = KickApiError.from_transport(ERR_PARSE_ERROR, "Saved Kick session descriptor is corrupt")
		return result
	result.descriptor = KickSessionDescriptor.from_dictionary(parsed)
	if result.descriptor == null or result.descriptor.session_slot != session_slot:
		result.descriptor = null
		result.error = KickApiError.from_transport(ERR_INVALID_DATA, "Saved Kick session descriptor has an unsupported schema or slot")
	return result


func delete_descriptor(session_slot: String) -> KickApiError:
	var path: String = path_for_slot(session_slot)
	if path.is_empty():
		return KickApiError.invalid("Invalid session slot")
	if not FileAccess.file_exists(path):
		return null
	var remove_error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return null if remove_error == OK else KickApiError.from_transport(remove_error, "Unable to delete the Kick session descriptor")


func _is_valid_slot(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for character: String in value:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(character):
			return false
	return true
