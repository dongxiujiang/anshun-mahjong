extends SceneTree
## 无摸牌回合（碰后出牌）必须保留手牌节点：旧牌飞走，其余牌平移补位。

const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const Tiles := preload("res://scripts/core/Tiles.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.controllers = [null, null, null, null]
	table.round.cancel_opening()
	table._table_animation_controller.cancel()
	table.round.phase = RoundState.Phase.PLAYING
	table.round.awaiting = false
	var base: Array = Tiles.all_values()
	for seat in 4:
		var player = table.round.players[seat]
		player.concealed.clear()
		player.just_drew = ""
		for i in 10:
			player.concealed.append(str(base[(seat * 10 + i) % base.size()]))
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table._table_animation_controller._pending_test_deals.clear()
	table._table_animation_controller._deal_animating = false
	var v2 = table._new_areas
	v2.auto_sort_hands = false
	v2.test_frozen = false
	v2._sort_started = true
	table._refresh()
	await process_frame

	var seat: int = table.human_seat
	var player = table.round.players[seat]
	var card := str(player.concealed[0])
	player.concealed.remove_at(0)
	player.just_drew = ""
	player.discards.append(card)
	player.discard_history.append(card)
	player.discard_ids.append(player.discard_count)
	player.discard_count += 1
	var nodes_before: Array = v2.hand_boxes[seat].get_children()
	t.expect(nodes_before.size() == 10, "无摸牌回合出牌前保留10张手牌节点")

	var completed := {"value": false}
	v2.animate_hand_discard(seat, card, 0, func(): completed.value = true)
	t.expect(v2.deal_animation_active, "无摸牌出牌先进入飞行动画")
	await create_timer(0.8).timeout
	t.expect(bool(completed.value) and not v2.deal_animation_active, "无摸牌出牌动画完整结束")
	t.expect(v2.draw_boxes[seat].get_child_count() == 0, "无摸牌回合不伪造摸牌位")

	var no_corner_refresh := true
	for node in v2.hand_boxes[seat].get_children():
		if node.position.length_squared() < 1.0:
			no_corner_refresh = false
	t.expect(no_corner_refresh, "补位动画没有从左上角刷新手牌")

	table.queue_free()
	await H.quit_cleanly(self, t.finish("table_v2_hand_discard"))
