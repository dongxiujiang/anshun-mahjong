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
	round.set_rng_seed(20261018)
	round.build_players(0)
	round.controllers = [null, null, null, null]
	round.phase = RoundState.Phase.PLAYING
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
	_test_invariants()
	if not failed:
		print("[rules_complete] scoring, payments, flip, priority, rob/pass, ready, wall and patterns passed")
	quit(1 if failed else 0)

func _test_scoring() -> void:
	var round := fixture()
	var plain := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "wan9"]
	round.players[0].concealed = plain
	round.round_meta.winner = 0
	round.round_meta.winners = [0]
	round.round_meta.self_draw = true
	var result := scored(round)
	expect(result.deltas == [72.0, -24.0, -24.0, -24.0], "四家结算鸡分为0时普通小牌自摸触发大干扣24")
	round.round_meta.self_draw = false
	round.round_meta.discard_seat = 2
	result = scored(round)
	expect(result.deltas == [0.0, 0.0, 0.0, 0.0], "普通点炮不收17/21基础费")
	var big := fixture()
	big.players[0].concealed = ["wan1", "wan1", "wan1", "wan2", "wan2", "wan2", "tong3", "tong3", "tong3", "tiao4", "tiao4", "tiao4", "wan9", "wan9"]
	big.round_meta.winner = 0
	big.round_meta.winners = [0]
	big.round_meta.self_draw = true
	var big_result := scored(big); expect(big_result.deltas == [42.0, -14.0, -14.0, -14.0], "大队子自摸每家付14")
	var clean := fixture()
	clean.players[0].concealed = ["tiao1", "tiao1", "tiao2", "tiao2", "tiao3", "tiao3", "tiao4", "tiao4", "tiao5", "tiao5", "tiao6", "tiao6", "tiao9", "tiao9"]
	clean.round_meta.winner = 0
	clean.round_meta.winners = [0]
	clean.round_meta.self_draw = true
	var clean_result := scored(clean)
	expect(clean_result.items[0].any(func(item): return item.get("label", "") == "清七对" and item.get("amount", 0) == 44), "清七对按44分且不叠加小七对清一色")
	var multi := fixture()
	multi.players[0].concealed = plain.duplicate()
	multi.players[1].concealed = plain.duplicate()
	multi.round_meta.winner = 0
	multi.round_meta.winners = [0, 1]
	multi.round_meta.self_draw = false
	multi.round_meta.discard_seat = 2
	var multi_result := scored(multi)
	expect(multi_result.pairwise[0][2] == 0 and multi_result.pairwise[1][2] == 0, "普通一炮多响不收基础费")
	expect(multi_result.deltas[2] == 0, "普通一炮多响放炮者不支付基础费")
	round = fixture()
	round.players[0].concealed = plain.duplicate()
	round.round_meta.winner = 0
	round.round_meta.winners = [0]
	round.round_meta.self_draw = true
	round.round_meta.kong_draw_seat = 0
	result = scored(round)
	expect(result.deltas == [87.0, -29.0, -29.0, -29.0], "大干扣24加杠开5按每家付款")
	round.round_meta.winner = -1
	round.round_meta.winners = []
	expect(scored(round).deltas == [0.0, 0.0, 0.0, 0.0], "流局不翻鸡且全员未叫不收分")

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
	expect(normal.can_win_on_discard(1, 0, "wan9"), "§十一：报听弃牌者允许普通小牌胡")

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
	expect(source_ready.can_win_on_discard(1, 0, "wan9"), "§十一：报听弃牌者是通行条件")
	var after_kong := fixture()
	after_kong.players[1].concealed = thirteen.duplicate()
	after_kong.last_discard = {"seat": 0, "tile": "wan9", "after_kong": true, "kong_kind": RoundState.KongKind.ADD_KONG}
	expect(after_kong.can_win_on_discard(1, 0, "wan9"), "Post-kong discard permits ordinary discard win")
	after_kong.players[0].discards = ["wan9"]
	after_kong._awaiting_response = {"seat": 1, "disc_seat": 0, "tile": "wan9"}
	after_kong._pending_responders = [1]
	after_kong._response_stage = RoundState.ResponseStage.WIN
	after_kong._process_response(1, 0, "wan9", {"action": "win"})
	expect(after_kong.round_meta.burn_chicken_seat == 0 and after_kong.round_meta.burn_chicken_reason == "after_kong_discard", "Post-kong discard win burns source chickens")
	var exposed_after_kong := fixture()
	exposed_after_kong.players[1].concealed = thirteen.duplicate()
	exposed_after_kong.last_discard = {"seat": 0, "tile": "wan9", "after_kong": true, "kong_kind": RoundState.KongKind.EXPOSED}
	expect(exposed_after_kong.can_win_on_discard(1, 0, "wan9"), "§十一：明杠后也能胡，但不烧鸡")
	exposed_after_kong._pending_responders = [1]
	exposed_after_kong._response_stage = RoundState.ResponseStage.WIN
	exposed_after_kong._process_response(1, 0, "wan9", {"action": "win"})
	expect(exposed_after_kong.round_meta.burn_chicken_seat == -1, "Exposed-kong discard cannot trigger burn chicken")
	var dark_after_kong := fixture()
	dark_after_kong.players[1].concealed = thirteen.duplicate()
	dark_after_kong.players[0].discards = ["wan9"]
	dark_after_kong.last_discard = {"seat": 0, "tile": "wan9", "after_kong": true, "kong_kind": RoundState.KongKind.CONCEALED}
	dark_after_kong._pending_responders = [1]
	dark_after_kong._response_stage = RoundState.ResponseStage.WIN
	dark_after_kong._process_response(1, 0, "wan9", {"action": "win"})
	expect(dark_after_kong.round_meta.burn_chicken_seat == 0, "Post-concealed-kong discard win burns source chickens")
	dark_after_kong.players[0].discards.append_array(["tiao1", "tong8"])
	expect(ScoringEngine.chicken_profile(dark_after_kong, 0, "tiao1").total == 0.0, "Burned kong discarder chicken score is exactly zero")
	var rob := fixture()
	rob.players[1].concealed = thirteen.duplicate()
	rob._pending_kong = {"seat": 0, "tile": "wan9", "index": 0}
	expect(rob.can_win_on_discard(1, 0, "wan9", RoundState.ResponseStage.ROB), "Robbed added kong permits discard win")

func _test_wall_and_patterns() -> void:
	var expected := [2, 86, 6, 36, 10, 94]
	for die in range(1, 7):
		expect(WallRing.compute_break(die) == expected[die - 1], "Dice break must skip specified stacks")
	var wall := WallRing.new(TileSetFactory.create_deck())
	for seat in 4:
		expect(wall.wall_remaining(seat) == (28 if seat in [0, 2] else 26), "14/13 double stacks")
	expect(not RuleEngine.analyze([], []).win, "Empty hand must not be seven pairs")
	expect(not RuleEngine.analyze(["wan1", "wan1"], []).win, "Incomplete pair must not win")
	var quad_pairs := ["wan1", "wan1", "wan1", "wan1", "wan2", "wan2", "wan3", "wan3", "tiao4", "tiao4", "tong5", "tong5", "tong6", "tong6"]
	expect(RuleEngine.analyze(quad_pairs, []).seven_pairs, "Four identical tiles may form two pairs")
	var clean_single := ["tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tiao7", "tiao9", "tiao9"]
	var single_pattern := RuleEngine.analyze(clean_single, [], "tiao9")
	expect(single_pattern.win and not single_pattern.clean_single_wait, "§十六：闭手四顺不能判清单吊")
	expect(not RuleEngine.analyze(clean_single, [], "tiao6").clean_single_wait, "清单吊 requires the actual winning tile to complete the pair")
	var clean_round := fixture()
	clean_round.round_meta.winner = 0
	clean_round.round_meta.self_draw = true
	clean_round.round_meta.win_tile = "tiao9"
	clean_round.players[0].concealed = clean_single.duplicate()
	var clean_result := scored(clean_round)
	expect(clean_result.items[0].any(func(item): return item.get("kind", "") == "pattern" and item.get("label", "") == "清一色" and item.get("amount", 0) == 24), "四顺清一色只计24")
	expect(clean_result.items[0].all(func(item): return item.get("label", "") != "清单吊"), "含顺子不能计清单吊54")
	var clean_big := ["tiao1", "tiao1", "tiao1", "tiao2", "tiao2", "tiao2", "tiao4", "tiao4", "tiao4", "tiao6", "tiao6", "tiao6", "tiao9", "tiao9"]
	var big_pattern := RuleEngine.analyze(clean_big, [])
	expect(big_pattern.clean_big_triplets and RuleEngine.special_pattern_key(big_pattern) == "clean_big_triplets", "清大对 special pattern has priority")
	var dragon := ["tiao1", "tiao1", "tiao1", "tiao1", "tiao2", "tiao2", "tiao3", "tiao3", "tiao5", "tiao5", "tiao7", "tiao7", "tiao9", "tiao9"]
	var dragon_pattern := RuleEngine.analyze(dragon, [])
	expect(dragon_pattern.clean_dragon_seven_pairs and RuleEngine.special_pattern_key(dragon_pattern) == "clean_dragon_seven_pairs", "清龙七对 special pattern has priority")
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
	round.phase = RoundState.Phase.SETTLED
	expect(round.serialize_for_seat(1).players[0].concealed == WAIT, "Settlement reveals all hands")

func _check_settlement_invariants(result: Dictionary, label: String) -> void:
	var matrix: Array = result.pairwise
	var total := 0.0
	for seat in 4:
		expect(is_zero_approx(float(matrix[seat][seat])), "%s 付款矩阵对角线必须为0" % label)
		var row := 0.0
		for other in 4:
			expect(is_zero_approx(float(matrix[seat][other]) + float(matrix[other][seat])), "%s 收付款必须相互抵消" % label)
			row += float(matrix[seat][other])
		expect(is_zero_approx(row - float(result.deltas[seat])), "%s 付款行合计必须等于净分" % label)
		total += float(result.deltas[seat])
	expect(is_zero_approx(total), "%s 四家结算必须零和" % label)

func _tile_accounted(round: RoundState) -> int:
	var accounted := 0
	for player in round.players:
		accounted += player.concealed.size() + player.discards.size()
		for meld in player.melds:
			accounted += 3 if meld.kind == "pung" else 4
	if round.wall != null:
		accounted += round.wall.remaining
	return accounted

func _test_invariants() -> void:
	var plain := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "wan9"]
	var self_draw := fixture()
	self_draw.players[0].concealed = plain.duplicate()
	self_draw.round_meta.winner = 0
	self_draw.round_meta.winners = [0]
	self_draw.round_meta.self_draw = true
	_check_settlement_invariants(ScoringEngine.settle(self_draw), "普通自摸")
	var multi := fixture()
	multi.players[0].concealed = plain.duplicate()
	multi.players[1].concealed = plain.duplicate()
	multi.round_meta.winner = 0
	multi.round_meta.winners = [0, 1]
	multi.round_meta.self_draw = false
	multi.round_meta.discard_seat = 2
	_check_settlement_invariants(ScoringEngine.settle(multi), "一炮多响")
	var live := RoundState.new()
	live.set_rng_seed(20261018)
	live.start_round(0, 1)
	expect(_tile_accounted(live) == 108, "开局发牌后牌墙、手牌、弃牌和碰杠牌必须守恒")
