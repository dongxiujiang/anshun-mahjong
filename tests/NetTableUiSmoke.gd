extends Node

var table
var actor := AiPlayer.new("UI test")
var host_mode := false
var failed := false
var turns := 0
var responses := 0

func _ready() -> void:
	host_mode = OS.get_cmdline_user_args().has("--table-host")
	_run()

func _run() -> void:
	if host_mode:
		_expect(Network.start_host(false, true, 7526), "Host must open the test port")
		var start := Time.get_ticks_msec()
		while Network.net_node._peer_seat.size() < 2 and Time.get_ticks_msec() - start < 10000:
			await get_tree().process_frame
		_expect(Network.net_node._peer_seat.size() >= 2, "Client must receive a seat before game starts")
		Network.net_node.start_net_game(1000)
	else:
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
			if host_mode:
				if Network.net_node.ack_flag:
					_expect(not Network.net_node.ack_text.contains("UI=fail"), "Client UI must pass")
					print("[net_table] host completed; turns=%d responses=%d client=%s" % [turns, responses, Network.net_node.ack_text])
					get_tree().quit(1 if failed else 0)
					return
			else:
				await get_tree().process_frame
				_expect(table.result_layer.visible, "Client must display settlement")
				_expect(round.last_result.has("deltas"), "Settlement scores must synchronize")
				_expect(turns > 0 and responses > 0, "Client must complete turn and response workflows")
				Network.net_node.rpc_id(1, "ack", "turns=%d responses=%d UI=%s" % [turns, responses, "fail" if failed else "ok"])
				await get_tree().create_timer(0.3).timeout
				print("[net_table] client completed; turns=%d responses=%d" % [turns, responses])
				get_tree().quit(1 if failed else 0)
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
