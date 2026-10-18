extends SceneTree
## 四个真人进程：全员准备、取消倒计时、旧消息、掉线替补及结算UI。
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var role := 0
var net: NetGameNode
var table: Control

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
		t.expect(await _wait_until(func(): return net._members.size() == 4), "Four real humans join")
	else:
		t.expect(network.start_client("127.0.0.1", 7536), "Human client connects")
		t.expect(await _wait_until(func(): return net.lobby.get("seats", []).size() == 4), "Client receives own seat")
	t.expect(await _wait_until(func(): return net.lobby.seats.filter(func(seat): return int(seat.peer) > 0).size() == 4), "Wait for all joins before first readiness")
	net.set_ready(true)
	if not t.expect(await _wait_until(func(): return net.round_number == 1), "First round dealt after lobby readiness"):
		quit(t.finish("next_round_network"))
		return
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	if role == 0:
		await create_timer(0.3).timeout
		net.game._finish()
	t.expect(await _wait_until(func(): return net.game.phase == RoundState.Phase.SETTLED and net.lobby.get("ready_round", -1) == 1), "Settlement ready state reaches every human")
	t.expect(await _wait_until(func(): return table._settlement_animation_controller.is_completed()), "Settlement preview finishes before controls unlock")
	await process_frame
	var settlement = table._settlement_animation_controller
	var board_count: int = 0 if settlement.plan.all_called_draw else 4
	t.expect(settlement.boards.size() == board_count and table._settlement_card._post_controls.visible, "Every player sees the final tabletop settlement and bottom readiness controls")
	t.expect(settlement.layer.mouse_filter == Control.MOUSE_FILTER_IGNORE and not table._settlement_card._post_controls is Panel, "Settlement uses non-blocking tabletop content and plain bottom controls")
	t.expect(table._next_round_button.get_parent() == table._settlement_card._post_controls and not table._next_round_button.disabled, "Every player has an enabled bottom ready button")
	t.expect(table._next_round_button.text == "准备下一局", "Guests get ready button instead of return to lobby")
	t.expect(table._next_round_button.size.y >= 80, "All humans have a usable next-round touch button")
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
	t.expect(await _wait_until(func(): return int(net.lobby.countdown) == 1), "All four ready synchronizes countdown")
	t.expect(table._settlement_card._post_controls.visible and table._next_round_hint.text.contains("1 秒"), "Bottom controls show the synchronized countdown")
	t.expect(table._next_round_status.text.contains("4 / 4"), "All four acknowledgements update the readiness summary")
	if role == 3:
		await create_timer(0.2).timeout
		table._next_round_button.pressed.emit()
	t.expect(await _wait_until(func(): return int(net.lobby.countdown) < 0), "Cancel readiness cancels countdown for everyone")
	await create_timer(1.15).timeout
	t.expect(net.round_number == 1, "Cancelled countdown never starts a round")
	t.expect(settlement.is_completed() and settlement.boards.size() == board_count and table._settlement_card._post_controls.visible, "Cancelling readiness preserves tabletop settlement and controls")
	t.expect(settlement.layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Readiness updates keep the tabletop input layer non-blocking")
	if role == 3:
		await create_timer(0.15).timeout
		net.next_round()
	t.expect(await _wait_until(func(): return int(net.lobby.countdown) == 1), "Ready again creates a fresh countdown")
	var ready_at := Time.get_ticks_msec()
	if role == 0:
		var remaining := net._countdown
		net.next_round()
		t.expect(net._countdown == remaining, "Duplicate readiness cannot extend countdown")
	t.expect(await _wait_until(func(): return net.round_number == 2), "Four humans enter the second round together")
	t.expect(Time.get_ticks_msec() - ready_at >= 850, "Authority waits one second after all ready")
	t.expect(net.game.dealer_seat == dealer and net.game.players.map(func(player): return player.score) == scores, "Dealer and scores survive ready transition")
	t.expect(not settlement.has_started() and settlement.boards.is_empty() and not table._settlement_card._post_controls.visible, "Second-round tiles replace settlement on all clients")
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
		quit(t.finish("next_round_network"))
		return
	t.expect(await _wait_until(func(): return net.lobby.seats.any(func(seat): return seat.disconnected)), "Lost connection reserves a seat for reconnect")
	var disconnected_at := Time.get_ticks_msec()
	await create_timer(1.15).timeout
	t.expect(net.round_number == 2 and int(net.lobby.countdown) < 0, "Reconnect reservation blocks next-round countdown")
	t.expect(await _wait_until(func(): return net.lobby.seats.any(func(seat): return seat.ai and seat.ready), 35.0), "Expired reconnect reservation becomes a ready AI")
	t.expect(Time.get_ticks_msec() - disconnected_at >= 27000, "Seat is held for the thirty-second reconnect window")
	t.expect(await _wait_until(func(): return net.round_number == 3), "Ready AI substitute allows the remaining humans to continue")
	# 主机必须给可靠快照发送/确认留时间，不能本机刚发牌就立刻关闭房间。
	if role == 0: await create_timer(0.6).timeout
	table.queue_free()
	await process_frame
	network.reset()
	await create_timer(1.3).timeout
	quit(t.finish("next_round_network"))
