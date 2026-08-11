class_name KickMediaCache
extends Node

## Adapted from redot-tuber's bounded media cache at commit
## 029c22d7d5a5a68abacd8d12aabfea0b8e6536d8 (MIT).
const ALLOWED_MIME_TYPES: PackedStringArray = ["image/png", "image/jpeg", "image/webp", "image/gif"]

@export_range(1, 1024, 1) var max_items: int = 128
@export_range(1024, 67108864, 1024) var max_item_bytes: int = 2 * 1024 * 1024
@export_range(1024, 536870912, 1024) var max_total_bytes: int = 32 * 1024 * 1024
@export_range(1, 16, 1) var max_concurrent_fetches: int = 4
@export_range(1, 2592000, 1) var ttl_seconds: int = 86400
@export var persist_to_disk: bool = false
@export var cache_directory: String = "user://redot-kicker/media-cache"

var _transport: KickHttpTransport = null
var _owns_transport: bool = false
var _entries: Dictionary = {}
var _total_bytes: int = 0
var _active_fetches: int = 0


func _init(transport: KickHttpTransport = null) -> void:
	_transport = transport


func fetch_texture(url: String, cancellation: KickCancellationToken = null) -> KickMediaResult:
	var validation: KickApiError = _validate_url(url)
	if validation != null:
		return _failed(validation)
	var cached: KickMediaResult = _memory_result(url)
	if cached != null:
		return cached
	if persist_to_disk:
		cached = _disk_result(url)
		if cached != null:
			return cached
	if _active_fetches >= max_concurrent_fetches:
		return _failed(KickApiError.custom("media_busy", "The bounded Kick media fetch limit is active", true))
	_ensure_transport()
	_active_fetches += 1
	var ticket: KickHttpTicket = _transport.request(
		url,
		PackedStringArray(["Accept: image/png,image/jpeg,image/webp,image/gif", "Accept-Encoding: identity"]),
		HTTPClient.METHOD_GET,
		PackedByteArray(),
		cancellation,
		true
	)
	var response: KickHttpResponse = await ticket.wait_for_response()
	_active_fetches -= 1
	if response == null or not response.is_success():
		return _failed(response.error if response != null and response.error != null else KickApiError.custom("media_transport", "Unable to download Kick media"))
	if response.body.is_empty() or response.body.size() > max_item_bytes:
		return _failed(KickApiError.custom("media_size", "Kick media is empty or exceeds the configured item limit"))
	var mime_type: String = _content_type(response.headers)
	if mime_type not in ALLOWED_MIME_TYPES:
		return _failed(KickApiError.custom("media_type", "Unsupported Kick media content type: %s" % mime_type))
	var texture: Texture2D = _decode_texture(response.body, mime_type)
	if mime_type != "image/gif" and texture == null:
		return _failed(KickApiError.custom("media_decode", "Kick media could not be decoded as %s" % mime_type))
	_store_memory(url, mime_type, response.body, texture)
	if persist_to_disk:
		var persist_error: KickApiError = _store_disk(url, mime_type, response.body)
		if persist_error != null:
			_remove_memory(url)
			return _failed(persist_error)
	return _build_result(url, mime_type, response.body, texture, false)


func clear_data() -> KickApiError:
	_entries.clear()
	_total_bytes = 0
	if not _safe_cache_directory():
		return KickApiError.invalid("Media cache directory must stay under user://redot-kicker/")
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cache_directory)):
		return null
	var directory: DirAccess = DirAccess.open(cache_directory)
	if directory == null:
		return KickApiError.custom("media_cache", "Unable to open the Kick media cache for deletion")
	for filename: String in directory.get_files():
		var removal_error: Error = directory.remove(filename)
		if removal_error != OK:
			return KickApiError.custom("media_cache", "Unable to remove Kick media cache entry %s" % filename)
	return null


func item_count() -> int:
	return _entries.size()


func total_bytes() -> int:
	return _total_bytes


func active_fetch_count() -> int:
	return _active_fetches


func _ensure_transport() -> void:
	if _transport != null:
		return
	_transport = KickHttpTransport.new()
	_transport.name = "KickMediaTransport"
	_transport.response_body_limit_bytes = max_item_bytes
	_transport.max_concurrent_requests = max_concurrent_fetches
	add_child(_transport)
	_owns_transport = true


func _validate_url(url: String) -> KickApiError:
	var secure: bool = url.begins_with("https://")
	var loopback: bool = url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")
	if not secure and not loopback:
		return KickApiError.invalid("Kick media URLs must use HTTPS")
	if url.length() > 4096:
		return KickApiError.invalid("Kick media URL exceeds the configured limit")
	return null


func _memory_result(url: String) -> KickMediaResult:
	if not _entries.has(url):
		return null
	var entry: Dictionary = _entries[url]
	if int(entry.get("expires_at_unix", 0)) <= int(Time.get_unix_time_from_system()):
		_remove_memory(url)
		return null
	entry["last_access_msec"] = Time.get_ticks_msec()
	return _build_result(url, str(entry.mime_type), entry.bytes, entry.texture, true)


func _disk_result(url: String) -> KickMediaResult:
	if not _safe_cache_directory():
		return null
	var key: String = url.sha256_text()
	var metadata_path: String = cache_directory.path_join(key + ".json")
	var data_path: String = cache_directory.path_join(key + ".bin")
	if not FileAccess.file_exists(metadata_path) or not FileAccess.file_exists(data_path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if not parsed is Dictionary or int(parsed.get("expires_at_unix", 0)) <= int(Time.get_unix_time_from_system()):
		_delete_disk_key(key)
		return null
	var mime_type: String = str(parsed.get("mime_type", ""))
	if mime_type not in ALLOWED_MIME_TYPES:
		_delete_disk_key(key)
		return null
	var file: FileAccess = FileAccess.open(data_path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > max_item_bytes:
		_delete_disk_key(key)
		return null
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if bytes.size() != int(parsed.get("size", -1)):
		_delete_disk_key(key)
		return null
	var texture: Texture2D = _decode_texture(bytes, mime_type)
	if mime_type != "image/gif" and texture == null:
		_delete_disk_key(key)
		return null
	_store_memory(url, mime_type, bytes, texture, int(parsed.get("expires_at_unix", 0)))
	return _build_result(url, mime_type, bytes, texture, true)


func _store_memory(url: String, mime_type: String, bytes: PackedByteArray, texture: Texture2D, expires_at_unix: int = 0) -> void:
	_remove_memory(url)
	_evict_memory_for(bytes.size())
	_entries[url] = {
		"mime_type": mime_type,
		"bytes": bytes.duplicate(),
		"texture": texture,
		"size": bytes.size(),
		"last_access_msec": Time.get_ticks_msec(),
		"expires_at_unix": expires_at_unix if expires_at_unix > 0 else int(Time.get_unix_time_from_system()) + ttl_seconds,
	}
	_total_bytes += bytes.size()


func _evict_memory_for(incoming_bytes: int) -> void:
	while not _entries.is_empty() and (_entries.size() >= max_items or _total_bytes + incoming_bytes > max_total_bytes):
		var oldest_url: String = ""
		var oldest_access: int = 9223372036854775807
		for url_value: Variant in _entries:
			var entry: Dictionary = _entries[url_value]
			if int(entry.last_access_msec) < oldest_access:
				oldest_access = int(entry.last_access_msec)
				oldest_url = str(url_value)
		if oldest_url.is_empty():
			break
		_remove_memory(oldest_url)


func _remove_memory(url: String) -> void:
	if not _entries.has(url):
		return
	_total_bytes = maxi(0, _total_bytes - int((_entries[url] as Dictionary).get("size", 0)))
	_entries.erase(url)


func _store_disk(url: String, mime_type: String, bytes: PackedByteArray) -> KickApiError:
	if not _safe_cache_directory():
		return KickApiError.invalid("Media cache directory must stay under user://redot-kicker/")
	var make_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_directory))
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return KickApiError.custom("media_cache", "Unable to create the Kick media cache directory")
	var key: String = url.sha256_text()
	var data_file: FileAccess = FileAccess.open(cache_directory.path_join(key + ".bin"), FileAccess.WRITE)
	if data_file == null:
		return KickApiError.custom("media_cache", "Unable to write Kick media cache data")
	data_file.store_buffer(bytes)
	data_file.close()
	var metadata_file: FileAccess = FileAccess.open(cache_directory.path_join(key + ".json"), FileAccess.WRITE)
	if metadata_file == null:
		_delete_disk_key(key)
		return KickApiError.custom("media_cache", "Unable to write Kick media cache metadata")
	metadata_file.store_string(JSON.stringify({
		"schema_version": 1,
		"mime_type": mime_type,
		"size": bytes.size(),
		"stored_at_unix": int(Time.get_unix_time_from_system()),
		"expires_at_unix": int(Time.get_unix_time_from_system()) + ttl_seconds,
	}))
	metadata_file.close()
	_enforce_disk_bounds()
	return null


func _enforce_disk_bounds() -> void:
	var directory: DirAccess = DirAccess.open(cache_directory)
	if directory == null:
		return
	var records: Array[Dictionary] = []
	var disk_bytes: int = 0
	for filename: String in directory.get_files():
		if not filename.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(cache_directory.path_join(filename)))
		var key: String = filename.trim_suffix(".json")
		if not parsed is Dictionary:
			_delete_disk_key(key)
			continue
		var size: int = int(parsed.get("size", 0))
		disk_bytes += size
		records.append({"key": key, "size": size, "stored_at": int(parsed.get("stored_at_unix", 0))})
	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return int(left.stored_at) < int(right.stored_at))
	while records.size() > max_items or disk_bytes > max_total_bytes:
		var oldest: Dictionary = records.pop_front()
		disk_bytes = maxi(0, disk_bytes - int(oldest.size))
		_delete_disk_key(str(oldest.key))


func _delete_disk_key(key: String) -> void:
	for extension: String in [".bin", ".json"]:
		var path: String = cache_directory.path_join(key + extension)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _safe_cache_directory() -> bool:
	var normalized: String = cache_directory.replace("\\", "/").trim_suffix("/")
	return normalized.begins_with("user://redot-kicker/") and normalized.length() > "user://redot-kicker/".length()


func _decode_texture(bytes: PackedByteArray, mime_type: String) -> Texture2D:
	if mime_type == "image/gif":
		return null
	var image: Image = Image.new()
	var decode_error: Error = ERR_FILE_UNRECOGNIZED
	match mime_type:
		"image/png": decode_error = image.load_png_from_buffer(bytes)
		"image/jpeg": decode_error = image.load_jpg_from_buffer(bytes)
		"image/webp": decode_error = image.load_webp_from_buffer(bytes)
	if decode_error != OK or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _content_type(headers: PackedStringArray) -> String:
	for header: String in headers:
		if header.to_lower().begins_with("content-type:"):
			return header.get_slice(":", 1).strip_edges().split(";", false)[0].to_lower()
	return ""


func _build_result(url: String, mime_type: String, bytes: PackedByteArray, texture: Texture2D, from_cache: bool) -> KickMediaResult:
	var result: KickMediaResult = KickMediaResult.new()
	result.url_hash = url.sha256_text()
	result.mime_type = mime_type
	result.bytes = bytes.duplicate()
	result.texture = texture
	result.from_cache = from_cache
	return result


func _failed(error: KickApiError) -> KickMediaResult:
	var result: KickMediaResult = KickMediaResult.new()
	result.error = error
	return result


func _exit_tree() -> void:
	if _owns_transport and is_instance_valid(_transport):
		_transport.cancel_all("media cache freed")
