extends SceneTree
## 验证四面牌墙在实际墙列上首尾相接，且南/西按环顺序从缺口端取牌。
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var host = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(host)
	host.round.controllers = [null, null, null, null]
	await process_frame
	var deck = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(deck)
	deck.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	deck.size = G.DESIGN_SIZE
	deck.set_round(host.round, 1)
	await process_frame
	var ring: Array = host.round.wall._ring
	t.expect(ring.size() == 108, "牌墙环108张")
	# 北左端 = 环0，北右端 = 环26/27；东上端 = 环28/29。
	t.expect(deck._wall_value(3, 0, 0) == ring[0] and deck._wall_value(3, 0, 1) == ring[1],
		"北墙左端接环首")
	t.expect(deck._wall_value(3, 13, 0) == ring[26] and deck._wall_value(3, 13, 1) == ring[27],
		"北墙右端接东墙")
	t.expect(deck._wall_value(0, 0, 0) == ring[28] and deck._wall_value(0, 0, 1) == ring[29],
		"东墙上端接北墙")
	t.expect(deck._wall_value(0, 12, 0) == ring[52] and deck._wall_value(0, 12, 1) == ring[53],
		"东墙下端接南墙")
	# 南墙从右端环54开始，左端环80结束。
	t.expect(deck._wall_value(1, 13, 0) == ring[54] and deck._wall_value(1, 13, 1) == ring[55],
		"南墙右端接东墙")
	t.expect(deck._wall_value(1, 0, 0) == ring[80] and deck._wall_value(1, 0, 1) == ring[81],
		"南墙左端接西墙")
	# 西墙从下端环82开始，上端环106结束。
	t.expect(deck._wall_value(2, 12, 0) == ring[82] and deck._wall_value(2, 12, 1) == ring[83],
		"西墙下端接南墙")
	t.expect(deck._wall_value(2, 0, 0) == ring[106] and deck._wall_value(2, 0, 1) == ring[107],
		"西墙上端接北墙")
	# 整墙数组按环顺序 N→E→S→W，54列首尾连续。
	var north: Array = deck._wall_pairs(ring, 0, 28, false)
	var east: Array = deck._wall_pairs(ring, 28, 26, false)
	var south: Array = deck._wall_pairs(ring, 54, 28, false)
	var west: Array = deck._wall_pairs(ring, 82, 26, false)
	var all_pairs: Array = north + east + south + west
	var connected := true
	for i in 108:
		if str(all_pairs[i]) != str(ring[i]): connected = false
	t.expect(connected, "2×54数组首尾相连")
	_double_six_opening(deck)
	deck.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish("table_v2_wall_ring"))

func _double_six_opening(deck) -> void:
	const FIRST_INDEX := [12, 40, 66, 94]
	for dealer in 4:
		var r := RoundState.new()
		r.next_dealer_seat = dealer
		r.start_round(1, 6, 6)
		var break_index: int = FIRST_INDEX[dealer]
		t.expect(r.round_meta.dice_double and r.round_meta.break == break_index,
			"双6只用红骰，庄家下家墙跳过六蹲")
		var actual: Array = r.wall.draw_log.slice(0, 4).map(func(draw): return draw.index)
		t.expect(actual == range(break_index, break_index + 4), "庄家首组拿下家墙的第七、八蹲")
		for viewer in 4:
			var client := RoundState.new()
			client.apply_sync(r.serialize_for_seat(viewer))
			deck.set_round(client, viewer)
			var batch: Dictionary = client.visual_events.filter(func(event): return event.type == "deal_batch")[0]
			var first: Dictionary = batch.deals[0]
			t.expect(first.indices == actual, "所有客户端收到同一组取牌下标")
			var wall_side := posmod(dealer - viewer, 4)
			var source: Vector2 = deck.wall_center_for_index(break_index)
			var source_side: Vector2 = [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP][wall_side]
			var offset := source - G.CENTER
			t.expect(offset.dot(source_side) > 280 and absf(offset.cross(source_side)) < 100,
				"庄家%d 视角%d：开牌墙跟随座位旋转" % [dealer, viewer])
			deck.animate_deal_group(dealer, first.cards, first.indices, 0, func(): pass)
			var display_order := [break_index + 1, break_index + 3, break_index, break_index + 2]
			for i in display_order.size():
				var tile: TileView = deck._deal_moving[i]
				var origin: Vector2 = deck.wall_center_for_index(display_order[i])
				t.expect((tile.position + tile.size / 2.0).is_equal_approx(origin),
					"开局飞牌从各自真实墙槽起飞")
			deck._finish_deal_group(deck._deal_moving, Callable())
