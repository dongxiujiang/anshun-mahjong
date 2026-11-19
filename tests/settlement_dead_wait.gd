extends SceneTree
## 真实快照：七条已明杠，手中八九条仍按死叫结算；不放宽实际胡牌。
const H := preload("res://tests/test_harness.gd")
const WIN := preload("res://scripts/core/WinScoring.gd")
const PLAN := preload("res://scripts/ui/table/SettlementAnimationPlan.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _fixture() -> RoundState:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dead_wait_snapshot.json"))
	var r := RoundState.new()
	r.build_players(1)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.SETTLED
	r.dealer_seat = 3
	r.round_meta.merge(data.round_meta, true)
	r.round_meta.winners = data.round_meta.winners.map(func(seat): return int(seat))
	for seat in 4:
		var player: PlayerState = r.players[seat]
		player.concealed = data.players[seat].concealed.duplicate()
		player.melds = data.players[seat].melds.duplicate(true)
		player.discards = data.players[seat].discards.duplicate()
		player.discard_ids = data.players[seat].discard_ids.duplicate()
	return r

func _paid(result: Dictionary, payer: int, receiver: int, reason: String) -> float:
	var amount := 0.0
	for row in result.transfers:
		if row.from == payer and row.to == receiver and row.reason == reason:
			amount += float(row.amount)
	return amount

func _run() -> void:
	var r := _fixture()
	var player: PlayerState = r.players[1]
	var before := r.serialize()
	var scored := ScoringEngine.settle(r)
	print("snapshot called=%s deltas=%s pairs=%s" % [scored.called, scored.deltas, scored.pairwise[1]])
	t.expect(scored.called == [true, true, false, true], "snapshot: own dead wait counts as called")
	t.expect(scored.deltas == [5.0, 5.0, -47.0, 37.0], "snapshot: independently calculated four-player deltas")
	t.expect(scored.pairwise[1] == [2.0, 0.0, 12.0, -9.0], "snapshot: own relative payments are +2, +12, -9")
	t.expect(scored.points[1] == 2.0, "snapshot: called hand chicken earns two")
	t.expect(_paid(scored, 0, 1, "明杠") == 4.0, "snapshot: source pays kong owner four")
	t.expect(_paid(scored, 1, 0, "未叫牌杠分") == 0.0, "snapshot: no reversed uncalled kong debt")
	t.expect(r.serialize() == before, "settlement does not mutate the actual tiles")
	t.expect(RuleEngine.waiting_tiles(player.concealed, player.melds).is_empty(), "dead wait grants no drawable winning tile")
	t.expect(not RuleEngine.can_win_on(player.concealed, player.melds, "tiao7"), "fifth seven-bamboo cannot actually win")
	player.ready = true
	t.expect(not r.can_win_on_discard(1, 0, "tiao7", RoundState.ResponseStage.WIN), "ready does not permit a fifth-tile discard win")
	t.expect(not r.can_win_on_discard(1, 0, "tiao7", RoundState.ResponseStage.ROB), "dead wait does not permit a fifth-tile rob-kong win")
	player.ready = false
	r.last_result = scored.duplicate(true)
	r.last_result.erase("called") # 正式网络结果也可只通过 status 传递查叫状态。
	for viewer in 4:
		var state := r.serialize_for_seat(viewer)
		var peer := RoundState.new()
		peer.apply_sync(state)
		t.expect(peer.last_result.status[1] == "叫牌", "network viewer %d retains called status" % viewer)
		t.expect(ScoringEngine.settle(peer).deltas == scored.deltas, "network viewer %d recomputes identical money" % viewer)
		var plan := PLAN.build(peer.last_result, peer.round_meta, state.players, viewer)
		t.expect(plan.called[1] and plan.deltas[1] == 5.0, "network viewer %d shows called marker and +5" % viewer)
		peer = null
	r.round_meta.chicken_multiplier = 2
	t.expect(ScoringEngine.settle(r).deltas == [10.0, 10.0, -94.0, 74.0], "dead-wait payments are doubled only once")
	r = null
	# 同样的四张上限也可能出现在手牌内，或碰牌加手中一张的单吊中。
	var four_held := ["wan1", "wan1", "wan1", "wan1", "tiao2", "tiao3", "tiao4", "tong3", "tong4", "tong5", "wan6", "wan7", "wan8"]
	t.expect(RuleEngine.waiting_tiles(four_held, []).is_empty(), "four held copies have no actual winning draw")
	t.expect(RuleEngine.settlement_patterns(four_held, []).keys() == ["wan1"], "four held copies still form a settlement dead wait")
	var fixed := [{"kind": "pung", "tile": "wan1"}, {"kind": "pung", "tile": "tiao2"}, {"kind": "pung", "tile": "tong3"}, {"kind": "pung", "tile": "wan6"}]
	t.expect(not RuleEngine.can_win_on(["wan1"], fixed, "wan1"), "fixed pung plus singleton cannot claim a fifth tile")
	t.expect(WIN.potential_pattern_info(["wan1"], fixed).get("score", 0.0) == 24.0, "dead single wait retains big-triplet-single-wait24")
	# 三类杠均按同样的结构查叫；清一色死叫仍收牌型24，不降为基础4。
	for kind in ["exposed", "concealed", "add_kong"]:
		r = _fixture()
		r.round_meta.winner = -1
		r.round_meta.winners = []
		r.round_meta.flip_tile = ""
		for seat in 4:
			r.players[seat].concealed = []
			r.players[seat].melds = []
			r.players[seat].discards = []
		player = r.players[1]
		player.concealed = ["tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tiao8", "tiao9", "tiao2", "tiao2"]
		player.melds = [{"kind": "add_kong" if kind == "add_kong" else "kong", "tile": "tiao7", "from_seat": 0, "concealed": kind == "concealed"}]
		scored = ScoringEngine.settle(r)
		t.expect(scored.called[1], "%s dead wait is called in a draw" % kind)
		t.expect(WIN.potential_pattern_info(player.concealed, player.melds).get("score", 0.0) == 24.0, "%s dead wait keeps flush pattern" % kind)
		for payer in [0, 2, 3]:
			t.expect(_paid(scored, payer, 1, "荒牌牌型分") == 24.0, "%s uncalled payer %d pays flush24" % [kind, payer])
		for seat in [0, 2, 3]:
			r.players[seat].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
		scored = ScoringEngine.settle(r)
		t.expect(scored.all_called_draw and scored.deltas == [0.0, 0.0, 0.0, 0.0], "%s all-called draw includes dead wait and zeros every payment" % kind)
		t.expect(scored.next_chicken_multiplier == 2, "all-called dead-wait draw still doubles next round")
		# 杠后放炮的17/21档位也使用相同查叫结果。
		r.round_meta.winner = 3
		r.round_meta.winners = [3]
		r.round_meta.self_draw = false
		r.round_meta.discard_seat = 1
		r.round_meta.win_tile = "wan9"
		r.players[3].concealed.append("wan9")
		r.last_discard = {"seat": 1, "tile": "wan9", "after_kong": true, "kong_kind": RoundState.KongKind.CONCEALED}
		scored = ScoringEngine.settle(r)
		t.expect(_paid(scored, 1, 3, "点炮基础分（叫牌）") == 17.0, "%s dead-wait post-kong discarder uses called fee17" % kind)
		r = null
	# 五张同牌已经存在于原始手牌/碰杠中属于坏数据，不能借死叫放宽。
	r = _fixture()
	r.players[1].concealed[0] = "tiao7"
	t.expect(not ScoringEngine.is_called(r, 1), "already invalid five-copy ownership is rejected")
	r = null
	quit(t.finish("settlement_dead_wait"))
