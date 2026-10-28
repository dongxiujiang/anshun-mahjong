extends SceneTree
## 计分单测：确定性构造结算，验证鸡分差额与鸡分。
## 运行： godot --headless --script res://tests/smoke_scoring.gd

const H := preload("res://tests/test_harness.gd")
const WIN := preload("res://scripts/core/WinScoring.gd")

const BIG := ["wan1","wan1","wan1","wan2","wan2","wan2","tong3","tong3","tong3","tiao4","tiao4","tiao4","wan9","wan9"]
const FLUSH := ["wan1","wan2","wan3","wan2","wan3","wan4","wan4","wan5","wan6","wan6","wan7","wan8","wan9","wan9"]
const SEVEN := ["wan1","wan1","wan2","wan2","wan4","wan4","tiao2","tiao2","tiao5","tiao5","tong3","tong3","tong7","tong7"]
const DRAGON := ["wan1","wan1","wan1","wan1","wan2","wan2","tiao2","tiao2","tiao5","tiao5","tong3","tong3","tong7","tong7"]
const CLEAN_BIG := ["wan1","wan1","wan1","wan2","wan2","wan2","wan4","wan4","wan4","wan6","wan6","wan6","wan9","wan9"]
const CLEAN_SEVEN := ["wan1","wan1","wan2","wan2","wan3","wan3","wan4","wan4","wan5","wan5","wan6","wan6","wan9","wan9"]
const CLEAN_DRAGON := ["wan1","wan1","wan1","wan1","wan2","wan2","wan3","wan3","wan5","wan5","wan7","wan7","wan9","wan9"]

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[smoke_scoring] 开始")

	# —— 场景A：平胡自摸，手含鸡一条 ----
	var r := RoundState.new()
	r.build_players(0)
	var w = r.players[0]
	# 123条, 456万, 789筒, 345万, 99万 = 平胡（混花色，非清一色）
	w.concealed = ["tiao1","tiao2","tiao3","wan4","wan5","wan6","tong7","tong8","tong9","wan3","wan4","wan5","wan9","wan9"]
	t.expect(RuleEngine.analyze(w.concealed, w.melds).win, "该手应成胡")
	r.round_meta.winner = 0
	r.round_meta.self_draw = true
	r.round_meta.flip_tile = "tiao5"
	var a = ScoringEngine.settle(r)
	print("  A deltas=", a.deltas)
	print("  A lines=", a.lines)
	# 胡牌按完整鸡分逐家比较；未叫牌者也要补胜者手中鸡，再付自摸4分。
	t.expect(a.deltas == [24.0, -8.0, -8.0, -8.0], "胡牌逐家比较完整鸡分并支付自摸费用; 实际 %s" % str(a.deltas))

	# —— 场景B：小七对自摸（每家给24）——
	var r2 := RoundState.new()
	r2.build_players(1)
	r2.round_meta.winner = 1
	r2.round_meta.self_draw = true
	r2.round_meta.flip_tile = ""
	var wsel = r2.players[1]
	wsel.concealed = ["tiao1","tiao1","wan2","wan2","wan3","wan3","tiao4","tiao4","tiao5","tiao5","tong6","tong6","tong7","tong7"]
	var b = ScoringEngine.settle(r2)
	print("  B deltas=", b.deltas)
	# 小七对每家24，加自摸4和手中鸡4。
	t.expect(RuleEngine.analyze(wsel.concealed, wsel.melds).seven_pairs, "应判小七对")
	t.expect(b.deltas == [-28.0, 84.0, -28.0, -28.0], "小七对24已含自摸基础，另逐家支付手中鸡4; 实际 %s" % str(b.deltas))

	# —— 场景C：吃胡（放炮），清一色 ——
	var r3 := RoundState.new()
	r3.build_players(0)
	r3.round_meta.winner = 0
	r3.round_meta.self_draw = false
	r3.round_meta.discard_seat = 3
	r3.round_meta.flip_tile = "wan4"
	var w3 = r3.players[0]
	w3.concealed = ["wan1","wan2","wan3","wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","wan5","wan5"]  # 全万=清一色
	var c = ScoringEngine.settle(r3)
	print("  C deltas=", c.deltas)
	print("  C lines=", c.lines)
	t.expect(RuleEngine.analyze(w3.concealed, w3.melds).flush, "应清一色")
	# 普通弃牌不收17/21基础费；清一色24只由放炮者支付，
	# 其他两家只按翻鸡6分参与两两比较。
	t.expect(c.deltas == [42.0, -6.0, -6.0, -30.0], "清一色放炮：放炮者付牌型分，其他两家只付翻鸡; 实际 %s" % str(c.deltas))
	t.expect(c.pairwise[0][3] == 30.0 and c.pairwise[0][1] == 6.0 and c.pairwise[0][2] == 6.0, "清一色放炮牌型分只进放炮者差额")

	# 24分补足回归：鸡20+自摸4，三家均须付24；准确截图牌面见scoring_pairwise。
	var r4 := RoundState.new()
	r4.build_players(0)
	r4.round_meta.winner = 0
	r4.round_meta.self_draw = true
	r4.round_meta.flip_tile = "tiao1"
	r4.players[0].concealed = ["tiao1", "tiao2", "tiao3", "tiao1", "tiao2", "tiao3", "wan4", "wan5", "wan6", "tong7", "tong8", "tong9", "wan9", "wan9"]
	r4.players[0].discards = ["tiao1"]
	r4.players[0].discard_ids = [0]
	r4.round_meta.charge_chickens = {"tiao1": {"owner": 0, "location": "discard", "discard_id": 0}}
	var d = ScoringEngine.settle(r4)
	t.expect(d.round_points[0] == 24.0 and d.deltas == [72.0, -24.0, -24.0, -24.0], "24分胜者三家逐家补足24; 实际本局%s 收付%s" % [d.round_points[0], d.deltas])
	t.expect(d.pairwise[0][1] == 24.0 and d.pairwise[0][2] == 24.0 and d.pairwise[0][3] == 24.0, "24分场景收付矩阵不能压成20")

	_test_pattern_discards()
	_test_multi_winner_pattern_discards()
	quit(t.finish("smoke_scoring"))

func _meld(tile: String) -> Dictionary:
	return {"kind": "pung", "tile": tile, "from_seat": 1, "concealed": false, "after_discard": 0}

func _four_mixed() -> Array:
	return [_meld("wan1"), _meld("wan2"), _meld("tong3"), _meld("tiao4")]

func _four_clean() -> Array:
	return [_meld("wan1"), _meld("wan2"), _meld("wan4"), _meld("wan6")]

func _check_pattern_discard(pattern_name: String, hand: Array, melds: Array, tile: String, key: String, label: String, score: float) -> void:
	var r := RoundState.new()
	r.build_players(0)
	r.round_meta.winner = 0
	r.round_meta.winners = [0]
	r.round_meta.self_draw = false
	r.round_meta.discard_seat = 3
	r.round_meta.win_tile = tile
	r.round_meta.flip_tile = ""
	var winner = r.players[0]
	winner.concealed = hand.duplicate()
	winner.melds = melds.duplicate(true)
	var pattern := RuleEngine.analyze(hand, melds, tile)
	t.expect(pattern.win, "%s放炮应成胡" % pattern_name)
	var info := WIN._pattern_info(pattern)
	t.expect(info.get("key", "") == key and float(info.get("score", 0.0)) == score, "%s放炮识别为%s" % [pattern_name, key])
	var result := ScoringEngine.settle(r)
	var pattern_items: Array = result.items[0].filter(func(item): return item.get("kind", "") == "pattern")
	t.expect(pattern_items.size() == 1, "%s放炮只有一个牌型项" % pattern_name)
	if pattern_items.size() == 1:
		t.expect(str(pattern_items[0].get("label", "")) == label and float(pattern_items[0].get("amount", 0.0)) == score, "%s放炮牌型分为%.0f" % [pattern_name, score])
	t.expect(float(result.round_points[0]) == score, "%s放炮本局分只算一次" % pattern_name)
	t.expect(float(result.pairwise[0][3]) == score, "%s放炮者付牌型分" % pattern_name)
	t.expect(float(result.pairwise[0][1]) == 0.0 and float(result.pairwise[0][2]) == 0.0, "%s其他两家不付牌型分" % pattern_name)
	t.expect(float(result.deltas[0]) == score and float(result.deltas[3]) == -score, "%s赢家收、放炮者付" % pattern_name)
	t.expect(float(result.deltas[1]) == 0.0 and float(result.deltas[2]) == 0.0, "%s其他两家净变化为0" % pattern_name)
	var pattern_payers := 0
	for transfer in result.transfers:
		if str(transfer.get("reason", "")) != label:
			continue
		pattern_payers += 1
		t.expect(int(transfer.get("from", -1)) == 3 and int(transfer.get("to", -1)) == 0 and float(transfer.get("amount", 0.0)) == score, "%s牌型分只由放炮者转给赢家" % pattern_name)
	t.expect(pattern_payers == 1, "%s只有一笔放炮牌型分" % pattern_name)
	t.expect(is_zero_approx(result.deltas.reduce(func(a, b): return a + b, 0.0)), "%s放炮四家收付相抵" % pattern_name)

func _test_pattern_discards() -> void:
	var cases := [
		["大对子", BIG, [], "wan2", "all_triplets", "大对子", 14.0],
		["大对子单吊", ["wan9", "wan9"], _four_mixed(), "wan9", "big_triplet_single_wait", "大对子单吊", 24.0],
		["小七对", SEVEN, [], "tong7", "seven_pairs", "小七对", 24.0],
		["龙七对", DRAGON, [], "wan1", "dragon_seven_pairs", "龙七对", 44.0],
		["清一色", FLUSH, [], "wan8", "flush", "清一色", 24.0],
		["清大对", CLEAN_BIG, [], "wan6", "clean_big_triplets", "清大对", 34.0],
		["清七对", CLEAN_SEVEN, [], "wan9", "clean_seven_pairs", "清七对", 44.0],
		["清单吊", ["wan9", "wan9"], _four_clean(), "wan9", "clean_single_wait", "清单吊", 54.0],
		["清龙对", CLEAN_DRAGON, [], "wan1", "clean_dragon_seven_pairs", "清龙对", 64.0],
	]
	for entry in cases:
		_check_pattern_discard(str(entry[0]), entry[1], entry[2], str(entry[3]), str(entry[4]), str(entry[5]), float(entry[6]))

func _test_multi_winner_pattern_discards() -> void:
	var r := RoundState.new()
	r.build_players(0)
	r.round_meta.winner = 0
	r.round_meta.winners = [0, 1]
	r.round_meta.self_draw = false
	r.round_meta.discard_seat = 3
	r.round_meta.win_tile = "wan9"
	r.round_meta.flip_tile = ""
	r.players[0].concealed = ["wan1","wan1","wan2","wan2","wan4","wan4","tiao2","tiao2","tiao5","tiao5","tong3","tong3","wan9","wan9"]
	r.players[1].concealed = ["wan1","wan1","wan2","wan2","wan4","wan4","wan5","wan5","wan7","wan7","wan8","wan8","wan9","wan9"]
	var result := ScoringEngine.settle(r)
	t.expect(result.items[0].any(func(item): return item.get("label", "") == "小七对" and float(item.get("amount", 0.0)) == 24.0), "多赢家：小七对24")
	t.expect(result.items[1].any(func(item): return item.get("label", "") == "清七对" and float(item.get("amount", 0.0)) == 44.0), "多赢家：清七对44")
	t.expect(float(result.pairwise[0][3]) == 24.0 and float(result.pairwise[1][3]) == 44.0, "放炮者分别付两家牌型分")
	t.expect(float(result.pairwise[1][0]) == 0.0, "多赢家之间不再互付牌型差额")
	t.expect(not result.transfers.any(func(transfer): return str(transfer.get("reason", "")) == "牌型差额"), "多赢家没有牌型差额流水")
	t.expect(result.deltas == [24.0, 44.0, 0.0, -68.0], "多赢家：放炮者付24+44，其他两家0; 实际 %s" % str(result.deltas))
	var pattern_total := 0.0
	for transfer in result.transfers:
		if str(transfer.get("reason", "")) in ["小七对", "清七对"]:
			pattern_total += float(transfer.get("amount", 0.0))
	t.expect(pattern_total == 68.0, "多赢家放炮牌型分合计68")
