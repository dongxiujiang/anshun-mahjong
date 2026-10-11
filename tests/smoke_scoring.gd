extends SceneTree
## 计分单测：确定性构造结算，验证多退少补与鸡分。
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
	# 对手未叫牌，不补手中鸡；每家只付自摸4分。
	t.expect(a.deltas == [12.0, -4.0, -4.0, -4.0], "未叫牌只补出牌鸡，另付自摸费用; 实际 %s" % str(a.deltas))

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
	# 小七对每家24，加自摸4；未叫牌不补手中鸡。
	t.expect(RuleEngine.analyze(wsel.concealed, wsel.melds).seven_pairs, "应判小七对")
	t.expect(b.deltas == [-28.0, 84.0, -28.0, -28.0], "小七对自摸支付应正确; 实际 %s" % str(b.deltas))

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
	# 放炮者付清一色24；未叫牌不补手中翻牌鸡。
	t.expect(c.deltas == [24.0, 0.0, 0.0, -24.0], "清一色放炮及未叫牌支付应正确; 实际 %s" % str(c.deltas))

	quit(t.finish("smoke_scoring"))
