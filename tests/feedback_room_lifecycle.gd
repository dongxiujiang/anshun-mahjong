extends SceneTree
const H = preload("res://tests/test_harness.gd")
var t = H.new()
func _initialize(): call_deferred("run")
func wait_for(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return predicate.call()
func run():
	var role := OS.get_cmdline_user_args()[0]
	var network = root.get_node("Network")
	root.get_node("GameConfig").set_player_name(role, false)
	network.start_client("127.0.0.1", 7596, "112233")
	var net = network.net_node
	t.expect(await wait_for(func(): return net._client_joined and not net.lobby.is_empty()), role + " joins")
	print(role, " JOINED")
	if role == "owner":
		t.expect(net.my_seat == 1 and net.is_room_owner(), "creator starts South")
		t.expect(await wait_for(func(): return net.lobby.seats.filter(func(s): return int(s.peer)>0).size() == 2), "guest arrives")
		net.set_ready(true)
		t.expect(await wait_for(func(): return net.game.phase == RoundState.Phase.PLAYING), "round starts")
		await network.leave_room()
		print("OWNER_LEFT")
	elif role == "guest":
		t.expect(net.my_seat == 0, "second player starts East")
		net.set_ready(true)
		t.expect(await wait_for(func(): return net.game.phase == RoundState.Phase.PLAYING), "guest sees round")
		t.expect(await wait_for(func(): return net.is_room_owner()), "owner departure transfers ownership")
		t.expect(await wait_for(func(): return net.lobby.seats[1].name == "third"), "third player fills former owner's seat")
		print("THIRD_VISIBLE")
		t.expect(await wait_for(func(): return int(net.lobby.seats[1].peer) < 1), "third player explicitly leaves")
		await network.leave_room()
		print("LAST_HUMAN_LEFT")
	else:
		t.expect(net.my_seat == 1, "late replacement takes vacant South")
		t.expect(await wait_for(func(): return net.game.phase == RoundState.Phase.PLAYING), "replacement immediately receives running table")
		t.expect(net.game.players[1].is_human and net.game.players[0].is_human, "both humans retain their seats")
		await create_timer(1.0).timeout
		await network.leave_room()
	await H.quit_cleanly(self, t.finish("room_" + role))
