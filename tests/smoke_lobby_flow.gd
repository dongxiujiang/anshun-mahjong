extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var actor := AiPlayer.new("lobby flow")
var online_url := ""

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var network := root.get_node("Network")
	network.reset()
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--directory="): online_url = value.substr(12)
	if online_url != "": network.directory.base_url = online_url
	var lobby = load("res://scenes/Lobby.tscn").instantiate()
	root.add_child(lobby)
	current_scene = lobby
	await process_frame
	if online_url != "": lobby._set_mode(true)
	lobby.room_input.text = "998877"
	lobby._create()
	var room_deadline := Time.get_ticks_msec() + 20000
	while not lobby._in_room and Time.get_ticks_msec() < room_deadline:
		await process_frame
	t.expect(lobby._in_room and network.net_node.game.players.is_empty(), "Actual lobby creation remains undealt")
	lobby.seat_buttons[2].pressed.emit()
	lobby.dealer_button.button_pressed = true
	lobby.ready_button.pressed.emit()
	t.expect(lobby.waiting.visible, "Ready stays in lobby until countdown")
	await create_timer(3.3).timeout
	var table = current_scene
	t.expect(table != null and table.has_method("_on_net_prompt"), "Countdown enters actual table scene")
	if table == null or not table.has_method("_on_net_prompt"):
		quit(1)
		return
	var opening_deadline := Time.get_ticks_msec() + 12000
	while table.round.phase == RoundState.Phase.DEALING and Time.get_ticks_msec() < opening_deadline:
		await process_frame
	t.expect(table.human_seat == 2 and table.round.dealer_seat == 2, "Seat and dealer preserved across scene")
	t.expect(table._selecting and table.draw_box[2].get_child_count() == 1, "First dealer prompt remains playable after scene change")
	t.expect(table.hand_box[2].get_child_count() == 13, "Hand fully drawn on entry")
	if online_url != "":
		t.expect(network.mode == "client" and network.net_node.is_room_owner(), "Online create UI joins dedicated room as owner")
		table._on_quit()
		await create_timer(0.25).timeout
		quit(t.finish("smoke_online_lobby_flow"))
		return
	var deadline := Time.get_ticks_msec() + 35000
	while table.round.phase != RoundState.Phase.SETTLED and Time.get_ticks_msec() < deadline:
		await process_frame
		if table._selecting:
			table._commit_turn(actor.decide_turn(table.round, 2))
		elif table._response_disc != "":
			var request: Dictionary = table.round._awaiting_response
			var decision := actor.decide_response(table.round, 2, request.disc_seat, request.tile, request.options)
			table._commit_response(decision.action)
	t.expect(table.round.phase == RoundState.Phase.SETTLED, "Lobby-to-table full game finishes")
	await process_frame
	t.expect(table.result_layer.visible, "Lobby-launched game shows settlement")
	var scores: Array = table.round.players.map(func(player): return player.score)
	var next_dealer: int = table.round.next_dealer_seat
	table._next_round()
	t.expect(network.net_node.round_number == 1 and table.result_layer.visible, "Readying keeps settlement until countdown completes")
	t.expect(table._next_round_button.text.contains("1 秒"), "Settlement shows one-second countdown")
	await create_timer(1.15).timeout
	t.expect(network.net_node.round_number == 2, "Next-round table button advances network round")
	t.expect(table.round.dealer_seat == next_dealer, "Next-round button uses result dealer")
	t.expect(table.round.players.map(func(player): return player.score) == scores, "Next-round button keeps scores")
	# Returning to menu closes discovery responder and network peer.
	table._confirm_quit()
	t.expect(network.mode == "host" and table._sound_settings.exit_confirmation.visible, "Exit leaves the room connected until confirmed")
	table._sound_settings.cancel_exit_button.pressed.emit()
	t.expect(network.mode == "host", "Cancel exit keeps the multiplayer room")
	table._confirm_quit()
	table._sound_settings.confirm_exit_button.pressed.emit()
	await process_frame
	t.expect(network.mode == "" and network.discovery._responder == null, "Leaving table closes room")
	await create_timer(0.25).timeout
	quit(t.finish("smoke_lobby_flow"))
