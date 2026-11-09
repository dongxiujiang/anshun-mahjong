extends SceneTree
## 拆分后多牌桌隔离、提交边界、动画取消和退出生命周期回归。
const H := preload("res://tests/test_harness.gd")
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	# CLI --script loads before autoloads; defer scene loading like other UI suites.
	var scene: PackedScene = load("res://scenes/GameTable.tscn")
	var first = scene.instantiate()
	var second = scene.instantiate()
	first.human_seat = 0
	second.human_seat = 0
	root.add_child(first)
	root.add_child(second)
	await process_frame
	for table in [first, second]:
		table.round.cancel_opening()
		table.round.phase = RoundState.Phase.PLAYING
		table.round.current_turn = table.human_seat
		table.round.awaiting = false
		table._table_animation_controller._pending_test_deals.clear()
		table._table_animation_controller._dealt = [13, 13, 13, 13]
		table._table_animation_controller._deal_animating = false
		if table._new_areas != null:
			table._new_areas.auto_sort_hands = false
			table._new_areas.test_deal_only = false
			table._new_areas.test_frozen = false
			table._new_areas._sort_started = true
			table._new_areas._frozen_hands.clear()
			table._new_areas.deal_animation_active = false
			table._new_areas._sort_animating = false
			table._new_areas._draw_flights.clear()
		for player in table.round.players:
			if player.concealed.is_empty():
				player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
					"wan7", "wan8", "wan9", "tiao1", "tiao2", "tiao3", "tiao4"]
	first._table_animation_controller.reset()
	second._table_animation_controller.reset()
	for table in [first, second]:
		table._table_animation_controller._dealt = [13, 13, 13, 13]
		table._table_animation_controller._deal_animating = false
		if table._new_areas != null:
			table._new_areas.test_frozen = false
			table._new_areas.deal_animation_active = false
			table._new_areas._sort_animating = false
			table._new_areas._draw_flights.clear()
	first._animation_layer.set_skip(true)
	second._animation_layer.set_skip(true)
	first.round.awaiting = true
	var actions = first._table_actions
	var hand_right: float = first._new_areas.action_bar_rect(Vector2.ZERO).end.x
	for titles in [["胡", "碰", "杠", "过"], ["碰", "过"], ["自摸", "暗杠", "加杠", "报听"], ["报听"], ["取消"]]:
		for child in actions.action_bar.get_children():
			actions.action_bar.remove_child(child)
			child.free()
		for title in titles:
			var action := Button.new()
			action.text = title
			actions.action_bar.add_child(action)
		actions._layout_actions_v2()
		var index := 0
		for child in actions.action_bar.get_children():
			var pos: Vector2 = actions.action_bar.position + child.position
			t.expect(is_equal_approx(pos.x + child.size.x, hand_right - index * (child.size.x + UI.ACTION_SEPARATION)), "Actions pack from the fixed hand right edge toward the left: " + child.text)
			t.expect(pos.y + child.size.y < 1026.4, "Action stays above the hand")
			index += 1

	for child in actions.action_bar.get_children():
		actions.action_bar.remove_child(child)
		child.free()
	var original := var_to_bytes(first.round.serialize())
	var event := {"id": 700, "type": "draw", "seat": first.human_seat, "tile": "tiao1"}
	first._on_visual_event(event)
	first._on_visual_event(event)
	event.tile = "tong8"
	t.expect(first._animation_queue.is_empty(), "V2 draw bypasses the old animation queue")
	t.expect(second._animation_queue.is_empty(), "Two table instances do not share animation queues")
	first._table_animation_controller.cancel(true)
	t.expect(not first._table_animation_controller._deal_animating
		and not first._table_animation_controller._draw_animating
		and not first._table_animation_controller._insert_animating
		and not first._table_animation_controller._meld_animating
		and first._table_animation_controller._draw_cards.values().all(func(v): return str(v) == ""),
		"Cancel clears every cross-round animation busy flag and pending draw card")
	first._on_visual_event({"id": 701, "type": "draw", "tile": "wan1"})
	t.expect(first._animation_queue.is_empty(), "V2 reconnect does not queue stale visuals")
	first._table_animation_controller.reset()
	first._table_animation_controller._dealt = [13, 13, 13, 13]
	if first._new_areas != null:
		first._new_areas.test_frozen = false
		first._new_areas.deal_animation_active = false
		first._new_areas._sort_animating = false
		first._new_areas._draw_flights.clear()
	first._on_visual_event({"id": 1, "type": "draw", "seat": first.human_seat, "tile": "wan1"})
	await process_frame
	await process_frame
	t.expect(first._animation_queue.is_empty() and not first._animation_busy, "V2 draw completes without the old queue")
	t.expect(var_to_bytes(first.round.serialize()) == original, "Playing or cancelling presentation never changes the live round")
	first._refresh()
	second._refresh()
	await process_frame
	var first_box = first._new_areas.hand_boxes[first.human_seat] if first._new_areas != null else first.hand_box[first.human_seat]
	var second_box = second._new_areas.hand_boxes[second.human_seat] if second._new_areas != null else second.hand_box[second.human_seat]
	t.expect(first_box.get_child_count() > 0 and second_box.get_child_count() > 0, "V2 hand boxes are populated")
	var first_tile: TileView = first_box.get_child(0)
	var second_tile: TileView = second_box.get_child(0)
	first._selected_tile = first_tile
	first_tile.set_selected(true)
	t.expect(not second_tile.selected and second._selected_tile == null, "Selection belongs only to its own table")
	var submissions: Array = []
	first.enable_net(func(decision): submissions.append(decision), Callable())
	first._on_require_turn(first.human_seat)
	var options: Dictionary = first.round.legal_turn_options(first.human_seat)
	first._commit_turn({"discard": options.discards[0], "discard_index": 0})
	t.expect(submissions.size() == 1 and not first._selecting, "Action component submits once through the authority boundary and locks input")
	t.expect(var_to_bytes(first.round.serialize()) == original, "Network action controls never apply rules locally")
	var button: Button = first._button("测试", func(): pass, UI.DISCARD_BUTTON_SIZE, true)
	t.expect(button.custom_minimum_size == UI.DISCARD_BUTTON_SIZE and button.get_theme_stylebox("hover").bg_color == UI.BUTTON_PRIMARY_HOVER, "Size and palette come from the common configuration")
	button.free()
	first.round.controllers = [null, null, null, null]
	first.round._finish()
	first._table_animation_controller.reset()
	var settled := var_to_bytes(first.round.serialize())
	var settlement = first._settlement_animation_controller
	settlement.reset()
	first._refresh()
	settlement.skip()
	var old_boards: Dictionary = settlement.boards.duplicate()
	settlement.start(true)
	first._refresh()
	t.expect(settlement.boards == old_boards and settlement.boards.size() == 4, "Repeated settlement start and refresh reuse all four tabletop boards")
	t.expect(not second._settlement_animation_controller.has_started() and second._settlement_animation_controller.boards.is_empty(), "Settlement state belongs only to its own table")
	settlement.reset()
	first._refresh()
	settlement.skip()
	await process_frame
	t.expect(settlement.is_completed() and settlement.boards.size() == 4 and settlement.payment_labels.size() == 4, "Reset rebuilds exactly four tabletop payment boards")
	for seat in 4:
		t.expect(not is_instance_valid(old_boards[seat]) and settlement.boards[seat].get_child_count() == 3, "Rebuilding removes old boards and leaves three relative payments per seat")
	first._settlement_card.show_post_settlement_controls()
	await process_frame
	t.expect(first._settlement_card._post_controls.visible and settlement.layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "V2 finished settlement exposes bottom controls without blocking the table")
	t.expect(var_to_bytes(first.round.serialize()) == settled, "Settlement rendering cannot change scores or pairwise payments")
	if DisplayServer.get_name() == "headless":
		await process_frame
		await process_frame
		settlement.reset()
		first._settlement_immediate = false
		first._new_areas._sort_started = true
		first._new_areas._sort_animating = true
		first._refresh()
		t.expect(not settlement.has_started(), "Settlement waits for the final pending hand sort")
		first._new_areas._finish_hand_sort()
		await process_frame
		await process_frame
		t.expect(settlement.is_completed(), "Last hand sort resumes settlement without another network snapshot")
	# Retain one helper externally to ensure it cannot retain a freed table.
	var controller = first._table_animation_controller
	t.expect(controller._tile_pool.MAX_POOL_SIZE >= 512,
		"Tile pool can retain an entire dense table without reallocating")
	var retained_round: RoundState = first.round
	var visual_callback := Callable(first, "_on_visual_event")
	var audio_callback := Callable(first, "_on_audio_event")
	var component_refs: Array = []
	for helper in [first._table_layout, first._player_tile_areas, first._table_actions, first._settlement_card, first._table_widgets]:
		component_refs.append(weakref(helper))
	first._player_tile_areas._scroll_to_latest(first.discard_scroll[0])
	actions = null
	first.free()
	await process_frame
	t.expect(controller.table == null and controller._animation_queue.is_empty(), "Freed tables cancel visuals and are not held alive by their helpers")
	t.expect(settlement.table == null and settlement.boards.is_empty(), "Freed tables also clear settlement visuals and release the table reference")
	t.expect(not retained_round.visual_event.is_connected(visual_callback) and not retained_round.audio_event.is_connected(audio_callback), "Leaving disconnects both presentation event streams")
	for ref in component_refs:
		t.expect(ref.get_ref() == null, "Components are released when their table exits")
	second.free()
	await process_frame
	await H.quit_cleanly(self, t.finish("table_components"))
