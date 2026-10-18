extends SceneTree
## 真实窗口验证开局时序、点牌出牌与联机准备区域；截图保存在 build/ 下。
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var table
var directory := "res://build/ui_review/table_controls"

func _initialize() -> void: call_deferred("_run")

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name + ".png"))

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720)
	root.get_node("UpdateManager").auto_check = false
	var config = root.get_node("GameConfig")
	config.animation_speed = "standard"
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null,null,null,null]
	var controller = table._table_animation_controller
	var start := Time.get_ticks_msec()
	var submissions: Array = []
	table.enable_net(func(decision): submissions.append(decision), Callable())
	var deadline := start + 12000
	var partial := false
	while (table.round.phase == RoundState.Phase.DEALING or controller.input_locked()) and Time.get_ticks_msec() < deadline:
		table._commit_turn({"discard": table.round.players[0].concealed[0]})
		if controller._dealt[0] > 0 and controller._dealt[0] < 13: partial = true
		await process_frame
	t.expect(submissions.is_empty(), "Neither human input nor direct submission can overtake actual opening animations")
	t.expect(partial and controller._dealt == [13,13,13,13], "All 16 clockwise deal batches complete visually before unlock")
	t.expect(table.round.phase == RoundState.Phase.PLAYING and table.round.awaiting and table.round.wall.remaining == 55, "Opening preserves the dealer draw and wall count")
	t.expect(Time.get_ticks_msec() - start >= int(config.OPENING_WAIT_SECONDS * 1000), "Visual unlock cannot precede the authoritative opening deadline")
	t.expect(not controller.input_locked() and table.draw_box[0].get_child(0).interactive, "The drawn tile becomes clickable after its slow animation finishes")
	# Replaying a draw event against the current snapshot verifies the visual
	# contract independently from the opening timer: the tile is already visible
	# in the draw slot before movement starts, then remains visible after it lands.
	var replay_draw: TileView = table.draw_box[0].get_child(0)
	var replay_id: int = int(controller._animation_last_id) + 1
	controller._on_visual_event({"id": replay_id, "type": "draw", "seat": 0, "tile": str(table.round.players[0].just_drew), "kind": "head"})
	controller.refresh_masks()
	t.expect(is_equal_approx(replay_draw.modulate.a, 1.0), "Replay draw keeps the slot visible before animation starts")
	while controller._animation_busy or not controller._animation_queue.is_empty(): await process_frame
	t.expect(is_equal_approx(replay_draw.modulate.a, 1.0), "Replay draw reveals the slot after animation finishes")
	await _shot("01_table")
	# 验证按钮可见区域下方的扩大热区通过实际 GUI 命中设置入口。
	var setting_tap := InputEventMouseButton.new()
	setting_tap.button_index = MOUSE_BUTTON_LEFT
	setting_tap.position = table._settings_button.global_position + Vector2(20, (table._settings_button.size.y + 20) * table.surface.scale.y)
	setting_tap.pressed = true
	Input.parse_input_event(setting_tap)
	await process_frame
	setting_tap.pressed = false
	Input.parse_input_event(setting_tap)
	await process_frame
	t.expect(table._sound_settings.is_open(), "Expanded settings hit area opens the panel without enlarging its visible button")
	table._sound_settings.close(false)
	# 两档设置都要保留真正的 0.5 秒落定停留。
	for speed in ["instant", "standard"]:
		config.animation_speed = speed
		var layer = table._animation_layer
		await process_frame
		await create_timer(0.05).timeout
		await process_frame
		start = Time.get_ticks_msec()
		layer.play({"type": "dice", "value": 6})
		await create_timer(config.OPENING_DICE_SECONDS + 0.06).timeout
		var die = layer._temporary[0] if not layer._temporary.is_empty() else null
		t.expect(die != null and die.value == 6 and is_equal_approx(die.rotation, TAU), "Final dice face is stationary in " + speed)
		if speed == "instant": await _shot("02_dice_hold")
		while layer._active != null: await process_frame
		print("[capture_table_controls] dice %s: %d ms" % [speed, Time.get_ticks_msec() - start])
		t.expect(Time.get_ticks_msec() - start >= 1650, "Dice roll and fixed half-second hold ignore per-client speed")
	# 完整一次点牌，输入经界面边界提交，但不在客户端本地改变牌局。
	table._on_require_turn(0)
	table._update_interactivity()
	var drawn: TileView = table.draw_box[0].get_child(0)
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = drawn.get_global_rect().get_center()
	Input.parse_input_event(down)
	await process_frame
	down.pressed = false
	Input.parse_input_event(down)
	await process_frame
	t.expect(submissions.size() == 1, "Native touchscreen input reaches the rendered tile and submits exactly once")
	table.round.round_meta.winner = 0
	table.round.round_meta.winners = [0]
	table.round.round_meta.self_draw = true
	table.round.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "wan2", "wan3", "wan4", "wan9", "wan9"]
	table.round.players[0].just_drew = "wan9"
	table.round.wall._ring[table.round.wall._head] = "tong3"
	table.round._finish()
	table._table_animation_controller.reset()
	var settlement = table._settlement_animation_controller
	settlement.reset()
	table._refresh()
	settlement.skip()
	await create_timer(0.3).timeout
	t.expect(settlement.is_completed() and settlement.boards.size() == 4 and table._settlement_card._post_controls.visible, "Single-player settlement shows tabletop payments and bottom next-round controls")
	await _shot("03_settlement_single")
	# 固定房间样例仅用于渲染，真实准备/取消另由多进程网络测试覆盖。
	var network = root.get_node("Network")
	network.mode = "host"
	var net = network.net_node
	net.game = table.round
	net.my_seat = 0
	net.round_number = 1
	net.lobby = {"ready_round":1, "countdown":-1, "owner":1, "ai_speed":"fast", "seats":[{"name":"你", "ai":false, "ready":false}, {"name":"下家", "ai":true, "ready":true}, {"name":"对家昵称很长也不能遮挡准备按钮", "ai":false, "ready":false}, {"name":"上家", "ai":true, "ready":true}]}
	table._settlement_card.show_post_settlement_controls()
	await create_timer(0.3).timeout
	await _shot("04_settlement_ready")
	var button: Button = table._next_round_button
	t.expect(table._next_round_status.text.contains("2 / 4") and not button.disabled, "Bottom readiness summary counts prepared AI seats")
	for control in [table._next_round_status, table._next_round_hint] + settlement.boards.values():
		t.expect(not control.get_global_rect().intersects(button.get_global_rect()), "Readiness text and tabletop payments never overlap the touch button")
	for member in net.lobby.seats: member.ready = true
	net.lobby.countdown = 1
	table._refresh_next_round_controls()
	t.expect(table._next_round_status.text.contains("4 / 4") and table._next_round_hint.text.contains("1 秒"), "Bottom controls render the all-ready countdown")
	await _shot("05_ready_countdown")
	net.lobby.countdown = -1
	net.lobby.seats[2].ready = false
	net.lobby.seats[2]["disconnected"] = true
	table._refresh_next_round_controls()
	t.expect(table._next_round_status.text.contains("3 / 4") and not button.text.contains("1 秒"), "Disconnect cancels the displayed countdown and updates readiness")
	await _shot("06_ready_disconnected")
	for dimensions in [Vector2i(960,540), Vector2i(2400,1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var screen_rect := Rect2(Vector2.ZERO, Vector2(dimensions))
		t.expect(screen_rect.encloses(button.get_global_rect()) and table._settlement_card._post_controls.visible, "Landscape bottom readiness control remains visible")
		for board in settlement.boards.values():
			t.expect(screen_rect.encloses(board.get_global_rect()) and not board.get_global_rect().intersects(button.get_global_rect()), "Resized tabletop payments stay visible and clear of the ready button")
		t.expect(settlement.layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Settlement does not add a blocking overlay after resize")
		await _shot("07_tabletop_ready_%dx%d" % [dimensions.x,dimensions.y])
	network.mode = ""
	table.queue_free()
	await process_frame
	quit(t.finish("capture_table_controls"))
