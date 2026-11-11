extends SceneTree
## Equal-size meld shapes plus live upstream claims and a synthetic full-river stress board.
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const CAPTURES := "res://build/equal-table/stress/"
var t := H.new()
var visual := false

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	visual = DisplayServer.get_name() != "headless"
	if visual:
		root.content_scale_size = Vector2i(G.DESIGN_SIZE)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		DirAccess.make_dir_recursive_absolute(CAPTURES)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	_check_shapes(view)
	for viewer in 4:
		await _check_upstream_chain(view, viewer)
		await _check_full_table(view, viewer)
	view.queue_free()
	await process_frame
	quit(t.finish("table_v2_red_spacing"))

func _check_shapes(view) -> void:
	var all_shapes: Array = [[], [], [], []]
	var fixed: Array = G.WALL_BOUNDS.duplicate()
	var human := 1
	view.human_seat = human
	for seat in 4:
		var rel := G.relative_seat(human, seat)
		var side := rel in [1, 3]
		var river_size := G.TILE_BASE * G.ORDINARY_UNIT
		if side: river_size = Vector2(river_size.y, river_size.x)
		for i in G.river_capacity(rel):
			fixed.append(Rect2(G.ordinary_slot_center(seat, i, human) - river_size / 2, river_size))
		fixed.append(G.hand13_rect(seat, human))
		var draw_size := G.hand_tile_size(seat, human)
		if side: draw_size = Vector2(draw_size.y, draw_size.x)
		fixed.append(Rect2(G.draw_slot_center(seat, human) - draw_size / 2, draw_size))
		fixed.append(G.meld_badge_rect(rel))
	for owner in 4:
		var rel := G.relative_seat(human, owner)
		for count in range(5):
			for stacks in range(count + 1):
				var timeline := []
				for i in count:
					timeline.append({"kind": "kong", "tile": ["tong8", "wan5", "tiao1", "wan7"][i],
						"from_seat": posmod(owner + (2 if i < stacks else 1 + 2 * (i % 2)), 4)})
				var layout: Array = view.meld_layout(timeline, owner, rel)
				var shape: Array[Rect2] = []
				var clear := layout.size() == count * 4
				for spec in layout:
					var wide: bool = bool(spec.sideways) != (rel in [1, 3])
					var extent := G.MELD_SIZE
					if wide: extent = Vector2(extent.y, extent.x)
					var rect := Rect2(Vector2(spec.center) - extent / 2, extent)
					clear = clear and G.TABLE_BOUNDS.encloses(rect) and _clear_of(rect, fixed + shape)
					shape.append(rect)
				t.expect(clear, "seat %d, groups %d, stacked %d: equal-size melds clear fixed zones" % [owner, count, stacks])
				var chickens := G.chicken_slot_centers(owner, human, layout)
				var chicken_clear := chickens.size() == 8
				for center in chickens:
					var rect := Rect2(center - Vector2(28, 28), Vector2(56, 56))
					chicken_clear = chicken_clear and _clear_of(rect, fixed + shape)
					shape.append(rect)
				t.expect(chicken_clear, "seat %d, groups %d, stacked %d: eight discarded chickens clear all reserved zones" % [owner, count, stacks])
				all_shapes[owner].append(shape)
	for owner in 4:
		for other in range(owner):
			var clear := true
			for shape in all_shapes[owner]:
				for candidate in all_shapes[other]:
					for rect in shape:
						clear = clear and _clear_of(rect, candidate)
			t.expect(clear, "all mixed meld shapes of seats %d and %d remain separate" % [owner, other])

func _check_upstream_chain(view, viewer: int) -> void:
	var r := RoundState.new()
	r.build_players(viewer)
	r._reset_meta()
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	r.current_turn = viewer
	var upper := posmod(viewer + 1, 4)
	var draws := ["wan1", "wan4", "wan7", "tong8", "tiao9"]
	var throws := ["tiao2", "tiao3", "tiao4", "tiao5"]
	var pool := TileSetFactory.create_deck()
	for tile in draws: pool.erase(tile)
	for tile in draws.slice(0, 4):
		for i in 2:
			r.players[upper].concealed.append(tile)
			pool.erase(tile)
	for tile in throws:
		r.players[upper].concealed.append(tile)
		pool.erase(tile)
	var used: Array = r.players[upper].concealed.duplicate()
	for seat in 4:
		var player: PlayerState = r.players[seat]
		while player.concealed.size() < 13:
			var tile := str(pool.pop_front())
			player.concealed.append(tile)
			used.append(tile)
	r.wall = WallRing.new(used + draws + pool)
	r.wall.set_head(0)
	for i in used.size(): r.wall.draw_head()
	view.set_round(r, viewer)
	r._begin_turn()
	for i in 4:
		var tile: String = draws[i]
		t.expect(r.current_turn == viewer and r.players[viewer].just_drew == tile,
			"viewer %d: consecutive draw %d comes from real wall" % [viewer, i + 1])
		view.refresh()
		var accepted := r.submit_turn(viewer, {"discard": tile, "discard_index": r.players[viewer].concealed.size() - 1})
		t.expect(accepted, "viewer %d: discard %s accepted" % [viewer, tile])
		_drain_responses(r, upper)
		var p: PlayerState = r.players[upper]
		t.expect(p.melds.size() == i + 1 and r.current_turn == upper and p.just_drew == "",
			"viewer %d: upstream seat claims %s without drawing" % [viewer, tile])
		t.expect(r.players[viewer].discards.is_empty(), "claimed tile leaves the river")
		view.refresh()
		var sprites := 0
		for layer in [view._meld_layer, view._red_layer]:
			for node in layer.get_children():
				if int(node.get_meta("meld_index", -1)) >= 0: sprites += 1
		t.expect(sprites == 3 * (i + 1), "viewer %d: claim %d has %d meld sprites" % [viewer, i + 1, sprites])
		await _capture("viewer%d-upstream-pong%d" % [viewer, i + 1])
		t.expect(r.submit_turn(upper, {"discard": throws[i], "discard_index": p.concealed.find(throws[i])}),
			"upstream seat can discard after claiming")
		_drain_responses(r, -1)
		t.expect(r.current_turn == viewer and r.wall.remaining == 54 - i,
			"target draws again without the other two seats taking a turn")

func _drain_responses(r: RoundState, claim_seat: int) -> void:
	for i in 16:
		var prompt: Dictionary = r._awaiting_response
		if prompt.is_empty(): return
		var seat := int(prompt.seat)
		var action := "pong" if seat == claim_seat and prompt.options.can_pong else "pass"
		if not r.submit_response(seat, str(prompt.tile), {"action": action}):
			t.expect(false, "response %s for seat %d rejected" % [action, seat])
			return
	t.expect(false, "response chain did not finish")

func _check_full_table(view, viewer: int) -> void:
	# Deliberately fill independent zones at once to stress visual boundaries.
	# This board is not a possible tile allocation; the chain above uses a real 108-tile deck.
	var r := RoundState.new()
	r.build_players(viewer)
	r._reset_meta()
	r.phase = RoundState.Phase.PLAYING
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	for seat in 4:
		var p: PlayerState = r.players[seat]
		p.ready = true
		p.concealed = ["wan1"]
		p.melds = [
			{"kind": "kong", "tile": "wan5", "from_seat": posmod(seat + 2, 4)},
			{"kind": "kong", "tile": "tong8", "from_seat": posmod(seat + 2, 4)},
			{"kind": "kong", "tile": "wan6", "from_seat": posmod(seat + 3, 4)},
			{"kind": "pung", "tile": "tiao4", "from_seat": posmod(seat + 1, 4)}]
		var capacity := G.river_capacity(G.relative_seat(viewer, seat))
		for i in capacity:
			p.discards.append(["wan2", "wan8", "tiao6", "tong2", "tong6", "tiao2"][i % 6]
				if i < capacity - 2 else ("tiao1" if i == capacity - 2 else "tong8"))
			p.discard_ids.append(seat * 100 + i)
		p.discard_count = capacity
	view.set_round(r, viewer)
	for node in view._red_layer.get_children():
		if int(node.get_meta("meld_index", -1)) < 0:
			t.expect(node.modulate == Color.WHITE, "discarded chickens retain their normal tile face colors")
	t.expect(view.count_kind("ordinary") == 74 and view.count_kind("red") == 24 and view._meld_layer.get_child_count() == 44,
		"viewer %d: all 82 river tiles and 60 meld tiles stay visible" % viewer)
	var obstacles: Array[Rect2] = []
	for tile in view._wall_layer.get_children():
		obstacles.append(view._visual_rect(tile))
	var occupied: Array[Rect2] = []
	var clear := true
	for layer in view._render_layers():
		if layer == view._wall_layer: continue
		for tile in layer.get_children():
			var rect: Rect2 = view._visual_rect(tile)
			clear = clear and G.TABLE_BOUNDS.encloses(rect) and _clear_of(rect, occupied + obstacles)
			occupied.append(rect)
	t.expect(clear, "viewer %d: full rivers, hands, four melds per seat and walls are separate" % viewer)
	var action: Rect2 = view.action_bar_rect(Vector2(546, 112))
	t.expect(_clear_of(action, occupied), "viewer %d: action buttons clear all public tiles except the wall" % viewer)
	var client := RoundState.new()
	client.apply_sync(r.serialize_for_seat(viewer))
	var before := _table_positions(view)
	view.set_round(client, viewer)
	var after := _table_positions(view)
	t.expect(before.size() == after.size() and before.keys().all(func(key): return after.has(key) and Vector2(before[key]).is_equal_approx(after[key])), "viewer %d: network snapshot keeps the same public tile positions" % viewer)
	await _capture("viewer%d-full-rivers-and-melds" % viewer)

func _table_positions(view) -> Dictionary:
	var positions := {}
	for layer in view._render_layers():
		for tile in layer.get_children():
			positions[view._render_key(tile)] = tile.position
	return positions

func _clear_of(rect: Rect2, obstacles: Array) -> bool:
	for other: Rect2 in obstacles:
		if rect.intersects(other.grow(-0.05)): return false
	return true

func _capture(name: String) -> void:
	if not visual: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(CAPTURES + name + ".png")
