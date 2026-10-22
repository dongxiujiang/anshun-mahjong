extends SceneTree
## Driven by run_reconnect.py: kill the client process, then launch a fresh one.
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
		if not await _wait(func(): return net.game != null and net.game.players.size() == 4 and net.game.players[1].score == -12, "Initial private state received"): return
		t.expect(network.has_saved_session(), "Token persisted before forced process termination")
		_marker("first_ready", {"seat": net.my_seat, "hand": net.game.players[net.my_seat].concealed, "score": net.game.players[net.my_seat].score, "prompt": net.game.prompt_id})
		# The Python driver terminates this process without running cleanup.
		return
	if role == "expired":
		await _expired()
		return
	t.expect(config.player_name == "重启小明", "Fresh process loads nickname")
	t.expect(network.has_saved_session(), "Fresh process loads reconnect identity")
	var menu = load("res://scenes/MainMenu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	t.expect(menu.resume_dialog != null, "Startup offers the previous room")
	menu.resume_dialog.confirmed.emit()
	if not await _wait(func(): return current_scene != null and current_scene.has_method("_on_net_prompt"), "Startup restores through lobby into real table"): return
	net = network.net_node
	var table = current_scene
	t.expect(net.my_seat == 1 and table.human_seat == 1, "Restart keeps original seat")
	t.expect(not net._resume_sync_pending and not table._awaiting_rejoin_snapshot, "Only authoritative snapshot unlocks restored table")
	t.expect(net.game.players[1].name_label == "重启小明", "Restored table keeps player name")
	var total := 0.0
	for player in net.game.players:
		total += player.score
		if player.seat != net.my_seat and net.game.phase != RoundState.Phase.SETTLED:
			t.expect(player.concealed.all(func(tile): return tile == "hidden0"), "Other hands remain private on restart")
	t.expect(is_equal_approx(total, 800.0), "Restart preserves score conservation")
	if role == "resume":
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/first_ready.json"))
		t.expect(net.game.players[1].concealed == expected.hand, "No redeal during restart")
		t.expect(net.game.players[1].score == -12, "Negative cumulative score survives restart")
		t.expect(net.game.prompt_id == int(expected.prompt), "Current prompt survives restart")
		net.rpc_id(1, "ack", "resumed-playing")
		if not await _wait(func(): return net.game.phase == RoundState.Phase.SETTLED, "Client receives settlement before second process termination"): return
		_marker("settled_ready", {"scores": net.game.players.map(func(player): return player.score)})
		return
	t.expect(net.game.phase == RoundState.Phase.SETTLED, "Second restart restores settled round")
	t.expect(table._settlement_animation_controller.is_completed(), "Restored settlement goes directly to final display")
	var settled: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + "/settled_ready.json"))
	t.expect(net.game.players.map(func(player): return player.score) == settled.scores, "Settled scores are not applied twice")
	net.rpc_id(1, "ack", "resumed-settled")
	# Preserve a stale identity only in the isolated test fixture for expiry rejection.
	DirAccess.copy_absolute(network.settings_path, folder + "/stale.cfg")
	table.queue_free()
	await process_frame
	await network.leave_room()
	t.expect(not network.has_saved_session(), "Explicit leave clears persisted record")
	_marker("left")
	await H.quit_cleanly(self, t.finish("restart_reconnect_" + role))

func _host() -> void:
	t.expect(network.start_host(false, true, 7594, "4321", "重启测试桌"), "Restart fixture host opens")
	if not await _wait(func(): return net._members.size() == 2 and net._members.values().any(func(member): return member.ready), "Initial client ready"): return
	net.set_wants_dealer(true)
	net.set_ready(true)
	t.expect(net.start_net_game(20261018), "Seeded round starts")
	net.game.players[0].score = 412
	net.game.players[1].score = -12
	net._host_broadcast()
	if not await _wait(func(): return net.ack_text == "resumed-playing", "New process restores playing round", 25.0): return
	t.expect(net._members.size() == 2 and net._peer_seat.size() == 2, "Restart creates no duplicate membership")
	t.expect(net.game.controllers[1] == null, "Restart hands control back to human")
	t.expect(net._orphaned.is_empty(), "Restart consumes seat reservation")
	net.game._finish()
	if not await _wait(func(): return net.ack_text == "resumed-settled", "Second new process restores settlement", 25.0): return
	if not await _wait(func(): return net._members.size() == 1, "Explicit leave reaches server"): return
	t.expect(not net.has_reconnect_reservations(), "Explicit leave immediately releases server reservation")
	network.reset()
	t.expect(network.start_host(false, true, 7594, "4321", "同号新房间"), "Replacement room reuses the original number")
	net = network.net_node
	_marker("replacement_ready")
	if not await _wait(func(): return FileAccess.file_exists(folder + "/expired_done.json"), "Expired identity rejected"): return
	t.expect(net._members.size() == 1, "Expired identity does not join as a new player")
	network.reset()
	await H.quit_cleanly(self, t.finish("restart_reconnect_host"))

func _expired() -> void:
	# Sessions written by 1.4.17 keep the token in the encrypted companion
	# file. Remove it so this fixture tests the legacy plaintext migration path.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(network.settings_path + ".session"))
	DirAccess.copy_absolute(folder + "/stale.cfg", network.settings_path)
	network.load_settings()
	t.expect(network.has_saved_session(), "Expiry fixture has previous credential")
	var errors: Array = []
	net.connection_error.connect(func(message): errors.append(message))
	t.expect(network.resume_saved_session(), "Expired session attempts resume")
	if not await _wait(func(): return not errors.is_empty(), "Server rejects released seat"): return
	t.expect(not network.has_saved_session(), "Authoritative rejection clears stale local identity")
	t.expect(net.my_seat == -1, "Rejected resume never silently joins a different seat")
	_marker("expired_done")
	network.reset()
	await H.quit_cleanly(self, t.finish("restart_reconnect_expired"))
