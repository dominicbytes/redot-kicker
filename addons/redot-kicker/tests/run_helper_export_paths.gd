extends SceneTree

const Paths = preload("res://addons/redot-kicker/auth/credential_helper_paths.gd")
const Exporter = preload("res://addons/redot-kicker/editor/credential_helper_export.gd")


func _initialize() -> void:
	var checks: int = 0
	var failures: int = 0
	var cases: Array[Array] = [
		[Paths.source_path("Windows", "x86_64"), "res://addons/redot-kicker/bin/windows/x86_64/redot-kicker-credential-helper.exe"],
		[Paths.source_path("Linux", "x86_64"), "res://addons/redot-kicker/bin/linux/x86_64/redot-kicker-credential-helper"],
		[Paths.runtime_path(false, "Windows", "x86_64", "C:/Games/Space Game/game.exe"), "C:/Games/Space Game/redot-kicker/redot-kicker-credential-helper.exe"],
		[Paths.runtime_path(false, "Linux", "x86_64", "/opt/Games/日本語/game"), "/opt/Games/日本語/redot-kicker/redot-kicker-credential-helper"],
		[Paths.runtime_path(false, "Linux", "arm64", "/opt/game"), ""],
		[Paths.runtime_path(false, "macOS", "x86_64", "/opt/game"), ""],
		[Paths.runtime_path(true, "Windows", "x86_64", "C:/engine.exe"), ProjectSettings.globalize_path(Paths.source_path("Windows", "x86_64"))],
		[Exporter.platform_for_features(PackedStringArray(["windows", "x86_64"])), "Windows"],
		[Exporter.platform_for_features(PackedStringArray(["linux", "x86_64"])), "Linux"],
		[Exporter.platform_for_features(PackedStringArray(["Windows", "x86_64"])), ""],
		[Exporter.platform_for_features(PackedStringArray(["windows", "linux", "x86_64"])), ""],
		[Exporter.source_path_for_features(PackedStringArray(["windows", "x86_64"])), "res://addons/redot-kicker/bin/windows/x86_64/redot-kicker-credential-helper.exe"],
		[Exporter.source_path_for_features(PackedStringArray(["linux", "x86_64"])), "res://addons/redot-kicker/bin/linux/x86_64/redot-kicker-credential-helper"],
		[Exporter.source_path_for_features(PackedStringArray(["windows", "arm64"])), ""],
		[Exporter.source_path_for_features(PackedStringArray(["linux", "x86_32"])), ""],
		[Exporter.source_path_for_features(PackedStringArray(["macos", "x86_64"])), ""],
	]
	for item: Array in cases:
		checks += 1
		if item[0] != item[1]:
			failures += 1
			push_error("Helper path mismatch: %s != %s" % [item[0], item[1]])
	if OS.get_name() in ["Windows", "Linux"]:
		checks += 1
		if not OS.has_feature(OS.get_name().to_lower()):
			failures += 1
			push_error("Redot host platform feature tag must be lowercase")
		checks += 1
		if OS.has_feature(OS.get_name()):
			failures += 1
			push_error("Redot host platform feature tag unexpectedly uses uppercase")
	for api_check: Array in [
		["EditorExportPlugin", "add_shared_object"],
		["EditorExportPlugin", "get_export_platform"],
		["EditorPlugin", "add_export_plugin"],
		["EditorPlugin", "remove_export_plugin"],
		["FileAccess", "set_unix_permissions"],
		["Engine", "get_architecture_name"],
		["OS", "has_feature"],
	]:
		checks += 1
		if not ClassDB.class_has_method(api_check[0], api_check[1]):
			failures += 1
			push_error("Redot API is unavailable: %s.%s" % [api_check[0], api_check[1]])
	checks += 1
	if Exporter == null:
		failures += 1
		push_error("Export plugin script is unavailable")
	print("HELPER EXPORT PATHS: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)
