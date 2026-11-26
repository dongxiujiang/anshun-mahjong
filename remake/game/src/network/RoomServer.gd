extends SceneTree
## One headless process per real online room. The public heartbeat contains no member IDs or tokens.
const Client = preload("res://src/network/GameClient.gd")
const Session = preload("res://src/session/RoomSession.gd")
var _service
var _status_path := ""
var _elapsed := 0.0
var _last_write := -3000
var _last_info := {}
var _boot := 0
var _ever_joined := false
var _closing := false

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	_status_path = OS.get_environment("DONGXIU_ROOM_STATUS")
	var number := OS.get_environment("DONGXIU_ROOM_NUMBER")
	var port := OS.get_environment("DONGXIU_ROOM_PORT")
	var settings = JSON.parse_string(OS.get_environment("DONGXIU_ROOM_SETTINGS"))
	if not _status_path.is_absolute_path() or not port.is_valid_int() or not settings is Dictionary or number.is_empty():
		printerr("房间启动参数无效")
		quit(2)
		return
	settings.record_storage = _status_path.get_base_dir().path_join("pending-records")
	_service = Client.new()
	_service.name = "RoomService"
	root.add_child(_service)
	_service.session_ended.connect(func(_reason): _close())
	if not _service.start_server(number, port.to_int(), settings, "online"):
		printerr("房间端口无法打开")
		quit(3)
		return
	_boot = Time.get_ticks_msec()
	_heartbeat()

func _process(delta: float) -> bool:
	if _service == null or _closing:
		return false
	_elapsed += delta
	if _elapsed >= 0.25:
		_elapsed = 0
		_heartbeat()
	return false

func _heartbeat() -> void:
	if FileAccess.file_exists(_status_path + ".stop"):
		_close()
		return
	var info: Dictionary = _service.discovery_info()
	if info.is_empty():
		_close()
		return
	var now := Time.get_ticks_msec()
	info.auth = _service.directory_auth_state()
	_ever_joined = _ever_joined or int(info.players) > 0
	if not _ever_joined and now - _boot >= Session.ROOM_GRACE_MS:
		_close()
		return
	if info == _last_info and now - _last_write < 2000:
		return
	var tmp := _status_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		_close()
		return
	file.store_string(JSON.stringify(info))
	file.close()
	if DirAccess.rename_absolute(tmp, _status_path) != OK:
		_close()
		return
	_last_info = info
	_last_write = now

func _close() -> void:
	if _closing:
		return
	_closing = true
	if FileAccess.file_exists(_status_path):
		DirAccess.remove_absolute(_status_path)
	if FileAccess.file_exists(_status_path + ".stop"):
		DirAccess.remove_absolute(_status_path + ".stop")
	await create_timer(0.25).timeout
	quit()
