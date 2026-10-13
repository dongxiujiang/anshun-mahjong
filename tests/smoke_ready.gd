extends SceneTree
## 定向验证：报听窗口（各自第一手）+ 报听后"不能换牌"(摸切)。
## 运行： godot --headless --script res://tests/smoke_ready.gd

const H := preload("res://tests/test_harness.gd")

const TENPAI13 := ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","wan5","wan5","wan2","wan4"]  # 等 wan3

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[smoke_ready] 开始")

	# ---- 1) 首手听牌 → 可报听 ----
	var r := RoundState.new()
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.phase = RoundState.Phase.PLAYING
	var ps = r.players[0]
	ps.concealed = TENPAI13.duplicate()
	ps.concealed.append("tong1")      # 14 张，打 tong1 后听牌
	ps.just_drew = "tong1"
	t.expect(r.can_declare_ready(0), "首手应处于报听窗口")
	t.expect(RuleEngine.is_tenpai(TENPAI13, []), "TENPAI13 应听牌")
	r._apply_turn_action(0, {"discard": "tong1", "ready": true})
	t.expect(ps.ready, "报听应生效")
	t.expect(ps.first_turn_done, "首手已打完")
	t.expect(not r.can_declare_ready(0), "非首手应关闭报听窗口")
	print("[ok] 首手报听生效；窗口随后关闭")

	# ---- 2) 报听后不能换牌：摸什么打什么 ----
	var ps2 = r.players[1]
	ps2.ready = true
	ps2.first_turn_done = true
	ps2.concealed = TENPAI13.duplicate()
	ps2.concealed.append("tiao9")     # 摸到 tiao9
	ps2.just_drew = "tiao9"
	# 玩家想打 wan1（换牌）→ 应被强制改为摸切 tiao9
	r.current_turn = 1
	r._apply_turn_action(1, {"discard": "wan1", "kong_declares": [], "add_kong": [], "ready": false, "self_win": false})
	var last: String = ps2.discards[ps2.discards.size() - 1]
	t.expect(last == "tiao9", "报听后应摸切 tiao9, 实际 %s" % last)
	print("[ok] 报听后强制摸切（尝试换牌被忽略）")

	quit(t.finish("smoke_ready"))
