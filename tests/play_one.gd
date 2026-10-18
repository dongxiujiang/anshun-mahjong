extends SceneTree
## 完整打一局并打印全程战报（骰子/摸打/碰杠/胡/结算明细），用于人工核对。
## 用法： godot --headless --script res://tests/play_one.gd

# 带日志的AI：委托 AiPlayer 决策并打印
class LogAi extends AiPlayer:
	var tag := ""
	func _init(t: String):
		super(t)
		tag = t
	static func _c(t: String) -> String:
		if t == "": return "-"
		var sn := {"wan": "万", "tiao": "条", "tong": "筒"}
		return "%d%s" % [Tiles.rank(t), sn.get(Tiles.suit(t), Tiles.suit(t))]
	func decide_turn(round, seat: int) -> Dictionary:
		var ps = round.players[seat]
		var drew: String = ps.just_drew
		var d := super.decide_turn(round, seat)
		if d.get("self_win", false):
			print("  %s 摸到 %s → 自摸胡！" % [tag, _c(drew)])
			return d
		for k in d.get("kong_declares", []):
			print("  %s 暗杠 %s" % [tag, _c(k)])
		for a in d.get("add_kong", []):
			print("  %s 加杠 %s" % [tag, _c(a)])
		if d.get("ready", false):
			print("  %s 报听！" % tag)
		if drew != "":
			print("  %s 摸 %s → 打 %s" % [tag, _c(drew), _c(d.get("discard", ""))])
		return d
	func decide_response(round, seat: int, disc_seat: int, tile: String, opts: Dictionary) -> Dictionary:
		var d := super.decide_response(round, seat, disc_seat, tile, opts)
		var a: String = d.get("action", "pass")
		match a:
			"win": print("  %s 胡 %s（%s 打的）" % [tag, _c(tile), round.players[disc_seat].name_label])
			"pong": print("  %s 碰 %s" % [tag, _c(tile)])
			"kong": print("  %s 杠 %s" % [tag, _c(tile)])
		return d

func _initialize() -> void:
	_run()
	quit(0)

func _run() -> void:
	var seed_val := 20261008
	var r := RoundState.new()
	r.set_rng_seed(seed_val)
	var tags := ["庄家", "下家", "对家", "上家"]
	var ctrls: Array = []
	for s in 4:
		ctrls.append(LogAi.new("%s(AI)" % tags[s]))
	r.controllers = ctrls

	print("════════ 完整一局战报（seed=%d） ════════" % seed_val)
	var deal_box := []
	r.dealt.connect(func(info): deal_box.append(info))
	r.start_round(0, -1)
	var m: Dictionary = r.round_meta
	print("掷骰 D=%d → 破墙起点=环位%d" % [m.get("die", -1), m.get("break", -1)])
	if deal_box.size() > 0:
		print("发牌张数：", deal_box[0].map(func(x): return "%s=%d" % [r.players[x.seat].name_label, x.count]))
	print("———— 行牌 ————")
	# 行牌过程已在 start_round 内同步执行并打印
	print("———— 结算 ————")
	print("胜者：%s   %s" % ["无人（流局）" if m.winner < 0 else r.players[m.winner].name_label, "自摸" if m.self_draw else ("点炮：%s" % r.players[m.discard_seat].name_label if m.winner >= 0 and m.discard_seat != null else "")])
	if m.winner >= 0:
		var w = r.players[m.winner]
		var wm: Array = []
		for x in w.concealed: wm.append(x)
		for x in w.melds: wm.append("[%s]" % x.tile)
		print("胡牌手：", wm)
		var chk: Dictionary = RuleEngine.analyze(w.concealed, w.melds)
		print("自校验：合法胡牌=%s  普通=%s 七对=%s 大对子=%s 清一色=%s" % [chk.win, chk.normal, chk.seven_pairs, chk.all_triplets, chk.flush])
		print("翻牌：", m.get("flip_tile", ""), " 冲锋鸡归属：", m.get("charge_chickens", {}))
	for line in r.last_result.get("lines", []):
		print("  · ", line)
	print("本局净分：", r.last_result.get("deltas", []))
	print("各家总分：")
	for p in r.players:
		print("  %s : %.0f" % [p.name_label, p.score])
