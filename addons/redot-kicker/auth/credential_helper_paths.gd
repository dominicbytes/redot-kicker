extends RefCounted
## Shared by runtime path resolution and the editor export hook.

const ADDON_ID: String = "redot-kicker"


static func helper_name(platform: String) -> String:
	match platform:
		"Windows":
			return ADDON_ID + "-credential-helper.exe"
		"Linux":
			return ADDON_ID + "-credential-helper"
	return ""


static func source_path(platform: String, architecture: String) -> String:
	var filename: String = helper_name(platform)
	if filename.is_empty() or architecture != "x86_64":
		return ""
	return "res://addons/%s/bin/%s/x86_64/%s" % [ADDON_ID, platform.to_lower(), filename]


static func runtime_path(editor_build: bool, platform: String, architecture: String, executable: String) -> String:
	var source: String = source_path(platform, architecture)
	if source.is_empty():
		return ""
	if editor_build:
		return ProjectSettings.globalize_path(source)
	return executable.get_base_dir().path_join(ADDON_ID).path_join(helper_name(platform))
