extends "res://tests/test_match_session.gd"
## 复用同一房间测试的真实双骰、库存守恒发牌和认证操作夹具。

const Record = preload("res://src/session/RoundRecord.gd")
const Protocol = preload("res://src/domain/Protocol.gd")

func _run() -> void:
	game = Match.new("replay")
	dice = Dice.new()
	root.add_child(dice)
	var host: Dictionary = game.join("private-player-id", "北", "host", now)
	instance = host.ticket.room_instance_id
	check(host.view.room.variant_id == Protocol.VARIANT_ID and host.view.room.rules_version == Protocol.RULES_VERSION, "room names its active rules")
	game.set_ready("host", true, now)
	if not await _roll(31500):
		quit(1)
		return
	var stock := _deck(1, int(dice.snapshot().result[0]), {1: "w123456789 t123 b5"}, "tong5")
	check(game.start_round(dice, stock, now, 1), "create first recorded game")
	stock.clear()
	check(game.last_completed_record().is_empty(), "no authority export of an incomplete first game")
	var opening := _seat_view(1)
	check(game.begin_dealer_turn(instance, 1, opening.prompt_id, now), "dealer animation recorded")
	var view := _seat_view(1)
	check(not game.submit("host", instance, 1, opening.prompt_id, "self_win", -1, now), "stale input excluded")
	check(_act(1, view.prompt_id, "self_win", -1), "recorded actual self draw")
	var win: Dictionary = game.last_completed_record()
	check(win.inputs.size() == 2 and win.wall.size() == 108 and win.next_dealer_seat == 1, "completed immutable input tape and fixed wall")
	win.wall[0] = "illegal"
	win = game.last_completed_record()
	check(win.wall[0] != "illegal", "exported value cannot change archive")
	var text := JSON.stringify(win)
	check(not text.contains(host.ticket.member_token) and not text.contains("private-player-id") and not text.contains(instance), "record contains no member credential or connection identity")
	var public_text := JSON.stringify(game.view_for("host", now))
	check(not public_text.contains("\"inputs\"") and not public_text.contains("\"wall\":") and not public_text.contains("\"checksum\""), "client room view does not include private record")
	var replayed := Record.replay_json(text)
	check(replayed.ok and replayed.ledger.deltas == win.ledger.deltas and replayed.facts == win.facts, "JSON winning replay matches authoritative facts and ledger")
	_tampering(win)

	game.set_ready("host", true, now)
	if not await _roll(31501):
		quit(1)
		return
	var ready_stock := _deck(1, int(dice.snapshot().result[0]), {1: "w123456789 t45 b55"}, "tong2")
	check(game.start_round(dice, ready_stock, now), "next game can retain prior completed record")
	check(game.last_completed_record().round_number == 1, "no partial new game replaces prior recorded finish")
	opening = _seat_view(1)
	game.begin_dealer_turn(instance, 2, opening.prompt_id, now)
	view = _seat_view(1)
	check(_act(1, view.prompt_id, "ready", view.players[1].draw_id), "record exact declaration tile")
	for step in 450:
		view = _seat_view(1)
		if view.phase == "settled":
			break
		if view.phase == "ready_draw":
			check(game.finish_draw_animation(instance, 2, view.prompt_id, view.turn, now), "record ready-draw completion")
			continue
		var advanced := false
		for seat in 4:
			var own := _seat_view(seat)
			var options: Dictionary = own.get("choices", {})
			if options.is_empty():
				continue
			if options.actions.has("pass"):
				advanced = game.expire_response_for(instance, 2, options.prompt_id, seat, now)
			else:
				advanced = _act(seat, options.prompt_id, "discard", options.discard_ids[0])
			break
		check(advanced, "play recorded draw through real authority inputs")
		if not advanced:
			break
	var draw: Dictionary = game.last_completed_record()
	check(draw.round_number == 2 and draw.facts.round_meta.winners.is_empty(), "completed draw available")
	check(draw.inputs.any(func(c): return c.type == "timeout" and c.action == "pass") and draw.inputs.any(func(c): return c.type == "finish_draw_animation"), "timeout and automatic ready-discard triggers captured")
	replayed = Record.replay_json(JSON.stringify(draw))
	check(replayed.ok and replayed.ledger == draw.ledger and replayed.facts == draw.facts, "wall exhaustion replay matches every payment and source after JSON round trip")
	await _tied_draw()
	print("RoundRecord: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## 重新计算本地校验和，确认重演本身也会发现伪造的指令或计分。
func _reseal(record: Dictionary) -> Dictionary:
	record.erase("checksum")
	record.checksum = Record._canonical(record).sha256_text()
	return record

func _tampering(original: Dictionary) -> void:
	check(not Record.replay_json("[").ok, "bad JSON rejected")
	var changed := original.duplicate(true)
	changed.record_version += 1
	check(Record.replay(changed).error == "unsupported_version", "unknown data version rejected")
	changed = original.duplicate(true)
	changed.rules_version += 1
	check(Record.replay(changed).error == "unsupported_version", "unknown rules rejected")
	changed = original.duplicate(true)
	changed.variant_id = "another"
	check(Record.replay(changed).error == "unsupported_version", "unknown variant rejected")
	changed = original.duplicate(true)
	var different := 1
	while changed.wall[different] == changed.wall[0]:
		different += 1
	var held: String = changed.wall[different]
	changed.wall[different] = changed.wall[0]
	changed.wall[0] = held
	check(Record.replay(changed).error == "checksum", "changed full stock caught even before affected tile is used")
	changed.wall[different] = held
	check(Record.replay(_reseal(changed)).error == "wall", "invalid physical stock rejected after reseal")
	changed = original.duplicate(true)
	changed.inputs[1].prompt_id += 1
	check(Record.replay(_reseal(changed)).error == "stale_input", "stale authority input rejected")
	changed = original.duplicate(true)
	changed.inputs[1].seat = 1.5
	check(Record.replay(_reseal(changed)).error == "illegal_input", "fractional JSON IDs never truncated")
	changed = original.duplicate(true)
	changed.inputs[1].seat = 3
	check(Record.replay(_reseal(changed)).error == "illegal_input", "other player's old move rejected")
	changed = original.duplicate(true)
	changed.inputs.pop_back()
	check(Record.replay(_reseal(changed)).error == "incomplete", "incomplete game cannot claim a settlement")
	changed = original.duplicate(true)
	changed.ledger.deltas[1] += 1.0
	check(Record.replay(_reseal(changed)).error == "ledger", "recomputed ledger rejects altered score")
	changed = original.duplicate(true)
	changed.facts.round_meta.flip_wall_index += 1
	check(Record.replay(_reseal(changed)).error == "result_facts", "recomputed flip provenance rejects rewrite")
	changed = original.duplicate(true)
	changed.dice.result[0] = 7 - int(changed.dice.result[0])
	check(Record.replay(_reseal(changed)).error == "dice", "physical top and saved pip must agree")
	changed = original.duplicate(true)
	changed.next_dealer_seat = 3
	check(Record.replay(_reseal(changed)).error == "next_dealer", "winner-dealer qualification verified without rerolling tie")

func _tied_draw() -> void:
	game = Match.new("tied-draw")
	var host: Dictionary = game.join("member", "北", "host", now)
	instance = host.ticket.room_instance_id
	game.set_ready("host", true, now)
	if not await _roll(31503):
		return
	var hands := {}
	for seat in 4:
		hands[seat] = "w12457 t12457 b147"
	var deck := _deck(1, int(dice.snapshot().result[0]), hands, "tong9")
	check(game.start_round(dice, deck, now, 1), "tied all-uncalled fixture starts with authentic four-copy inventory")
	game.begin_dealer_turn(instance, 1, _seat_view(1).prompt_id, now)
	for step in 150:
		var view := _seat_view(1)
		if view.phase == "settled":
			break
		if view.phase == "turn":
			var own := _seat_view(view.turn)
			check(_act(view.turn, view.prompt_id, "discard", own.players[view.turn].draw_id), "discard only draw to keep all four real initial hands")
		else:
			for seat in 4:
				if not _seat_view(seat).get("choices", {}).is_empty():
					game.expire_response_for(instance, 1, view.prompt_id, seat, now)
					break
	var tied: Dictionary = game.last_completed_record()
	check(tied.ledger.called == [false, false, false, false] and _total(tied.ledger.deltas) == 0, "all four uncalled and nobody pays")
	tied.next_dealer_seat = (int(tied.next_dealer_seat) + 1) % 4
	check(Record.replay(_reseal(tied)).ok, "valid alternative tied seat accepted without selecting again")
