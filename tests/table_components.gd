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
	first.round.phase = RoundState.Phase.SETTLED
	first.round.last_result = ScoringEngine.settle(first.round)
	var settled := var_to_bytes(first.round.serialize())
	first._show_result()
	var old_panel: Control = first._result_panel
	first._show_result()
	t.expect(first._result_panel != old_panel and first.result_layer.get_child_count() == 2, "Rebuilding settlement leaves one shade and one card")
	first._toggle_result_panel(false)
	t.expect(first._result_restore.visible and first._result_restore.position == first.panel_position_for_result_toggle(), "Table/card switching retains the same clickable position")
	first._toggle_result_panel(true)
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
	t.expect(not retained_round.visual_event.is_connected(visual_callback) and not retained_round.audio_event.is_connected(audio_callback), "Leaving disconnects both presentation event streams")
	for ref in component_refs:
		t.expect(ref.get_ref() == null, "Components are released when their table exits")
	second.free()
	await process_frame
	quit(t.finish("table_components"))
