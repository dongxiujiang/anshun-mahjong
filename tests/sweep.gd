extends SceneTree
## 多种子扫描：统计胡/流局、碰/杠/加杠/抢杠/报听/自摸/点炮 出现次数，并打印含碰杠的局。
## 运行： godot --headless --script res://tests/sweep.gd
## 这是统计工具而非严格单测：只断言每局都能正常结算，其余数字仅供观察。

const H := preload("res://tests/test_harness.gd")

const N := 30

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var stat := {"win": 0, "penzu": 0, "self": 0, "rob": 0, "pung": 0, "kong": 0, "ready": 0, "robkong": 0}
	var shown := 0
	for i in N:
		var r := RoundState.new()
		r.set_rng_seed(70000 + i)
		var ctrls: Array = []
		for s in 4:
			ctrls.append(AiPlayer.new("AI%d" % s))
		r.controllers = ctrls
		r.start_round(0, -1)
		var m: Dictionary = r.round_meta
		if not t.expect(r.phase == RoundState.Phase.SETTLED, "第%d局未结算, phase=%s" % [i, r.phase]):
			continue
		if m.winner >= 0:
			stat.win += 1
			if m.self_draw: stat.self += 1
			else: stat.rob += 1
			if m.get("burn_chicken_seat", -1) >= 0: stat.robkong += 1
		else:
			stat.penzu += 1
		var mp := 0; var mk := 0; var mr := 0
		for ps in r.players:
			for md in ps.melds:
				if md.kind == "pung": mp += 1
				else: mk += 1
			if ps.ready: mr += 1
		stat.pung += mp; stat.kong += mk; stat.ready += mr
		# 打印含碰或杠的局
		if (mp + mk) > 0 and shown < 6:
			shown += 1
			var melds_txt := []
			for ps in r.players:
				for md in ps.melds:
					melds_txt.append("%s:%s%s" % [ps.name_label, md.kind, md.tile])
			print("  局%d 胜者=%s 面子=[%s] 报听人=%d" % [i, "流局" if m.winner < 0 else r.players[m.winner].name_label, ", ".join(melds_txt), mr])
	t.expect(stat.win >= 1, "%d 局中应至少出现1次胡牌" % N)
	print("════ %d 局统计 ════" % N)
	print("胡=%d（自摸%d 点炮%d） 流局=%d" % [stat.win, stat.self, stat.rob, stat.penzu])
	print("碰=%d 杠=%d 报听人次=%d 抢杠=%d" % [stat.pung, stat.kong, stat.ready, stat.robkong])

	quit(t.finish("sweep"))
