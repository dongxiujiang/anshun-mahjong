extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var exited := false

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	t.expect(table._settings_button.text == "设置" and table._settings_button.size == table.UI.SETTINGS_BUTTON_SIZE, "Settings uses its own compact touch size")
	t.expect(table._settings_button.get_rect().end.y <= table._table_bounds().position.y, "Settings stays above the playing area")
	table._settings_button.pressed.emit()
	var settings = table._sound_settings
	t.expect(settings.is_open() and settings.speed_buttons.size() == 3, "One settings panel contains sound and three AI speeds")
	t.expect(settings.panel.get_node("ExitRoomButton").size.y >= table.DISCARD_BUTTON_SIZE.y, "Exit entry is large enough to tap")
	table.quit_to_menu.connect(func(): exited = true)
	settings.panel.get_node("ExitRoomButton").pressed.emit()
	t.expect(not exited and settings.exit_confirmation.visible, "Exit asks for confirmation before leaving")
	t.expect(settings.confirm_exit_button.size.y >= 126 and settings.cancel_exit_button.size.y >= 126, "Exit confirmation has large buttons")
	settings.cancel_exit_button.pressed.emit()
	t.expect(not exited and table.is_inside_tree(), "Cancel exit preserves the table")
	settings.close(false)
	# 无牌面变化的重复同步应保留牌控件，包括当前选中的手牌。
	table._refresh()
	var ids: Array = table.hand_box[table.human_seat].get_children().map(func(tile): return tile.get_instance_id())
	var selected: TileView = table.hand_box[table.human_seat].get_child(0)
	table._selected_tile = selected
	selected.set_selected(true)
	var before := Time.get_ticks_usec()
	for index in 30: table._refresh()
	var elapsed := Time.get_ticks_usec() - before
	t.expect(table.hand_box[table.human_seat].get_children().map(func(tile): return tile.get_instance_id()) == ids, "Unchanged updates reuse all hand tile nodes")
	t.expect(table._selected_tile == selected, "Unchanged synchronization preserves a selected tile for touch input")
	before = Time.get_ticks_usec()
	for index in 30:
		table._seat_visual_keys.clear()
		table._refresh()
	var rebuild_elapsed := Time.get_ticks_usec() - before
	print("[table_controls_perf] 30 refreshes: reuse=%d us, rebuild=%d us" % [elapsed, rebuild_elapsed])
	await process_frame
	# 三张鸡碰牌始终竖放，不因冲锋鸡来源而横放。
	for seat in 4:
		for chicken in ["tiao1", "tong8"]:
			var layout: Dictionary = table._meld_tile_layout({"kind": "pung", "tile": chicken, "charge_marker": true, "from_seat": (seat + 3) % 4}, seat, 1.35, 4.0)
			t.expect(layout.sideways == -1 and layout.positions.size() == 3, "Chicken pung stays upright for every seat")
	# 大号下一局底部区域要与玩家结算明细分开。
	table.round.phase = RoundState.Phase.SETTLED
	table.round.last_result = ScoringEngine.settle(table.round)
	table._show_result()
	t.expect(table._next_round_button.size == table.NEXT_ROUND_BUTTON_SIZE and table._next_round_button.size.y == table.DISCARD_BUTTON_SIZE.y, "Next round matches discard touch height")
	var next_bounds: Rect2 = table._next_round_button.get_rect()
	for seat in 4:
		t.expect(not next_bounds.intersects(table._result_panel.get_node("ResultSeat%d" % seat).get_rect()), "Next round never covers score details")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 720)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/new_settlement_controls.png")
		table._toggle_result_panel(false)
		settings.open()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/new_table_settings.png")
		settings.confirm_exit()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/new_exit_confirmation.png")
	table.queue_free()
	await process_frame
	quit(t.finish("table_controls_perf"))
