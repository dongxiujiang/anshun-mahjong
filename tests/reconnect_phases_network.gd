extends SceneTree
## Real ENet: resume with a still-live transport, then recover claim and settlement state.
const H := preload("res://tests/test_harness.gd")
const PORT := 7589
const TILE := "tong9"
var t := H.new()
var net: NetGameNode
var joins := 0
var seat := -1
var old_transport: ENetMultiplayerPeer
var notice := ""

func _initialize() -> void: call_deferred("_run")

func _wait(predicate: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 7000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	var ok := t.expect(bool(predicate.call()), label)
	if not ok: quit(t.finish("reconnect_phases"))
	return ok

func _run() -> void:
	var network := root.get_node("Network")
	net = network.net_node
	if "--phases-host" in OS.get_cmdline_user_args():
		await _host()
	else:
		await _guest()

func _guest_peer() -> int:
	return int(net._seat_peer[seat])

func _host() -> void:
	t.expect(net.host(false, true, PORT, "4242"), "Starts localhost authority")
	net.game._recorder.auto_save = false
	if not await _wait(func(): return net._members.size() == 2 and net._members.values().any(func(member): return member.ready), "Guest readies before the authority starts the game"): return
	seat = int(net._peer_seat.values().filter(func(candidate): return candidate != net.my_seat)[0])
	net.set_wants_dealer(true)
	net.set_ready(true)
	if not await _wait(func(): return net.ack_text == "waiting-opening", "Guest joined and deliberately has not acknowledged opening"): return
	var previous := _guest_peer()
	t.expect(net.game.pause_after_opening and net._opening_waiters.has(previous), "Opening waits for original connection")
	net.notice.rpc_id(previous, "foreground")
	if not await _wait(func(): return _guest_peer() != previous and _guest_peer() > 1 and net.ack_text == "rejoined-opening", "Foreground establishes a fresh ENet connection at the original seat"): return
	if not await _wait(func(): return net.game.awaiting and net.game.current_turn == net.my_seat,
		"New peer's acknowledgement releases opening without waiting for the obsolete peer"): return
	t.expect(net._opening_waiters.is_empty(), "Opening contains no abandoned peer ids")

	# Three copies open the KONG window. No other player can claim this discard.
	for player in net.game.players:
		player.concealed = ["wan1", "wan2", "wan4", "wan5", "wan7", "wan8", "tiao1", "tiao2", "tiao4", "tiao5", "tiao7", "tiao8", "tong1"]
		player.just_drew = ""
		player.first_turn_done = true
	for index in 3: net.game.players[seat].concealed[index] = TILE
	net.game.players[net.my_seat].concealed.append(TILE)
	net.game.players[net.my_seat].just_drew = TILE
	t.expect(net.game.submit_turn(net.my_seat, {"discard": TILE}), "Authority plays the claim fixture tile")
	var prompt := net.game.prompt_id
	var session := net.game.audio_session
	if not await _wait(func(): return net.ack_text == "waiting-kong", "Guest sees the pending kong window"): return
	previous = _guest_peer()
	net.multiplayer.multiplayer_peer.disconnect_peer(previous)
	if not await _wait(func(): return net.ack_text == "rejoined-kong", "Lost ENet connection recovers the pending kong window"): return
	t.expect(_guest_peer() != previous and net.game.prompt_id == prompt, "Authority keeps the same claim prompt after reconnect")
	t.expect(net.game.audio_session == session and net.game.players[net.my_seat].discard_count == 1,
		"Recovering the response does not re-deal or duplicate the discard")
	net.notice.rpc_id(_guest_peer(), "pass-kong")
	if not await _wait(func(): return net.ack_text == "waiting-pong", "Passing the first claim opens the pong window"): return
	previous = _guest_peer()
	net.multiplayer.multiplayer_peer.disconnect_peer(previous)
	if not await _wait(func(): return net.ack_text == "rejoined-pong", "Lost ENet connection recovers the pending pong window"): return
	# Pause only this node's timers; SceneTree continues receiving real ENet RPCs.
	net.set_process(false)
	previous = _guest_peer()
	var expired_seen := Time.get_ticks_msec() - NetGameNode.HEARTBEAT_TIMEOUT_MS - 1
	net._peer_last_seen[previous] = expired_seen
	net.notice.rpc_id(previous, "pong")
	if not await _wait(func(): return net.game.players[seat].melds.size() == 1, "Authenticated guest sends its reliable pong action while heartbeats are expired"): return
	var response_alive := int(net._peer_last_seen.get(previous, expired_seen)) > expired_seen
	t.expect(response_alive, "Authenticated reliable response refreshes host liveness")
	if response_alive: net._process(0.0)
	t.expect(net._peer_connected(previous) and not net._orphaned.has(seat), "Host keeps the active response sender's original connection and seat")
	expired_seen = Time.get_ticks_msec() - NetGameNode.HEARTBEAT_TIMEOUT_MS - 1
	net._peer_last_seen[previous] = expired_seen
	net.notice.rpc_id(previous, "discard")
	if not await _wait(func(): return net.game.players[seat].discard_count == 1, "Authenticated guest sends its reliable discard action while heartbeats are expired"): return
	var turn_alive := int(net._peer_last_seen.get(previous, expired_seen)) > expired_seen
	t.expect(turn_alive, "Authenticated reliable turn refreshes host liveness")
	if turn_alive: net._process(0.0)
	t.expect(net._peer_connected(previous) and not net._orphaned.has(seat), "Host keeps the active turn sender's original connection and seat")
	# Preserve the remaining reconnect checks after a failed liveness assertion.
	net._peer_last_seen[previous] = Time.get_ticks_msec()
	net.set_process(true)
	if not await _wait(func(): return net.ack_text == "played", "Guest acts on recovered pong and discard prompts"): return
	t.expect(net.game.players[seat].melds.size() == 1 and net.game.players[seat].melds[0].kind == "pung",
		"Guest's pong is applied exactly once")
	t.expect(net.game.players[seat].discard_count == 1 and net.game.players[net.my_seat].discard_count == 1,
		"Guest's new discard and authority's earlier discard are each recorded once")
	# Score a settled win, preserving a nonzero pre-existing balance for each seat.
	for index in 4: net.game.players[index].score = [17.0, -3.0, -9.0, -5.0][index]
	net.game.round_meta.winner = seat
	net.game.round_meta.winners = [seat]
	net.game.round_meta.self_draw = true
	net.game.round_meta.win_tile = TILE
	net.game._finish()
	var scores: Array = net.game.players.map(func(player): return player.score)
	var result := net.game.last_result.duplicate(true)
	t.expect(scores != [17.0, -3.0, -9.0, -5.0] and is_zero_approx(scores.reduce(func(sum, score): return sum + score, 0.0)),
		"Configured settlement changes balances and conserves the total")
	if not await _wait(func(): return net.ack_text == "settled", "Guest receives the initial settlement"): return
	previous = _guest_peer()
	net.multiplayer.multiplayer_peer.disconnect_peer(previous)
	net.game._finish()
	if not await _wait(func(): return net.ack_text.begins_with("["), "Guest recovers the final settlement and sends observed balances"): return
	t.expect(JSON.parse_string(net.ack_text) == scores and net.game.players.map(func(player): return player.score) == scores and net.game.last_result == result,
		"Reconnect and repeated finish preserve the exact settlement and all four credits")
	net.notice.rpc_id(_guest_peer(), "complete")
	await create_timer(0.35).timeout
	await H.quit_cleanly(self, t.finish("reconnect_phases_host"))

func _guest() -> void:
	net.connection_error.connect(func(message):
		t.expect(false, message)
		quit(t.finish("reconnect_phases_guest")))
	net.room_ready.connect(func(assigned):
		joins += 1
		if joins == 1:
			seat = assigned
			net.set_ready(true)
		else:
			t.expect(assigned == seat and net._resume_sync_pending, "Seat assignment preserves the original seat and waits for current gameplay data"))
	net.state_updated.connect(func():
		if joins == 1: net._opening_ack_session = net.game.audio_session)
	net.lobby_notice.connect(func(message): notice = message)
	t.expect(net.client("127.0.0.1", PORT, "4242", "阶段重连测试"), "Guest opens localhost connection")
	if not await _wait(func(): return net.game.players.size() == 4, "Initial opening snapshot arrives"): return
	_ack("waiting-opening")
	if not await _wait(func(): return notice == "foreground", "Authority signals the foreground fixture"): return
	# Retain the old ENet transport until after the hand-off, as happens when a
	# stale mobile socket has not yet been detected by the authority.
	old_transport = net.multiplayer.multiplayer_peer
	net.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	net.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	if not await _wait(func(): return joins == 2 and not net._resume_sync_pending, "Foreground receives current snapshot"): return
	_ack("rejoined-opening")
	old_transport = null
	if not await _wait(func(): return _claim_stage() == RoundState.ResponseStage.KONG, "Kong is offered on the correct seat"): return
	var prompt := net.game.prompt_id
	var scores: Array = net.game.players.map(func(player): return player.score)
	var hand: Array = net.game.players[seat].concealed.duplicate()
	_ack("waiting-kong")
	if not await _wait(func(): return joins == 3 and not net._resume_sync_pending, "Kong reconnect applies a fresh snapshot"): return
	t.expect(_claim_stage() == RoundState.ResponseStage.KONG and net.game.legal_response_options(seat, net.game._awaiting_response.disc_seat, TILE, _claim_stage()).can_kong,
		"Current kong remains actionable after reconnect")
	t.expect(net.game.prompt_id == prompt and net.game.players[seat].concealed == hand and net.game.players.map(func(player): return player.score) == scores,
		"Claim prompt, hand and all scores survive reconnect")
	t.expect(net.game.players.filter(func(player): return player.seat != seat).all(func(player): return player.concealed.all(func(tile): return tile == "hidden0") and player.ready_wait_tiles.is_empty()),
		"Fresh ENet snapshot contains no opponents' hidden hand faces or waits")
	var other_deals: Array = []
	for event in net.game.visual_events:
		for deal in event.get("deals", []):
			if int(deal.seat) != seat: other_deals.append_array(deal.cards)
	t.expect(not other_deals.is_empty() and other_deals.all(func(tile): return tile == "hidden0"), "Opponent card faces are also masked in the deal animation")
	_ack("rejoined-kong")
	if not await _wait(func(): return notice == "pass-kong", "Authority allows passing the kong"): return
	net.submit_client_response(TILE, {"action": "pass"})
	if not await _wait(func(): return _claim_stage() == RoundState.ResponseStage.MELD, "Pong is offered after kong is passed"): return
	prompt = net.game.prompt_id
	_ack("waiting-pong")
	if not await _wait(func(): return joins == 4 and not net._resume_sync_pending, "Pong reconnect applies a fresh snapshot"): return
	t.expect(_claim_stage() == RoundState.ResponseStage.MELD and net.game.prompt_id == prompt, "Pong reconnect keeps the same response prompt")
	net.set_process(false)
	_ack("rejoined-pong")
	if not await _wait(func(): return notice == "pong", "Authority allows pong on the recovered prompt"): return
	for duplicate in 2: net.submit_client_response(TILE, {"action": "pong"})
	if not await _wait(func(): return net.game.awaiting and net.game.current_turn == seat and net.game._awaiting_response.is_empty(), "Pong leads to the guest's discard prompt"): return
	if not await _wait(func(): return notice == "discard", "Authority allows the independently aged reliable turn check"): return
	for duplicate in 2: net.submit_client_turn({"discard": "tong1"})
	if not await _wait(func(): return net.game.players[seat].discard_count == 1, "Guest observes a single discard from the recovered turn"): return
	_ack("played")
	net.set_process(true)
	if not await _wait(func(): return net.game.phase == RoundState.Phase.SETTLED, "Initial settlement arrives"): return
	var result := net.game.last_result.duplicate(true)
	scores = net.game.players.map(func(player): return player.score)
	_ack("settled")
	if not await _wait(func(): return joins == 5 and not net._resume_sync_pending, "Settlement reconnect applies a fresh snapshot"): return
	t.expect(net.game.phase == RoundState.Phase.SETTLED and not net.game.awaiting and net.game.last_result == result and net.game.players.map(func(player): return player.score) == scores,
		"Guest sees the same settlement and balances, with no leftover action")
	_ack(JSON.stringify(scores))
	if not await _wait(func(): return notice == "complete", "Authority confirms the final state"): return
	await H.quit_cleanly(self, t.finish("reconnect_phases_guest"))

func _claim_stage() -> int:
	return int(net.game._awaiting_response.get("stage", RoundState.ResponseStage.NONE))

func _ack(message: String) -> void:
	net.ack.rpc_id(1, message)
