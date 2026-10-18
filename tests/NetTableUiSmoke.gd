extends Node

var table
var actor := AiPlayer.new("UI test")
var host_mode := false
var failed := false
var turns := 0
var responses := 0
var audio_events := 0
var audio_ids := {}

func _ready() -> void:
	AudioManager.event_played.connect(_on_audio_event)
	host_mode = OS.get_cmdline_user_args().has("--table-host")
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
		if round.phase == RoundState.Phase.SETTLED:
			var settlement_deadline := Time.get_ticks_msec() + 10000
			while not table._settlement_animation_controller.is_completed() and Time.get_ticks_msec() < settlement_deadline:
				await get_tree().process_frame
			_expect(table._settlement_animation_controller.is_completed(), "Network settlement reaches its final tabletop state")
			_expect(audio_events > 0, "Host and client table must both receive audio events")
			_expect(AudioManager._last_event_id == round.audio_event_id, "Table audio must reach the latest synced event")
			if host_mode:
				if Network.net_node.ack_flag:
					_expect(not Network.net_node.ack_text.contains("UI=fail"), "Client UI must pass")
					var stats: Dictionary = Network.net_node.state_metrics
					_expect(int(stats.coalesced) > 0 and int(stats.bytes) < int(stats.full_bytes), "Coalescing and incremental audio reduce network traffic")
					print("[net_table] sync metrics: ", stats)
					print("[net_table] host completed; turns=%d responses=%d client=%s" % [turns, responses, Network.net_node.ack_text])
					await _finish_test()
					return
			else:
				await get_tree().process_frame
				var settlement = table._settlement_animation_controller
				var board_count: int = 0 if settlement.plan.all_called_draw else 4
				_expect(settlement.boards.size() == board_count and table._settlement_card._post_controls.visible, "Client sees the final tabletop settlement and bottom readiness controls automatically")
				_expect(settlement.layer.mouse_filter == Control.MOUSE_FILTER_IGNORE and not table._settlement_card._post_controls is Panel, "Client settlement uses non-blocking tabletop content and plain bottom controls")
				_expect(table._next_round_button.get_parent() == table._settlement_card._post_controls and not table._next_round_button.disabled, "Client can ready from the bottom button")
				_expect(round.last_result.has("deltas"), "Settlement scores must synchronize")
				_expect(settlement.current_pairs == round.last_result.pairwise, "Client tabletop payments match the authoritative settlement")
				for owner in settlement.boards:
					_expect(settlement.boards[owner].is_visible_in_tree() and settlement.payment_labels[owner].size() == 3, "All clients retain three payments per seat")
				_expect(turns > 0 and responses > 0, "Client must complete turn and response workflows")
				Network.net_node.rpc_id(1, "ack", "turns=%d responses=%d UI=%s" % [turns, responses, "fail" if failed else "ok"])
				await get_tree().create_timer(0.3).timeout
				print("[net_table] client completed; turns=%d responses=%d" % [turns, responses])
				await _finish_test()
				return
		elif table._selecting:
			var player: PlayerState = round.players[seat]
			_expect(table.hand_box[seat].get_child_count() + table.draw_box[seat].get_child_count() == player.concealed.size(), "Every local hand tile must appear once")
			if player.just_drew != "":
				_expect(table.draw_box[seat].get_child_count() == 1, "Drawn tile must appear separately")
			turns += 1
			table._commit_turn(actor.decide_turn(round, seat))
		elif table._response_disc != "":
			var card: String = table._response_disc
			var options: Dictionary = round._awaiting_response.options
			var response: Dictionary = actor.decide_response(round, seat, int(round.last_discard.get("seat", -1)), card, options)
			responses += 1
			table._commit_response(response.action)
	push_error("Network UI test timed out")
	get_tree().quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _finish_test() -> void:
	table.queue_free()
	# 给音频线程完成停止和释放播放实例的时间。
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(1 if failed else 0)

func _on_audio_event(event: Dictionary) -> void:
	var identity := "%s:%d" % [event.session, event.id]
	_expect(not audio_ids.has(identity), "Network refresh must not replay an audio event")
	audio_ids[identity] = true
	audio_events += 1
