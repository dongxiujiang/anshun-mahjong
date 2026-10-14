extends SceneTree
## 计分单测：确定性构造结算，验证鸡分差额与鸡分。
## 运行： godot --headless --script res://tests/smoke_scoring.gd

const H := preload("res://tests/test_harness.gd")

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
	# 放炮者付清一色24；完整翻鸡6由三家逐家比较。
	t.expect(c.deltas == [42.0, -6.0, -6.0, -30.0], "清一色放炮及完整翻鸡逐家支付应正确; 实际 %s" % str(c.deltas))

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

	quit(t.finish("smoke_scoring"))
