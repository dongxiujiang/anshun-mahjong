extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	table.round.opening_delay_seconds = 0.0
	for _i in 240:
		await process_frame
		if table.round.players[1].concealed.size() >= 13: break
	table.round.cancel_opening()
	table._table_animation_controller.cancel()
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table._table_animation_controller._pending_test_deals.clear()
	table._table_animation_controller._deal_animating = false
	table._new_areas.auto_sort_hands = false
	table._new_areas.test_deal_only = false
	table._new_areas.test_frozen = false
	table.round.phase = RoundState.Phase.PLAYING
	table.round.current_turn = table.human_seat
	table.round.awaiting = false
	table.round._begin_turn()
	for _i in 20: await process_frame
	table._refresh()
	await process_frame
	await create_timer(0.2).timeout
	var v2 = table._new_areas
	t.expect(v2 != null and v2.hand_boxes.size() == 4, "TableV2 手牌容器存在")
	var box = v2.hand_boxes[table.human_seat]
	t.expect(box.get_child_count() >= 13, "本地手牌渲染")
	var tile: TileView = box.get_child(0)
	var legal = table.round.legal_turn_options(table.human_seat)
	print("[v2 input] selecting=", table._table_actions._selecting, " interactive=", tile.interactive,
		" legal=", legal.get("discards", []).size(), " turn=", table.round.current_turn,
		" phase=", table.round.phase, " hand=", table.round.players[table.human_seat].concealed.size())
	t.expect(tile.interactive, "本地手牌可交互")
	var before: int = table.round.players[table.human_seat].discards.size()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = tile.size / 2.0
	tile.gui_input.emit(ev)
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = false
	ev2.position = ev.position
	tile.gui_input.emit(ev2)
	await process_frame
	await create_timer(0.3).timeout
	t.expect(table.round.players[table.human_seat].discards.size() == before + 1, "点击手牌完成出牌")
	root.get_node("AudioManager").stop_effects()
	root.get_node("AudioManager").end_table(table)
	table.queue_free()
	await create_timer(0.5).timeout
	quit(t.finish("v2_live_input"))
