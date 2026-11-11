extends SceneTree
## Forced process termination must never resurrect an old-room prompt.
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var network: Node
var net: NetGameNode
var role := ""
var folder := ""

func _initialize() -> void: call_deferred("_run")

func _wait(predicate: Callable, label: String, seconds: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	var ok := t.expect(bool(predicate.call()), label)
	if not ok: quit(1)
	return ok

func _marker(name_value: String, data: Dictionary = {}) -> void:
	var file := FileAccess.open(folder + "/" + name_value + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--restart-role="): role = argument.trim_prefix("--restart-role=")
		if argument.begins_with("--restart-dir="): folder = argument.trim_prefix("--restart-dir=")
	network = root.get_node("Network")
	net = network.net_node
	if role == "host":
		await _host()
		return
	network.settings_path = folder + "/network.cfg"
	network.persist_settings = true
	network.load_settings()
	var config := root.get_node("GameConfig")
	config.settings_path = folder + "/game.cfg"
	config.persist_settings = true
	config.load_settings()
	if role == "first":
		config.set_player_name("重启小明")
		network.save_lobby_preferences(false, "4321", "重启测试桌")
		net.room_ready.connect(func(_seat): net.set_ready(true))
		t.expect(network.start_client("127.0.0.1", 7594, "4321"), "Initial client joins")
		if not await _wait(func(): return net.game != null and net.game.players.size() == 4 \
				and net.game.players[0].score == -12 and net.game.prompt_id > 0, "Initial playing prompt received after opening confirmation"): return
		t.expect(network.has_saved_session(), "Token persisted before forced process termination")
		_marker("first_ready", {"seat": net.my_seat, "hand": net.game.players[net.my_seat].concealed, "score": net.game.players[net.my_seat].score, "prompt": net.game.prompt_id})
		# The Python driver terminates this process without running cleanup.
		return
	t.expect(config.player_name == "重启小明", "Fresh process retains nickname")
	t.expect(not network.has_saved_session(), "Fresh process abandons previous room identity")
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	t.expect(menu.resume_dialog == null, "Startup has no old-room reconnect prompt")
	t.expect(network.mode == "" and not net._client_joined, "Startup does not reconnect in the background")
	t.expect(network.lobby_preferences.number == "4321", "Room input preference survives clearing session")
	_marker("fresh_done")
	menu.queue_free()
	await H.quit_cleanly(self, t.finish("restart_reconnect_" + role))

func _host() -> void:
	t.expect(network.start_host(false, true, 7594, "4321", "重启测试桌"), "Restart fixture host opens")
	if not await _wait(func(): return net._members.size() == 2 and net._members.values().any(func(member): return member.ready), "Initial client ready"): return
	net.set_wants_dealer(true)
	net.set_ready(true)
	if not await _wait(func(): return net._started, "Ready humans start the restart fixture"): return
	net.game.players[1].score = 412
	net.game.players[0].score = -12
	net._host_broadcast()
	if not await _wait(func(): return FileAccess.file_exists(folder + "/fresh_done.json"), "Restart completes without reconnecting", 25.0): return
	t.expect(net._members.size() <= 2, "Restart creates no extra membership")
	network.reset()
	await H.quit_cleanly(self, t.finish("restart_reconnect_host"))
