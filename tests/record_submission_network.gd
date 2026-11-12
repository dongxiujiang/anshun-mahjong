extends SceneTree
const H := preload("res://tests/test_harness.gd")
const SMOKE := preload("res://tests/smoke_round.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 25000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return bool(predicate.call())

func _run() -> void:
	root.get_node("UpdateManager").auto_check = false
	var network := root.get_node("Network")
	network.reset()
	network.directory.base_url = OS.get_environment("MAHJONG_RECORD_TEST_URL")
	var net: NetGameNode = network.net_node
	var host := OS.get_cmdline_user_args().has("--host")
	var dedicated := OS.get_cmdline_user_args().has("--dedicated")
	var port := int(OS.get_environment("MAHJONG_RECORD_TEST_PORT"))
	if host:
		t.expect(net.host(false, true, port, "86751234", "记录提交测试", dedicated), "authority opens room")
		if net._ai_service != null:
			net._ai_service.stop()
			net._ai_service = null
			net.game.ai_service = null
		net.opening_speed = "0.00"
		net.game.ai_delay_seconds = 1000.0
	else:
		t.expect(network.start_client("127.0.0.1", port, "86751234"), "ordinary player connects")
	if not t.expect(await _wait_until(func(): return net.lobby.get("seats", []).filter(func(s): return int(s.peer) > 1).size() == 1), "real client is authenticated"):
		network.reset()
		quit(1)
		return
	if host:
		for member in net._members.values(): member.ready = true
		net.ai_speed = "1.00"
		t.expect(net.start_net_game(162222), "authority starts real seeded game")
		net.game.controllers = [null, null, null, null]
		t.expect(await _wait_until(func(): return net._round_submitter != null and net._round_submitter.state.get("status") == "waiting"), "client request reaches authority before settlement")
		t.expect(net._round_submitter._http == null, "authority has not uploaded an unfinished game")
		t.expect(await _wait_until(func(): return net.game.phase == RoundState.Phase.PLAYING), "opening completes")
		for seat in 4: net.game.controllers[seat] = SMOKE.SimpleAi.new("AI")
		net.game.ai_delay_seconds = 0.0
		net.game.ai_response_delay_seconds = 0.0
		net.game._ask_turn_actor()
		t.expect(net.game.phase == RoundState.Phase.SETTLED, "real network game completes")
		t.expect(await _wait_until(func(): return net._round_submitter.state.get("status") == "done"), "authority uploads complete record")
		t.expect(await _wait_until(func(): return net.ack_text == "record-checked"), "client sees server confirmation")
	else:
		t.expect(await _wait_until(func(): return net.game != null and net.game.phase in [RoundState.Phase.DEALING, RoundState.Phase.PLAYING]), "client receives starting state")
		net._submit_lobby("submit_record", {"session": net.game.audio_session})
		t.expect(await _wait_until(func(): return net.lobby.get("record_submission", {}).get("status") == "waiting"), "client sees end-of-round registration")
		t.expect(net.game.replay_record().is_empty(), "hidden authoritative history never leaks into client snapshot")
		t.expect(await _wait_until(func(): return net.lobby.get("record_submission", {}).get("status") == "done"), "client receives stored confirmation over ENet")
		net._submit_lobby("submit_record", {"session": net.game.audio_session})
		net.rpc_id(1, "ack", "record-checked")
		await create_timer(0.3).timeout
	network.reset()
	await H.quit_cleanly(self, t.finish("record_submission_network"))
