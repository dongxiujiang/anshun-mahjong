extends SceneTree
## 最新安顺捉鸡规则独立回归：牌型、逐人付款、荒牌、过牌锁和一炮多响。
const H := preload("res://tests/test_harness.gd")
var t := H.new()
const PLAIN := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "wan9"]
const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
const MELD_WAIT := ["wan1", "wan2", "wan3", "tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]

func _initialize() -> void: call_deferred("_run")

func fixture() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261018)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	r.awaiting = true
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	return r

func score(hand: Array, self_draw: bool = true, source: int = -1) -> Dictionary:
	var r := fixture()
	r.players[0].concealed = hand.duplicate()
	r.round_meta.winner = 0
	r.round_meta.winners = [0]
	r.round_meta.self_draw = self_draw
	r.round_meta.discard_seat = source
	return ScoringEngine.settle(r)

func _run() -> void:
	_test_config_and_patterns()
	_test_payments()
	_test_draw_and_kong()
	_test_response_locks()
	quit(t.finish("rules_v2"))

func _test_config_and_patterns() -> void:
	t.expect(GameConfig.SCORE_KONG_DRAW == 5.0 and GameConfig.SCORE_LAST_FOUR == 5.0, "杠开与海底均为5分")
	var big := ["wan1","wan1","wan1","wan2","wan2","wan2","tong3","tong3","tong3","tiao4","tiao4","tiao4","wan9","wan9"]
	var p := RuleEngine.analyze(big, [], "wan9")
	t.expect(p.all_triplets and not p.big_triplet_single_wait, "闭手大对子并非手牌只剩一张的单吊")
	var seven := ["tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao4","tiao4","tiao5","tiao5","tiao6","tiao6","tiao9","tiao9"]
	p = RuleEngine.analyze(seven, [])
	t.expect(p.clean_seven_pairs and RuleEngine.special_pattern_key(p) == "clean_seven_pairs", "清七对优先于小七对和清一色")
	var dragon := ["tiao1","tiao1","tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao5","tiao5","tiao7","tiao7","tiao9","tiao9"]
	p = RuleEngine.analyze(dragon, [])
	t.expect(p.clean_dragon_seven_pairs and RuleEngine.special_pattern_key(p) == "clean_dragon_seven_pairs", "清龙对判定")
	var single := ["tiao1","tiao2","tiao3","tiao4","tiao5","tiao6","tiao2","tiao3","tiao4","tiao5","tiao6","tiao7","tiao9","tiao9"]
	t.expect(not RuleEngine.analyze(single, [], "tiao9").clean_single_wait, "有顺子不是清单吊")
	for item in [["小七对", 24.0], ["龙七对", 44.0], ["大对子", 14.0], ["大对子单吊", 24.0], ["清一色", 24.0], ["清大对", 34.0], ["清七对", 44.0], ["清单吊", 54.0], ["清龙对", 64.0]]:
		var found := false
		for raw in GameConfig.PATTERNS:
			if raw.label == item[0] and float(raw.score) == item[1]: found = true
		t.expect(found, "%s配置分值" % item[0])

func _test_payments() -> void:
	var ordinary := score(PLAIN)
	t.expect(ordinary.deltas == [72.0, -24.0, -24.0, -24.0], "四家结算鸡分均为0时大干扣24")
	var gun := score(PLAIN, false, 2)
	t.expect(gun.deltas == [0.0, 0.0, 0.0, 0.0], "普通点炮不收17/21基础费")
	var big := ["wan1","wan1","wan1","wan2","wan2","wan2","tong3","tong3","tong3","tiao4","tiao4","tiao4","wan9","wan9"]
	t.expect(score(big).deltas == [42.0, -14.0, -14.0, -14.0], "大对子自摸14")
	var clean := ["tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao4","tiao4","tiao5","tiao5","tiao6","tiao6","tiao9","tiao9"]
	var clean_result := score(clean)
	t.expect(clean_result.items[0].any(func(v): return v.label == "清七对" and v.amount == 44.0), "清七对44且不重复叠加")
	var multi := fixture()
	multi.players[0].concealed = PLAIN.duplicate(); multi.players[1].concealed = PLAIN.duplicate()
	multi.round_meta.winner = 0; multi.round_meta.winners = [0, 1]; multi.round_meta.self_draw = false; multi.round_meta.discard_seat = 2
	var multi_result := ScoringEngine.settle(multi)
	t.expect(multi_result.pairwise[0][2] == 0.0 and multi_result.pairwise[1][2] == 0.0 and multi_result.deltas[2] == 0.0, "普通一炮多响不收基础费")
	var ready := fixture(); ready.players[0].concealed = PLAIN.duplicate(); ready.players[0].ready = true; ready.round_meta.winner = 0; ready.round_meta.winners = [0]; ready.round_meta.self_draw = true
	t.expect(ScoringEngine.settle(ready).deltas == [72.0, -24.0, -24.0, -24.0], "报听普通自摸每家24，不再加自摸4")
	var killed := fixture(); killed.players[0].concealed = PLAIN.duplicate(); killed.players[1].concealed = PLAIN.duplicate(); killed.players[1].ready = true; killed.round_meta.winner = 0; killed.round_meta.winners = [0]; killed.round_meta.self_draw = true
	var killed_result := ScoringEngine.settle(killed)
	t.expect(killed_result.deltas == [72.0, -24.0, -24.0, -24.0], "自摸杀报只由报听者支付24，不再另付自摸4")
	var seven_ready := fixture()
	seven_ready.players[0].concealed = ["tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao4","tiao4","tiao5","tiao5","tiao6","tiao6","tiao9","tiao9"]
	seven_ready.players[1].ready = true
	seven_ready.round_meta.winner = 0
	seven_ready.round_meta.winners = [0]
	seven_ready.round_meta.self_draw = true
	var seven_result := ScoringEngine.settle(seven_ready)
	var ready_pattern := 0.0
	for transfer in seven_result.transfers:
		if int(transfer.get("from", -1)) == 1 and int(transfer.get("to", -1)) == 0 \
			and str(transfer.get("reason", "")) == "清七对":
			ready_pattern += float(transfer.get("amount", 0.0))
	t.expect(is_equal_approx(ready_pattern, 44.0), "报听付款者仍付完整牌型分，但不额外加自摸4")
	var multi_ready := fixture()
	multi_ready.players[0].concealed = PLAIN.duplicate()
	multi_ready.players[1].ready = true
	multi_ready.players[2].ready = true
	multi_ready.round_meta.winner = 0
	multi_ready.round_meta.winners = [0]
	multi_ready.round_meta.self_draw = true
	var multi_ready_result := ScoringEngine.settle(multi_ready)
	var kill_by_payer := {}
	for transfer in multi_ready_result.transfers:
		if str(transfer.get("reason", "")) == "杀报":
			kill_by_payer[int(transfer.get("from", -1))] = float(transfer.get("amount", 0.0))
	t.expect(kill_by_payer.get(1, 0.0) == 24.0 and kill_by_payer.get(2, 0.0) == 24.0,
		"多个报听付款者各付一份杀报24")
	t.expect(multi_ready_result.pairwise[0][3] == 24.0,
		"未报听第三家仍按普通自摸/干扣支付")
	t.expect(multi_ready_result.pairwise[0][1] == 24.0 and multi_ready_result.pairwise[0][2] == 24.0,
		"报听付款者不再另付自摸4")
	var multi_winner := fixture()
	multi_winner.players[0].concealed = PLAIN.duplicate()
	multi_winner.players[1].concealed = PLAIN.duplicate()
	multi_winner.players[2].ready = true
	multi_winner.round_meta.winner = 0
	multi_winner.round_meta.winners = [0, 1]
	multi_winner.round_meta.self_draw = false
	multi_winner.round_meta.discard_seat = 2
	var multi_winner_result := ScoringEngine.settle(multi_winner)
	var kill_to := {}
	for transfer in multi_winner_result.transfers:
		if str(transfer.get("reason", "")) == "杀报":
			kill_to[int(transfer.get("to", -1))] = float(transfer.get("amount", 0.0))
	t.expect(kill_to.get(0, 0.0) == 24.0 and kill_to.get(1, 0.0) == 24.0,
		"一个报听放炮者向每个未报听赢家各付一份杀报24")
	var dry := fixture(); dry.players[0].concealed = PLAIN.duplicate(); dry.players[1].concealed = WAIT.duplicate(); dry.players[1].discards = ["tiao1"]; dry.players[1].discard_ids = [0]
	dry.round_meta.charge_chickens = {"tiao1": {"owner": 1, "location": "discard", "discard_id": 0}}
	dry.round_meta.winner = 0; dry.round_meta.winners = [0]; dry.round_meta.self_draw = true
	var dry_result := ScoringEngine.settle(dry)
	t.expect(dry_result.items[0].any(func(v): return v.label == "干扣" and v.amount == 14.0), "另有叫牌玩家鸡分时普通无鸡自摸按干扣14")
	var all_uncalled_dry := fixture()
	all_uncalled_dry.players[0].concealed = PLAIN.duplicate()
	for seat in [1, 2, 3]:
		all_uncalled_dry.players[seat].concealed = ["wan1", "wan2", "wan9"]
		all_uncalled_dry.players[seat].discards = ["tiao1", "tong8"]
		all_uncalled_dry.players[seat].discard_ids = [0, 1]
	all_uncalled_dry.round_meta.winner = 0
	all_uncalled_dry.round_meta.winners = [0]
	all_uncalled_dry.round_meta.self_draw = true
	var all_uncalled_result := ScoringEngine.settle(all_uncalled_dry)
	t.expect(all_uncalled_result.items[0].any(func(v): return v.label == "大干扣" and v.amount == 24.0),
		"其他玩家都未叫牌时大干扣，即使他们各自有打出鸡")
	var called_clean_dry := fixture()
	called_clean_dry.players[0].concealed = PLAIN.duplicate()
	called_clean_dry.players[1].concealed = WAIT.duplicate()
	for seat in [2, 3]:
		called_clean_dry.players[seat].concealed = ["wan1", "wan2", "wan9"]
		called_clean_dry.players[seat].discards = ["tiao1", "tong8"]
	called_clean_dry.round_meta.winner = 0
	called_clean_dry.round_meta.winners = [0]
	called_clean_dry.round_meta.self_draw = true
	var called_clean_result := ScoringEngine.settle(called_clean_dry)
	t.expect(called_clean_result.items[0].any(func(v): return v.label == "大干扣" and v.amount == 24.0),
		"有叫牌玩家且叫牌玩家无鸡时，未叫牌玩家的鸡不阻止大干扣")
	var called_chicken_dry := fixture()
	called_chicken_dry.players[0].concealed = PLAIN.duplicate()
	called_chicken_dry.players[1].concealed = WAIT.duplicate()
	called_chicken_dry.players[1].discards = ["tong8"]
	called_chicken_dry.round_meta.winner = 0
	called_chicken_dry.round_meta.winners = [0]
	called_chicken_dry.round_meta.self_draw = true
	var called_chicken_result := ScoringEngine.settle(called_chicken_dry)
	t.expect(called_chicken_result.items[0].any(func(v): return v.label == "干扣" and v.amount == 14.0),
		"叫牌玩家有鸡时只能干扣14")
	var draw_pattern := fixture()
	draw_pattern.players[0].concealed = ["tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao4","tiao4","tiao5","tiao5","tiao6","tiao6","tiao9"]
	for seat in [1, 2, 3]:
		draw_pattern.players[seat].concealed = ["wan1", "wan2", "wan9"]
	draw_pattern.round_meta.winner = -1
	draw_pattern.round_meta.winners = []
	draw_pattern.round_meta.self_draw = false
	var draw_pattern_result := ScoringEngine.settle(draw_pattern)
	var draw_fee := 0.0
	for transfer in draw_pattern_result.transfers:
		if int(transfer.get("from", -1)) == 1 and int(transfer.get("to", -1)) == 0 \
			and str(transfer.get("reason", "")) == "荒牌牌型分":
			draw_fee += float(transfer.get("amount", 0.0))
	t.expect(is_equal_approx(draw_fee, 44.0), "流局叫牌清七对时未叫者付44，替代基础4")
	t.expect(draw_pattern_result.deltas[0] == 132.0 and draw_pattern_result.deltas[1] == -44.0,
		"流局牌型补付按每个未叫者分别支付")
	var draw_no_pattern := fixture()
	draw_no_pattern.players[0].concealed = WAIT.duplicate()
	draw_no_pattern.players[1].concealed = ["wan1", "wan2", "wan9"]
	draw_no_pattern.round_meta.winner = -1
	draw_no_pattern.round_meta.winners = []
	draw_no_pattern.round_meta.self_draw = false
	var no_pattern_result := ScoringEngine.settle(draw_no_pattern)
	var no_pattern_base := false
	for transfer in no_pattern_result.transfers:
		if int(transfer.get("from", -1)) == 1 and int(transfer.get("to", -1)) == 0 \
			and str(transfer.get("reason", "")) == "荒牌基础补付" \
			and is_equal_approx(float(transfer.get("amount", 0.0)), 4.0):
			no_pattern_base = true
	t.expect(no_pattern_base, "叫牌无牌型时流局仍付基础4")
	var draw_multi := fixture()
	draw_multi.players[0].concealed = ["tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao4","tiao4","tiao5","tiao5","tiao6","tiao6","tiao9"]
	draw_multi.players[1].concealed = WAIT.duplicate()
	draw_multi.players[2].concealed = ["wan1", "wan2", "wan9"]
	draw_multi.round_meta.winner = -1
	draw_multi.round_meta.winners = []
	draw_multi.round_meta.self_draw = false
	var draw_multi_result := ScoringEngine.settle(draw_multi)
	var multi_fees := {}
	for transfer in draw_multi_result.transfers:
		if int(transfer.get("from", -1)) == 2:
			multi_fees[int(transfer.get("to", -1))] = float(transfer.get("amount", 0.0))
	t.expect(is_equal_approx(multi_fees.get(0, 0.0), 44.0) and is_equal_approx(multi_fees.get(1, 0.0), 4.0),
		"多家叫牌时未叫者分别向叫牌者支付各自牌型分/基础4")
	var chicken_sources := [
		{"name": "手中幺鸡", "discards": [], "melds": [], "flip": "", "hand": ["tiao1"] + PLAIN.slice(1)},
		{"name": "打出八筒", "discards": ["tong8"], "melds": [], "flip": "", "hand": PLAIN},
		{"name": "暗杠幺鸡", "discards": [], "melds": [{"kind": "kong", "tile": "tiao1", "concealed": true}], "flip": "", "hand": PLAIN},
		{"name": "明杠八筒", "discards": [], "melds": [{"kind": "kong", "tile": "tong8", "from_seat": 1}], "flip": "", "hand": PLAIN},
		{"name": "加杠幺鸡", "discards": [], "melds": [{"kind": "add_kong", "tile": "tiao1", "from_seat": 1}], "flip": "", "hand": PLAIN},
		{"name": "翻鸡万二", "discards": [], "melds": [], "flip": "wan2", "hand": PLAIN},
	]
	for source in chicken_sources:
		var r := fixture()
		r.players[0].concealed = source.hand.duplicate()
		r.players[0].melds = source.melds.duplicate(true)
		r.players[0].discards = source.discards.duplicate()
		r.round_meta.winner = 0
		r.round_meta.winners = [0]
		r.round_meta.self_draw = true
		r.round_meta.flip_tile = source.flip
		var result := ScoringEngine.settle(r)
		var dry_labels: Array = result.items[0].filter(func(v): return v.label in ["干扣", "大干扣"])
		t.expect(dry_labels.is_empty(), "赢家有%s时不能干扣/大干扣" % source.name)

func _test_draw_and_kong() -> void:
	var r := fixture()
	r.players[0].concealed = WAIT.duplicate(); r.players[1].concealed = WAIT.duplicate()
	r.players[0].discards = ["tiao1"]; r.players[1].discards = ["tong8"]
	r.players[0].discard_ids = [0]; r.players[1].discard_ids = [0]
	r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}, "tong8": {"owner": 1, "location": "discard", "discard_id": 0}}
	var draw := ScoringEngine.settle(r)
	t.expect(draw.deltas == [16.0, 16.0, -16.0, -16.0], "荒牌双方出牌鸡相加并补基础4分")
	var k := fixture(); k.players[0].concealed = MELD_WAIT.duplicate(); k.players[0].melds = [{"kind": "kong", "tile": "wan7", "concealed": true}]; k.players[1].concealed = WAIT.duplicate(); k.round_meta.winner = -1
	var kd := ScoringEngine.settle(k)
	t.expect(kd.deltas == [16.0, 8.0, -12.0, -12.0], "荒牌暗杠与基础补付分别向未叫者收取")

func _test_response_locks() -> void:
	var r := fixture(); r.players[1].concealed = ["wan1","wan1","wan1"]
	var options := r.legal_response_options(1, 0, "wan1", RoundState.ResponseStage.MELD)
	t.expect(options.can_pong and options.can_kong, "三张同牌可选择碰或杠")
	r.players[1].concealed = ["wan1","wan1"]
	options = r.legal_response_options(1, 0, "wan1", RoundState.ResponseStage.MELD)
	t.expect(options.can_pong and not options.can_kong, "两张同牌可以碰")
	r.players[1].passed_win_until_draw = true
	t.expect(not r.can_win_on_discard(1, 0, "wan1"), "过胡后下一摸前不能再胡")
	r.players[1].passed_win_until_draw = false
	r.players[1].passed_pong_tiles.append("wan1")
	t.expect(not r.legal_response_options(1, 0, "wan1", RoundState.ResponseStage.MELD).can_pong, "过碰后同牌不能再碰")
	r.players[1].passed_pong_tiles.clear()
	r.players[1].forbidden_discard_tile = "wan1"
	var turn_options := r.legal_turn_options(1)
	t.expect(not turn_options.discards.has("wan1"), "碰牌后不能立即打出刚碰的同一张牌")
	var seven_wait := ["tiao1","tiao1","wan2","wan2","wan4","wan4","tiao5","tiao5","tong6","tong6","tong8","tong8","wan9"]
	r.players[2].concealed = seven_wait
	t.expect(r.can_win_on_discard(2, 0, "wan9"), "小七对可胡别人打出的牌")
