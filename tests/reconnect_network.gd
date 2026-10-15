extends SceneTree
## Real ENet reconnects in the lobby and after dealing, with bounded stage waits.
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var net: NetGameNode
var server := false
var joins := 0
var original_seat := -1
var finished := false
var last_ack := ""

func _initialize() -> void:
	server = "--reconnect-host" in OS.get_cmdline_user_args()
	call_deferred("_run")

func _wait_until(predicate: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var ok := t.expect(bool(predicate.call()), label)
	if not ok: quit(t.finish("reconnect_network"))
	return ok

func _run() -> void:
	net = root.get_node("Network").net_node
	net.connection_error.connect(func(message):
		t.expect(false, message)
		quit(t.finish("reconnect_network")))
	if server: await _host_test()
	else: await _client_test()

func _host_test() -> void:
	t.expect(net.host(false, true, 7593, "1234"), "Host opens")
	if not await _wait_until(func(): return net.ack_text == "lobby-1", "Client initially ready"): return
	var peer := _guest_peer()
	var seat := int(net._peer_seat[peer])
	t.expect(seat == posmod(GameConfig.TURN_DIRECTION, 4), "Guest occupies the next seat in configured turn order")
	var token: String = net._members[peer].resume_token
	_drop_guest()
	t.expect(net._orphaned[seat].token == token, "Reservation belongs to original client")
	if not await _wait_until(func(): return net.ack_text == "lobby-2", "Client reconnects to lobby"): return
	t.expect(net._orphaned.is_empty(), "Lobby reconnect consumes reservation")
	peer = _guest_peer()
	t.expect(int(net._peer_seat[peer]) == seat and net._members[peer].ready, "Seat and readiness survive lobby reconnect")
	t.expect(net._members[peer].name == "重连测试", "Player name survives reconnect")
	net.set_wants_dealer(true)
	net.set_ready(true)
	t.expect(net.start_net_game(101), "Ready humans start game")
	if not await _wait_until(func(): return net.ack_text == "game-start", "Client receives first private snapshot"): return
	t.expect(net.game.current_turn == 0 and net.game.awaiting, "Host holds turn while testing restoration")
	var hand: Array = net.game.players[seat].concealed.duplicate()
	var score: float = net.game.players[seat].score
	_drop_guest()
	if not await _wait_until(func(): return net.ack_text.begins_with("{"), "Client restores private game snapshot"): return
	t.expect(net._orphaned.is_empty(), "Game reconnect consumes reservation")
	t.expect(net.game.controllers[seat] == null, "Reconnected player controls own seat")
	var received: Dictionary = JSON.parse_string(net.ack_text)
	t.expect(received.hand == hand and received.hand == net.game.players[seat].concealed, "Full private hand restored without redealing")
	t.expect(float(received.score) == score, "Score restored")
	t.expect(int(received.round) == net.round_number and int(received.prompt) == net.game.prompt_id, "Round and action prompt restored")
	# Lose the guest again, then advance into a delayed substitute turn before reconnect.
	net.ack_text = ""
	net.game.ai_delay_seconds = 1.5
	_drop_guest()
	var safe_tile := ""
	for tile in net.game.players[0].concealed:
		var available := true
		for opponent in range(1, 4):
			var trial: Array = net.game.players[opponent].concealed.duplicate()
			trial.append(tile)
			if Tiles.count(trial, tile) >= 3 or RuleEngine.analyze(trial, net.game.players[opponent].melds).win: available = false
		if available:
			safe_tile = tile
			break
	if not t.expect(safe_tile != "", "Fixture has a discard without intervening claims"):
		quit(t.finish("reconnect_network_host"))
		return
	t.expect(net.game.submit_turn(0, {"discard": safe_tile}), "Host advances to disconnected guest")
	t.expect(net.game.current_turn == seat and not net.game.awaiting, "Substitute turn is waiting on delay")
	if not await _wait_until(func(): return net.ack_text.begins_with("{"), "Guest reclaims pending AI turn"): return
	received = JSON.parse_string(net.ack_text)
	var prompt: int = net.game.prompt_id
	var discards: int = net.game.players[seat].discard_count
	t.expect(net.game.controllers[seat] == null and net.game.awaiting and net.game.current_turn == seat, "Host immediately restores a human prompt")
	t.expect(received.hand == net.game.players[seat].concealed and int(received.prompt) == prompt, "Guest receives fresh hand and prompt")
	await create_timer(1.7).timeout
	t.expect(net.game.players[seat].discard_count == discards and net.game.prompt_id == prompt and net.game.awaiting, "Expired substitute timer cannot act after ENet reconnect")
	net.notice.rpc_id(_guest_peer(), "discard-now")
	if not await _wait_until(func(): return net.game.players[seat].discard_count == discards + 1, "Reconnected guest completes its own discard"): return
	net.notice.rpc_id(_guest_peer(), "test-complete")
	await create_timer(0.5).timeout
	quit(t.finish("reconnect_network_host"))

func _client_test() -> void:
	net.room_ready.connect(func(seat):
		# Choose the seat immediately after the host using the real lobby API.
		# A seat assignment from this move is not a reconnect.
		if original_seat < 0 and seat != posmod(GameConfig.TURN_DIRECTION, 4):
			net.select_seat(posmod(GameConfig.TURN_DIRECTION, 4))
			return
		joins += 1
		if original_seat < 0: original_seat = seat
		t.expect(seat == original_seat, "Reconnect retains original seat")
		if joins == 1: net.set_ready(true))
	net.lobby_updated.connect(func():
		if joins <= 2 and not net.lobby.is_empty() and net.lobby.seats[net.my_seat].ready:
			var label := "lobby-%d" % joins
			if last_ack != label:
				last_ack = label
				net.rpc_id(1, "ack", label))
	net.state_updated.connect(func():
		if joins == 2 and last_ack != "game-start":
			last_ack = "game-start"
			net.rpc_id(1, "ack", "game-start")
		elif (joins == 3 and last_ack != "restored") or (joins == 4 and last_ack != "takeover" and net.game.awaiting and net.game.current_turn == net.my_seat):
			last_ack = "restored" if joins == 3 else "takeover"
			for player in net.game.players:
				if player.seat != net.my_seat:
					t.expect(player.concealed.all(func(tile): return tile == "hidden0"), "Reconnect keeps other hands private")
			net.rpc_id(1, "ack", JSON.stringify({"hand": net.game.players[net.my_seat].concealed, "score": net.game.players[net.my_seat].score, "round": net.round_number, "prompt": net.game.prompt_id})))
	net.lobby_notice.connect(func(message):
		if message == "test-complete": finished = true
		elif message == "discard-now":
			t.expect(not net._resume_sync_pending and net.game.awaiting, "Client waits for a fresh snapshot before allowing input")
			net.submit_client_turn({"discard": net.game.players[net.my_seat].just_drew}))
	t.expect(net.client("127.0.0.1", 7593, "1234", "重连测试"), "Client connects")
	if not await _wait_until(func(): return finished, "Host completes restoration assertions"): return
	t.expect(joins == 4, "Recovered in lobby, game and queued substitute turn")
	quit(t.finish("reconnect_network_client"))

func _guest_peer() -> int:
	return int(net._peer_seat.keys().filter(func(id): return id > 1)[0])

func _drop_guest() -> void:
	var peer := _guest_peer()
	net._on_peer_disconnected(peer)
	net.multiplayer.multiplayer_peer.disconnect_peer(peer)
	t.expect(not net._orphaned.is_empty(), "Disconnected seat reserved")
	t.expect(not net.all_ready(), "No new round starts while reconnecting")
