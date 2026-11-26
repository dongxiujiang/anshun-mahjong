extends SceneTree
const Assist = preload("res://src/app/TingAssistantOverlay.gd")
const Table = preload("res://src/presentation/TableView.gd")
const TileArt = preload("res://src/presentation/TileArt.gd")
const TableTheme = preload("res://src/presentation/TableTheme.gd")
const ActionFX = preload("res://src/app/ActionEffectsStage.gd")
const Progress = preload("res://src/app/PlayerProgress.gd")
const Career = preload("res://src/app/CareerPanel.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL smart assist: " + label)

func _run() -> void:
	# 1. 验证清一色听牌、剩余张数与严禁偷看别家暗杠规则
	var own_hand := []
	var vals := ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","wan2","wan3","wan5","wan5","tiao9"]
	for i in vals.size():
		own_hand.append({"id": i, "value": vals[i]})
	var fake_view := {
		"prompt_id": 7,
		"phase": "turn",
		"viewer_seat": 1,
		"choices": {"discard_ids": range(14)},
		"players": [
			{"seat": 0, "hand": [], "discards": [{"id": 30, "value": "wan1"}, {"id": 31, "value": "wan4"}], "discard_count": 2,
				"melds": [{"kind": "kong", "concealed": true, "tile": "wan4", "formed_at": 1}]},
			{"seat": 1, "hand": own_hand, "discards": [], "discard_count": 1, "melds": [], "ready": false},
			{"seat": 2, "hand": [], "discards": [{"id": 40, "value": "wan4"}], "discard_count": 5,
				"melds": [{"kind": "pung", "concealed": false, "tile": "tong2", "formed_at": 2}]},
			{"seat": 3, "hand": [], "discards": [], "discard_count": 1, "melds": []},
		],
	}
	var seen := Assist.visible_counts(fake_view, 1)
	check(int(seen.get("wan1", 0)) == 2, "counts own hand + public discard for wan1")
	check(int(seen.get("wan4", 0)) == 3, "counts own wan4 + two public discards, NEVER peeks at seat 0 hidden concealed kong")
	check(int(seen.get("tong2", 0)) == 3, "counts public pung meld")
	var discards := Assist.analyze_discards(fake_view, 1)
	check(discards.has("tiao9"), "discarding tiao9 enters tenpai")
	if discards.has("tiao9"):
		var entry: Dictionary = discards["tiao9"]
		var wait_tiles: Array = entry.waits.map(func(w): return w.tile)
		check(wait_tiles.has("wan1") and wait_tiles.has("wan4"), "wan2+wan3 waits on wan1 and wan4")
		check(entry.best_label == "清一色", "detects authoritative Anshun flush pattern: " + str(entry.best_label))
		for w in entry.waits:
			if w.tile == "wan1":
				check(int(w.remaining) == 2, "wan1 has 2 remaining visible copies")
			elif w.tile == "wan4":
				check(int(w.remaining) == 1, "wan4 has 1 remaining visible copy")

	# 2. 验证手牌抬起仅显示已出张数 + 常驻听牌胶囊（摸牌不消失，改听实时更新）
	var overlay := Assist.new()
	overlay.size = Vector2(1602, 720)
	root.add_child(overlay)
	await process_frame
	var anchor := Rect2(Vector2(20, 650), Vector2(128, 52))
	# 抬起 wan4（牌桌上 seat0 弃1张 + seat2 弃1张 = 已出 2 张，不含手中暗牌也不偷看暗杠）
	overlay.sync_state(fake_view, 1, 3, true, anchor, Vector2(600, 580))
	check(overlay._popup.visible and overlay._popup_label.text == "4万 · 已出 2 张", "lifting hand tile shows only table played count: " + overlay._popup_label.text)
	overlay.sync_state(fake_view, 1, -1, true, anchor)
	check(not overlay._popup.visible, "deselecting hides played-count pill")
	# 13 张听牌态应持续展示在玩家名字和分数上方
	fake_view.players[1].hand = own_hand.slice(0, 13)
	fake_view.prompt_id = 8
	overlay.sync_state(fake_view, 1, -1, true, anchor)
	check(overlay._badge.visible and overlay._badge.position.y + overlay._badge.size.y <= anchor.position.y, "13-tile tenpai hand shows persistent ting strip directly above own badge")
	# 摸第 14 张牌时，听牌胶囊持续显示不消失！
	fake_view.players[1].hand = own_hand.duplicate(true)
	fake_view.prompt_id = 9
	overlay.sync_state(fake_view, 1, -1, true, anchor)
	check(overlay._badge.visible, "drawing 14th tile keeps persistent ting badge visible without flickering away")
	# 出牌改听后，听牌内容实时更新
	var changed_hand := []
	for i in ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","tong2","tong3","tong5","tong5"].size():
		changed_hand.append({"id": i, "value": ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","tong2","tong3","tong5","tong5"][i]})
	fake_view.players[1].hand = changed_hand
	fake_view.prompt_id = 10
	overlay.sync_state(fake_view, 1, -1, true, anchor)
	var new_waits: Array = overlay._cache_ready_waits.map(func(w): return w.tile)
	check(overlay._badge.visible and new_waits.has("tong1") and new_waits.has("tong4") and not new_waits.has("wan1"), "changing tenpai after discard immediately updates displayed waits")
	overlay.show_toast("智能排法 1/2", 0.2)
	check(overlay._toast.visible, "smart sort toast appears cleanly")
	if overlay._toast_tween != null and overlay._toast_tween.is_valid():
		overlay._toast_tween.kill()
	overlay.free()

	# 3. 验证 TableView 多主题切换 + 同牌柔光高亮 + AI 参谋微光 + 翻鸡爆光 + 动作特效舞台
	var table := Table.new()
	root.add_child(table)
	await process_frame
	for tid in TableTheme.TABLE_ORDER:
		for bid in TableTheme.TILE_BACK_ORDER:
			table.apply_theme(tid, bid)
	check(table._table_theme_id == TableTheme.TABLE_ORDER[-1] and table._tile_back_id == TableTheme.TILE_BACK_ORDER[-1], "all table & tile back themes apply cleanly")
	table._place(10, "wan5", Transform3D.IDENTITY, "discard", false)
	table._place(11, "wan5", Transform3D.IDENTITY, "hand", false)
	table._place(12, "tiao1", Transform3D.IDENTITY, "chicken", false)
	table.set_match_highlight("wan5")
	check(table.tiles[10].material_override == TileArt.highlight_material("match"), "matching public tile highlights softly")
	check(table.tiles[11].material_override == TileArt.material(true), "hand tile stays normal during match highlight")
	table.set_hint_tile(11)
	check(table.tiles[11].material_override == TileArt.highlight_material("hint"), "AI advisor highlights recommended hand tile")
	table.set_chicken_highlights([12])
	check(table.tiles[12].material_override == TileArt.highlight_material("chicken"), "chicken reveal highlights matched chicken tile")
	table.clear_chicken_highlights()
	table.set_match_highlight("")
	table.set_hint_tile(-1)
	check(table.tiles[10].material_override == TileArt.material(true) and table.tiles[12].material_override == TileArt.material(true), "clearing highlights restores base resin material")
	table.free()

	var fx := ActionFX.new()
	fx.size = Vector2(1602, 720)
	root.add_child(fx)
	for kind in ["pong", "kong", "concealed_kong", "add_kong", "ready", "charge_chicken", "burn_chicken"]:
		fx.play_action(kind, 0)
	fx.play_chicken_banner("翻鸡揭晓 · 冲锋金鸡×2", 2)
	await process_frame
	check(fx._bursts.size() > 0 and not fx._banner.is_empty(), "action effects stage drives all burst kinds and chicken banner")
	fx.clear_all()
	fx.free()

	# 4. 验证本地生涯统计、连胜、大牌图鉴解锁与持久化及战绩界面构建
	var cpath := "user://career-test-%d.cfg" % Time.get_ticks_usec()
	var prog := Progress.new(cpath)
	var fake_settlement := {
		"round_meta": {"self_draw": true},
		"ledger": {
			"winners": [1],
			"deltas": [-18, 54, -18, -18],
			"items": [[], [
				{"kind": "pattern", "label": "清一色", "amount": 10, "tiles": ["wan1"]},
				{"kind": "charge", "label": "冲锋金鸡", "amount": 8, "tiles": ["tiao1"]},
				{"kind": "bonus", "label": "杠开", "amount": 4, "tiles": []},
			], [], []],
		},
	}
	var m1 := prog.record_settlement("r1/1", fake_settlement, 1)
	check(m1.won and int(prog.stats.wins) == 1 and int(prog.stats.best_round_gain) == 54, "records win and best round gain")
	check(prog.unlocked.has("first_win") and prog.unlocked.has("flush_master") and prog.unlocked.has("charge_chicken") and prog.unlocked.has("gold_chicken") and prog.unlocked.has("kong_bloom"), "unlocks all achieved Anshun badges")
	var m_dup := prog.record_settlement("r1/1", fake_settlement, 1)
	check(m_dup.is_empty() and int(prog.stats.rounds) == 1, "duplicate settlement key never double-counts")
	prog.record_settlement("r1/2", fake_settlement, 1)
	prog.record_settlement("r1/3", fake_settlement, 1)
	check(int(prog.stats.streak) == 3 and prog.unlocked.has("streak_3") and prog.rank_title() == "竹林雀士", "tracks 3-win streak and rank progression")
	var reloaded := Progress.new(cpath)
	check(int(reloaded.stats.wins) == 3 and reloaded.unlocked.has("flush_master"), "career progress persists across reload")
	var panel := Career.new()
	root.add_child(panel)
	panel.build(reloaded, "牌友测试")
	await process_frame
	check(panel.get_child_count() >= 3, "career panel builds cleanly")
	panel.free()
	DirAccess.remove_absolute(cpath)
	await process_frame
	print("Smart assist & FX: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
