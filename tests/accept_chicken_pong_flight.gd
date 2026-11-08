extends SceneTree
const H := preload("res://tests/test_harness.gd")
const Tiles := preload("res://scripts/core/Tiles.gd")
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var t := H.new()
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
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
	var p1 = table.round.players[1]
	p1.concealed[0] = "tiao1"
	p1.concealed[1] = "tiao1"
	var src = table.round.players[0]
	src.discards.append("tiao1")
	src.discard_ids.append(0)
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table._table_animation_controller._pending_test_deals.clear()
	table._table_animation_controller._deal_animating = false
	table._new_areas.auto_sort_hands = false
	table._new_areas.test_deal_only = false
	table._new_areas.test_frozen = false
	table._new_areas._sort_started = true
	table._refresh()
	await create_timer(0.25).timeout
	var indices: Array = []
	for i in p1.concealed.size():
		if p1.concealed[i] == "tiao1": indices.append(i)
	p1.concealed.remove_at(int(indices[1]))
	p1.concealed.remove_at(int(indices[0]))
	p1.melds.append({"kind": "pung", "tile": "tiao1", "from_seat": 0})
	src.discards.clear()
	src.discard_ids.clear()
	var ev := {"type": "meld", "seat": 1, "source": 0, "source_discard_id": 0,
		"hand_indices": [indices[0], indices[1]], "tile": "tiao1",
		"kind": "pung", "index": 0}
	table._table_animation_controller._on_visual_event(ev)
	await create_timer(0.55).timeout
	var mine := 0
	var source_left := 0
	for node in table._new_areas._red_layer.get_children():
		if str(node.tile) != "tiao1": continue
		if int(node.get_meta("v2_seat", -1)) == 1 and int(node.get_meta("meld_index", -1)) == 0: mine += 1
		if int(node.get_meta("v2_seat", -1)) == 0 and int(node.get_meta("discard_id", -1)) == 0: source_left += 1
	print("[chicken-pong] mine=", mine, " source_left=", source_left,
		" hand=", table._new_areas.hand_boxes[1].get_child_count())
	t.expect(mine == 3, "鸡牌碰落我的红牌区3张")
	t.expect(source_left == 0, "来源红牌区弃牌已飞走")
	t.expect(table._new_areas.hand_boxes[1].get_child_count() == 11, "手牌减少2张")
	table.queue_free(); await H.quit_cleanly(self, t.finish("accept_chicken_pong_flight"))
