extends SceneTree
const H := preload("res://tests/test_harness.gd")
const STORE := preload("res://scripts/core/UserSettingsStore.gd")
const SESSIONS := preload("res://scripts/core/NetworkSessionStore.gd")
var t := H.new()
var folder := "res://build/network_persistence/%d" % OS.get_process_id()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var network := root.get_node("Network")
	var config := root.get_node("GameConfig")
	network.settings_path = folder + "/network.cfg"
	network.persist_settings = true
	config.settings_path = folder + "/game.cfg"
	config.persist_settings = true
	config.set_player_name("  重启后的玩家  ")
	config.player_name = "未加载"
	config.load_settings()
	t.expect(config.player_name == "重启后的玩家", "Nickname is saved immediately and restored")
	var saved := STORE.read_config(config.settings_path)
	saved.set_value("player", "name", 123)
	saved.save(config.settings_path)
	config.load_settings()
	t.expect(config.player_name == "重启后的玩家", "Invalid name type does not overwrite valid player name")
	network.save_lobby_preferences(true, "001234", "朋友房间")
	var directory := OnlineDirectory.new()
	directory.settings_path = network.settings_path
	directory.persist_settings = true
	root.add_child(directory)
	t.expect(directory.base_url == "https://mj.dongxiu.fun", "Fresh install uses the production directory by default")
	t.expect(directory.configure("https://example.com/rooms-service/"), "Directory address can be saved")
	var session := {"host": "127.0.0.1", "port": 7594, "number": "001234", "name": "朋友房间",
		"player_name": "重启后的玩家", "token": "a".repeat(64), "online": true}
	t.expect(SESSIONS.write_session(network.settings_path, session) == OK, "Confirmed session saved")
	network.load_settings()
	t.expect(network.saved_session == session, "All reconnection fields survive loading")
	t.expect(network.lobby_preferences == {"online": true, "number": "001234", "name": "朋友房间"}, "Mode, room number and room title persist")
	directory.configure("https://example.com/changed")
	t.expect(SESSIONS.read_session(network.settings_path) == session, "Editing directory URL preserves reconnection identity")
	network.save_lobby_preferences(false, "765432", "新的房间")
	t.expect(STORE.read_config(network.settings_path).get_value("online", "url") == "https://example.com/changed", "Editing lobby fields preserves directory URL")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(network.settings_path))
	t.expect(SESSIONS.read_session(network.settings_path) == session, "Interrupted write can recover session backup")
	network.clear_saved_session()
	t.expect(SESSIONS.read_session(network.settings_path).is_empty(), "Explicit leave clears saved identity")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(network.settings_path))
	t.expect(SESSIONS.read_session(network.settings_path).is_empty(), "Backup cannot resurrect a discarded identity")
	t.expect(STORE.read_config(network.settings_path).get_value("online", "url") == "https://example.com/changed", "Clearing session preserves server preference")
	for bad in [{"port": 0}, {"port": "7594"}, {"number": "x123"}, {"token": "short"}, {"token": "z".repeat(64)}, {"player_name": 9}]:
		var invalid := session.duplicate(true)
		invalid.merge(bad, true)
		t.expect(not SESSIONS.valid(invalid), "Malformed session rejected: " + str(bad.keys()))
	SESSIONS.write_session(network.settings_path, session)
	network.load_settings()
	network.reset()
	t.expect(network.has_saved_session(), "Transport reset retains retryable identity")
	t.expect(network.resume_saved_session(), "Restart opens resume-only connection")
	t.expect(network.net_node._resume_sync_pending and network.net_node._resume_requested, "Gameplay locked before authoritative resume snapshot")
	network.net_node._reconnect_attempt = 5
	network.net_node._reconnect_step()
	t.expect(network.has_saved_session(), "Temporary network failure retains identity for retry")
	network.net_node.join_rejected("expired")
	t.expect(not network.has_saved_session(), "Server rejection removes expired identity")
	network.reset()
	# Reservation survives longer than the 30-second readiness wait.
	t.expect(network.start_host(false, true, 7595, "001234"), "Reservation fixture host opens")
	var net: NetGameNode = network.net_node
	net.set_ready(true)
	net._orphaned[1] = {"until": Time.get_ticks_msec() + NetGameNode.RESUME_GRACE_MS,
		"ready_until": Time.get_ticks_msec() + NetGameNode.READY_GRACE_MS, "member": {"name": "离线玩家"}}
	t.expect(not net.all_ready(), "First thirty seconds wait for the disconnected player")
	net._orphaned[1].ready_until = Time.get_ticks_msec() - 1
	net._process(0.0)
	t.expect(net.all_ready() and net.has_reconnect_reservations(), "Other players can continue while restart reservation remains")
	t.expect(net.lobby.seats[1].ready and net.lobby.seats[1].disconnected, "Lobby presents ready substitute without losing reservation")
	net._orphaned[1].until = Time.get_ticks_msec() - 1
	net._process(0.0)
	t.expect(not net.has_reconnect_reservations(), "Five-minute deadline releases reserved seat")
	network.reset()
	# Real lobby inputs persist without requiring Join/Create.
	var lobby = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	lobby.player_input.text = "新的昵称"
	lobby.player_input.text_changed.emit(lobby.player_input.text)
	lobby.room_input.text = "123456"
	lobby.room_input.text_changed.emit(lobby.room_input.text)
	lobby.room_name_input.text = "测试桌"
	lobby.room_name_input.text_changed.emit(lobby.room_name_input.text)
	t.expect(STORE.read_config(config.settings_path).get_value("player", "name") == "新的昵称", "Nickname input saves without joining")
	t.expect(STORE.read_config(network.settings_path).get_value("lobby", "name") == "测试桌", "Room title input saves without creating")
	lobby.queue_free()
	directory.queue_free()
	await process_frame
	network.discovery.stop_search()
	network.persist_settings = false
	config.persist_settings = false
	await H.quit_cleanly(self, t.finish("network_persistence"))
