extends SceneTree

var failed := false
const WIN := ["tiao1", "tiao2", "tiao3", "wan4", "wan5", "wan6", "tong7", "tong8", "tong9", "wan3", "wan4", "wan5", "wan9", "wan9"]
const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tong1", "tong2", "tong3", "wan9"]

func _initialize() -> void:
	call_deferred("_run")

func expect(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func fixture() -> RoundState:
	var round := RoundState.new()
	round.build_players(0)
	round.controllers = [null, null, null, null]
	round.phase = "playing"
	round.current_turn = 0
	round.awaiting = true
	round.wall = WallRing.new(TileSetFactory.create_deck())
	round.wall.set_head(0)
	return round

func scored(round: RoundState) -> Dictionary:
	var result := ScoringEngine.settle(round)
	var sum := 0.0
	for value in result.deltas:
		sum += value
	expect(is_zero_approx(sum), "Every settlement must be zero-sum")
	return result

func _run() -> void:
	_test_scoring()
	_test_turns()
	_test_rob()
	_test_discard_win_restrictions()
	_test_wall_and_patterns()
	_test_private_sync()
	if not failed:
		print("[rules_complete] scoring, payments, flip, priority, rob/pass, ready, wall and patterns passed")
	quit(1 if failed else 0)

func _test_scoring() -> void:
	var round := fixture()
	round.round_meta.winner = 0
	round.round_meta.self_draw = true
	round.players[0].concealed = WIN.duplicate()
	round.round_meta.flip_tile = "tiao5"
	var result := scored(round)
	expect(result.deltas == [12.0, -4.0, -4.0, -4.0], "Uncalled opponents pay self-draw bonus but not held chickens")
	round.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}}
	round.players[0].discards = ["tiao1"]
	result = scored(round)
	expect(result.points[0] == 12.0, "Charge chicken is worth four instead of ordinary two")
	round.players[0].discard_history = ["tiao1"]
	round.players[0].discards.clear()
	result = scored(round)
	expect(result.points[0] == 8.0, "Removed chicken must not score from stale history")
	round.players[0].discard_history.append("tong8")
	result = scored(round)
	expect(result.points[0] == 8.0, "History alone never scores claimed chickens")
	round.round_meta.burn_chicken_seat = 0
	result = scored(round)
	expect(result.points[0] == 4.0, "Burn clears chicken points only")
	round.round_meta.burn_chicken_seat = -1
	round.round_meta.charge_chickens.clear()
	round.players[0].discards.clear()
	round.players[0].discard_history.clear()
	round.players[1].concealed = WAIT.duplicate()
	expect(ScoringEngine.is_called(round, 1), "Normal tenpai must count as called without declaration")
	round.round_meta.flip_tile = "tiao2"
	result = scored(round)
	expect(result.points[1] == 6.0, "One chicken and flip trio must score, doubling the chicken")
	round.players[1].concealed = ["wan2", "wan3", "wan4", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9"]
	round.players[1].melds = [{"kind": "pung", "tile": "tiao1"}]
	round.round_meta.flip_tile = "tiao1"
	result = scored(round)
	expect(result.points[1] == 13.0, "All three meld chickens and held neighbors must count")
	round.players[1].concealed = ["wan2", "wan3", "wan4", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9"]
	round.players[1].melds = [{"kind": "kong", "tile": "tiao1"}]
	result = scored(round)
	expect(result.points[1] == 17.0, "All four kong chickens must count")
	round = fixture()
	round.players[0].concealed = WIN.duplicate()
	round.round_meta.winner = 0
	round.round_meta.self_draw = true
	round.players[0].ready = true
	result = scored(round)
	expect(result.deltas == [84.0, -28.0, -28.0, -28.0], "Declared-ready self draw pays twenty-four plus self draw from each opponent")
	round.players[1].ready = true
	result = scored(round)
	expect(result.deltas == [84.0, -28.0, -28.0, -28.0], "Ready payment must not be charged twice")
	round.players[0].ready = false
	result = scored(round)
	expect(result.deltas[1] == -28.0, "Killed ready opponent pays twenty-four plus self draw")
	round.round_meta.self_draw = false
	round.round_meta.discard_seat = 2
	round.players[0].ready = true
	result = scored(round)
	expect(result.deltas == [48.0, -24.0, -24.0, 0.0], "Ready discard win charges source and killed ready player")
	round = fixture()
	round.players[0].concealed = ["wan1", "wan1", "wan2", "wan2", "wan3", "wan3", "wan4", "wan4", "wan5", "wan5", "wan6", "wan6", "wan7", "wan7"]
	round.round_meta.winner = 0
	round.round_meta.self_draw = true
	round.round_meta.flip_tile = "tiao4"
	result = scored(round)
	expect(result.deltas == [198.0, -66.0, -66.0, -66.0], "Seven pairs and flush stack with self draw and no chicken")
	round.round_meta.self_draw = false
	round.round_meta.discard_seat = 2
	result = scored(round)
	expect(result.deltas == [90.0, -14.0, -62.0, -14.0], "Discard winner's patterns are paid by source, chicken points compared with all")
	round.round_meta.winner = -1
	expect(scored(round).deltas == [0.0, 0.0, 0.0, 0.0], "Draw is score-neutral")
	round = fixture()
	round.round_meta.winner = 0
	round.round_meta.self_draw = true
	round.round_meta.flip_tile = "tong9"
	round.players[0].concealed = ["wan2", "wan2", "wan2", "wan4", "wan4", "wan4", "tiao3", "tiao3", "tiao3", "tong5", "tong5", "tong5", "tiao8", "tiao8"]
	expect(scored(round).deltas == [96.0, -32.0, -32.0, -32.0], "Triplets self draw pays fourteen per opponent plus no-chicken and self-draw")
	round.round_meta.self_draw = false
	round.round_meta.discard_seat = 1
	expect(scored(round).deltas == [56.0, -28.0, -14.0, -14.0], "Triplets discard win pays fourteen from source plus no-chicken bonus")
	round = fixture()
	round.players[0].concealed = WIN.duplicate()
	round.round_meta.winner = 0
	round.round_meta.self_draw = true
	round.wall.set_head(40)
	var flip := round.wall.peek_head()
	round._finish()
	expect(round.round_meta.flip_tile == flip, "Flip must be known before settlement")
	expect(round.last_result.points == ScoringEngine.settle(round).points, "Display and actual score must use same flip")

func _test_turns() -> void:
	var round := fixture()
	round.players[0].concealed = WAIT.duplicate()
	round.players[0].concealed.append("tong9")
	round.players[0].just_drew = "tong9"
	expect(not round.submit_turn(0, {"discard": "bad"}), "Reject nonexistent tile")
	expect(round.awaiting, "Invalid action must leave prompt active")
	expect(round.submit_turn(0, {"discard": "tong9", "ready": true}), "First draw-discard can declare ready")
	expect(round.players[0].ready, "Ready must be active")
	round = fixture()
	round.players[0].concealed = ["wan2"]
	round.players[0].just_drew = "wan2"
	round.players[1].concealed = ["wan2", "wan2", "tong5"]
	round.players[2].concealed = ["wan1", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tong1", "tong2", "tong3", "wan9", "wan9"]
	round.submit_turn(0, {"discard": "wan2"})
	expect(round._awaiting_response.get("seat", -1) == 1, "Normal discard win is unavailable without a permitted exception")
	expect(not round.submit_response(1, "wan2", {"action": "win"}), "Plain hand cannot win another player's discard")
	expect(not round.submit_response(2, "wan3", {"action": "win"}), "Reject stale response tile")
	round.submit_response(1, "wan2", {"action": "pong"})
	round.players[1].ready = true
	expect(not round.submit_response(1, "wan2", {"action": "pong"}), "Ready player cannot change hand by pong")

func _rob_fixture() -> RoundState:
	var round := fixture()
	round.players[0].melds = [{"kind": "pung", "tile": "wan9"}]
	round.players[0].concealed = ["wan9", "tiao2", "tiao4", "tiao6", "tong2", "tong4", "tong6", "wan4", "wan5", "wan6", "tiao9"]
	round.players[0].just_drew = "wan9"
	round.players[0].discards = ["wan9"]
	round.players[1].concealed = WAIT.duplicate()
	return round

func _test_rob() -> void:
	var round := _rob_fixture()
	var before := round.wall.remaining
	round.submit_turn(0, {"add_kong": ["wan9"]})
	expect(round._awaiting_response.get("seat", -1) == 1, "Human can choose whether to rob kong")
	expect(round.players[0].melds[0].kind == "pung", "Pending kong must remain a pung")
	round.submit_response(1, "wan9", {"action": "win"})
	expect(round.round_meta.burn_chicken_seat == 0 and round.round_meta.winner == 1, "Rob records burned player and winner")
	expect(round.players[0].discards == ["wan9"], "Rob must not remove an earlier discard of the same value")
	expect(round.wall.remaining == before, "Rob must not draw replacement")
	round = _rob_fixture()
	before = round.wall.remaining
	round.submit_turn(0, {"add_kong": ["wan9"]})
	round.submit_response(1, "wan9", {"action": "pass"})
	expect(round.players[0].melds[0].kind == "add_kong", "Passed rob completes added kong")
	expect(round.wall.remaining == before - 1 and round.awaiting and round.current_turn == 0, "Kong replacement requests a new discard")

func _test_discard_win_restrictions() -> void:
	var normal := fixture()
	var thirteen := WIN.duplicate()
	thirteen.erase("wan9")
	normal.players[1].concealed = thirteen
	expect(not normal.can_win_on_discard(1, 0, "wan9"), "Plain hand cannot win another player's discard")
	normal.players[1].melds = [{"kind": "kong", "tile": "tong9", "concealed": true}]
	normal.players[1].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "wan9"]
	expect(normal.can_win_on_discard(1, 0, "wan9"), "Own concealed kong permits discard win")
	normal.players[1].melds = [{"kind": "kong", "tile": "tong9", "from_seat": 0}]
	expect(not normal.can_win_on_discard(1, 0, "wan9"), "Claimed exposed kong does not count as own kong")
	normal.players[1].ready = true
	expect(normal.can_win_on_discard(1, 0, "wan9"), "Ready winner can win another player's discard")
	normal.players[1].ready = false
	normal.players[0].ready = true
	expect(normal.can_win_on_discard(1, 0, "wan9"), "Discard from a ready player bypasses hand pattern restriction")

	var seven := fixture()
	seven.players[1].concealed = ["wan1", "wan1", "wan2", "wan2", "wan3", "wan3", "wan4", "wan4", "wan5", "wan5", "wan6", "wan6", "wan9"]
	expect(seven.can_win_on_discard(1, 0, "wan9"), "Seven pairs permits discard win")
	var triplets := fixture()
	triplets.players[1].concealed = ["wan1", "wan1", "wan1", "wan2", "wan2", "wan2", "tiao3", "tiao3", "tiao3", "tong4", "tong4", "tong4", "wan9"]
	expect(triplets.can_win_on_discard(1, 0, "wan9"), "All triplets permits discard win")
	var flush := fixture()
	flush.players[1].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "wan2", "wan3", "wan4", "wan9"]
	expect(flush.can_win_on_discard(1, 0, "wan9"), "Flush permits discard win")

	var source_ready := fixture()
	source_ready.players[1].concealed = thirteen.duplicate()
	source_ready.players[0].ready = true
	source_ready.last_discard = {"seat": 0, "tile": "wan9"}
	expect(source_ready.can_win_on_discard(1, 0, "wan9"), "Ready source permits ordinary discard win")
	var after_kong := fixture()
	after_kong.players[1].concealed = thirteen.duplicate()
	after_kong.last_discard = {"seat": 0, "tile": "wan9", "after_kong": true, "kong_kind": "add_kong"}
	expect(after_kong.can_win_on_discard(1, 0, "wan9"), "Post-kong discard permits ordinary discard win")
	var rob := fixture()
	rob.players[1].concealed = thirteen.duplicate()
	rob._pending_kong = {"seat": 0, "tile": "wan9", "index": 0}
	expect(rob.can_win_on_discard(1, 0, "wan9", "rob"), "Robbed added kong permits discard win")

func _test_wall_and_patterns() -> void:
	var expected := [2, 32, 6, 90, 10, 40]
	for die in range(1, 7):
		expect(WallRing.compute_break(die) == expected[die - 1], "Dice break must skip specified stacks")
	var wall := WallRing.new(TileSetFactory.create_deck())
	for seat in 4:
		expect(wall.wall_remaining(seat) == (28 if seat in [0, 2] else 26), "14/13 double stacks")
	expect(not RuleEngine.analyze([], []).win, "Empty hand must not be seven pairs")
	expect(not RuleEngine.analyze(["wan1", "wan1"], []).win, "Incomplete pair must not win")
	var quad_pairs := ["wan1", "wan1", "wan1", "wan1", "wan2", "wan2", "wan3", "wan3", "tiao4", "tiao4", "tong5", "tong5", "tong6", "tong6"]
	expect(RuleEngine.analyze(quad_pairs, []).seven_pairs, "Four identical tiles may form two pairs")
	var round := fixture()
	round.players[0].concealed = WIN.duplicate()
	round.players[0].just_drew = "wan9"
	round._draw_remaining_before = 5
	round._do_self_win(0)
	expect(round.round_meta.last_four_self_draw_seat == -1, "Fifth-from-last is not last-four bonus")
	round = fixture()
	round.players[0].concealed = WIN.duplicate()
	round.players[0].just_drew = "wan9"
	round._draw_remaining_before = 4
	round._kong_draw_turn = true
	round._do_self_win(0)
	expect(round.round_meta.last_four_self_draw_seat == 0 and round.round_meta.kong_draw_seat == 0, "Last-four and kong draw bonuses can stack")

func _test_private_sync() -> void:
	var round := fixture()
	for seat in 4:
		round.players[seat].concealed = WAIT.duplicate()
		round.players[seat].just_drew = "wan9"
	round.players[2].melds = [{"kind": "kong", "tile": "tong8", "concealed": true}]
	var view := round.serialize_for_seat(1)
	expect(view.players[1].concealed == WAIT, "Client retains its own tiles")
	for seat in [0, 2, 3]:
		expect(view.players[seat].concealed.count("hidden0") == 13, "Opponent hands must not be transmitted")
		expect(view.players[seat].just_drew == "hidden0", "Draw identity must stay hidden")
	expect(view.players[2].melds[0].tile == "hidden0", "Opponent concealed kong stays private")
	expect(round.players[2].melds[0].tile == "tong8" and round.players[0].concealed == WAIT, "Privacy filtering cannot alter host state")
	round.phase = "settled"
	expect(round.serialize_for_seat(1).players[0].concealed == WAIT, "Settlement reveals all hands")
