extends SceneTree
## AI 自战多局：验证真实 AI 能稳定打完、产生胡牌、牌数守恒、分数可负。
## 运行： godot --headless --script res://tests/smoke_ai.gd

const H := preload("res://tests/test_harness.gd")
const ORACLE := preload("res://tests/settlement_oracle.gd")

const ROUNDS := 24

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rounds := ROUNDS
	var requested := OS.get_environment("AI_ROUNDS")
	if requested.is_valid_int():
		rounds = maxi(1, int(requested))
	var minimum_rounds := 1
	var minimum_requested := OS.get_environment("AI_MIN_ROUNDS")
	if minimum_requested.is_valid_int():
		minimum_rounds = maxi(1, int(minimum_requested))
	t.expect(rounds >= minimum_rounds, "配置要求至少%d局 AI 对战，当前为%d局" % [minimum_rounds, rounds])
	print("[smoke_ai] 开始 共%d局" % rounds)
	var stats := {"win": 0, "penzu": 0, "self": 0}
	var tiles_ok := true
	for i in rounds:
		var r := RoundState.new()
		r.set_rng_seed(1000 + i)
		var ctrls := []
		for s in 4:
			ctrls.append(AiPlayer.new("AI%d" % s))
		r.controllers = ctrls
		r.start_round(0, -1)
		if not t.expect(r.phase == RoundState.Phase.SETTLED, "第%d局应结算, 实际 phase=%s" % [i, r.phase]):
			continue
		var res = r.last_result
		ORACLE.check(r, res, t, "AI局%d" % i)
		t.expect(is_zero_approx(res.total_delta), "第%d局总分变化必须为0, 实际 %s" % [i, str(res.total_delta)])
		var scores_total := 0.0
		for player in r.players:
			scores_total += player.score
		t.expect(scores_total == 800.0, "第%d局四人总分必须保持800, 实际 %s" % [i, str(scores_total)])
		var w: int = res.round_meta.winner
		if w >= 0:
			stats.win += 1
			if res.round_meta.self_draw: stats.self += 1
			var wps = r.players[w]
			t.expect(RuleEngine.analyze(wps.concealed, wps.melds).win,
				"局%d 胜者手牌不成胡: concealed=%s melds=%s" % [i, str(wps.concealed), str(wps.melds)])
		else:
			stats.penzu += 1
		# 牌守恒
		var accounted := 0
		for ps in r.players:
			accounted += ps.concealed.size() + ps.discards.size()
			for m in ps.melds:
				accounted += 3 if m.kind == "pung" else 4
		accounted += r.wall.remaining
		# 多家同胡同一张弃牌时，每位赢家都需要把胡牌张放入逻辑手牌；
		# 这张牌只有一张实体牌，因此守恒统计要扣除共享的重复引用。
		if not bool(res.round_meta.get("self_draw", false)):
			accounted -= maxi(0, res.round_meta.get("winners", []).size() - 1)
		if not t.expect(accounted == 108, "局%d 牌不守恒: %d" % [i, accounted]):
			tiles_ok = false
		# 打印每局胜负
		print("  局%d: winner=%d self=%s deltas=%s" % [i, w, res.round_meta.self_draw, str(res.deltas)])
	print("[smoke_ai] 统计: 胡=%d 流局=%d 自摸=%d; 牌守恒=%s" % [stats.win, stats.penzu, stats.self, tiles_ok])
	t.expect(stats.win >= 1, "应至少出现1次胡牌")

	quit(t.finish("smoke_ai"))
