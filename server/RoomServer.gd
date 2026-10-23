extends SceneTree
## 云端每个房间一个无界面 Godot 进程，复用同一权威状态机和 RPC。
var _status_path := ""
var _tick := 0.0
var _empty_seconds := 0.0
var _net: NetGameNode

func _initialize() -> void:
	call_deferred("_run")

func _argument(name_value: String, fallback: String = "") -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(name_value + "="): return value.substr(name_value.length() + 1)
	return fallback

func _run() -> void:
	var network := root.get_node("Network")
	_net = network.net_node
	_status_path = _argument("--status-file")
	var owner_token := OS.get_environment("MAHJONG_OWNER_TOKEN")
	if owner_token == "": owner_token = _argument("--owner-token")
	if not _net.host(false, true, int(_argument("--room-port", "7600")), _argument("--room-number", "0000"), _argument("--room-name", "在线麻将"), true, owner_token):
		quit(1)
		return
	_net.game.ai_delay_seconds = 1.0
	_net.lobby_updated.connect(_write_status)
	_net.room_empty.connect(func():
		_write_status()
		quit())
	_write_status()

func _process(delta: float) -> bool:
	if _net == null or not _net.host_mode: return false
	_tick += delta
	_empty_seconds = _empty_seconds + delta if _net._members.is_empty() else 0.0
	if _empty_seconds > 60.0 and not _net.has_reconnect_reservations():
		quit()
		return false
	if _tick >= 1.0:
		_tick = 0.0
		_write_status()
	return false

func _token_digest(token: String) -> String:
	if token == "": return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(token.to_utf8_buffer())
	return "sha256:" + context.finish().hex_encode()

func _write_status() -> void:
	if _status_path == "": return
	var file := FileAccess.open(_status_path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_error("无法写入房间状态文件，目录服务将看不到此房间")
		return
	var members := {}
	for peer in _net._members:
		var seat := int(_net._peer_seat.get(peer, -1))
		var token := str(_net._members[peer].get("resume_token", ""))
		if seat >= 0 and token != "":
			members[str(seat)] = _token_digest(token)
	file.store_string(JSON.stringify({"number": _net.room_number, "port": _net._port, "name": _net.room_name, "players": _net._members.size(), "started": _net._started, "members": members, "host_token": _token_digest(_net._owner_token), "updated": Time.get_unix_time_from_system()}))
	file.close()
	if DirAccess.rename_absolute(_status_path + ".tmp", _status_path) != OK:
		push_error("无法更新房间状态文件")
