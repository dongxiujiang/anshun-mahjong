extends Node
const H := preload("res://tests/test_harness.gd")

var table
var actor := AiPlayer.new("UI test")
var host_mode := false
var failed := false
var turns := 0
var responses := 0
var audio_events := 0
var audio_ids := {}
var graphical := false
var captured_opening_wall := false
var tested_resume_turn := false
var tested_resume_settlement := false

func _ready() -> void:
	AudioManager.event_played.connect(_on_audio_event)
	host_mode = OS.get_cmdline_user_args().has("--table-host")
	graphical = DisplayServer.get_name() != "headless"
	if graphical:
		GameConfig.set_settlement_speed("0.25", false)
		GameConfig.set_tile_animation_seconds(0.15, false)
	_run()

func _run() -> void:
	if host_mode:
		_expect(Network.start_host(false, true, 7526), "Host must open the test port")
		Network.net_node.measure_state_traffic = true
		var start := Time.get_ticks_msec()
		while Network.net_node._peer_seat.size() < 2 and Time.get_ticks_msec() - start < 10000:
			await get_tree().process_frame
		_expect(Network.net_node._peer_seat.size() >= 2, "Client must receive a seat before game starts")
		Network.net_node.set_ready(true)
		while not Network.net_node.all_ready() and Time.get_ticks_msec() - start < 10000:
			await get_tree().process_frame
		Network.net_node.start_net_game(1000)
	else:
		Network.net_node.room_ready.connect(func(_seat): Network.net_node.set_ready(true))
		Network.start_client("127.0.0.1", 7526)
	table = load("res://scenes/GameTable.tscn").instantiate()
	add_child(table)
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 45000:
		await get_tree().process_frame
		var round: RoundState = table.round
		if round.players.size() != 4:
			continue
		var seat: int = table.human_seat
		_expect(table._relative_seat(seat) == 0, "Local seat must be at the bottom")
		if not host_mode and round.phase != RoundState.Phase.SETTLED:
			for opponent in 4:
				if opponent != seat:
					_expect(round.players[opponent].concealed.all(func(tile): return tile == "hidden0"), "Opponent hand values must stay private")
			if graphical and not captured_opening_wall and table._table_animation_controller.dice_gate_active():
				captured_opening_wall = true
				var visible_tiles := 0
				for tile in table._new_areas._wall_layer.get_children():
					visible_tiles += int(tile.visible)
				_expect(visible_tiles == 108, "Client keeps all 108 wall tiles visible while the dice roll")
				await _capture("opening-wall")
		if round.phase == RoundState.Phase.SETTLED:
			if not host_mode and not tested_resume_settlement:
				tested_resume_settlement = true
				await _check_foreground_restore("settlement")
				continue
			var settlement_deadline := Time.get_ticks_msec() + 10000
			while not table._settlement_animation_done() and Time.get_ticks_msec() < settlement_deadline:
				await get_tree().process_frame
			_expect(table._settlement_animation_done(), "Network settlement reaches its final tabletop state")
			_expect(audio_events > 0, "Host and client table must both receive audio events")
			_expect(AudioManager._last_event_id == round.audio_event_id, "Table audio must reach the latest synced event")
			if host_mode:
				if Network.net_node.ack_flag:
					_expect(not Network.net_node.ack_text.contains("UI=fail"), "Client UI must pass")
					var stats: Dictionary = Network.net_node.state_metrics
					_expect(int(stats.coalesced) > 0 and int(stats.bytes) < int(stats.full_bytes), "Coalescing and incremental audio reduce network traffic")
					print("[net_table] sync metrics: ", stats)
					print("[net_table] host completed; turns=%d responses=%d client=%s" % [turns, responses, Network.net_node.ack_text])
					if graphical: await _capture("settlement")
					await _finish_test()
					return
			else:
				await get_tree().process_frame
				if graphical: _expect(captured_opening_wall, "Client must observe the opening wall during the dice animation")
				_expect(table._settlement_card._post_controls.visible, "Client sees bottom readiness controls automatically")
				_expect(table._next_round_button.get_parent() == table._settlement_card._post_controls and not table._next_round_button.disabled, "Client can ready from the bottom button")
				_expect(round.last_result.has("deltas"), "Settlement scores must synchronize")
				if graphical:
					var view = table._new_areas
					_expect(is_instance_valid(view._native_settlement) and view._native_settlement.is_visible_in_tree(), "Client sees the native settlement card")
					_expect(view._settlement_pairs == round.last_result.pairwise, "Native client payments match the server settlement")
					await _capture("settlement")
				else:
					var settlement = table._settlement_animation_controller
					var board_count: int = 0 if settlement.plan.all_called_draw else 4
					_expect(settlement.boards.size() == board_count, "Client sees the expected final tabletop settlement")
					_expect(settlement.layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Client settlement preserves table input")
					_expect(settlement.current_pairs == round.last_result.pairwise, "Client tabletop payments match the authoritative settlement")
					for owner in settlement.boards:
						_expect(settlement.boards[owner].is_visible_in_tree() and settlement.payment_labels[owner].size() == 3, "All clients retain three payments per seat")
				# A legal seeded hand can offer zero claim windows to this seat;
				# response UI is covered deterministically by
				# play_animation_flow/table_interaction. Require at least the
				# client's own turn loop to have run here.
				_expect(turns > 0, "Client must complete turn workflows")
				Network.net_node.rpc_id(1, "ack", "turns=%d responses=%d UI=%s" % [turns, responses, "fail" if failed else "ok"])
				await get_tree().create_timer(0.3).timeout
				print("[net_table] client completed; turns=%d responses=%d" % [turns, responses])
				await _finish_test()
				return
		elif table._selecting:
			if not host_mode and not tested_resume_turn:
				tested_resume_turn = true
				await _check_foreground_restore("turn")
				continue
			var player: PlayerState = round.players[seat]
			var ui_deadline := Time.get_ticks_msec() + 3000
			while table._table_actions.input_locked() and Time.get_ticks_msec() < ui_deadline:
				await get_tree().process_frame
			await get_tree().process_frame
			var hand_box: Control = table.hand_box[seat]
			var draw_box: Control = table.draw_box[seat]
			if table._new_areas != null and DisplayServer.get_name() != "headless":
				hand_box = table._new_areas.hand_boxes[seat]
				draw_box = table._new_areas.draw_boxes[seat]
			var visible_hand_count := hand_box.get_child_count() + draw_box.get_child_count()
			if visible_hand_count != player.concealed.size():
				print("[net_table] local tile mismatch host=%s visible=%d concealed=%d just_drew=%s selecting=%s locked=%s deal=%s draw=%s sort=%s opening=%s phase=%s dealt=%s" % [
					host_mode, visible_hand_count, player.concealed.size(), player.just_drew,
					table._selecting, table._table_actions.input_locked(),
					table._new_areas.deal_animation_active if table._new_areas != null else false,
					table._new_areas._draw_animating if table._new_areas != null else false,
					table._new_areas._sort_animating if table._new_areas != null else false,
					table._new_areas._opening_mode() if table._new_areas != null else false,
					round.phase,
					table._table_animation_controller.dealt_count(seat)])
			_expect(visible_hand_count == player.concealed.size(), "Every local hand tile must appear once")
			if player.just_drew != "":
				_expect(draw_box.get_child_count() == 1, "Drawn tile must appear separately")
			if graphical and turns == 0: await _capture("first-turn")
			turns += 1
			table._commit_turn(actor.decide_turn(round, seat))
		elif table._response_disc != "":
			var card: String = table._response_disc
			var options: Dictionary = round._awaiting_response.options
			var response: Dictionary = actor.decide_response(round, seat, int(round.last_discard.get("seat", -1)), card, options)
			responses += 1
			table._commit_response(response.action)
	print("[net_table] timeout host=%s turns=%d responses=%d phase=%d turn=%d awaiting=%s locked=%s dealt=%s pending=%s" % [host_mode, turns, responses, table.round.phase, table.round.current_turn, table.round.awaiting, table._table_actions.input_locked(), table._table_animation_controller._dealt, table._table_animation_controller.has_pending()])
	push_error("Network UI test timed out")
	await _finish_test(1)

func _check_foreground_restore(stage: String) -> void:
	var net: NetGameNode = Network.net_node
	var revision: int = net._received_revision
	var seat: int = net.my_seat
	var hand: Array = net.game.players[seat].concealed.duplicate()
	get_tree().multiplayer_poll = false
	if stage == "settlement": table._sound_settings.open()
	net.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT if stage == "turn" else Node.NOTIFICATION_APPLICATION_PAUSED)
	net.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN if stage == "turn" else Node.NOTIFICATION_APPLICATION_RESUMED)
	_expect(net._resume_sync_pending and table._awaiting_rejoin_snapshot, "Foreground return gates table input until a fresh snapshot")
	_expect(net._reconnecting and net._reconnect_wait == 0.0, "Foreground return immediately replaces a possibly suspended socket")
	_expect(table._connection_overlay._title.text == "重连中", "Foreground feedback explicitly shows reconnection")
	_expect(table._connection_overlay.is_open() and table._connection_overlay.modulate.a == 1.0, "Foreground connection feedback appears immediately")
	_expect(table._connection_overlay.get_parent() is CanvasLayer and table._connection_overlay.get_parent().layer > table._sound_settings.layer, "Connection progress stays above an already-open settings panel")
	_expect(table._connection_overlay._loading_bar.indeterminate, "Foreground wait has an animated progress indicator")
	var blocked := {"discard":net.game.players[seat].just_drew}
	net.submit_client_turn(blocked)
	_expect(not blocked.has("prompt_id"), "No stale turn is submitted during the foreground wait")
	if graphical:
		await _capture("resume-" + stage + "-connecting")
		await get_tree().create_timer(0.45).timeout
		await _capture("resume-" + stage + "-waiting")
	get_tree().multiplayer_poll = true
	var deadline := Time.get_ticks_msec() + 5000
	while table._awaiting_rejoin_snapshot and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not net._resume_sync_pending and not table._awaiting_rejoin_snapshot and net._received_revision > revision, "Fresh authority restores the foreground table")
	_expect(not table._connection_overlay.is_open(), "Successful synchronization removes the connection overlay")
	_expect(net.my_seat == seat and net.game.players[seat].concealed == hand, "Foreground resume keeps the original seat and hand")
	if stage == "settlement": table._sound_settings.close(false)
	if graphical: await _capture("resume-" + stage + "-restored")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _capture(stage: String) -> void:
	await RenderingServer.frame_post_draw
	if stage == "settlement":
		var bounds := get_viewport().get_visible_rect()
		for button: Button in [table._settlement_card._return_seat_button, table._settlement_card._next_round_button]:
			var rect: Rect2 = button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, button.size)
			_expect(bounds.encloses(rect), "Network settlement button must fit inside the viewport")
	var folder := "res://build/network-table-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var role := "host" if host_mode else "client"
	_expect(get_viewport().get_texture().get_image().save_png(folder.path_join(role + "-" + stage + ".png")) == OK,
		"Save a screenshot of the graphical network table")

func _finish_test(code: int = 0) -> void:
	var workers: Array = [Network.net_node._ai_service]
	if is_instance_valid(table):
		workers.append_array([table._ai_service, table._ai_teach_worker, table._ai_proxy_worker])
	if is_instance_valid(table): table.queue_free()
	Network.reset()
	await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 5000
	while workers.any(func(worker): return worker != null and worker.is_started()) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_expect(not workers.any(func(worker): return worker != null and worker.is_started()), "AI workers stop before the test exits")
	await H.quit_cleanly(get_tree(), 1 if failed else code)

func _on_audio_event(event: Dictionary) -> void:
	var identity := "%s:%d" % [event.session, event.id]
	_expect(not audio_ids.has(identity), "Network refresh must not replay an audio event")
	audio_ids[identity] = true
	audio_events += 1
