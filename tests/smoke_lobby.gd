extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var network := root.get_node("Network")
	network.reset()
	t.expect(network.start_host(false, true, 7532, "001234", "准备测试"), "Host opens room")
	var net: NetGameNode = network.net_node
	t.expect(net.game.phase == "idle" and net.game.players.is_empty(), "No tiles before readiness")
	t.expect(not net.start_net_game(9), "Unready start rejected")
	t.expect(net.lobby.seats.size() == 4, "Four seats published")
	for seat in range(1, 4):
		t.expect(net.lobby.seats[seat].ai and net.lobby.seats[seat].ready, "AI defaults ready")
	net.select_seat(3)
	t.expect(net.my_seat == 3 and net._peer_seat[1] == 3, "Host can select AI seat")
	t.expect(net.game.players.is_empty() and not net.all_ready(), "Seat selection does not deal")
	net.set_ready(true)
	t.expect(net.all_ready() and net._countdown == net.START_DELAY, "All ready starts countdown")
	net.select_seat(1)
	t.expect(net.my_seat == 1 and not net.all_ready() and net._countdown < 0, "Changing seat clears ready/countdown")
	net.set_ready(true)
	net.set_wants_dealer(true)
	t.expect(not net.all_ready(), "Dealer change clears own ready")
	var rng := RandomNumberGenerator.new()
	rng.seed = 771
	for index in 20: t.expect(net.choose_first_dealer(rng) == 1, "Single applicant is dealer")
	net.set_wants_dealer(false)
	var seen := {}
	for index in 80: seen[net.choose_first_dealer(rng)] = true
	t.expect(seen.size() == 4, "Without applicants all seats participate")
	# Only dealer selector is pure; real multi-peer swaps are tested in lobby_network.
	net._members[99] = {"wants_dealer": true}
	net._peer_seat[99] = 2
	net._members[1].wants_dealer = true
	seen.clear()
	for index in 80: seen[net.choose_first_dealer(rng)] = true
	t.expect(seen.size() == 2 and seen.has(1) and seen.has(2), "Multiple applicants exclusively chosen")
	net._members.erase(99)
	net._peer_seat.erase(99)
	net.set_ready(true)
	t.expect(net.start_net_game(999), "Ready room starts")
	t.expect(net.game.dealer_seat == 1 and net.game.players.size() == 4, "Actual chosen dealer gets tiles")
	t.expect(net.game.players[1].is_human, "Moved host keeps local control")
	var old := net.my_seat
	net.select_seat(0)
	t.expect(net.my_seat == old, "Seat lock during match")
	t.expect(not net.start_net_game(), "Cannot deal same first round twice")
	for value in ["123", "123456789", "-1234", "12a34", " 1234", "１２３４"]:
		t.expect(not NetGameNode.valid_room_number(value), "Invalid room number rejected")
	t.expect(NetGameNode.valid_room_number("0001"), "Leading zero preserved")
	network.reset()
	var lobby = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	await process_frame
	await process_frame
	for dimensions in [Vector2i(1280, 720), Vector2i(2400, 1080), Vector2i(960, 540)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var rect: Rect2 = lobby.content.get_global_rect()
		t.expect(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= root.size.x + 1 and rect.end.y <= root.size.y + 1, "Landscape lobby stays in viewport")
		t.expect(lobby.room_input.visible and not lobby.waiting.visible, "Search shown before joining")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/lobby_search.png")
	lobby.room_input.text = "012345"
	lobby.room_name_input.text = "朋友麻将局"
	lobby._create()
	await create_timer(2.1).timeout
	t.expect(lobby._in_room and lobby.waiting.visible and not lobby.browser.visible, "Create button opens waiting room")
	t.expect(network.net_node.room_number == "012345", "Entered room number preserved")
	t.expect(network.net_node.game.players.is_empty(), "UI creation doesn't deal")
	lobby.seat_buttons[2].pressed.emit()
	t.expect(network.net_node.my_seat == 2, "Seat button changes local seat")
	lobby.dealer_button.button_pressed = true
	t.expect(network.net_node.lobby.seats[2].wants_dealer, "Dealer checkbox sends applicant")
	lobby.ready_button.pressed.emit()
	t.expect(network.net_node.all_ready() and lobby.ready_button.text == "取消准备", "Ready UI sends ready state")
	lobby.ready_button.pressed.emit()
	t.expect(not network.net_node.all_ready(), "Ready UI can cancel")
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/lobby_waiting.png")
	lobby._back()
	t.expect(not lobby._in_room and network.mode == "", "Leave room returns to browser")
	lobby.queue_free()
	await process_frame
	quit(t.finish("smoke_lobby"))
