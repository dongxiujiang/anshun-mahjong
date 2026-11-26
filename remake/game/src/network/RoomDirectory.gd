extends Node
## HTTPS room discovery; ENet subsequently authenticates the seat and holds the authoritative round.
const Protocol = preload("res://src/domain/Protocol.gd")
signal rooms_received(rooms: Array)
signal room_received(room: Dictionary)
signal failed(message: String)
signal room_verified(room: Dictionary)
signal verification_failed(reason: String)

var _base_url := ""
var _request: HTTPRequest
var _operation := ""
var _expected_number := ""
var _expected_instance := ""

func configure(base_url: String) -> bool:
	cancel()
	var url := base_url.strip_edges().trim_suffix("/")
	_base_url = ""
	if url.is_empty():
		return false
	var pattern := RegEx.new()
	pattern.compile("^https://[A-Za-z0-9.\\-]+(:[0-9]{1,5})?(/[A-Za-z0-9_./\\-]*)?$|^http://(127\\.0\\.0\\.1|localhost)(:[0-9]{1,5})?(/[A-Za-z0-9_./\\-]*)?$")
	if pattern.search(url) == null:
		failed.emit("请输入有效的 HTTPS 房间服务地址")
		return false
	_base_url = url
	return true

func cancel() -> void:
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null
	_operation = ""

func list_rooms() -> bool:
	return _send("list", "/v1/rooms")

func create_room(room_name: String, settings: Dictionary = {}, number: String = "") -> bool:
	var desired := number if not number.is_empty() else str(settings.get("number", ""))
	var options := settings.duplicate()
	options.erase("number")
	return _send("create", "/v1/rooms", {"name": room_name, "number": desired, "settings": options})

func find_room(number: String) -> bool:
	if not _number_valid(number):
		failed.emit("请输入4至8位房间号")
		return false
	return _send("find", "/v1/rooms/" + number)

func verify_room(number: String, instance: String) -> bool:
	if not _number_valid(number) or not _instance_valid(instance):
		verification_failed.emit("unavailable")
		return false
	_expected_number = number
	_expected_instance = instance
	return _send("verify", "/v1/rooms/" + number)

static func _instance_valid(value: Variant) -> bool:
	return value is String and value.length() == 64 and value.is_valid_hex_number()

static func _number_valid(number: String) -> bool:
	if number.length() < 4 or number.length() > 8:
		return false
	for digit in number.to_ascii_buffer():
		if digit < 48 or digit > 57:
			return false
	return true

func _send(operation: String, path: String, payload: Dictionary = {}) -> bool:
	if _base_url.is_empty():
		_fail(operation, "请先设置在线房间服务地址")
		return false
	cancel()
	_operation = operation
	_request = HTTPRequest.new()
	_request.timeout = 4 if operation == "verify" else 12
	_request.body_size_limit = 262144
	_request.max_redirects = 0
	add_child(_request)
	_request.request_completed.connect(_completed.bind(_request))
	var headers := PackedStringArray(["Accept: application/json", "Content-Type: application/json"])
	var method := HTTPClient.METHOD_GET if payload.is_empty() else HTTPClient.METHOD_POST
	var error := _request.request(_base_url + path, headers, method, "" if payload.is_empty() else JSON.stringify(payload))
	if error != OK:
		cancel()
		_fail(operation, "无法联系在线房间服务")
		return false
	return true

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, source: HTTPRequest) -> void:
	if source != _request:
		return
	var operation := _operation
	source.queue_free()
	_request = null
	_operation = ""
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail(operation, "在线房间服务暂时不可用")
		return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		_fail(operation, "房间服务返回了无效数据")
		return
	var response: Dictionary = parser.data
	if operation == "verify":
		_verify_response(code, response)
		return
	if code < 200 or code >= 300:
		failed.emit(str(response.get("error", "房间请求失败")).left(120))
		return
	if response.get("protocol") != Protocol.PROTOCOL_VERSION or response.get("variant") != Protocol.VARIANT_ID:
		failed.emit("房间服务版本不匹配")
		return
	if operation == "list":
		var rows = response.get("rooms")
		if rows is Array and rows.size() <= 256 and rows.all(_valid_room):
			rooms_received.emit(rows)
			return
	elif _valid_room(response.get("room")):
		room_received.emit(response.room)
		return
	failed.emit("房间服务返回了无效房间信息")

func _fail(operation: String, message: String) -> void:
	if operation == "verify":
		verification_failed.emit("unavailable")
	else:
		failed.emit(message)

func _verify_response(code: int, response: Dictionary) -> void:
	if response.get("protocol") != Protocol.PROTOCOL_VERSION or response.get("variant") != Protocol.VARIANT_ID:
		verification_failed.emit("unavailable")
		return
	if code == 404 and response.get("reason") == "room_not_found":
		verification_failed.emit("missing")
		return
	var room: Variant = response.get("room")
	if code != 200 or not _valid_room(room) or room.number != _expected_number or not _instance_valid(room.get("room_instance_id")):
		verification_failed.emit("unavailable")
	elif room.room_instance_id != _expected_instance:
		verification_failed.emit("missing")
	else:
		room_verified.emit(room)

func _valid_room(room) -> bool:
	if not room is Dictionary or not room.get("number") is String or not _number_valid(room.number):
		return false
	if not room.get("host") is String or room.host.is_empty() or room.host.length() > 253 or not room.get("name") is String:
		return false
	if not typeof(room.get("port")) in [TYPE_INT, TYPE_FLOAT] or not typeof(room.get("players")) in [TYPE_INT, TYPE_FLOAT]:
		return false
	return room.port >= 1 and room.port <= 65535 and room.port == int(room.port) and room.players >= 0 and room.players <= 4 and room.players == int(room.players) and room.get("started") is bool
