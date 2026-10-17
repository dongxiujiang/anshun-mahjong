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
	config.animation_speed = "slow"
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
	for speed in ["fast", "slow"]:
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
		if speed == "fast": await _shot("02_dice_hold")
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
	table.round.phase = RoundState.Phase.SETTLED
	table.round.round_meta.winner = 0
	table.round.round_meta.self_draw = true
	table.round.round_meta.flip_tile = "tong3"
	table.round.last_result = {"round_points": [24,0,4,8], "pairwise": [[0,24,20,16],[-24,0,-4,-8],[-20,4,0,-4],[-16,8,4,0]], "status": ["自摸", "未叫牌", "叫牌", "叫牌"], "items": [[{"kind":"bonus", "label":"清一色", "amount":24}], [], [{"kind":"chicken", "label":"普通鸡", "tiles":["tiao1","tong8"], "amount":4}], [{"kind":"charge", "label":"冲锋鸡", "tiles":["tong8"], "amount":4}]]}
	table._show_result()
	await create_timer(0.3).timeout
	await _shot("03_settlement_single")
	# 固定房间样例仅用于渲染，真实准备/取消另由多进程网络测试覆盖。
	var network = root.get_node("Network")
	network.mode = "host"
	var net = network.net_node
	net.game = table.round
	net.my_seat = 0
	net.round_number = 1
	net.lobby = {"ready_round":1, "countdown":-1, "owner":1, "ai_speed":"fast", "seats":[{"name":"你", "ai":false, "ready":false}, {"name":"下家", "ai":true, "ready":true}, {"name":"对家昵称很长也不能遮挡准备按钮", "ai":false, "ready":false}, {"name":"上家", "ai":true, "ready":true}]}
	table._show_result()
	await create_timer(0.3).timeout
	await _shot("04_settlement_ready")
	var footer: Control = table._result_panel.get_node("ReadinessFooter")
	var button: Button = table._next_round_button
	for chip in table._settlement_card._ready_chips:
		t.expect(not Rect2(footer.position + chip.position, chip.size).intersects(button.get_rect()), "Member readiness never overlaps the touch button")
	for member in net.lobby.seats: member.ready = true
	net.lobby.countdown = 1
	table._refresh_next_round_controls()
	await _shot("05_ready_countdown")
	net.lobby.countdown = -1
	net.lobby.seats[2].ready = false
	net.lobby.seats[2]["disconnected"] = true
	table._refresh_next_round_controls()
	await _shot("06_ready_disconnected")
	table._toggle_result_panel(false)
	for dimensions in [Vector2i(960,540), Vector2i(2400,1080)]:
		root.size = dimensions
		await process_frame
		await process_frame
		t.expect(table.surface.get_rect().end.x >= 0, "Landscape surface remains usable")
		await _shot("07_table_%dx%d" % [dimensions.x,dimensions.y])
		table._toggle_result_panel(true)
		await _shot("08_ready_%dx%d" % [dimensions.x,dimensions.y])
		table._toggle_result_panel(false)
	network.mode = ""
	table.queue_free()
	await process_frame
	quit(t.finish("capture_table_controls"))
