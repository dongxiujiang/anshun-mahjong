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
	root.add_child(first)
	root.add_child(second)
	await process_frame
	first._table_animation_controller.reset()
	second._table_animation_controller.reset()
	first._animation_layer.set_skip(true)
	second._animation_layer.set_skip(true)
	var original := var_to_bytes(first.round.serialize())
	var event := {"id": 700, "type": "draw", "seat": first.human_seat, "tile": "tiao1"}
	first._on_visual_event(event)
	first._on_visual_event(event)
	event.tile = "tong8"
	t.expect(first._animation_queue.size() == 1 and first._animation_queue[0].tile == "tiao1", "Repeated visual events queue once and own an immutable copy")
	t.expect(second._animation_queue.is_empty(), "Two table instances do not share animation queues")
	first._table_animation_controller.cancel(true)
	first._on_visual_event({"id": 701, "type": "draw", "tile": "wan1"})
	t.expect(first._animation_queue.is_empty() and not first._skip_visual_once, "Reconnect cancels pending visuals and skips exactly the next event")
	first._table_animation_controller.reset()
	first._on_visual_event({"id": 1, "type": "draw", "seat": first.human_seat, "tile": "wan1"})
	await process_frame
	await process_frame
	t.expect(first._animation_queue.is_empty() and not first._animation_busy, "A new round accepts low event IDs and headless playback completes")
	t.expect(var_to_bytes(first.round.serialize()) == original, "Playing or cancelling presentation never changes the live round")
	var first_tile: TileView = first.hand_box[first.human_seat].get_child(0)
	var second_tile: TileView = second.hand_box[second.human_seat].get_child(0)
	first._selected_tile = first_tile
	first_tile.set_selected(true)
	t.expect(not second_tile.selected and second._selected_tile == null, "Selection belongs only to its own table")
	var submissions: Array = []
	first.enable_net(func(decision): submissions.append(decision), Callable())
	first._on_require_turn(first.human_seat)
	var options: Dictionary = first.round.legal_turn_options(first.human_seat)
	first._commit_turn({"discard": options.discards[0]})
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
	t.expect(first._settlement_card._post_controls.visible and settlement.layer.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Finished settlement exposes bottom controls without blocking the table")
	t.expect(var_to_bytes(first.round.serialize()) == settled, "Settlement rendering cannot change scores or pairwise payments")
	# Retain one helper externally to ensure it cannot retain a freed table.
	var controller = first._table_animation_controller
	var retained_round: RoundState = first.round
	var visual_callback := Callable(first, "_on_visual_event")
	var audio_callback := Callable(first, "_on_audio_event")
	var component_refs: Array = []
	for helper in [first._table_layout, first._player_tile_areas, first._table_actions, first._settlement_card, first._table_widgets]:
		component_refs.append(weakref(helper))
	first._player_tile_areas._scroll_to_latest(first.discard_scroll[0])
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
