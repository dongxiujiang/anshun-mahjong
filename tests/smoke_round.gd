extends SceneTree
## 集成冒烟：用简化AI把一局打到底，验证 RoundState+ScoringEngine 流程与牌数守恒、胡牌合法。
## 运行： godot --headless --script res://tests/smoke_round.gd

const H := preload("res://tests/test_harness.gd")

class SimpleAi:
	extends RefCounted
	var name := "ai"
	func _init(n: String): name = n
	func decide_turn(round, seat) -> Dictionary:
		var ps = round.players[seat]
		if RuleEngine.analyze(ps.concealed, ps.melds).win:
			return {"self_win": true}
		var kongs: Array = []
		for c in ps.concealed.duplicate():
			if Tiles.count(ps.concealed, c) >= 4:
				kongs.append(c)
				break
		# 选出向听数最低的舍弃牌
		var best_tile: String = ps.concealed[0]
		var best_sh := 99
		for tile in ps.concealed.duplicate():
			var trial: Array = ps.concealed.duplicate()
			trial.erase(tile)
			var sh := Shanten.shanten(trial, ps.melds)
			if sh < best_sh:
				best_sh = sh
				best_tile = tile
		return {"discard": best_tile, "kong_declares": kongs, "add_kong": [], "ready": false, "self_win": false}
	func decide_response(round, seat, disc_seat, tile, opts) -> Dictionary:
		if opts.get("can_win", false): return {"action": "win"}
		# 只在向听降低时碰
		if opts.get("can_pong", false):
			var ps = round.players[seat]
			var trial: Array = ps.concealed.duplicate()
			trial.erase(tile); trial.erase(tile)
			var trial_melds: Array = ps.melds.duplicate(true)
			trial_melds.append({"kind": "pung", "tile": tile, "robbed": false})
			var sh0 := Shanten.shanten(ps.concealed, ps.melds)
			var sh1 := Shanten.shanten(trial, trial_melds)
			if sh1 <= sh0:
				return {"action": "pong"}
		if opts.get("can_kong", false): return {"action": "kong"}
		return {"action": "pass"}

var _round: RoundState
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[smoke_round] 开始")
	_round = RoundState.new()
	_round.set_rng_seed(42)
	# 4 个同步AI
	var ctrls := []
	for s in 4:
		ctrls.append(SimpleAi.new("ai%d" % (s + 1)))
	_round.controllers = ctrls
	_round.start_round(0, 3)  # human_seat=0, die=3（仅作测试贯穿）
	# 同步控制器会在 start_round 内递归跑到底
	t.expect(_round.phase == RoundState.Phase.SETTLED, "应已结算, 实际 phase=%s" % _round.phase)
	if _round.phase != RoundState.Phase.SETTLED:
		quit(t.finish("smoke_round"))
		return
	# 结算结果
	var res := _round.build_result()
	print("  胜者=%d self_draw=%s flip=%s" % [res.round_meta.winner, res.round_meta.self_draw, res.flip_tile])
	print("  deltas=", res.deltas)
	if res.round_meta.winner >= 0:
		var wps = _round.players[res.round_meta.winner]
		t.expect(RuleEngine.analyze(wps.concealed, wps.melds).win, "胜者手牌应成胡")
		t.expect(is_zero_approx(res.total_delta), "每局总分变化必须为0, 实际 %s" % str(res.total_delta))
	# 牌数守恒：(每人家 hidden+discards + 面子张数) + 墙剩余 == 108
	var accounted := 0
	for ps in _round.players:
		accounted += ps.concealed.size() + ps.discards.size()
		for m in ps.melds:
			accounted += 3 if m.kind == "pung" else 4
	accounted += _round.wall.remaining
	print("  牌守恒: 分配 %d + 墙 %d = %d (目标108)" % [accounted - _round.wall.remaining, _round.wall.remaining, accounted])
	t.expect(accounted == 108, "牌数应守恒, 得 %d" % accounted)

	quit(t.finish("smoke_round"))
