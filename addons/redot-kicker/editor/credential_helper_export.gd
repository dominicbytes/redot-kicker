@tool
extends EditorExportPlugin

const Paths = preload("res://addons/redot-kicker/auth/credential_helper_paths.gd")

var _linux_sidecar: String = ""


func _get_name() -> String:
	return "RedotKickerCredentialHelper"


static func platform_for_features(features: PackedStringArray) -> String:
	var is_windows: bool = features.has("windows")
	var is_linux: bool = features.has("linux")
	if is_windows == is_linux:
		return ""
	return "Windows" if is_windows else "Linux"


static func source_path_for_features(features: PackedStringArray) -> String:
	if not features.has("x86_64"):
		return ""
	return Paths.source_path(platform_for_features(features), "x86_64")


func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	_linux_sidecar = ""
	var platform: String = platform_for_features(features)
	var source: String = source_path_for_features(features)
	if platform.is_empty() or source.is_empty():
		push_error("Redot Kicker credential exports support Windows/Linux x86_64 only")
		return
	if not FileAccess.file_exists(source):
		push_error("Redot Kicker credential helper is missing from the addon")
		return
	# Shared objects are external files; unlike add_file(), this does not put
	# the executable inside the PCK. The platform exporter copies the sidecar.
	add_shared_object(source, PackedStringArray(), Paths.ADDON_ID)
	if platform == "Linux":
		_linux_sidecar = path.get_base_dir().path_join(Paths.ADDON_ID).path_join(Paths.helper_name(platform))


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	if path.begins_with("res://addons/redot-kicker/bin/"):
		skip()


func _export_end() -> void:
	# Unix mode bits cannot be set on a Windows filesystem. Cross-exported
	# Linux distributions must preserve/set 0755 when assembled on Linux.
	if not _linux_sidecar.is_empty() and OS.get_name() == "Linux" and FileAccess.file_exists(_linux_sidecar):
		var error: Error = FileAccess.set_unix_permissions(_linux_sidecar, 493)
		if error != OK:
			push_error("Redot Kicker could not set execute permissions on the exported helper")
	_linux_sidecar = ""
