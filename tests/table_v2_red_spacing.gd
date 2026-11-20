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
	_check_action_row_fallback(view)
	for viewer in 4:
		await _check_upstream_chain(view, viewer)
		await _check_meld_replay(view, viewer, "opposite_kong_held_hand")
		await _check_meld_replay(view, viewer, "meld_held_hand_own_area")
		await _check_full_table(view, viewer)
	view.queue_free()
	await process_frame
	quit(t.finish("table_v2_red_spacing"))

func _check_action_row_fallback(view) -> void:
	var source := TileView.new()
	view._discard_layer.add_child(source)
	var width := Vector2(750.0, 112.0)
	var preferred: Rect2 = view.action_bar_rect(width, true)
	# Synthetic pressure fixture: force the preferred band to have no horizontal gap.
	var obstacle := Rect2(0.0, preferred.position.y, G.DESIGN_SIZE.x, preferred.size.y)
	var id := source.get_instance_id()
	view._table_3d._rects[id] = obstacle
	var placed: Rect2 = view.action_bar_rect(width)
	t.expect(not placed.intersects(obstacle) and Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(placed),
		"when the entire preferred band is occupied, the action row moves to a clear band on screen")
	t.expect(placed.size == preferred.size, "moving the action row preserves the original touch targets")
	view._table_3d._rects.erase(id)
	source.free()

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
					t.expect(_public_faces_visible(view),"rendered public faces clear the retained hands")
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
	r.start_round(1, int(record.red), int(record.white), false)
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
		t.expect(_public_faces_visible(view), "held-hand kong keeps its printed area visible through the real 3D projection")
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
	# A maximum river is a late-game board; a full undealt wall cannot coexist with it.
	for i in 108: r.wall.draw_head()
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
	t.expect(view.count_kind("ordinary") == 116 and view.count_kind("red") == 24 and view._meld_layer.get_child_count() == 44,
		"viewer %d: all 124 river tiles and 60 meld tiles stay visible" % viewer)
	var obstacles: Array[Rect2] = []
	for tile in view._wall_layer.get_children():
		obstacles.append(_face_rect(view, tile))
	var occupied: Array[Rect2] = []
	var occupied_tiles: Array = []
	var identities: Array = []
	var clear := true
	var conflicts := []
	for layer in view._render_layers():
		if layer == view._wall_layer: continue
		for tile in layer.get_children():
			var rect: Rect2 = _face_rect(view, tile)
			if not Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(rect) or not _clear_of(rect, obstacles): conflicts.append([tile.get_meta("new_kind"), tile.get_meta("v2_seat"), rect])
			clear = clear and Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(rect) and _clear_of(rect, obstacles)
			var identity := [tile.get_meta("v2_seat",-1),tile.get_meta("meld_index",-1),tile.get_meta("new_kind", "")]
			for j in occupied.size():
				if int(identity[1])>=0 and identity==identities[j]: continue
				if str(identity[2]) in ["hand", "draw"] or str(identities[j][2]) in ["hand", "draw"]: continue
				if _faces_overlap(view, tile, occupied_tiles[j]): conflicts.append([identity, identities[j], rect.intersection(occupied[j])])
				clear = clear and not _faces_overlap(view, tile, occupied_tiles[j])
			occupied.append(rect)
			occupied_tiles.append(tile)
			identities.append(identity)
	t.expect(clear, "viewer %d: projected river and exposed faces stay on screen and separate: %s" % [viewer, conflicts])
	t.expect(_public_faces_visible(view), "every full-table printed face stays identifiable")
	var painted_clear := true
	for tile in view._meld_layer.get_children():
		if tile.tile != "wan6": continue
		for chicken in view._red_layer.get_children():
			if chicken.get_meta("v2_seat") != tile.get_meta("v2_seat"): continue
			# Projected faces are quadrilaterals; their bounding boxes include empty corners.
			painted_clear = painted_clear and not _faces_overlap(view, tile, chicken)
	t.expect(painted_clear, "viewer %d: six-character meld faces never cover the eight-circle or chicken tiles" % viewer)
	var action: Rect2 = view.action_bar_rect(Vector2(546, 112))
	var action_conflicts := []
	for i in occupied.size():
		if action.intersects(occupied[i]): action_conflicts.append([identities[i], occupied[i]])
	t.expect(_clear_of(action, occupied), "viewer %d: action buttons %s clear all public tiles except the wall: %s; two-button-clear=%s" % [viewer, action, action_conflicts, _clear_of(view.action_bar_rect(Vector2(366, 112)), occupied)])
	var client := RoundState.new()
	client.apply_sync(r.serialize_for_seat(viewer))
	var before := _table_positions(view)
	view.set_round(client, viewer)
	var after := _table_positions(view)

	var differences := []
	for key in before:
		if not after.has(key) or not Vector2(before[key]).is_equal_approx(after[key]): differences.append([key, before[key], after.get(key)])
	t.expect(before.size() == after.size() and differences.is_empty(), "viewer %d: network snapshot keeps the same public tile positions: %d -> %d %s" % [viewer, before.size(), after.size(), differences])
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
			"tiao1": {"owner": chicken_owner, "location": "discard", "discard_id": r.players[chicken_owner].discards.size() - 8},
			"tong8": {"owner": chicken_owner, "location": "discard", "discard_id": r.players[chicken_owner].discards.size() - 7},
		}
		view.set_round(r, viewer)
		occupied.clear()
		occupied_tiles.clear()
		identities.clear()
		clear = true
		conflicts.clear()
		for layer in view._render_layers():
			if layer == view._wall_layer: continue
			for tile in layer.get_children():
				var rect: Rect2 = _face_rect(view, tile)
				if not Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(rect) or not _clear_of(rect, obstacles): conflicts.append([tile.get_meta("new_kind"), tile.get_meta("v2_seat"), rect])
				clear = clear and Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(rect) and _clear_of(rect, obstacles)
				var identity := [tile.get_meta("v2_seat",-1),tile.get_meta("meld_index",-1),tile.get_meta("new_kind", "")]
				for j in occupied.size():
					if int(identity[1])>=0 and identity==identities[j]: continue
					if str(identity[2]) in ["hand", "draw"] or str(identities[j][2]) in ["hand", "draw"]: continue
					if _faces_overlap(view, tile, occupied_tiles[j]): conflicts.append([identity, identities[j], rect.intersection(occupied[j])])
					clear = clear and not _faces_overlap(view, tile, occupied_tiles[j])
				occupied.append(rect)
				occupied_tiles.append(tile)
				identities.append(identity)
		t.expect(clear and view.count_kind("red") == 24,
			"viewer %d: seat %d keeps eight chickens and four melds within its own area: %s" % [viewer, chicken_owner, conflicts])
		t.expect(_public_faces_visible(view), "eight chickens and four melds keep their printed faces visible")
		t.expect(view.EXPOSED.clear(view._exposed_layout(), obstacles), "exposed tiles and shadows stay in their owner's bounded area")
		t.expect(_clear_of(view.action_bar_rect(Vector2(546, 112)), occupied), "eight chickens never enter the action buttons")
		await _capture("viewer%d-seat%d-eight-chickens-and-melds" % [viewer, chicken_owner])

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

func _face_rect(view, tile: TileView) -> Rect2:
	var points := _face_polygon(view, tile)
	return Rect2(points[0], Vector2.ZERO).expand(points[1]).expand(points[2]).expand(points[3])

func _face_polygon(view, tile: TileView) -> PackedVector2Array:
	var renderer = view._table_3d
	if not renderer.tile_nodes.has(tile.get_instance_id()): renderer.sync_tiles()
	var mesh: MeshInstance3D = renderer.tile_nodes[tile.get_instance_id()]
	var points := PackedVector2Array()
	for corner in [Vector2(-0.45, -0.60), Vector2(-0.45, 0.60), Vector2(0.45, 0.60), Vector2(0.45, -0.60)]:
		points.append(renderer.camera.unproject_position(mesh.transform * Vector3(corner.x, 0.31 if tile.face_up else -0.31, corner.y)) / Vector2(renderer.viewport.size) * renderer.size)
	return points

func _faces_overlap(view, a: TileView, b: TileView) -> bool:
	return not Geometry2D.intersect_polygons(_face_polygon(view, a), _face_polygon(view, b)).is_empty()

func _public_faces_visible(view) -> bool:
	return preload("res://tests/table_3d_visibility.gd").public_faces_visible(view)
