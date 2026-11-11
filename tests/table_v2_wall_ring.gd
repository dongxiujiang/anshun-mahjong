extends SceneTree
## 验证四面牌墙在实际墙列上首尾相接，且南/西按环顺序从缺口端取牌。
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		root.content_scale_size = Vector2i(G.DESIGN_SIZE)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
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
	host.hide()
	await _opening_matrix(deck)
	deck.queue_free()
	host.queue_free()
	await process_frame
	quit(t.finish("table_v2_wall_ring"))

func _opening_matrix(deck) -> void:
	const WALL_START := [28, 54, 82, 0]
	const WALL_OFFSETS := [2, 3, 2, 1, 2, 3]
	var visual := DisplayServer.get_name() != "headless"
	if visual:
		DirAccess.make_dir_recursive_absolute("res://build/equal-table/openings")
	for dealer in 4:
		for die in range(1, 7):
			var r := RoundState.new()
			r.next_dealer_seat = dealer
			var seed_value := 4910 + dealer * 6 + die
			r.set_rng_seed(seed_value)
			r.pause_after_opening = true
			r.start_round(dealer, die, die)
			r.controllers = [null, null, null, null]
			var logical_side := posmod(dealer + int(WALL_OFFSETS[die - 1]), 4)
			var first: int = WALL_START[logical_side] + die * 2
			var name := "dealer%d-red%d" % [dealer, die]
			var dealt: Array = r.wall.draw_log.map(func(draw): return int(draw.index))
			var want: Array = range(first, first + 52).map(func(i): return i % 108)
			t.expect(r.round_meta.dice_double and r.round_meta.break == first and dealt == want,
				name + ": red die alone sets break; all 52 tiles follow the real wall ring")
			t.expect(r.wall.remaining == 56 and r.players.all(func(p): return p.concealed.size() == 13),
				name + ": four full hands and 56 tiles remain before first draw")
			var first_four: Array = want.slice(0, 4)
			for viewer in 4:
				var label := name + "-viewer%d" % viewer
				var client := RoundState.new()
				client.apply_sync(r.serialize_for_seat(viewer))
				deck.set_round(r, viewer)
				var local := _visible_wall(deck)
				deck.set_round(client, viewer)
				var remote := _visible_wall(deck)
				t.expect(_same_wall(local, remote, 56)
					and dealt.all(func(index): return not remote.has(index)),
					label + ": local and synced clients keep the same 56 real wall slots")
				var batch: Dictionary = client.visual_events.filter(func(event): return event.type == "deal_batch")[0]
				var opening: Dictionary = batch.deals[0]
				t.expect(int(opening.seat) == dealer and opening.indices == first_four,
					label + ": the actual dealer receives the correct opening indices")
				var screen := posmod(logical_side - viewer + 1, 4)
				var wall_bounds: Rect2 = G.WALL_BOUNDS[screen]
				t.expect(wall_bounds.has_point(deck.wall_center_for_index(first)), label + ": break is on the expected rotated wall")
				deck.animate_deal_group(dealer, opening.cards, opening.indices, 0, func(): pass)
				var display_order := [first + 1, first + 3, first, first + 2]
				var matching: bool = deck._deal_moving.size() == 4
				for i in deck._deal_moving.size():
					var tile: TileView = deck._deal_moving[i]
					matching = matching and (tile.position + tile.size / 2.0).is_equal_approx(
						deck.wall_center_for_index(display_order[i]))
				t.expect(matching, label + ": all four deal sprites take off from their physical slots")
				deck._finish_deal_group(deck._deal_moving, Callable())
				if visual and viewer == dealer:
					deck.set_round(r, viewer)
					await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://build/equal-table/openings/" + name + ".png")
			r.resume_after_opening()
			t.expect(r.current_turn == dealer and r.wall.remaining == 55
				and int(r.wall.draw_log.back().index) == (first + 52) % 108,
				name + ": dealer's first draw takes the next live wall slot")
			for viewer in 4:
				var client := RoundState.new()
				client.apply_sync(r.serialize_for_seat(viewer))
				deck.set_round(r, viewer)
				var local := _visible_wall(deck)
				deck.set_round(client, viewer)
				t.expect(_same_wall(local, _visible_wall(deck), 55)
					and not local.has((first + 52) % 108), name + ": first draw leaves the same half-stack on both peers")

			for white in range(1, 7):
				if white == die: continue
				var single := RoundState.new()
				single.next_dealer_seat = dealer
				single.set_rng_seed(seed_value)
				single.pause_after_opening = true
				single.start_round(dealer, die, white)
				t.expect(not single.round_meta.dice_double and int(single.round_meta.die_white) == white
					and single.round_meta.break == first and single.wall.draw_log == r.wall.draw_log.slice(0, 52),
					name + "-white%d: white die does not move the wall break or change dealt cards" % white)

func _visible_wall(deck) -> Dictionary:
	var slots := {}
	for tile in deck._wall_layer.get_children():
		var index := int(tile.get_meta("wall_ring_index", -1))
		slots[index] = tile.position
	return slots

func _same_wall(local: Dictionary, remote: Dictionary, count: int) -> bool:
	return local.size() == count and remote.size() == count and local.keys().all(
		func(index): return remote.has(index) and Vector2(local[index]).is_equal_approx(remote[index]))
