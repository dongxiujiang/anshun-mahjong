extends SceneTree
const H := preload("res://tests/test_harness.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var t := H.new()
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	table.round.opening_delay_seconds = 0.0
	for _i in 400:
		await process_frame
		if table.round.players[1].concealed.size() >= 13: break
	table.round.cancel_opening()
	table._table_animation_controller.cancel()
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table._table_animation_controller._pending_test_deals.clear()
	table._table_animation_controller._deal_animating = false
	table.round.phase = RoundState.Phase.PLAYING
	table.round.current_turn = table.human_seat
	table.round.awaiting = false
	# Opening may already have drawn once before the loop exits.  Normalize the
	# fixture to the exact 13-tile pre-draw state before testing one tap.
	var fixture_player = table.round.players[table.human_seat]
	if fixture_player.concealed.size() > 13:
		fixture_player.concealed = fixture_player.concealed.slice(0, 13)
	fixture_player.just_drew = ""
	table.round._begin_turn()
	for _i in 40: await process_frame
	table._refresh()
	await create_timer(0.5).timeout
	var v2 = table._new_areas
	table._table_layout._hide_legacy_table(table._player_tile_areas)
	await process_frame
	await create_timer(0.1).timeout
	var hs: Array = v2.hand_boxes[1].get_children()
	var lo := INF
	var hi := -INF
	for n in hs:
		lo = minf(lo, n.position.x)
		hi = maxf(hi, n.position.x + n.size.x)
	var center := (lo + hi) * 0.5
	var draw_count: int = v2.draw_boxes[1].get_child_count()
	print("[accept] v2size=", v2.size, " scale=", v2.scale, " pos=", v2.position,
		" surface=", table.surface.size, " surface_scale=", table.surface.scale)
	print("[accept] hand_n=", hs.size(), " center=", center, " table=", 1140.0,
		" draw_n=", draw_count,
		" bar=", table._table_actions.action_bar.get_child_count())
	if DisplayServer.get_name() != "headless":
		var shot := root.get_texture().get_image()
		if shot != null:
			shot.save_png("res://build/accept_godot_01_table.png")
	var tile: TileView = v2.hand_boxes[1].get_child(0)
	var pos: Vector2 = tile.get_global_transform() * (tile.size / 2.0)
	var before: int = table.round.players[1].discards.size()
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		if DisplayServer.get_name() == "headless":
			# Dummy renderer has no GUI hit-test pass; emit the same gui_input
			# signal with local coordinates that the real viewport supplies.
			ev.position = tile.size / 2.0
			tile.gui_input.emit(ev)
		else:
			ev.position = pos
			ev.global_position = pos
			table.get_viewport().push_input(ev)
		await process_frame
	await create_timer(1.6).timeout
	print("[accept] discard=", before, "->", table.round.players[1].discards.size(),
		" selecting=", table._table_actions._selecting,
		" lanes=", table._table_animation_controller._discard_tasks.size(),
		" hand_after=", v2.hand_boxes[1].get_child_count(),
		" draw_after=", v2.draw_boxes[1].get_child_count(),
		" state_hand=", table.round.players[1].concealed.size(),
		" snapshot_hand=", int(v2.snapshot.get("seats", [])[1].get("hand_count", -1)),
		" controller_draw=", bool(table._table_animation_controller._draw_animating),
		" controller_insert=", bool(table._table_animation_controller._insert_animating),
		" v2_busy=", v2.visual_recovery_pending())
	var hand_after: int = v2.hand_boxes[1].get_child_count()
	var draw_after: int = v2.draw_boxes[1].get_child_count()
	for node in table.find_children("*", "", true, false):
		if node is TileView:
			var gp: Vector2 = node.get_global_transform() * (node.size / 2.0)
			if gp.distance_to(Vector2(565, 500)) < 180.0:
				print("[accept] tile ", node.tile, " at ", gp, " kind=", node.get_meta("new_kind", ""),
					" parent=", node.get_parent().name)
	if DisplayServer.get_name() != "headless":
		var shot := root.get_texture().get_image()
		if shot != null:
			shot.save_png("res://build/accept_godot_02_after_tap.png")
	t.expect(hand_after == 13 and draw_after == 0, "出牌后恢复13张手牌且摸牌位清空")
	t.expect(is_equal_approx(center, 1140.0), "手牌居中")
	t.expect(draw_count == 1, "摸牌独立显示")
	t.expect(table.round.players[1].discards.size() == before + 1, "真实点击出牌")
	table.queue_free(); await H.quit_cleanly(self, t.finish("accept_tap_center"))
