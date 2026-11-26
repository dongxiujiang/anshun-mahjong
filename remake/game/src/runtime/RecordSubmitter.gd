extends Node
## A successful HTTP acknowledgement, not a click or a local save, completes a submission.
signal status_changed(number: int, state: Dictionary)
const MAX_BYTES := 2 * 1024 * 1024
const MAX_PENDING := 16
var _url := ""
var _instance := ""
var _mode := ""
var _signing_key := PackedByteArray()
var _states := {}
var _payloads := {}
var _request: HTTPRequest
var _active := ""
var _root := "user://record-outbox-v1"

func configure(instance: String, mode: String, url: String, storage: String = "user://record-outbox-v1") -> void:
	_instance = instance
	_mode = mode
	_signing_key.clear()
	var secret := OS.get_environment("DONGXIU_RECORD_SIGNING_KEY") if mode == "online" else ""
	if RegEx.create_from_string("\\A[a-f0-9]{64}\\z").search(secret) != null:
		_signing_key = secret.hex_decode()
	_root = storage
	set_service_url(url)
	DirAccess.make_dir_recursive_absolute(_root)
	_load_saved()
	_pump.call_deferred()

func _key(number: int) -> String:
	return _instance + ":" + str(number)

static func safe_url(url: String) -> bool:
	var parts := RegEx.create_from_string("\\A(https?)://(\\[[0-9a-fA-F:]+\\]|[A-Za-z0-9.-]+)(?::([0-9]{1,5}))?(/[^\\s#]*)?\\z").search(url)
	if parts == null: return false
	var port := parts.get_string(3)
	if not port.is_empty() and (port.to_int() < 1 or port.to_int() > 65535): return false
	return parts.get_string(1) == "https" or parts.get_string(2) in ["127.0.0.1", "localhost", "[::1]"]

func set_service_url(url: String) -> void:
	_url = url if safe_url(url) else ""

func state(number: int) -> Dictionary:
	return _states.get(_key(number), {}).duplicate(true)

func enqueue(number: int) -> bool:
	var key := _key(number)
	for old in _states.keys():
		if old != key and _states[old].status == "stored": _states.erase(old)
	if number <= 0 or (_states.size() >= MAX_PENDING and not _states.has(key)): return false
	if _states.get(key, {}).get("status") in ["stored", "sending", "queued"]: return true
	_set_status(key, "queued", "已登记，本局结算后提交")
	retry_pending()
	return true

func complete(record: Dictionary) -> void:
	var number := int(record.get("round_number", -1))
	var key := _key(number)
	if not _states.has(key) or _states[key].status == "stored" or _payloads.has(key): return
	var payload := {"mode": _mode, "room_instance_id": _instance, "record": record.duplicate(true)}
	var text := JSON.stringify(payload)
	if text.to_utf8_buffer().size() > MAX_BYTES:
		_set_status(key, "failed", "记录过大，未提交")
		return
	var path := _root.path_join(_instance + "-" + str(number) + ".json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		_set_status(key, "failed", "记录保存失败，未提交")
		return
	file.store_string(JSON.stringify({"format": 1, "endpoint": _url, "payload": payload}))
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		_set_status(key, "failed", "记录保存失败，未提交")
		return
	_payloads[key] = {"body": text, "path": path, "checksum": record.checksum, "endpoint": _url}
	_pump()

func _set_status(key: String, status: String, message: String) -> void:
	var number := int(key.get_slice(":", 1))
	_states[key] = {"status": status, "message": message, "round_number": number}
	if key.get_slice(":", 0) == _instance:
		status_changed.emit(number, _states[key].duplicate())

# Only completed records explicitly requested before are retried, once per round/restart/click.
func retry_pending() -> void:
	for key in _payloads:
		if _states[key].status == "failed":
			_set_status(key, "queued", "正在重试已请求的本局记录")
	_pump()

func _load_saved() -> void:
	if _url.is_empty(): return
	for name in DirAccess.get_files_at(_root):
		if _payloads.size() >= MAX_PENDING: break
		if not name.ends_with(".json"): continue
		var path := _root.path_join(name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > MAX_BYTES + 1024: continue
		var saved = JSON.parse_string(file.get_as_text())
		if not saved is Dictionary or saved.get("format") != 1 or saved.get("endpoint") != _url: continue
		var payload = saved.get("payload")
		if not payload is Dictionary or payload.get("mode") != _mode or not payload.get("record") is Dictionary: continue
		var instance = payload.get("room_instance_id")
		var number = payload.record.get("round_number")
		var checksum = payload.record.get("checksum")
		if not instance is String or instance.is_empty() or instance.contains(":"): continue
		if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(number) or number != int(number) or number < 1 or number > 2147483647: continue
		if not checksum is String or checksum.is_empty() or name != instance + "-" + str(int(number)) + ".json": continue
		var key: String = instance + ":" + str(int(number))
		var body := JSON.stringify(payload)
		if body.to_utf8_buffer().size() > MAX_BYTES: continue
		_payloads[key] = {"body": body, "path": path, "checksum": checksum, "endpoint": _url}
		_set_status(key, "queued", "继续提交已保存的记录")

func _pump() -> void:
	if not _active.is_empty() or not is_inside_tree(): return
	for key in _payloads:
		if _states[key].status != "queued": continue
		if _url.is_empty() or _payloads[key].endpoint != _url:
			_set_status(key, "failed", "记录服务未配置或已变更，记录仍保存在本机")
			continue
		var headers := PackedStringArray(["Content-Type: application/json"])
		if _mode == "online":
			var signature := _signature(_payloads[key].body)
			if signature.is_empty():
				_set_status(key, "failed", "记录服务身份未配置，记录仍保存在服务器")
				continue
			headers.append("X-Dongxiu-Record-Signature: " + signature)
		_request = HTTPRequest.new()
		_request.timeout = 12.0
		_request.body_size_limit = 65536
		_request.max_redirects = 0
		add_child(_request)
		_request.request_completed.connect(_finished)
		_active = key
		_set_status(key, "sending", "正在提交本局记录")
		var error := _request.request(_url, headers, HTTPClient.METHOD_POST, _payloads[key].body)
		if error != OK: _finished(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())
		return

func _signature(body: String) -> String:
	if _signing_key.size() != 32: return ""
	var context := HMACContext.new()
	if context.start(HashingContext.HASH_SHA256, _signing_key) != OK or context.update(body.to_utf8_buffer()) != OK: return ""
	return context.finish().hex_encode()

func _finished(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	var key := _active
	_active = ""
	_request.queue_free()
	_request = null
	var reply = JSON.parse_string(bytes.get_string_from_utf8())
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and reply is Dictionary and reply.get("status") == "stored" and reply.get("id") == key and reply.get("checksum") == _payloads[key].checksum:
		_set_status(key, "stored", "本局记录已提交")
		DirAccess.remove_absolute(_payloads[key].path)
		_payloads.erase(key)
	else:
		_set_status(key, "failed", "提交失败，已保存在本机；可重试，也会在下一局继续提交")
	_pump()

func _exit_tree() -> void:
	if _request != null: _request.cancel_request()
