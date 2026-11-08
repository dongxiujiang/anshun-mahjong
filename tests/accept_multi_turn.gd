extends SceneTree
const H := preload("res://tests/test_harness.gd")
const Tiles := preload("res://scripts/core/Tiles.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var t := H.new()
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	await process_frame
	table.round.cancel_opening()
	table._table_animation_controller.cancel()
	table.round.phase = RoundState.Phase.PLAYING
	table.round.awaiting = false
	var base: Array = Tiles.all_values()
	for seat in 4:
		var p = table.round.players[seat]
		p.concealed.clear()
		p.just_drew = ""
		for i in 13: p.concealed.append(str(base[(seat * 13 + i) % base.size()]))
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table._table_animation_controller._deal_animating = false
	table._table_animation_controller._pending_test_deals.clear()
	table._new_areas.test_deal_only = false
	table._new_areas.test_frozen = false
	table._new_areas._sort_started = true
	table._new_areas._frozen_hands.clear()
	table._refresh()
	await create_timer(0.3).timeout
	var v2 = table._new_areas
	for turn in 3:
		table.round.current_turn = table.human_seat
		table.round.awaiting = false
		table.round._begin_turn()
		for _i in 80:
			await process_frame
			if v2.draw_boxes[table.human_seat].get_child_count() == 1: break
		var hand_before: int = v2.hand_boxes[table.human_seat].get_child_count()
		var draw_before: int = v2.draw_boxes[table.human_seat].get_child_count()
		var p = table.round.players[table.human_seat]
		var index := 0
		for i in p.concealed.size():
			if p.concealed[i] != p.just_drew: index = i; break
		var card := str(p.concealed[index])
		var discards_before: int = p.discards.size()
		table._submit_discard(card, index)
		for _i in 120:
			await process_frame
			if v2.draw_boxes[table.human_seat].get_child_count() == 0 \
					and int(p.discards.size()) == discards_before + 1: break
		var hand_after: int = v2.hand_boxes[table.human_seat].get_child_count()
		var draw_after: int = v2.draw_boxes[table.human_seat].get_child_count()
		var no_corner_refresh := true
		for node in v2.hand_boxes[table.human_seat].get_children():
			if node.position.length_squared() < 1.0:
				no_corner_refresh = false
		print("[turn] ", turn, " before hand=", hand_before, " draw=", draw_before,
			" after hand=", hand_after, " draw=", draw_after,
			" discards=", p.discards.size())
		t.expect(hand_before == 13 and draw_before == 1, "第%d轮摸牌13+1" % turn)
		t.expect(hand_after == 13 and draw_after == 0, "第%d轮弃牌插入13+0" % turn)
		t.expect(no_corner_refresh, "第%d轮手牌补位没有从左上角刷新" % turn)
		t.expect(p.discards.size() == discards_before + 1, "第%d轮弃牌成功" % turn)
	table.queue_free(); await H.quit_cleanly(self, t.finish("accept_multi_turn"))
