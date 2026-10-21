extends Node
## 渲染截图：加载 GameTable（单机），数帧后把视口存成 PNG，便于人工核对牌面/排版。
## 需以窗口模式运行（非 --headless）： godot res://tests/shot_scene.tscn

func _ready() -> void:
	_run()

func _run() -> void:
	var table = load("res://scenes/GameTable.tscn").instantiate()
	add_child(table)
	await get_tree().process_frame
	# 自动代打真人座位若干回合，让盘面有弃牌/碰杠，便于视觉核对
	var t := 0.0
	while t < 2.2 and table.round != null and table.round.phase != RoundState.Phase.SETTLED:
		await get_tree().process_frame
		t += 0.016
		var r = table.round
		if not r.awaiting: continue
		if not r._awaiting_response.is_empty():
			if r._awaiting_response.seat == table.human_seat:
				var ps = r.players[table.human_seat]
				var tile = r._awaiting_response.tile
				var act = "pong" if Tiles.count(ps.concealed, tile) >= 2 else "pass"
				r.submit_response(table.human_seat, tile, {"action": act})
		elif r.current_turn == table.human_seat:
			var ps = r.players[table.human_seat]
			# 真人已有碰杠且轮到他时停下截图：验证"碰杠多了→手牌右移、保持一牌间距"
			if ps.just_drew != "" and ps.melds.size() >= 1:
				break
			if not ps.concealed.is_empty():
				r.submit_turn(table.human_seat, {"discard": ps.concealed[ps.concealed.size() - 1], "kong_declares": [], "add_kong": [], "ready": false, "self_win": false})
	for i in 3:
		await get_tree().process_frame
	for s in [0, 1, 2, 3]:
		for z in ["hand", "draw", "meld"]:
			var box = table.get(z + "_box").get(s)
			var kind := "VBox" if box is VBoxContainer else "HBox"
			print("[shot] seat=%d %s %s pos=%s n=%d" % [s, z, kind, str(box.position), box.get_child_count()])
		for i in 3:
			var db = table.discard_box[s][i]
			print("[shot] seat=%d disc%d pos=%s n=%d" % [s, i + 1, str(db.position), db.get_child_count()])
	var img: Image = get_viewport().get_texture().get_image()
	var out := "user://shot_table.png"
	img.save_png(out)
	print("[shot] 已保存 ", ProjectSettings.globalize_path(out), "  size=", img.get_size())
	get_tree().quit(0)
