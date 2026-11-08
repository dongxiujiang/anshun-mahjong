extends SceneTree
## 四个真人进程：全员准备、取消倒计时、旧消息、掉线替补及结算UI。
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var role := 0
var net: NetGameNode
var table: Control
var discard_sent_at := 0.0
var discard_received_at := 0.0

func _initialize() -> void: call_deferred("_run")

func _wait_until(predicate: Callable, seconds: float = 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(predicate.call())

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ready-role="): role = int(argument.substr(13))
	var network := root.get_node("Network")
	network.reset()
	net = network.net_node
	if role == 0:
		t.expect(network.start_host(false, false, 7536), "Host opens readiness test")
	else:
		t.expect(network.start_client("127.0.0.1", 7536), "Human client connects")
		t.expect(await _wait_until(func(): return net.lobby.get("seats", []).size() == 4), "Client receives own seat")
	var expected_seat: int = [1, 0, 3, 2][role]
	t.expect(net.my_seat == expected_seat, "Join order allocates South, East, North, West")
	print("[next_round] SEAT_ASSIGNED")
	t.expect(await _wait_until(func(): return net.lobby.seats.filter(func(seat): return int(seat.peer) > 0).size() == 4), "Wait for all joins before first readiness")
	if role == 0:
		root.get_node("GameConfig").set_tile_animation_seconds(0.4, false)
		root.get_node("GameConfig").set_ai_speed("0.60", false)
		root.get_node("GameConfig").set_settlement_speed("0.90", false)
		root.get_node("GameConfig").set_ai_strength("weak", false)
		net.set_opening_speed("0.40")
		net.set_ai_speed("0.60")
		net.set_settlement_speed("0.90")
		net.set_ai_strength("weak")
		net.set_wants_dealer(true)
	else:
		net.lobby_notice.connect(func(message: String):
			if message.begins_with("test-discard-time="):
				discard_sent_at = float(message.get_slice("=", 1)))
		net.state_updated.connect(func():
			if discard_received_at == 0.0 and net.game.players.size() == 4 \
					and not net.game.players[1].discard_history.is_empty():
				discard_received_at = Time.get_unix_time_from_system())
	t.expect(await _wait_until(func(): return net.lobby.get("opening_speed", "") == "0.40" and net.lobby.get("ai_speed", "") == "0.60" and net.lobby.get("settlement_speed", "") == "0.90" and net.lobby.get("ai_strength", "") == "weak"), "all peers immediately receive the owner's four shared settings")
	if role != 0:
		t.expect(root.get_node("GameConfig").ai_speed == "0.80" and root.get_node("GameConfig").ai_strength == "medium", "joining does not overwrite the guest's own offline preferences")
		net.set_ai_strength("strong")
		net.set_settlement_speed("0.10")
		await create_timer(0.1).timeout
		t.expect(net.lobby.ai_strength == "weak" and net.lobby.settlement_speed == "0.90", "nonowners cannot change shared room settings through the network")
	net.set_ready(true)
	if not t.expect(await _wait_until(func(): return net.round_number == 1), "First round dealt after lobby readiness"):
		await H.quit_cleanly(self, t.finish("next_round_network"))
		return
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	if role == 0:
		t.expect(await _wait_until(func(): return net.game.awaiting and net.game.current_turn == net.my_seat),
			"South dealer can submit a real discard")
		# Measure an in-game update after peers have mounted their first table.
		await create_timer(1.0).timeout
		var initial_revision := net._state_revision
		var started_at := Time.get_unix_time_from_system()
		var discard: String = net.game.players[net.my_seat].just_drew
		t.expect(net.game.submit_turn(net.my_seat, {"discard": discard}), "Authority accepts the dealer discard")
		print("[next_round] authority submit: %.1f ms" % ((Time.get_unix_time_from_system() - started_at) * 1000.0))
		for peer in net._peer_seat:
			if peer > 1: net.notice.rpc_id(peer, "test-discard-time=%.6f" % started_at)
		t.expect(await _wait_until(func(): return net._state_revision > initial_revision, 1.0), "Authority broadcasts the accepted discard")
		print("[next_round] authority flush: %.1f ms" % ((Time.get_unix_time_from_system() - started_at) * 1000.0))
		await create_timer(1.25).timeout
		# This fixture forces settlement instead of playing the remaining turns.
		table._table_animation_controller.recover_after_resume()
		net.game._finish()
	else:
		t.expect(await _wait_until(func(): return discard_received_at > 0.0 and discard_sent_at > 0.0),
			"Every client receives the first discard")
		if discard_received_at > 0.0 and discard_sent_at > 0.0:
			var latency := discard_received_at - discard_sent_at
			print("[next_round] discard sync role=%d: %.1f ms" % [role, latency * 1000.0])
			t.expect(latency >= 0.0 and latency < 1.0, "Discard arrives before the next action or settlement")
	t.expect(await _wait_until(func(): return net.game.phase == RoundState.Phase.SETTLED and net.lobby.get("ready_round", -1) == 1), "Settlement ready state reaches every human")
	t.expect(await _wait_until(func(): return table._settlement_animation_controller.is_completed()), "Settlement preview finishes before controls unlock")
	await process_frame
	var settlement = table._settlement_animation_controller
	var board_count: int = 0 if settlement.plan.all_called_draw else 4
	print("[next_round] role=%d boards=%d expected=%d controls=%s all_called=%s completed=%s" % [
		role, settlement.boards.size(), board_count, table._settlement_card._post_controls.visible,
		settlement.plan.all_called_draw, settlement.is_completed()])
	t.expect(settlement.boards.size() == board_count and table._settlement_card._post_controls.visible, "Every player sees the final tabletop settlement and bottom readiness controls")
	t.expect(settlement.layer.mouse_filter == Control.MOUSE_FILTER_IGNORE and not table._settlement_card._post_controls is Panel, "Settlement uses non-blocking tabletop content and plain bottom controls")
	t.expect(table._next_round_button.get_parent() == table._settlement_card._post_controls and not table._next_round_button.disabled, "Every player has an enabled bottom ready button")
	t.expect(table._next_round_button.text.contains("准备"), "Guests get ready button instead of return to lobby")
	t.expect(table._next_round_button.size.y >= 96 and table._next_round_button.size.x >= 480, "All humans have a usable next-round touch button")
	t.expect(not net.lobby.seats[net.my_seat].ready, "Own readiness resets at settlement")
	for seat in settlement.boards:
		var board: Control = settlement.boards[seat]
		t.expect(board.is_visible_in_tree() and settlement.payment_labels[seat].size() == 3, "Every seat retains its three tabletop payments")
		t.expect(not board.get_global_rect().intersects(table._next_round_button.get_global_rect()), "Tabletop payments never cover the prepare button")
	var scores: Array = net.game.players.map(func(player): return player.score)
	var dealer: int = net.game.next_dealer_seat
	if role != 3:
		table._next_round_button.pressed.emit()
		t.expect(await _wait_until(func(): return net.lobby.seats[net.my_seat].ready), "Own readiness acknowledged")
	else:
		t.expect(await _wait_until(func(): return net.lobby.seats.filter(func(seat): return seat.ready).size() == 3), "Three humans ready, fourth still waiting")
		await create_timer(1.2).timeout
		t.expect(net.round_number == 1 and int(net.lobby.countdown) < 0, "Three ready cannot start without the fourth")
		table._next_round_button.pressed.emit()
	var ready_at := Time.get_ticks_msec()
	t.expect(await _wait_until(func(): return net.round_number == 2), "All four ready immediately enter the second round")
	if role == 3:
		t.expect(Time.get_ticks_msec() - ready_at < 850, "Last ready starts without an extra countdown")
	t.expect(int(net.lobby.countdown) < 0, "Immediate next round has no countdown")
	t.expect(net.game.dealer_seat == dealer and net.game.players.map(func(player): return player.score) == scores, "Dealer and scores survive ready transition")
	t.expect(await _wait_until(func(): return not settlement.has_started() and settlement.boards.is_empty() and not table._settlement_card._post_controls.visible), "Second-round tiles replace settlement on all clients")
	if role == 0:
		await create_timer(0.4).timeout
		net.game._finish()
	t.expect(await _wait_until(func(): return net.game.phase == RoundState.Phase.SETTLED and net.lobby.get("ready_round", -1) == 2), "Next settlement resets readiness again")
	t.expect(not net.lobby.seats[net.my_seat].ready, "No previous ready flag leaks into next settlement")
	# 模拟上一局延迟到达的准备消息，不能把新结算的玩家标记为已准备。
	if role == 0:
		net._apply_lobby_action(1, "ready", {"value": true, "round_number": 1})
		net._apply_lobby_action(999999, "ready", {"value": true, "round_number": 2})
		t.expect(not net.lobby.seats[net.my_seat].ready, "Old-round and unknown-peer requests are rejected")
	if role != 3:
		net.next_round()
		t.expect(await _wait_until(func(): return net.lobby.seats[net.my_seat].ready), "Remaining human readies")
	else:
		t.expect(await _wait_until(func(): return net.lobby.seats.filter(func(seat): return seat.ready).size() == 3), "Disconnect test leaves one unready human")
		table.queue_free()
		await process_frame
		network.reset()
		await create_timer(1.3).timeout
		await H.quit_cleanly(self, t.finish("next_round_network"))
		return
	t.expect(await _wait_until(func(): return net.lobby.seats.any(func(seat): return seat.disconnected)), "Lost connection reserves a seat for reconnect")
	var disconnected_at := Time.get_ticks_msec()
	await create_timer(1.15).timeout
	t.expect(net.round_number == 2 and int(net.lobby.countdown) < 0, "Reconnect reservation blocks immediate next-round start")
	t.expect(await _wait_until(func(): return net.lobby.seats.any(func(seat): return seat.ai and seat.ready), 35.0), "Expired reconnect reservation becomes a ready AI")
	t.expect(Time.get_ticks_msec() - disconnected_at >= 27000, "Seat is held for the thirty-second reconnect window")
	t.expect(await _wait_until(func(): return net.round_number == 3), "Ready AI substitute allows the remaining humans to continue")
	# 主机必须给可靠快照发送/确认留时间，不能本机刚发牌就立刻关闭房间。
	if role == 0: await create_timer(0.6).timeout
	table.queue_free()
	await process_frame
	network.reset()
	await create_timer(1.3).timeout
	await H.quit_cleanly(self, t.finish("next_round_network"))
