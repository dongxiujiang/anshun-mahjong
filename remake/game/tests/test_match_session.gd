extends SceneTree

const Match = preload("res://src/session/MatchSession.gd")
const Dice = preload("res://src/runtime/DiceRoll.gd")
const Wall = preload("res://src/domain/Wall.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
var checks := 0
var failures := 0
var now := 30
var game
var dice
var instance := ""
var connections := {1: "host"}

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr(message)

func _roll(seed_value: int) -> bool:
	check(dice.roll(seed_value), "start genuine authority dice")
	for _tick in 1800:
		await physics_frame
		if dice.phase == "settled":
			return true
	check(false, "authority dice failed to settle")
	return false

## 把牌型排入真实牌墙，再走正式发牌。其余位置从合法的剩余牌池补齐。
func _deck(dealer: int, red: int, hands: Dictionary, first_draw: String) -> Array:
	var probe := Wall.new(Catalog.values(697))
	probe.open(dealer, red)
	var fixed := {}
	for seat in hands:
		var offset := posmod(dealer - int(seat), 4)
		var cards := []
		for group in hands[seat].split(" "):
			var suit: String = {"w": "wan", "b": "tong", "t": "tiao"}[group.left(1)]
			for digit in group.substr(1):
				cards.append(suit + digit)
		for i in cards.size():
			var relative := 48 + offset if i == 12 else (i / 4) * 16 + offset * 4 + i % 4
			fixed[(probe.break_index + relative) % 108] = cards[i]
	fixed[(probe.break_index + 52) % 108] = first_draw
	var pool := Catalog.values(285)
	for value in fixed.values():
		check(pool.has(value), "fixture uses at most four copies")
		pool.erase(value)
	var deck := []
	for i in 108:
		deck.append(fixed[i] if fixed.has(i) else pool.pop_back())
	return deck

func _run() -> void:
	game = Match.new("12")
	dice = Dice.new()
	root.add_child(dice)
	var host: Dictionary = game.join("u-host", "小东", "host", now)
	instance = host.ticket.room_instance_id
	check(host.view.seat == 1 and host.view.round.is_empty(), "initial preparation and south default")
	check(game.view_for("intruder", now).is_empty(), "unknown connection sees no room")
	check(not game.start_round(dice, Catalog.values(11), now, 0), "no round from unthrown dice")
	if not await _roll(31500):
		quit(1)
		return
	var red: int = dice.snapshot().result[0]
	var deck := _deck(0, red, {0: "w123456789 t123 b5"}, "tong5")
	check(not game.start_round(dice, deck, now, 0) and host.view.room.round_number == 0, "unready human prevents commit")
	game.set_ready("host", true, now)
	check(not game.start_round(dice, deck, now), "first dealer must be supplied")
	check(not game.start_round(dice, [], now, 0), "invalid stock prevents room transition")
	check(game.start_round(dice, deck, now, 0), "commit valid wall and settled dice once")
	var first: Dictionary = game.view_for("host", now)
	check(first.room.round_number == 1 and first.round.phase == "dealt" and first.round.wall_remaining == 56, "four hands dealt before dealer animation finishes")
	check(first.round.players[0].hand.is_empty() and first.round.players[1].hand.size() == 13 and not first.round.has("events"), "only own hand reaches human")
	check(not game.begin_dealer_turn("other-room", 1, first.round.prompt_id, now), "stale opening animation rejected")
	check(game.begin_dealer_turn(instance, 1, first.round.prompt_id, now), "authority completes the dealer deal")
	var work: Dictionary = game.ai_job(0, now)
	check(work.view.players[0].hand.size() == 14 and work.view.players[1].hand.is_empty() and work.view.viewer_seat == 0, "AI gets only its masked view")
	check(not game.submit("host", instance, 1, work.prompt_id, "self_win", -1, now), "human cannot claim AI seat action")
	check(game.submit_ai(work, "self_win", -1, now), "pure AI wins legitimately on initial dealer draw")
	var closed: Dictionary = game.view_for("host", now)
	var scores: Array = closed.settlement.scores.duplicate()
	check(scores[0] > 200 and _total(scores) == 800 and closed.settlement.next_dealer_seat == 0, "real ledger applies once and winner becomes dealer")
	check(not game.submit_ai(work, "self_win", -1, now) and game.view_for("host", now).settlement.scores == scores, "replayed AI job cannot repay ledger")
	closed.settlement.ledger.deltas[0] = 9999
	check(game.view_for("host", now).settlement.ledger.deltas[0] != 9999, "settlement views cannot mutate authority")
	game.set_ready("host", true, now)
	check(not game.start_round(dice, deck, now, 0), "old settled dice cannot start the next round")
	if not await _roll(31501):
		quit(1)
		return
	var second_wall := Catalog.values(165)
	check(game.start_round(dice, second_wall, now), "winner carries dealer into new round")
	var second: Dictionary = game.view_for("host", now)
	check(second.room.round_number == 2 and second.room.seats[0].score == scores[0] and not second.has("settlement"), "new hand preserves scores and clears current result")
	game.begin_dealer_turn(instance, 2, second.round.prompt_id, now)
	var stale_ai: Dictionary = game.ai_job(0, now)
	var first_hand: Array = stale_ai.view.players[0].hand.duplicate(true)
	var joined: Dictionary = game.join("u-new", "小西", "new", now)
	check(joined.ticket.seat == 0 and joined.view.room.seats[0].score == scores[0] and joined.view.round.players[0].hand == first_hand, "live takeover inherits AI hand, score and turn")
	check(joined.view.round.prompt_id == stale_ai.prompt_id and joined.view.round.players[1].hand.is_empty(), "joining does not redeal or restart prompt")
	var tile: int = joined.view.round.choices.discard_ids[0]
	check(not game.submit_ai(stale_ai, "discard", tile, now) and game.ai_job(0, now).is_empty(), "retired controller cannot finish old job")
	check(game.disconnect_human("new", now) and game.ai_job(0, now).is_empty(), "disconnected member never becomes a permanent AI")
	check(not game.submit("new", instance, 2, stale_ai.prompt_id, "discard", tile, now), "disconnected transport cannot submit")
	var ticket: Dictionary = joined.ticket
	check(game.resume("wrong", ticket.player_id, ticket.member_token, "back", now).is_empty(), "room instance tied to recovery")
	var back: Dictionary = game.resume(instance, ticket.player_id, ticket.member_token, "back", now)
	check(back.round.players[0].hand == first_hand and back.round.players[2].hand.is_empty() and back.round.prompt_id == stale_ai.prompt_id, "resumes latest private view")
	check(game.view_for("new", now).is_empty() and not game.submit_ai(stale_ai, "discard", tile, now), "old connection and old AI both invalid")
	check(not game.submit("back", instance, 1, stale_ai.prompt_id, "discard", tile, now), "reject prior round with same-looking prompt")
	check(not game.submit("back", "other", 2, stale_ai.prompt_id, "discard", tile, now), "reject foreign instance")
	check(not game.submit("back", instance, 2, stale_ai.prompt_id - 1, "discard", tile, now), "reject outdated prompt")
	check(game.view_for("back", now).round == back.round, "failed submissions leave state intact")
	connections[0] = "back"
	check(game.submit("back", instance, 2, stale_ai.prompt_id, "discard", tile, now), "recovered owner now controls the same tile")
	check(not game.submit("back", instance, 2, stale_ai.prompt_id, "discard", tile, now), "duplicate human action rejected")
	_exhaust_round()
	var draw: Dictionary = game.view_for("host", now)
	check(draw.round.phase == "settled" and draw.round.result.winners.is_empty() and draw.settlement.ledger.next_chicken_multiplier == 2, "wall exhaustion commits draw ledger and carry")
	check(_total(draw.settlement.scores) == 800, "full table score conserved after second settlement")
	_test_dealer_selection()
	game.set_ready("host", true, now)
	if not await _roll(31502):
		quit(1)
		return
	check(not game.start_round(dice, second_wall, now), "second human must also ready up")
	game.set_ready("back", true, now)
	var dealer: int = draw.room.next_dealer_seat
	var third_deck := _deck(dealer, int(dice.snapshot().result[0]), {dealer: "w123456789 t123 b5"}, "tong5")
	check(game.start_round(dice, third_deck, now), "draw to third hand")
	var third: Dictionary = game.view_for("host", now)
	game.begin_dealer_turn(instance, 3, third.round.prompt_id, now)
	var winner_view := _seat_view(dealer)
	check(_act(dealer, winner_view.prompt_id, "self_win", -1), "third hand winner")
	var paid: Dictionary = game.view_for("host", now).settlement
	check(paid.ledger.multiplier == 2 and paid.ledger.next_chicken_multiplier == 1 and _total(paid.scores) == 800, "draw carry applied once and reset after win")
	await _timeout_one_seat()
	await _historical_viewer()
	print("MatchSession: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _seat_view(seat: int) -> Dictionary:
	if connections.has(seat):
		return game.view_for(connections[seat], now).round
	return game.ai_job(seat, now).get("view", {})

func _act(seat: int, prompt: int, action: String, id: int) -> bool:
	if connections.has(seat):
		var state: Dictionary = game.view_for(connections[seat], now)
		return game.submit(connections[seat], instance, state.room.round_number, prompt, action, id, now)
	return game.submit_ai(game.ai_job(seat, now), action, id, now)

func _exhaust_round() -> void:
	for _step in 320:
		var state: Dictionary = game.view_for("host", now)
		if state.round.phase == "settled":
			return
		var acted := false
		for seat in 4:
			var view := _seat_view(seat)
			var opts: Dictionary = view.get("choices", {})
			if opts.is_empty():
				continue
			if opts.actions.has("pass"):
				acted = _act(seat, opts.prompt_id, "pass", -1)
			else:
				acted = _act(seat, opts.prompt_id, "discard", opts.discard_ids[0])
			break
		check(acted, "each live prompt has a legal authenticated action")
		if not acted:
			return
	check(false, "draw round finished within bounded turns")

func _timeout_one_seat() -> void:
	# 三家同时可胡。只一家的计时结束，不触碰同窗另外两家的选择。
	game = Match.new("13")
	connections = {1: "host"}
	var host: Dictionary = game.join("owner2", "西", "host", now)
	instance = host.ticket.room_instance_id
	game.set_ready("host", true, now)
	if not await _roll(31603):
		return
	var deck := _deck(1, int(dice.snapshot().result[0]), {0: "w1122334456677", 3: "t112233445566 w5", 2: "b112233445566 w5"}, "wan5")
	check(game.start_round(dice, deck, now, 1), "three-winner fixture through room start")
	var opening: Dictionary = game.view_for("host", now)
	game.begin_dealer_turn(instance, 1, opening.round.prompt_id, now)
	var view := _seat_view(1)
	check(_act(1, view.prompt_id, "discard", view.players[1].draw_id), "source discards real winning tile")
	var job: Dictionary = game.ai_job(0, now)
	check(game.expire_response_for(instance, 1, job.prompt_id, 0, now), "single seat timed out")
	check(not game.expire_response_for(instance, 1, job.prompt_id, 0, now) and not game.submit_ai(job, "win", -1, now), "expired seat cannot choose again")
	check(_act(2, job.prompt_id, "win", -1) and _act(3, job.prompt_id, "win", -1), "other seats can still win at their pace")
	var result: Dictionary = game.view_for("host", now).settlement
	check(result.round_meta.winners == [3, 2] and _total(result.scores) == 800, "only eligible final winners included")

func _test_dealer_selection() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 321
	var scored := {"all_called_draw": false, "winners": [0, 1, 3], "called": [true, true, false, true], "deltas": [12, 20, -35, 3]}
	check(Match.next_dealer(scored, 1, rng) == 1, "highest winner net wins dealer")
	scored.winners = []
	scored.deltas = [-12, -20, 4, -2]
	scored.called = [false, false, true, false]
	check(Match.next_dealer(scored, 2, rng) == 1, "most negative uncalled seat takes dealer")
	scored.deltas = [-20, -20, 42, -2]
	var selected := {}
	for _i in 30:
		selected[Match.next_dealer(scored, 2, rng)] = true
	check(selected.has(0) and selected.has(1) and selected.size() == 2, "ties only draw from eligible tied seats")
	scored.all_called_draw = true
	check(Match.next_dealer(scored, 2, rng) == 2, "all called draw dealer stays")

func _total(values: Array) -> int:
	var total := 0
	for value in values:
		total += int(value)
	return total

func _historical_viewer() -> void:
	game = Match.new("historic-view")
	var joined: Dictionary = game.join("original-player", "南", "host", now)
	instance = joined.ticket.room_instance_id
	game.set_ready("host", true, now)
	if not await _roll(31605):
		return
	var deck := _deck(1, int(dice.snapshot().result[0]), {1: "w123456789 t123 b5"}, "tong5")
	check(game.start_round(dice, deck, now, 1), "historical viewer fixture starts")
	var view: Dictionary = game.view_for("host", now)
	game.begin_dealer_turn(instance, 1, view.round.prompt_id, now)
	view = game.view_for("host", now)
	check(game.submit("host", instance, 1, view.round.prompt_id, "self_win", -1, now), "human winner before changing seat")
	var before: Dictionary = game.view_for("host", now).settlement
	check(before.viewer_seat == 1 and before.next_dealer_seat == 1 and before.scores[1] > 200, "historic winner fixed in south")
	check(game.move_to_empty_seat("host", 0, now), "winner moves to east at preparation")
	view = game.view_for("host", now)
	check(view.seat == 0 and view.room.next_dealer_seat == 0 and view.settlement.viewer_seat == 1, "live dealer moves; past viewer keeps winning seat")
	check(view.settlement.next_dealer_seat == 1 and view.settlement.seats == before.seats and view.settlement.ledger == before.ledger, "frozen dealer choice, identities and ledger are stable")
	var newcomer: Dictionary = game.join("after-finish", "新", "new", now)
	check(newcomer.view.seat == 1 and newcomer.view.settlement.viewer_seat == -1, "post-round member has no historic score row")
	game.disconnect_human("host", now)
	var restored: Dictionary = game.resume(instance, joined.ticket.player_id, joined.ticket.member_token, "back", now + 1)
	check(restored.seat == 0 and restored.settlement.viewer_seat == 1 and restored.settlement.scores == before.scores, "recovery preserves both current seat and historic winner identity")
