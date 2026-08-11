class_name KickCredentialHelperClient
extends RefCounted

## Adapted from redot-tuber's standalone helper client at commit
## 029c22d7d5a5a68abacd8d12aabfea0b8e6536d8 (MIT).
const ProtocolClass = preload("res://addons/redot-kicker/auth/kick_credential_protocol.gd")
const DEFAULT_TIMEOUT_MSEC: int = 15000
const MAX_RESPONSE_BYTES: int = 16 * 1024

var helper_path_override: String = ""
var timeout_msec: int = DEFAULT_TIMEOUT_MSEC
var _protocol: KickCredentialProtocol = ProtocolClass.new()


func ping(cancellation: KickCancellationToken = null) -> KickCredentialResult:
	return await _invoke("ping", "", "", cancellation)


func store(target: String, secret: String, cancellation: KickCancellationToken = null) -> KickCredentialResult:
	if target.is_empty() or secret.is_empty():
		return _error_result("protocol_error", ERR_INVALID_PARAMETER, "Credential target and broker session are required")
	return await _invoke("store", target, secret, cancellation)


func read(target: String, cancellation: KickCancellationToken = null) -> KickCredentialResult:
	if target.is_empty():
		return _error_result("protocol_error", ERR_INVALID_PARAMETER, "Credential target is required")
	return await _invoke("read", target, "", cancellation)


func delete(target: String, cancellation: KickCancellationToken = null) -> KickCredentialResult:
	if target.is_empty():
		return _error_result("protocol_error", ERR_INVALID_PARAMETER, "Credential target is required")
	return await _invoke("delete", target, "", cancellation)


func resolved_helper_path() -> String:
	if not helper_path_override.is_empty():
		return ProjectSettings.globalize_path(helper_path_override) if helper_path_override.begins_with("res://") else helper_path_override
	var relative: String = ""
	match OS.get_name():
		"Windows":
			relative = "res://addons/redot-kicker/bin/windows/x86_64/redot-kicker-credential-helper.exe"
		"Linux":
			relative = "res://addons/redot-kicker/bin/linux/x86_64/redot-kicker-credential-helper"
		_:
			return ""
	return ProjectSettings.globalize_path(relative)


func _invoke(command: String, target: String, secret: String, cancellation: KickCancellationToken) -> KickCredentialResult:
	var helper_path: String = resolved_helper_path()
	if helper_path.is_empty() or not FileAccess.file_exists(helper_path):
		return _error_result("unavailable", ERR_FILE_NOT_FOUND, "Credential helper is unavailable for this operating system and architecture")
	var request_wire: String = _protocol.encode_request(command, target, secret)
	secret = ""
	if request_wire.is_empty():
		return _error_result("protocol_error", ERR_INVALID_DATA, "Credential helper request is invalid")
	var process: Dictionary = OS.execute_with_pipe(helper_path, PackedStringArray(), false)
	var stdio: FileAccess = process.get("stdio", null)
	var stderr: FileAccess = process.get("stderr", null)
	var pid: int = int(process.get("pid", -1))
	if stdio == null or pid <= 0:
		_close_pipe(stdio)
		_close_pipe(stderr)
		return _error_result("unavailable", ERR_CANT_FORK, "Credential helper could not be started")
	stdio.store_string(request_wire)
	stdio.flush()
	request_wire = ""
	var deadline: int = Time.get_ticks_msec() + clampi(timeout_msec, 1000, 60000)
	while OS.is_process_running(pid):
		if cancellation != null and cancellation.is_cancelled():
			OS.kill(pid)
			_close_pipe(stdio)
			_close_pipe(stderr)
			return _error_result("cancelled", ERR_SKIP, "Credential operation was cancelled")
		if Time.get_ticks_msec() >= deadline:
			OS.kill(pid)
			_close_pipe(stdio)
			_close_pipe(stderr)
			return _error_result("unavailable", ERR_TIMEOUT, "Credential helper timed out")
		await (Engine.get_main_loop() as SceneTree).process_frame
	var exit_code: int = OS.get_process_exit_code(pid)
	var response_wire: String = stdio.get_as_text()
	_close_pipe(stdio)
	_close_pipe(stderr)
	if response_wire.to_utf8_buffer().size() > MAX_RESPONSE_BYTES:
		return _error_result("protocol_error", ERR_OUT_OF_MEMORY, "Credential helper response exceeded the protocol limit")
	var result: KickCredentialResult = _protocol.decode_response(response_wire)
	response_wire = ""
	if result.status == "protocol_error" and exit_code != 0:
		result.detail = "helper exited without a valid response"
	return result


func _error_result(status: String, code: int, message: String) -> KickCredentialResult:
	var result: KickCredentialResult = KickCredentialResult.new()
	result.status = status
	result.error = KickApiError.from_transport(code, message)
	result.error.category = status
	return result


func _close_pipe(file: FileAccess) -> void:
	if file != null:
		file.close()
