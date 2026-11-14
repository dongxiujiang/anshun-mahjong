extends SceneTree
## Equal-size meld shapes plus live upstream claims and a synthetic full-river stress board.
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const CAPTURES := "res://build/equal-table/stress/"
var t := H.new()
var visual := false

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	root.get_node("GameConfig").set_tile_animation_seconds(0.0, false)
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
		await _check_meld_replay(view, viewer, "opposite_kong_held_hand")
		await _check_meld_replay(view, viewer, "meld_held_hand_own_area")
		await _check_full_table(view, viewer)
	view.queue_free()
	await process_frame
	quit(t.finish("table_v2_red_spacing"))

func _check_shapes(view) -> void:
	for rel in 4:
		var size: Vector2 = view.EXPOSED.size_for(rel)
		var group := {"rel": rel, "count": 1, "charge": false, "source_slot": -1, "opposite": false, "width": size.x}
		var bounds: Vector2 = view.EXPOSED.axis_bounds(rel)
		t.expect(not view.EXPOSED.clear(view.EXPOSED.place(group, bounds.y + 8, false), []), "whole groups cannot borrow neighbouring corners")
	# Geometry boundaries: short hands match each meld count; no impossible 13+4-meld hand.
	for viewer in 4:
		for owner in 4:
			for count in range(5):
				for source in [1,2,3]:
					var r := RoundState.new()
					r.build_players(viewer)
					r.phase = RoundState.Phase.PLAYING
					var p = r.players[owner]
					for i in 13-3*count: p.concealed.append("tong9")
					for i in count: p.melds.append({"kind":"kong","tile":"wan%d" % (i+1),"from_seat":posmod(owner+source,4)})
					p.discards = ["tiao1","tong8"]
					p.discard_ids = [0,1]
					view.set_round(r,viewer)
					var specs: Array = view._exposed_layout()
					t.expect(specs.size()==4*count+2,"every chicken and meld appears: viewer=%d owner=%d count=%d source=%d" % [viewer,owner,count,source])
					var obstacles := []
					for seat in 4:
						obstacles.append(view._seat_hud_rect(seat))
						for node in view.hand_boxes[seat].get_children(): obstacles.append(_paint_rect(node))
					t.expect(view.EXPOSED.clear(specs,obstacles),"groups clear retained hands and name panels")
					for i in specs.size():
						for j in i:
							if source != 2 and specs[i].meld_index>=0 and specs[i].meld_index==specs[j].meld_index: continue
							t.expect(not specs[i].rect.grow(-0.05).intersects(specs[j].rect),"meld faces and shadows never overlap")
					if source == 2:
						for meld in count:
							var group := specs.filter(func(spec): return spec.meld_index == meld)
							if group.size() != 4: continue
							var front: Dictionary = group.filter(func(spec): return spec.sideways)[0]
							var upright := group.filter(func(spec): return not spec.sideways)
							var axis: Vector2 = view.EXPOSED.AXES[G.relative_seat(viewer, owner)]
							var inward: Vector2 = view.EXPOSED.INWARD[G.relative_seat(viewer, owner)]
							t.expect(is_equal_approx(front.center.dot(axis), (upright[0].center.dot(axis) + upright[2].center.dot(axis)) / 2.0), "opposite source tile stays centered on the three upright tiles")
							t.expect(front.center.dot(inward) > upright[0].center.dot(inward), "opposite source tile is in front toward the table center for every viewer")

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

func _check_meld_replay(view, viewer: int, fixture: String) -> void:
	# Real shuffled games: retain the hand positions during opposite and repeated claims.
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/%s.json" % fixture))
	var r := RoundState.new()
	r.controllers = [null, null, null, null]
	r.set_rng_seed(int(record.seed))
	r.next_dealer_seat = int(record.dealer)
	r.pause_after_opening = true
	r.start_round(1, int(record.red), int(record.white))
	r.resume_after_opening()
	var events := []
	r.visual_event.connect(func(event): events.append(event))
	view.auto_sort_hands = false
	view.set_round(r, viewer)
	view._sort_started = true
	for index in record.actions.size():
		var action: Dictionary = record.actions[index]
		events.clear()
		var accepted: bool = r.submit_turn(int(action.seat), action.decision) if action.kind == "turn" else r.submit_response(int(action.seat), str(action.tile), action.decision)
		t.expect(accepted, "meld layout regression replays legal action %d" % index)
		for event in events:
			if event.type == "discard": view._held_hand_centers.erase(int(event.seat))
			if event.type == "meld": view.animate_meld(event, func(): pass)
		view.refresh()
		var expected := 0
		for player in r.players:
			expected += player.discards.filter(func(tile): return Tiles.is_chicken(tile)).size()
			for meld in player.melds: expected += 3 if meld.kind == "pung" else 4
		var specs: Array = view._exposed_layout()
		t.expect(specs.size() == expected, "held-hand replay keeps every exposed tile")
		var obstacles := [view.action_bar_rect(Vector2(546, 112))]
		for layer in view.hand_boxes + view.draw_boxes + [view._discard_layer, view._wall_layer]:
			for node in layer.get_children():
				obstacles.append(view.EXPOSED.rect_for(node.position + node.size / 2, node.size * node.scale, node.rotation))
		for seat in 4: obstacles.append(view._seat_hud_rect(seat))
		t.expect(view.EXPOSED.clear(specs, obstacles), "held-hand kong including shadows clears walls, rivers, hands and controls")
		if index in [34, 54, 57] or index == record.actions.size() - 1: await _capture("viewer%d-%s-%d" % [viewer, fixture, index])
	var client := RoundState.new()
	client.apply_sync(r.serialize_for_seat(viewer))
	view.set_round(client, viewer)
	t.expect(view._exposed_layout().size() > 0, "network snapshot also places the retained-hand melds")
	await _capture("viewer%d-%s-synced" % [viewer, fixture])

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
		t.expect((node.size * node.scale).is_equal_approx(view._exposed_size(int(node.get_meta("v2_seat")))),
			"discarded and melded chickens use the same full tile dimensions")
		if int(node.get_meta("meld_index", -1)) < 0:
			t.expect(node.modulate == Color.WHITE, "discarded chickens retain their normal tile face colors")
	t.expect(view.count_kind("ordinary") == 88 and view.count_kind("red") == 24 and view._meld_layer.get_child_count() == 44,
		"viewer %d: all 96 river tiles and 60 meld tiles stay visible" % viewer)
	var obstacles: Array[Rect2] = []
	for tile in view._wall_layer.get_children():
		obstacles.append(view._visual_rect(tile))
	var occupied: Array[Rect2] = []
	var identities: Array = []
	var clear := true
	for layer in view._render_layers():
		if layer == view._wall_layer: continue
		for tile in layer.get_children():
			var rect: Rect2 = view._visual_rect(tile)
			clear = clear and G.TABLE_BOUNDS.encloses(rect) and _clear_of(rect, obstacles)
			var identity := [tile.get_meta("v2_seat",-1),tile.get_meta("meld_index",-1)]
			for j in occupied.size():
				if int(identity[1])>=0 and identity==identities[j]: continue
				clear = clear and not rect.grow(-0.05).intersects(occupied[j])
			occupied.append(rect)
			identities.append(identity)
	t.expect(clear, "viewer %d: full rivers, hands, four melds per seat and walls are separate" % viewer)
	var painted_clear := true
	for tile in view._meld_layer.get_children():
		if tile.tile != "wan6": continue
		for chicken in view._red_layer.get_children():
			if chicken.get_meta("v2_seat") != tile.get_meta("v2_seat"): continue
			painted_clear = painted_clear and not _paint_rect(tile).intersects(_paint_rect(chicken).grow(-0.05))
	t.expect(painted_clear, "viewer %d: six-character meld faces AND shadows never cover the eight-circle or chicken tiles" % viewer)
	var action: Rect2 = view.action_bar_rect(Vector2(546, 112))
	t.expect(_clear_of(action, occupied), "viewer %d: action buttons clear all public tiles except the wall" % viewer)
	var client := RoundState.new()
	client.apply_sync(r.serialize_for_seat(viewer))
	var before := _table_positions(view)
	view.set_round(client, viewer)
	var after := _table_positions(view)

	t.expect(before.size() == after.size() and before.keys().all(func(key): return after.has(key) and Vector2(before[key]).is_equal_approx(after[key])), "viewer %d: network snapshot keeps the same public tile positions" % viewer)
	await _capture("viewer%d-full-rivers-and-melds" % viewer)
	# Test eight discarded chickens at each seat in turn. Giving all four seats
	# eight would invent 32 chickens, then force them into neighbouring seats.
	for chicken_owner in 4:
		for seat in 4:
			var p: PlayerState = r.players[seat]
			p.discards = p.discards.filter(func(tile): return not Tiles.is_chicken(tile))
			if seat == chicken_owner:
				for i in 8: p.discards.append("tiao1" if i % 2 == 0 else "tong8")
			p.discard_ids = range(p.discards.size())
		r.round_meta.charge_chickens = {
			"tiao1": {"owner": chicken_owner, "location": "discard", "discard_id": 22},
			"tong8": {"owner": chicken_owner, "location": "discard", "discard_id": 23},
		}
		view.set_round(r, viewer)
		occupied.clear()
		identities.clear()
		clear = true
		for layer in view._render_layers():
			if layer == view._wall_layer: continue
			for tile in layer.get_children():
				var rect: Rect2 = view._visual_rect(tile)
				clear = clear and G.TABLE_BOUNDS.encloses(rect) and _clear_of(rect, obstacles)
				var identity := [tile.get_meta("v2_seat",-1),tile.get_meta("meld_index",-1)]
				for j in occupied.size():
					if int(identity[1])>=0 and identity==identities[j]: continue
					clear = clear and not rect.grow(-0.05).intersects(occupied[j])
				occupied.append(rect)
				identities.append(identity)
		t.expect(clear and view.count_kind("red") == 24,
			"viewer %d: seat %d keeps eight chickens and four melds within its own area" % [viewer, chicken_owner])
		t.expect(view.EXPOSED.clear(view._exposed_layout(), obstacles), "exposed tiles and shadows stay in their owner's bounded area")
		t.expect(_clear_of(action, occupied), "eight chickens never enter the action buttons")
		await _capture("viewer%d-seat%d-eight-chickens-and-melds" % [viewer, chicken_owner])

func _table_positions(view) -> Dictionary:
	var positions := {}
	for layer in view._render_layers():
		for tile in layer.get_children():
			positions[view._render_key(tile)] = tile.position
	return positions

func _paint_rect(tile: Control) -> Rect2:
	var local := Rect2(Vector2.ZERO, tile.size)
	if int(tile.get_meta("meld_index", -1)) >= 0:
		local = local.merge(Rect2(Vector2(2, 4) * tile.unit, tile.size))
	return tile.get_transform() * local

func _clear_of(rect: Rect2, obstacles: Array) -> bool:
	for other: Rect2 in obstacles:
		if rect.intersects(other.grow(-0.05)): return false
	return true

func _capture(name: String) -> void:
	if not visual: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(CAPTURES + name + ".png")
