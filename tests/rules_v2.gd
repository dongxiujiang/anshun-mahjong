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
	t.expect(p.all_triplets and p.big_triplet_single_wait, "大队子及大队子单吊判定")
	var seven := ["tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao4","tiao4","tiao5","tiao5","tiao6","tiao6","tiao9","tiao9"]
	p = RuleEngine.analyze(seven, [])
	t.expect(p.clean_seven_pairs and RuleEngine.special_pattern_key(p) == "clean_seven_pairs", "清七对优先于小七对和清一色")
	var dragon := ["tiao1","tiao1","tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao5","tiao5","tiao7","tiao7","tiao9","tiao9"]
	p = RuleEngine.analyze(dragon, [])
	t.expect(p.clean_dragon_seven_pairs and RuleEngine.special_pattern_key(p) == "clean_dragon_seven_pairs", "清龙对判定")
	var single := ["tiao1","tiao2","tiao3","tiao4","tiao5","tiao6","tiao2","tiao3","tiao4","tiao5","tiao6","tiao7","tiao9","tiao9"]
	t.expect(RuleEngine.analyze(single, [], "tiao9").clean_single_wait, "清单吊判定")
	for item in [["小七对", 24.0], ["龙七对", 44.0], ["大队子", 14.0], ["大队子单吊", 24.0], ["清一色", 24.0], ["清大对", 34.0], ["清大队单吊", 44.0], ["清七对", 44.0], ["清单吊", 54.0], ["清龙对", 64.0]]:
		var found := false
		for raw in GameConfig.PATTERNS:
			if raw.label == item[0] and float(raw.score) == item[1]: found = true
		t.expect(found, "%s配置分值" % item[0])

func _test_payments() -> void:
	var ordinary := score(PLAIN)
	t.expect(ordinary.deltas == [72.0, -24.0, -24.0, -24.0], "四家结算鸡分均为0时大干扣24")
	var gun := score(PLAIN, false, 2)
	t.expect(gun.deltas == [4.0, 0.0, -4.0, 0.0], "普通点炮仅放炮者付4")
	var big := ["wan1","wan1","wan1","wan2","wan2","wan2","tong3","tong3","tong3","tiao4","tiao4","tiao4","wan9","wan9"]
	t.expect(score(big).deltas == [42.0, -14.0, -14.0, -14.0], "大队子自摸14")
	var clean := ["tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao4","tiao4","tiao5","tiao5","tiao6","tiao6","tiao9","tiao9"]
	var clean_result := score(clean)
	t.expect(clean_result.items[0].any(func(v): return v.label == "清七对" and v.amount == 44.0), "清七对44且不重复叠加")
	var multi := fixture()
	multi.players[0].concealed = PLAIN.duplicate(); multi.players[1].concealed = PLAIN.duplicate()
	multi.round_meta.winner = 0; multi.round_meta.winners = [0, 1]; multi.round_meta.self_draw = false; multi.round_meta.discard_seat = 2
	var multi_result := ScoringEngine.settle(multi)
	t.expect(multi_result.pairwise[0][2] == 4.0 and multi_result.pairwise[1][2] == 4.0 and multi_result.deltas[2] == -8.0, "一炮多响逐人收取4分")
	var ready := fixture(); ready.players[0].concealed = PLAIN.duplicate(); ready.players[0].ready = true; ready.round_meta.winner = 0; ready.round_meta.winners = [0]; ready.round_meta.self_draw = true
	t.expect(ScoringEngine.settle(ready).deltas == [72.0, -24.0, -24.0, -24.0], "报听普通胡牌每家付24")
	var killed := fixture(); killed.players[0].concealed = PLAIN.duplicate(); killed.players[1].concealed = PLAIN.duplicate(); killed.players[1].ready = true; killed.round_meta.winner = 0; killed.round_meta.winners = [0]; killed.round_meta.self_draw = true
	var killed_result := ScoringEngine.settle(killed)
	t.expect(killed_result.deltas[1] == -48.0 and killed_result.deltas[0] == 96.0, "大干扣24与杀报24按各自规则计付")
	var dry := fixture(); dry.players[0].concealed = PLAIN.duplicate(); dry.players[1].concealed = WAIT.duplicate(); dry.players[1].discards = ["tiao1"]; dry.players[1].discard_ids = [0]
	dry.round_meta.charge_chickens = {"tiao1": {"owner": 1, "location": "discard", "discard_id": 0}}
	dry.round_meta.winner = 0; dry.round_meta.winners = [0]; dry.round_meta.self_draw = true
	var dry_result := ScoringEngine.settle(dry)
	t.expect(dry_result.items[0].any(func(v): return v.label == "干扣" and v.amount == 14.0), "另有叫牌玩家鸡分时普通无鸡自摸按干扣14")

func _test_draw_and_kong() -> void:
	var r := fixture()
	r.players[0].concealed = WAIT.duplicate(); r.players[1].concealed = WAIT.duplicate()
	r.players[0].discards = ["tiao1"]; r.players[1].discards = ["tong8"]
	r.players[0].discard_ids = [0]; r.players[1].discard_ids = [0]
	r.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}, "tong8": {"owner": 1, "location": "discard", "discard_id": 0}}
	var draw := ScoringEngine.settle(r)
	t.expect(draw.deltas == [8.0, 8.0, -8.0, -8.0], "荒牌双方出牌鸡相加后逐家补付")
	var k := fixture(); k.players[0].concealed = MELD_WAIT.duplicate(); k.players[0].melds = [{"kind": "kong", "tile": "wan7", "concealed": true}]; k.players[1].concealed = WAIT.duplicate(); k.round_meta.winner = -1
	var kd := ScoringEngine.settle(k)
	t.expect(kd.deltas == [8.0, 0.0, -4.0, -4.0], "叫牌暗杠由每家未叫者支付4")

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
