extends SceneTree

var _checks: int = 0
var _failures: PackedStringArray = PackedStringArray()


class ImageServer extends Node:
	var server: TCPServer = TCPServer.new()
	var peers: Array[Dictionary] = []
	var request_count: int = 0
	var png_bytes: PackedByteArray = PackedByteArray()

	func start() -> Error:
		var result: Error = server.listen(0, "127.0.0.1")
		set_process(result == OK)
		return result

	func port() -> int:
		return server.get_local_port()

	func stop() -> void:
		set_process(false)
		for item: Dictionary in peers:
			var peer: StreamPeerTCP = item.peer
			if peer != null:
				peer.disconnect_from_host()
		peers.clear()
		server.stop()

	func _process(_delta: float) -> void:
		while server.is_connection_available():
			peers.append({"peer": server.take_connection(), "request": "", "responded": false})
		for item: Dictionary in peers:
			if bool(item.responded):
				continue
			var peer: StreamPeerTCP = item.peer
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				continue
			var available: int = peer.get_available_bytes()
			if available > 0:
				item.request = str(item.request) + peer.get_utf8_string(available)
			if not str(item.request).contains("\r\n\r\n"):
				continue
			request_count += 1
			var first_line: String = str(item.request).split("\r\n", false)[0]
			var target: String = first_line.split(" ", false)[1]
			if target == "/text":
				_send(peer, "text/plain", "not an image".to_utf8_buffer())
			else:
				_send(peer, "image/png", png_bytes)
			item.responded = true

	func _send(peer: StreamPeerTCP, content_type: String, body: PackedByteArray) -> void:
		var headers: String = "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [content_type, body.size()]
		peer.put_data(headers.to_utf8_buffer())
		peer.put_data(body)
		peer.disconnect_from_host()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var server: ImageServer = ImageServer.new()
	var source_image: Image = Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)
	source_image.fill(Color(0.0, 0.9, 0.2, 1.0))
	server.png_bytes = source_image.save_png_to_buffer()
	root.add_child(server)
	_check(server.start() == OK, "media harness binds IPv4 loopback")
	var transport: KickHttpTransport = KickHttpTransport.new()
	transport.max_retries = 0
	root.add_child(transport)
	var cache: KickMediaCache = KickMediaCache.new(transport)
	cache.persist_to_disk = true
	cache.cache_directory = "user://redot-kicker/test-media-cache"
	cache.max_item_bytes = 1024
	cache.max_total_bytes = 4096
	cache.max_items = 2
	root.add_child(cache)
	cache.clear_data()

	var invalid: KickMediaResult = await cache.fetch_texture("http://example.com/image.png")
	_check(invalid.error != null, "non-loopback plaintext media URL is rejected")
	var url: String = "http://127.0.0.1:%d/image.png" % server.port()
	var first: KickMediaResult = await cache.fetch_texture(url)
	_check(first.is_success() and first.mime_type == "image/png" and first.texture != null, "bounded media cache decodes a PNG")
	var second: KickMediaResult = await cache.fetch_texture(url)
	_check(second.is_success() and second.from_cache, "second media request is served from cache")
	_check(server.request_count == 1, "cached media avoids a second network request")
	var wrong_type: KickMediaResult = await cache.fetch_texture("http://127.0.0.1:%d/text" % server.port())
	_check(wrong_type.error != null and wrong_type.error.category == "media_type", "unsupported media content type is rejected")
	_check(cache.item_count() == 1 and cache.total_bytes() > 0, "media cache reports bounded in-memory state")
	_check(cache.clear_data() == null and cache.item_count() == 0 and cache.total_bytes() == 0, "clear-data removes memory and disk media state")

	cache.queue_free()
	transport.queue_free()
	server.stop()
	server.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + label)
	else:
		_failures.append(label)


func _finish() -> void:
	if _failures.is_empty():
		print("REDOT KICKER MEDIA SUITE PASS: %d checks" % _checks)
		quit(0)
		return
	for failure: String in _failures:
		push_error("REDOT KICKER MEDIA SUITE FAIL: " + failure)
	print("REDOT KICKER MEDIA SUITE FAILED: %d of %d checks" % [_failures.size(), _checks])
	quit(1)
