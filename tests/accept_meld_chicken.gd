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
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	table._new_areas.auto_sort_hands = false
	table._new_areas.test_deal_only = false
	table._new_areas.test_frozen = false
	table._new_areas._sort_started = true
	# 四个鸡牌：每种第一张横放，之后竖放。
	var p1 = table.round.players[1]
	for card in ["tiao1", "tiao1", "tong8", "tong8"]:
		p1.discards.append(card)
		p1.discard_ids.append(p1.discard_count)
		p1.discard_count += 1
	table.round.round_meta["charge_chickens"] = {
		"tiao1": {"owner": 1, "location": "discard", "discard_id": 0},
		"tong8": {"owner": 1, "location": "discard", "discard_id": 2},
	}
	table._refresh()
	await create_timer(0.2).timeout
	var v2 = table._new_areas
	var chicken_angles: Array = []
	for node in v2._red_layer.get_children():
		if int(node.get_meta("v2_seat", -1)) == 1:
			chicken_angles.append({"tile": str(node.tile), "rot": node.rotation})
	print("[meld] chicken=", chicken_angles)
	var first_tiao: Dictionary = chicken_angles.filter(func(a): return a.tile == "tiao1")[0]
	var second_tiao: Dictionary = chicken_angles.filter(func(a): return a.tile == "tiao1")[1]
	var first_tong: Dictionary = chicken_angles.filter(func(a): return a.tile == "tong8")[0]
	t.expect(absf(absf(first_tiao.rot) - PI / 2.0) < 0.1, "第一张幺鸡横放")
	t.expect(absf(second_tiao.rot) < 0.1, "第二张幺鸡竖放")
	t.expect(absf(absf(first_tong.rot) - PI / 2.0) < 0.1, "第一张八筒横放")
	# 碰/杠渲染到碰杠区。
	var p2 = table.round.players[2]
	p2.melds.append({"kind": "pung", "tile": "wan5", "from_seat": 1})
	p2.concealed = p2.concealed.slice(0, 10)
	var p3 = table.round.players[3]
	p3.melds.append({"kind": "kong", "tile": "tiao9", "from_seat": 1})
	p3.concealed = p3.concealed.slice(0, 9)
	table._refresh()
	await create_timer(0.2).timeout
	var meld_nodes: Array = v2._meld_layer.get_children()
	var c2 := meld_nodes.filter(func(n): return int(n.get_meta("v2_seat", -1)) == 2).size()
	var c3 := meld_nodes.filter(func(n): return int(n.get_meta("v2_seat", -1)) == 3).size()
	print("[meld] pung_nodes=", c2, " kong_nodes=", c3)
	t.expect(c2 == 3, "碰渲染3张")
	t.expect(c3 == 4, "杠渲染4张")
	table.queue_free(); await H.quit_cleanly(self, t.finish("accept_meld_chicken"))
