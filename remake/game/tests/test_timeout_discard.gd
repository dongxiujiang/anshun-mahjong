extends "res://tests/test_match_session.gd"

const Clock = preload("res://src/session/TurnClock.gd")
const Ai = preload("res://src/ai/AiPlayer.gd")
const Record = preload("res://src/session/RoundRecord.gd")

func _run() -> void:
	game = Match.new("one-discard")
	dice = Dice.new()
	root.add_child(dice)
	connections[1] = "initial"
	var joined: Dictionary = game.join("timeout-member", "南", "initial", now)
	var ticket: Dictionary = joined.ticket
	instance = ticket.room_instance_id
	game.set_ready("initial", true, now)
	if not await _roll(31500):
		quit(1)
		return
	var deck := _deck(1, int(dice.snapshot().result[0]), {1: "w123456789 t123 b5"}, "tong5")
	check(game.start_round(dice, deck, now, 1), "start timeout fixture")
	var open := _seat_view(1)
	check(game.discard_timeout_job(_intent(open.prompt_id, 1), now).is_empty(), "no timeout discard during deal")
	game.begin_dealer_turn(instance, 1, open.prompt_id, now)
	var view := _seat_view(1)
	check(view.choices.actions.has("self_win"), "winner option exists before one-shot timeout")
	var clock := Clock.new(instance)
	var intent := _expiry(clock, view.prompt_id)
	check(game.discard_timeout_job(intent, now - 1).is_empty(), "authority cannot mint this due intent before its deadline")
	var job: Dictionary = game.discard_timeout_job(intent, now)
	var duplicate: Dictionary = game.resume(instance, ticket.player_id, ticket.member_token, "initial", now)
	var after_duplicate: Dictionary = game.discard_timeout_job(intent, now)
	check(duplicate.round.prompt_id == job.prompt_id and after_duplicate.nonce == job.nonce and after_duplicate.control_revision == job.control_revision, "idempotent recovery preserves the existing timeout capability")
	check(not job.is_empty() and job.view.choices.actions == ["discard"] and job.view.choices.size() == 3, "one job offers only legal discard IDs")
	check(job.view.players[0].hand.is_empty() and not job.view.has("wall") and job.view.viewer_seat == 1, "fallback worker cannot inspect opponents or wall")
	var decision := Ai.decide(job.view, "low")
	check(decision.action == "discard" and job.view.choices.discard_ids.has(decision.tile_id), "real AI picks one legal discard, cannot win or declare ready")
	check(not game.submit_ai(job, "self_win", -1, now), "ordinary AI API cannot control a human")
	var edited := job.duplicate()
	edited.nonce = "not-issued"
	check(not game.submit_timeout_discard(edited, decision.tile_id, now), "reject unissued timeout worker")
	check(not game.submit_timeout_discard(job, -99, now), "invalid worker output never discards")
	check(game.submit_timeout_discard(job, decision.tile_id, now) and clock.action_accepted(1, job.prompt_id, 1), "one fallback succeeds on connected human")
	check(not game.submit_timeout_discard(job, decision.tile_id, now) and game.discard_timeout_job(intent, now).is_empty(), "single use and stale prompt rejected")
	check(_advance_to(1), "play other seats to next ordinary turn")
	view = _seat_view(1)
	check(view.choices.actions.has("discard") and game.ai_job(1, now).is_empty(), "next turn still belongs to human")
	intent = _expiry(clock, view.prompt_id)
	var old_job: Dictionary = game.discard_timeout_job(intent, now)
	check(game.disconnect_human("initial", now) and not game.submit_timeout_discard(old_job, old_job.view.choices.discard_ids[0], now), "disconnect invalidates active callback")
	var offline_job: Dictionary = game.discard_timeout_job(intent, now)
	check(not offline_job.is_empty() and offline_job.nonce != old_job.nonce, "offline member can obtain new one-shot job")
	var back: Dictionary = game.resume(instance, ticket.player_id, ticket.member_token, "back", now + 1)
	now += 1
	connections[1] = "back"
	check(back.round.prompt_id == view.prompt_id and not game.submit_timeout_discard(offline_job, offline_job.view.choices.discard_ids[0], now), "reconnect retains prompt but invalidates offline worker")
	var renewed: Dictionary = game.discard_timeout_job(intent, now)
	check(renewed.control_revision != offline_job.control_revision and renewed.nonce != offline_job.nonce, "adjudicated intent can be reissued on current controller")
	var newer: Dictionary = game.resume(instance, ticket.player_id, ticket.member_token, "newer", now)
	check(newer.round.prompt_id == intent.prompt_id and game.view_for("back", now).is_empty() and not game.submit_timeout_discard(renewed, renewed.view.choices.discard_ids[0], now), "new transport replaces an active connection and invalidates its worker")
	var rebound_job: Dictionary = game.discard_timeout_job(intent, now)
	check(rebound_job.nonce != renewed.nonce and rebound_job.control_revision != renewed.control_revision and clock.tick(1, view.prompt_id, now).is_empty(), "same expired clock intent reissues immediately without another countdown")
	check(game.disconnect_human("newer", now) and game.ai_job(1, now).is_empty(), "last human offline under five-minute room grace")
	var final_job: Dictionary = game.discard_timeout_job(intent, now + 1)
	now += 1
	decision = Ai.decide(final_job.view, "low")
	check(game.submit_timeout_discard(final_job, decision.tile_id, now), "one-off room authority discard for a disconnected human")
	game.resume(instance, ticket.player_id, ticket.member_token, "host", now)
	connections[1] = "host"
	_exhaust_round()
	var record: Dictionary = game.last_completed_record()
	var timed: Array = record.inputs.filter(func(c): return c.type == "timeout" and c.action == "discard")
	check(timed.size() == 2 and timed[1].tile_id == decision.tile_id, "archive contains both fallback actions and actual IDs")
	check(not JSON.stringify(record).contains(final_job.nonce) and Record.replay_json(JSON.stringify(record)).ok, "fallback archive replays without private capability")
	await _reserved_windows()
	print("TimeoutDiscard: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _expiry(clock, prompt: int) -> Dictionary:
	var seats: Array[int] = [1]
	check(clock.begin_prompt(1, prompt, Clock.Kind.DISCARD, seats), "time ordinary discard for one seat")
	check(clock.tick(1, prompt, now + 50000).is_empty(), "no fallback before animation completes")
	check(clock.animation_finished(1, prompt, 1, now), "clock starts when action available")
	check(clock.tick(1, prompt, now + 14999).is_empty(), "ordinary default 10+5 has no intent at 14.999 seconds")
	now += 15000
	var due: Array = clock.tick(1, prompt, now)
	check(due.size() == 1 and due[0].action == "ai_discard" and clock.tick(1, prompt, now).is_empty(), "exactly one clock intent at fifteen seconds")
	return due[0]

func _intent(prompt: int, seat: int) -> Dictionary:
	return {"action": "ai_discard", "room_instance_id": instance, "round_number": 1,
		"prompt_id": prompt, "seat": seat, "deadline_ms": now}

func _advance_to(target: int) -> bool:
	for step in 30:
		var state: Dictionary = game.view_for(connections[1], now).round
		if state.turn == target and state.phase in ["turn", "ready_draw"]:
			return true
		if state.phase == "turn":
			var own := _seat_view(state.turn)
			check(game.discard_timeout_job(_intent(state.prompt_id, state.turn), now).is_empty(), "pure AI does not get a human-timeout ticket")
			if not _act(state.turn, state.prompt_id, "discard", own.players[state.turn].draw_id):
				return false
		elif state.phase == "response":
			for seat in 4:
				if not _seat_view(seat).get("choices", {}).is_empty():
					game.expire_response_for(instance, 1, state.prompt_id, seat, now)
					break
		else:
			return false
	return false

func _reserved_windows() -> void:
	game = Match.new("ready-response")
	var host: Dictionary = game.join("r1", "南", "host", now)
	instance = host.ticket.room_instance_id
	connections = {1: "host"}
	# 第二个真人持有两张五万，可选择碰，响应超时只允许过。
	game.join("r0", "东", "east", now)
	connections[0] = "east"
	game.set_ready("host", true, now)
	game.set_ready("east", true, now)
	if not await _roll(31501):
		return
	var red: int = dice.snapshot().result[0]
	var deck := _deck(1, red, {1: "w123456789 t45 b55", 0: "w55"}, "wan5")
	var probe := Wall.new(deck)
	probe.open(1, red)
	var next_draw := (probe.break_index + 56) % 108
	for distance in range(56, 108):
		var donor := (probe.break_index + distance) % 108
		if deck[donor] in ["tiao3", "tiao6"]:
			var saved: String = deck[next_draw]
			deck[next_draw] = deck[donor]
			deck[donor] = saved
			break
	check(game.start_round(dice, deck, now, 1), "legitimate mixed response/ready fixture")
	var view := _seat_view(1)
	game.begin_dealer_turn(instance, 1, view.prompt_id, now)
	view = _seat_view(1)
	check(_act(1, view.prompt_id, "ready", view.players[1].draw_id), "declare ready with actual drawn copy")
	var east := _seat_view(0)
	check(east.choices.actions.has("pong") and game.discard_timeout_job(_intent(east.prompt_id, 0), now).is_empty(), "claim window never issues a discard fallback")
	# East now plays its own turns, so use generic human/AI act for the next orbit.
	for step in 20:
		view = _seat_view(1)
		if view.phase == "ready_draw":
			break
		if view.phase == "response":
			for seat in 4:
				if not _seat_view(seat).get("choices", {}).is_empty():
					game.expire_response_for(instance, 1, view.prompt_id, seat, now)
					break
		else:
			var own := _seat_view(view.turn)
			_act(view.turn, view.prompt_id, "discard", own.players[view.turn].draw_id)
	check(view.phase == "ready_draw" and game.discard_timeout_job(_intent(view.prompt_id, 1), now).is_empty(), "automatic ready draw not an ordinary turn")
	game.finish_draw_animation(instance, 1, view.prompt_id, 1, now)
	view = _seat_view(1)
	check(view.choices.actions == ["self_win", "pass"] and game.discard_timeout_job(_intent(view.prompt_id, 1), now).is_empty(), "ready self-win uses response timeout only")
