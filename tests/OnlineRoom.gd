extends Node
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var room: Dictionary = {}
var error_text := ""
var room_owner := false
var actor := AiPlayer.new("online integration")

func _ready() -> void: _run()

func _arg(name_value: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(name_value + "="): return value.substr(name_value.length() + 1)
	return ""

func _wait_until(predicate: Callable, seconds: float = 18.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())

func _run() -> void:
	room_owner = _arg("--owner-token") != ""
	# Never save a test endpoint into the user's preferences.
	var directory := OnlineDirectory.new()
	add_child(directory)
	directory.base_url = _arg("--directory")
	directory.directory_error.connect(func(message): error_text = message)
	directory.search()
	t.expect(await _wait_until(func(): return not directory.busy), "Online list finishes")
	t.expect(error_text == "", "Online directory reachable")
	for candidate in directory.rooms:
		if candidate.number == "654321": room = candidate
	t.expect(not room.is_empty(), "Real dedicated room listed")
	if room.is_empty():
		get_tree().quit(1)
		return
	Network.start_client(str(room.host), int(room.port), str(room.number), _arg("--owner-token"))
	var net := Network.net_node
	t.expect(await _wait_until(func(): return not net.lobby.is_empty()), "Cloud room handshake")
	t.expect(net.game.phase == "idle" and net.game.players.is_empty(), "Online waits before dealing")
	t.expect(net.is_room_owner() == room_owner, "Creator exclusively owns room")
	if room_owner:
		net.select_seat(2)
		t.expect(await _wait_until(func(): return net.my_seat == 2), "Online seat change")
		net.set_wants_dealer(true)
		print("[online_room] OWNER_WAITING")
		t.expect(await _wait_until(func(): return int(net.lobby.seats[0].peer) > 1 and bool(net.lobby.seats[0].ready)), "Guest joined and readied")
		t.expect(net.game.players.is_empty(), "Guest readiness alone cannot deal")
		net.set_ready(true)
	else:
		net.set_ready(true)
	t.expect(await _wait_until(func(): return net.game.phase == "playing"), "Ready online room starts")
	t.expect(net.game.dealer_seat == 2, "Applicant becomes initial dealer")
	for seat in 4:
		if seat != net.my_seat:
			t.expect(net.game.players[seat].concealed.all(func(tile): return tile == "hidden0"), "Cloud keeps opponents private")
	if room_owner:
		t.expect(net.game.players[2].concealed.size() == 14, "Dealer receives first draw")
		directory.search()
		await _wait_until(func(): return not directory.busy)
		await get_tree().create_timer(1.2).timeout
		directory.search()
		await _wait_until(func(): return not directory.busy)
		for candidate in directory.rooms:
			if candidate.number == "654321": t.expect(bool(candidate.started), "Directory reflects started game")
	var deadline := Time.get_ticks_msec() + 100000
	while net.game.phase != "settled" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not net.game.awaiting: continue
		if net.game._awaiting_response.get("seat", -1) == net.my_seat:
			var request: Dictionary = net.game._awaiting_response
			net.submit_client_response(request.tile, actor.decide_response(net.game, net.my_seat, request.disc_seat, request.tile, request.options))
			net.game.awaiting = false
		elif net.game.current_turn == net.my_seat:
			net.submit_client_turn(actor.decide_turn(net.game, net.my_seat))
			net.game.awaiting = false
	t.expect(net.game.phase == "settled", "Dedicated room plays complete match")
	var scores: Array = net.game.players.map(func(player): return player.score)
	var dealer: int = net.game.next_dealer_seat
	if room_owner:
		# Give guest time to capture settlement before requesting the second round.
		await get_tree().create_timer(0.8).timeout
		net.next_round()
	else:
		net.next_round()
		await get_tree().create_timer(0.2).timeout
		t.expect(net.round_number == 1, "Guest cannot start next round")
	t.expect(await _wait_until(func(): return net.round_number == 2), "Owner starts next round through dedicated server")
	t.expect(net.game.dealer_seat == dealer, "Next dealer obeys settlement")
	t.expect(net.game.players.map(func(player): return player.score) == scores, "Online score preserved")
	if room_owner:
		# Guest disconnect is handed to AI; no network UI gets stuck.
		t.expect(await _wait_until(func(): return bool(net.lobby.seats[0].ai)), "Cloud disconnect becomes AI")
	get_tree().quit(t.finish("online_room"))
