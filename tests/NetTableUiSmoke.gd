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
		if not host_mode and round.phase != "settled":
			for opponent in 4:
				if opponent != seat:
					_expect(round.players[opponent].concealed.all(func(tile): return tile == "hidden0"), "Opponent hand values must stay private")
		if round.phase == "settled":
			_expect(audio_events > 0, "Host and client table must both receive audio events")
			_expect(AudioManager._last_event_id == round.audio_event_id, "Table audio must reach the latest synced event")
			if host_mode:
				if Network.net_node.ack_flag:
					_expect(not Network.net_node.ack_text.contains("UI=fail"), "Client UI must pass")
					print("[net_table] host completed; turns=%d responses=%d client=%s" % [turns, responses, Network.net_node.ack_text])
					await _finish_test()
					return
			else:
				await get_tree().process_frame
				_expect(table.result_layer.visible, "Client must display settlement")
				_expect(round.last_result.has("deltas"), "Settlement scores must synchronize")
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
