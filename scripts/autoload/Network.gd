extends Node
## 联机入口（Autoload）：持有 NetGameNode（跨场景存活，RPC 路径两端一致 /root/Network/Net）。

signal peer_joined(peer_id)
signal peer_left(peer_id)

var mode := ""            # "host" / "client" / ""
var net_node: NetGameNode = null
var def_port := 7500
var discovery: LanDiscovery
var directory: OnlineDirectory
const STORE := preload("res://scripts/core/UserSettingsStore.gd")
const SESSIONS := preload("res://scripts/core/NetworkSessionStore.gd")
var settings_path := "user://network.cfg"
var persist_settings := DisplayServer.get_name() != "headless"
var saved_session: Dictionary = {}
var lobby_preferences := {"online": false, "number": "", "name": "朋友麻将局", "room_name_manual": false}
var resume_on_lobby := false
var resume_prompt_shown := false
var room_generation := 0
const SESSION_MAX_AGE_SECONDS := 31 * 60

func _ready() -> void:
	_new_net_node()
	discovery = LanDiscovery.new()
	add_child(discovery)
	directory = OnlineDirectory.new()
	directory.settings_path = settings_path
	directory.persist_settings = persist_settings
	add_child(directory)
	if persist_settings: load_settings()

func _new_net_node() -> void:
	net_node = NetGameNode.new()
	net_node.name = "Net"
	add_child(net_node)
	net_node.room_ready.connect(func(_seat): _remember_session())
	net_node.lobby_updated.connect(_remember_session)
	net_node.session_invalidated.connect(clear_saved_session)

func load_settings() -> void:
	saved_session = SESSIONS.read_session(settings_path)
	var config := STORE.read_config(settings_path)
	for key in lobby_preferences:
		var value = config.get_value("lobby", key, lobby_preferences[key])
		if typeof(value) == typeof(lobby_preferences[key]): lobby_preferences[key] = value

func save_lobby_preferences(online: bool, number: String, title: String, room_name_manual: bool = false, persist: bool = true) -> void:
	lobby_preferences = {"online": online, "number": number.left(8), "name": title.left(24),
		"room_name_manual": room_name_manual}
	if not persist or not persist_settings: return
	var config := STORE.read_config(settings_path)
	for key in lobby_preferences: config.set_value("lobby", key, lobby_preferences[key])
	if STORE.write_config(config, settings_path) != OK: push_warning("无法保存联机设置")

func _remember_session() -> void:
	if mode != "client" or not net_node._client_joined: return
	var session := {"host": net_node._server_ip, "port": net_node._server_port,
		"number": net_node._join_number if net_node.lobby.is_empty() else net_node.room_number,
		"name": net_node.room_name, "token": net_node._resume_token,
		"player_name": net_node._join_name, "online": bool(lobby_preferences.online),
		"saved_at": Time.get_unix_time_from_system()}
	if not SESSIONS.valid(session) or session == saved_session: return
	saved_session = session
	if persist_settings and SESSIONS.write_session(settings_path, session) != OK:
		push_warning("无法保存重连信息，请检查存储空间")

func has_saved_session() -> bool:
	return SESSIONS.valid(saved_session) and not _saved_session_expired()

func clear_saved_session() -> void:
	saved_session = {}
	resume_on_lobby = false
	if persist_settings and SESSIONS.write_session(settings_path, {}) != OK:
		push_warning("无法清除上次房间信息")

func _saved_session_expired() -> bool:
	var now := Time.get_unix_time_from_system()
	var saved_at := float(saved_session.get("saved_at", 0.0))
	if saved_at > 0.0 and now - saved_at <= SESSION_MAX_AGE_SECONDS:
		return false
	# 旧记录没有 saved_at 时用加密会话文件的修改时间兜底；测试/CI 的时钟
	# 或迁移场景不会因此误删刚写入的会话。
	var modified := SESSIONS.modified_time(settings_path)
	if modified > 0 and now - float(modified) <= SESSION_MAX_AGE_SECONDS:
		return false
	return true

func resume_saved_session() -> bool:
	if not has_saved_session(): return false
	if _saved_session_expired():
		clear_saved_session()
		return false
	mode = "client"
	return net_node.client(saved_session.host, saved_session.port, saved_session.number,
		saved_session.player_name, "", saved_session.token, true)

func leave_room() -> void:
	var leaving_node := net_node
	var generation := room_generation
	clear_saved_session()
	if mode == "client" and net_node._client_joined and not net_node._reconnecting and multiplayer.multiplayer_peer != null:
		net_node.request_leave.rpc_id(1)
		net_node._server_ip = ""
		net_node._client_joined = false
		# Flush the reliable leave before closing ENet; window/app closure does not call this.
		await get_tree().create_timer(0.15, true, false, true).timeout
	# A new host/client may have been started while the leave packet flushed;
	# never tear down that newer room.
	if generation != room_generation:
		return
	if net_node == leaving_node: reset()

## 建主机：host_auto=主机自己是否自动代打(否则由本机UI操作)，ai_fill=空位补AI
func start_host(host_auto: bool, ai_fill: bool, port: int = 0, number: String = "0000", title: String = "麻将房间") -> bool:
	room_generation += 1
	var ok := net_node.host(host_auto, ai_fill, port if port > 0 else def_port, number, title)
	if ok:
		mode = "host"
		clear_saved_session()
	return ok

func start_client(ip: String, port: int = 0, number: String = "", owner_token: String = "") -> bool:
	room_generation += 1
	if not net_node.client(ip, port if port > 0 else def_port, number, GameConfig.player_name, owner_token):
		return false
	mode = "client"
	return true

func reset() -> void:
	room_generation += 1
	if net_node != null and net_node.host_mode and net_node.game != null: net_node.game.export_replay()
	mode = ""
	discovery.stop_search()
	discovery.stop_advertise()
	multiplayer.multiplayer_peer = null
	if net_node != null:
		remove_child(net_node)
		net_node.queue_free()
	_new_net_node()

func is_host() -> bool:
	return mode == "host" and multiplayer.get_unique_id() == 1
