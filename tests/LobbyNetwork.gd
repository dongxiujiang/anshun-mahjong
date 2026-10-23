extends Node
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var is_host := false
var is_late := false
var actor := AiPlayer.new("lobby network test")
var _stage := ""

func _ready() -> void:
	is_host = OS.get_cmdline_user_args().has("--lobby-host")
	is_late = OS.get_cmdline_user_args().has("--lobby-late")
	_run()

func _wait_until(predicate: Callable, seconds: float = 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bool(predicate.call())

func _run() -> void:
	if is_late:
		var error_text := ""
		Network.net_node.connection_error.connect(func(message): _stage = message)
		Network.start_client("127.0.0.1", 7533, "456789")
		t.expect(await _wait_until(func(): return _stage != ""), "Late join receives rejection")
		t.expect(_stage.contains("开局"), "Late join cannot replace AI")
		get_tree().quit(t.finish("lobby_network_late"))
		return
	if is_host:
		t.expect(Network.start_host(false, true, 7533, "456789", "联机测试"), "Host opened")
		t.expect(Network.discovery.advertise(Network.net_node), "Host advertises")
		var net := Network.net_node
		t.expect(await _wait_until(func(): return net._members.size() == 2), "Client joins discovered room")
		t.expect(net.game.phase == RoundState.Phase.IDLE and net.game.players.is_empty(), "Join doesn't deal")
		t.expect(await _wait_until(func(): return int(net._seat_peer[2]) > 1 and bool(net._members[int(net._seat_peer[2])].ready)), "Client selects AI seat and readies")
		t.expect(not net.all_ready(), "Host unready blocks start")
		net.select_seat(2)
		t.expect(await _wait_until(func(): return net.ack_text == "swap-refused"), "Client declined first swap")
		t.expect(net.my_seat == 0, "Refusal preserves seat")
		net.select_seat(2)
		t.expect(await _wait_until(func(): return net.my_seat == 2), "Consent swaps both humans")
		t.expect(not net.all_ready(), "Swap invalidates readiness")
		net.select_seat(3)
		t.expect(net.my_seat == 3, "Host moves to another AI position")
		var snapshot := net._seat_peer.duplicate()
		net._apply_lobby_action(99999, "seat", {"seat": 0})
		t.expect(snapshot == net._seat_peer, "Unknown peer cannot move seats")
		net.set_ready(true)
		t.expect(await _wait_until(func(): return net.ack_text == "cancelled"), "Ready cancellation arrives")
		t.expect(net.game.phase == RoundState.Phase.IDLE and net._countdown < 0, "Cancel countdown prevents deal")
		t.expect(await _wait_until(func(): return net._started), "All ready automatically deal")
		t.expect(net.game.dealer_seat == 0, "Only dealer applicant selected after swap")
		print("[lobby_network] GAME_STARTED")
		# Leave enough time for the third Godot process to start and attempt
		# the late join; CI process startup can exceed the old two seconds.
		await get_tree().create_timer(8.0).timeout
	else:
		# Validate actual LAN query/reply; no manually entered host address.
		Network.discovery.search()
		if OS.get_cmdline_user_args().has("--lobby-interface"):
			# Exercise the real hotspot/Wi-Fi adapter instead of a same-PC loopback.
			Network.discovery.stop_search()
			Network.discovery.searching = true
			Network.discovery._query = PacketPeerUDP.new()
			t.expect(Network.discovery._query.bind(0) == OK, "Interface test opens query socket")
			Network.discovery._refresh_interfaces()
			Network.discovery._timer = 3600.0
			t.expect(not Network.discovery._probes.is_empty(), "Connected LAN adapter available")
		t.expect(await _wait_until(func(): return Network.discovery.has_number("456789")), "LAN room discovered")
		var room: Dictionary = {}
		for candidate in Network.discovery.rooms.values():
			if candidate.number == "456789": room = candidate
		t.expect(not room.is_empty(), "Room number resolves endpoint")
		if OS.get_cmdline_user_args().has("--lobby-interface"):
			t.expect(str(room.get("host", "")) != "127.0.0.1", "LAN handshake uses real interface, no loopback")
		if room.is_empty():
			get_tree().quit(1)
			return
		# A wrong room number must fail the handshake.
		Network.net_node.connection_error.connect(func(message): _stage = message)
		Network.start_client(str(room.host), int(room.port), "111111")
		t.expect(await _wait_until(func(): return _stage.contains("不匹配")), "Wrong room number rejected")
		Network.reset()
		Network.start_client(str(room.host), int(room.port), "456789")
		var net := Network.net_node
		t.expect(await _wait_until(func(): return not net.lobby.is_empty()), "Receives lobby state")
		t.expect(net.game.phase == RoundState.Phase.IDLE and net.game.players.is_empty(), "No hidden early deal")
		net.select_seat(2)
		t.expect(await _wait_until(func(): return net.my_seat == 2), "AI seat selectable")
		net.set_wants_dealer(true)
		net.set_ready(true)
		t.expect(await _wait_until(func(): return not net.lobby.swap.is_empty()), "Swap request received")
		net.respond_swap(false)
		await get_tree().create_timer(0.15).timeout
		net.rpc_id(1, "ack", "swap-refused")
		t.expect(await _wait_until(func(): return not net.lobby.swap.is_empty()), "Second request received")
		net.respond_swap(true)
		t.expect(await _wait_until(func(): return net.my_seat == 0), "Swapped seat synchronized")
		t.expect(await _wait_until(func(): return bool(net.lobby.seats[3].ready)), "Moved host readied")
		net.set_ready(true)
		t.expect(await _wait_until(func(): return int(net.lobby.countdown) >= 0), "Countdown synchronized")
		net.set_ready(false)
		t.expect(await _wait_until(func(): return int(net.lobby.countdown) < 0), "Countdown cancelled")
		net.rpc_id(1, "ack", "cancelled")
		await get_tree().create_timer(0.2).timeout
		net.set_ready(true)
		t.expect(await _wait_until(func(): return net.game.phase != RoundState.Phase.IDLE), "Tiles arrive only after ready")
		t.expect(net.game.dealer_seat == 0, "Dealer synchronized")
		for seat in range(1, 4):
			t.expect(net.game.players[seat].concealed.all(func(tile): return tile == "hidden0"), "Opponent tiles remain private")
	var net := Network.net_node
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if net.game.phase == RoundState.Phase.SETTLED:
			if is_host:
				if net.ack_text == "settled-ok": break
			else:
				net.rpc_id(1, "ack", "settled-ok")
				await get_tree().create_timer(0.5).timeout
				break
		elif net.game.awaiting:
			if net.game._awaiting_response.get("seat", -1) == net.my_seat:
				var request: Dictionary = net.game._awaiting_response
				var decision := actor.decide_response(net.game, net.my_seat, request.disc_seat, request.tile, request.options)
				if is_host: net.game.submit_response(net.my_seat, request.tile, decision)
				else:
					net.submit_client_response(request.tile, decision)
					net.game.awaiting = false
			elif net.game.current_turn == net.my_seat:
				var decision := actor.decide_turn(net.game, net.my_seat)
				if is_host: net.game.submit_turn(net.my_seat, decision)
				else:
					net.submit_client_turn(decision)
					net.game.awaiting = false
	t.expect(net.game.phase == RoundState.Phase.SETTLED, "Moved seats play full match")
	if is_host: t.expect(net.ack_text == "settled-ok", "Client completed")
	print("[lobby_network] ", "host" if is_host else "client")
	get_tree().quit(t.finish("lobby_network"))
