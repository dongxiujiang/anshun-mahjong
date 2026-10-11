class_name OnlineDirectory
extends Node
signal rooms_updated
signal room_created(room)
signal directory_error(message)
var rooms: Array = []
var base_url := ""
var busy := false
var _http: HTTPRequest
var _operation := ""

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("user://network.cfg") == OK: base_url = str(config.get_value("online", "url", ""))
	_http = HTTPRequest.new()
	_http.timeout = 12.0
	_http.body_size_limit = 256 * 1024
	add_child(_http)
	_http.request_completed.connect(_completed)

func configure(url: String) -> bool:
	var value := url.strip_edges().trim_suffix("/")
	if value != "" and not (value.begins_with("https://") or value.begins_with("http://")):
		directory_error.emit("服务器地址需以 https:// 或 http:// 开头")
		return false
	if busy: _http.cancel_request()
	busy = false
	base_url = value
	rooms.clear()
	var config := ConfigFile.new()
	config.set_value("online", "url", base_url)
	config.save("user://network.cfg")
	return true

func search() -> void:
	_request("list", "/rooms", HTTPClient.METHOD_GET)

func cancel() -> void:
	_http.cancel_request()
	busy = false
	_operation = ""

func create_room(number: String, title: String) -> void:
	_request("create", "/rooms", HTTPClient.METHOD_POST, {"number": number, "name": title})

func _request(operation: String, path: String, method: int, body: Dictionary = {}) -> void:
	if busy: return
	if base_url == "":
		directory_error.emit("在线模式尚未配置服务器，请先在服务器设置中保存地址")
		return
	busy = true
	_operation = operation
	var err := _http.request(base_url + path, PackedStringArray(["Content-Type: application/json"]), method, JSON.stringify(body) if method == HTTPClient.METHOD_POST else "")
	if err != OK:
		busy = false
		directory_error.emit("无法连接房间服务器，请稍后重试")

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		directory_error.emit("房间服务器未响应，请检查服务器设置")
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		directory_error.emit("服务器返回的房间数据无效")
		return
	if code < 200 or code >= 300:
		directory_error.emit(str(data.get("error", "房间请求失败（%d）" % code)))
		return
	if _operation == "list":
		rooms.clear()
		for room in data.get("rooms", []):
			if _valid_room(room): rooms.append(room)
		rooms_updated.emit()
	elif _operation == "create":
		var room = data.get("room", {})
		if _valid_room(room): room_created.emit(room)
		else: directory_error.emit("服务器未返回可连接的房间")

func _valid_room(room: Variant) -> bool:
	return room is Dictionary and NetGameNode.valid_room_number(str(room.get("number", ""))) and str(room.get("host", "")) != "" and int(room.get("port", 0)) > 0 and int(room.get("port", 0)) <= 65535
