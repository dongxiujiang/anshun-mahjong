extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const REPLAY := preload("res://scripts/core/RoundReplay.gd")
const EDGE := preload("res://tests/fixtures/projected_tile_edge.gd")
var t := H.new()

class Host extends Control:
	var round: RoundState
	var human_seat := 1
	var _table_animation_controller = null
	func _net_mode() -> String: return ""
	func _refresh() -> void: pass
	func _update_interactivity() -> void: pass
	func _pump_visual_animation() -> void: pass

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	await _recorded_other_draws()
	await _recorded_own_discards()
	await _recorded_north_chicken()
	await _recorded_added_groups()
	for number in [5, 9]: await _recorded_side_river_opening(number)
	await _recorded_north_pung_at_wall()
	for passage in [[1, 2, [27,28,29]], [1, 2, [30,31,32]], [2, 2, [29,30,31]], [2, 2, [33,34,35]], [2, 3, [39,40]]]:
		await _recorded_opponent_melds(passage[0], passage[1], passage[2])
	for screen in [Vector2i(1920, 1080), Vector2i(1920, 864)]:
		for from_seat in [2, 3, 0]: await _case(screen, from_seat)
	await _case(Vector2i(1920, 864), 3, true)
	for screen in [Vector2i(1920, 1080), Vector2i(1920, 864)]: await _case(screen, 3, false, true)
	for screen in [Vector2i(1920, 1080), Vector2i(1920, 864)]:
		for footer in [0.0, 110.0, 150.0]: await _chicken_case(screen, footer)
	await _chicken_case(Vector2i(1920, 864), 150.0, true)
	for screen in [Vector2i(1920, 1080), Vector2i(1920, 864)]:
		for footer in [0.0, 110.0, 150.0]: await _endpoint_case(screen, footer)
	await H.quit_cleanly(self, t.finish("table_3d_own_exposed_flight"))

func _recorded_side_river_opening(number: int) -> void:
	var path := "res://tests/fixtures/north-pung-r20-river-%02d.json" % number
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var action: Dictionary = data.actions.pop_back()
	var replayed := REPLAY.replay(data)
	if not t.expect(replayed.ok, "R20 round %d reaches the side river opening" % number): return
	var view = _recorded_table()
	var host: Host = view.table
	host.round = replayed.round
	view.set_round(host.round, 1)
	view._sort_started = true
	view.refresh()
	await process_frame
	var before := _north_pung_rects(view)
	var prior_count := 0 if number == 5 else 8
	t.expect(view._ordinary_count(0) == prior_count, "the right river starts with the recorded tile count")
	t.expect(host.round.submit_turn(action.seat, action.decision), "the recorded right discard is accepted")
	view.refresh()
	var after := _north_pung_rects(view)
	t.expect(view._ordinary_count(0) == prior_count + 1, "the discard opens a right river row")
	t.expect(before.size() == 3 and after == before,
		"R20 round %d north pung stays put as a side river row opens" % number)
	if number == 9:
		# The reserve touches at 14 tiles, but the rendered river still clears the pung.
		var right = host.round.players[0]
		for i in 5:
			right.discards.append("wan3")
			right.discard_ids.append(700 + i)
			right.discard_count += 1
		view.refresh()
		t.expect(view._ordinary_count(0) == 14 and _north_pung_rects(view) == before,
			"the north pung keeps its space when only the side river padding touches it")
		var spec: Dictionary = view._exposed_specs.filter(func(piece):
			return piece.seat == 3 and piece.meld_index == 0 and piece.meld_slot == 0)[0]
		var source: TileView = view._red_layer.get_children().filter(func(tile):
			return view._render_key(tile) == "red-meld:3:0:0")[0]
		var river: TileView = view._discard_layer.get_children().filter(func(tile):
			return tile.get_meta("v2_seat") == 0)[0]
		var renderer = view._table_3d
		var mesh: MeshInstance3D = renderer.tile_nodes[source.get_instance_id()]
		view._render_tiles["red-meld:3:0:0"] = source
		var obstacle: Dictionary[Rect2, Dictionary] = {spec.rect: {"seat": 0, "slot": 0, "count": 14}}
		t.expect(renderer.can_keep_north_exposed([spec], obstacle),
			"the actual side river does not block the original north tile")
		var saved := mesh.transform
		mesh.transform = renderer.tile_nodes[river.get_instance_id()].transform
		t.expect(not renderer.can_keep_north_exposed([spec], obstacle),
			"an actual mesh at the side river tile cannot keep its pose")
		mesh.transform = saved
		view._render_tiles.clear()
	host.free()

func _recorded_north_pung_at_wall() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/north-pung-r22-round16.json"))
	var actions: Array = data.actions
	data.actions = []
	data.initial.visual_session = "recorded-north-pung"
	var replayed := REPLAY.replay(data)
	if not t.expect(replayed.ok, "R22 round 16 initial state is valid"): return
	var view = _recorded_table()
	var host: Host = view.table
	host.round = replayed.round
	view.set_round(host.round, 1)
	view._sort_started = true
	view.refresh()
	await process_frame
	for index in actions.size():
		var check_placement := index in [37, 46]
		var before := _north_pung_rects(view, "wan2") if check_placement else {}
		var west_before := _recorded_west_charge_edge(view) if index == 46 else PackedVector2Array()
		var action: Dictionary = actions[index]
		var accepted := host.round.submit_turn(action.seat, action.decision) if action.kind == "turn" \
			else host.round.submit_response(action.seat, action.tile, action.decision)
		if not t.expect(accepted, "R22 round 16 action %d is legal" % (index + 1)): break
		view.refresh()
		if not check_placement: continue
		var after := _north_pung_rects(view, "wan2")
		t.expect(before.size() == 3 and after == before,
			"R22 round 16 north pung stays put after side discard %d" % (index + 1))
		if index == 46:
			var west_after := _recorded_west_charge_edge(view)
			t.expect(west_before.size() == 2 and west_after == west_before,
				"R22 round 16 west charge retains its visible placement on action 47")
	host.free()

func _recorded_west_charge_edge(view) -> PackedVector2Array:
	var charges: Array = view._red_layer.get_children().filter(func(tile):
		return tile.tile == "tong8" and tile.get_meta("v2_seat", -1) == 2 and tile.get_meta("v2_charge", false))
	var neighboring_pung: Array = view._meld_layer.get_children().filter(func(tile):
		return tile.tile == "wan8" and tile.get_meta("v2_seat", -1) == 2 and tile.get_meta("meld_index", -1) == 1)
	if not t.expect(charges.size() == 1 and neighboring_pung.size() == 3, "the recorded charge has its adjacent eight-character pung"):
		return PackedVector2Array()
	var renderer = view._table_3d
	var charge: TileView = charges[0]
	var edge := EDGE.near_top(renderer, renderer.tile_nodes[charge.get_instance_id()], Vector3.LEFT)
	var reference := EDGE.nearest_meld(renderer, neighboring_pung, edge, Vector3.LEFT)
	var offsets := EDGE.pixel_offsets(reference, edge).abs()
	t.expect(maxf(offsets.x, offsets.y) <= 1.0, "the west charge follows the visible eight-character top edge")
	_check_recorded_face(renderer, charge, view._dealer_meld_badges[2])
	return edge

func _north_pung_rects(view, card: String = "tiao1") -> Dictionary:
	var renderer = view._table_3d
	renderer.sync_tiles()
	var rects := {}
	for tile in view._red_layer.get_children() + view._meld_layer.get_children():
		if tile.tile != card or tile.get_meta("v2_seat", -1) != 3 or tile.get_meta("meld_index", -1) != 0: continue
		rects[tile.get_meta("meld_slot")] = renderer.project_tile(tile)
		_check_recorded_face(renderer, tile, view._dealer_meld_badges[3])
	return rects

func _recorded_added_groups() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/added-exposed-r15-round3.json"))
	var actions: Array = data.actions
	data.actions = actions.slice(0, 14)
	var replayed := REPLAY.replay(data)
	if not t.expect(replayed.ok, "R15 round 3 reaches the first own pung"): return
	var view = _recorded_table()
	var host: Host = view.table
	host.round = replayed.round
	view.set_round(host.round, 1)
	view._sort_started = true
	view.refresh()
	await process_frame
	var previous := {}
	for i in range(14, actions.size()):
		var action: Dictionary = actions[i]
		var ok := host.round.submit_turn(action.seat, action.decision) if action.kind == "turn" else host.round.submit_response(action.seat, action.tile, action.decision)
		if not t.expect(ok, "R15 recorded action %d accepted" % (i + 1)): break
		if i == 14 or i == 49:
			view.animate_meld(data.events[0 if i == 14 else 4], Callable())
			await create_timer(0.65).timeout
		elif i == 38:
			var discard: Dictionary = data.events[1]
			view.animate_draw_insert(1, discard.tile, discard.draw_tile, Callable(), int(discard.discard_index), discard.hand_slot_map)
			await create_timer(0.65).timeout
			var draw: Dictionary = data.events[2]
			view.animate_draw(draw.seat, draw.tile, draw.wall_index, Callable())
			await create_timer(0.4).timeout
		view.refresh()
		var renderer = view._table_3d
		renderer.sync_tiles()
		if i not in [37, 38, 48, 49]: continue
		var keys := ["meld:1:0:0", "meld:1:0:1", "meld:1:0:2"] if i <= 38 else ["red-discard:2:4"]
		var current := {}
		for source in view._meld_layer.get_children() + view._red_layer.get_children():
			var key: String = view._render_key(source)
			if key in keys: current[key] = renderer.project_tile(source)
			if i in [38, 49] and source.face_up:
				_check_recorded_face(renderer, source, view._dealer_meld_badges[int(source.get_meta("v2_seat"))])
		t.expect(current.size() == keys.size(), "R15 old group is drawn in full")
		if i in [38, 49]:
			for key in keys:
				t.expect(current.has(key) and previous.has(key) and current[key].is_equal_approx(previous[key]),
					"R15 stable %s through added group at action %d" % [key, i + 1])
		previous = current
	host.free()

func _recorded_north_chicken() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/red-exposed-r14-round1.json"))
	var actions: Array = data.actions
	data.actions = actions.slice(0, 20)
	var replayed: Dictionary = REPLAY.replay(data)
	t.expect(replayed.ok, "R14 chicken replay reaches the response to eight wan")
	if not replayed.ok: return
	var view = _recorded_table()
	var host: Host = view.table
	host.round = replayed.round
	view.set_round(host.round, 1)
	view._sort_started = true
	view.refresh()
	await process_frame
	var pung: Dictionary = data.events[0]
	t.expect(host.round.submit_response(0, "wan8", actions[20].decision), "recorded event 49 pung accepted")
	view.animate_meld(pung, Callable())
	await create_timer(0.7).timeout
	view.refresh()
	var landed: Rect2 = _north_chicken_face(view)
	var discard: Dictionary = data.events[1]
	var draw: Dictionary = data.events[2]
	t.expect(host.round.submit_turn(0, actions[21].decision), "recorded event 50 discard accepted")
	view.animate_hand_discard(0, discard.tile, int(discard.discard_hand_index), Callable())
	await create_timer(0.5).timeout
	view.animate_draw(3, draw.tile, int(draw.wall_index), Callable())
	await create_timer(0.4).timeout
	view.refresh()
	t.expect(_north_chicken_face(view).is_equal_approx(landed), "north chicken stays at its legal landing across events 50 and 51")
	_check_chicken_placement_changes(view)
	host.free()

func _north_chicken_face(view) -> Rect2:
	view._table_3d.sync_tiles()
	for tile in view._red_layer.get_children():
		if int(tile.get_meta("v2_seat", -1)) == 3 and tile.tile == "tong8":
			_check_recorded_face(view._table_3d, tile, view._dealer_meld_badges[3])
			return view._table_3d.project_tile(tile)
	t.expect(false, "the recorded north chicken is visible")
	return Rect2()


func _check_chicken_placement_changes(view) -> void:
	var original: Array = view._exposed_specs.duplicate(true)
	var placement: Array = view._exposed_placement_key.duplicate(true)
	t.expect(view.EXPOSED.solve(view) != original, "the saved layout differs from first-free in this snapshot")
	var north_chicken := func(piece): return piece.seat == 3 and piece.tile == "tong8"
	var original_center: Vector2 = original.filter(north_chicken)[0].center
	var wall = view._wall_layer.get_child(0)
	var wall_position: Vector2 = wall.position
	wall.position = original_center - wall.size / 2
	var obstruction: Rect2 = view.EXPOSED.rect_for(wall.position + wall.size / 2, wall.size * wall.scale, wall.rotation)
	var relocated: Array = view._exposed_layout().filter(north_chicken)
	t.expect(relocated.size() == 1 and not relocated[0].center.is_equal_approx(original_center) and not relocated[0].rect.grow(-0.05).intersects(obstruction),
		"a real wall entity occupying the previous chicken landing forces a clear relocation")
	wall.position = wall_position

	var state: RoundState = view.round
	var host: Host = view.table
	var session := state._presentation.session
	var scale_before := host.scale
	var from_seat: int = state.players[0].melds[0].from_seat
	var reveal_before: bool = view.test_reveal_all_hands
	var formal_before: bool = view.formal_mode
	for changed in ["session", "viewport transform", "face reveal", "pung source", "kong upgrade", "human seat", "settled"]:
		# Each change starts with the same proven, legal placement, distinct from a fresh solve.
		view._exposed_specs = original.duplicate(true)
		view._exposed_placement_key = placement.duplicate(true)
		match changed:
			"session": state._presentation.session = "new-round"
			"viewport transform": host.scale = scale_before * 0.97
			"face reveal":
				view.test_reveal_all_hands = true
				view.formal_mode = false
			"pung source": state.players[0].melds[0].from_seat = posmod(from_seat + 1, 4)
			"kong upgrade": state.players[0].melds[0].kind = "kong"
			"human seat": view.human_seat = 2
			"settled": state.phase = RoundState.Phase.SETTLED
		view._invalidate_exposed_layout()
		var actual: Array = view._exposed_layout()
		t.expect(actual == view.EXPOSED.solve(view), "a change in %s yields current geometry and metadata" % changed)
		t.expect(view._exposed_placement_key != placement, "previous placement identity expires after a change in " + changed)
		state._presentation.session = session
		host.scale = scale_before
		view.test_reveal_all_hands = reveal_before
		view.formal_mode = formal_before
		state.players[0].melds[0].from_seat = from_seat
		state.players[0].melds[0].kind = "pung"
		view.human_seat = 1
		state.phase = RoundState.Phase.PLAYING

func _recorded_table():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 1000)
	var host := Host.new()
	host.size = G.DESIGN_SIZE
	# Match the recorded Android table's top/side safe margins and 90 px footer.
	var margin := float(preload("res://scripts/ui/table/TableUiConfig.gd").SAFE_MARGIN) * root.size.x / G.DESIGN_SIZE.x
	host.position = Vector2(margin, margin)
	host.scale = (Vector2(root.size) - Vector2(2.0 * margin, margin)) / G.DESIGN_SIZE
	root.add_child(host)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
	view.test_touch_height = 90.0 / host.scale.y
	host.add_child(view)
	view.table = host
	view.auto_sort_hands = false
	return view

func _recorded_other_draws() -> void:
	# Real R10 Android round 1, recorded actions 0–33 and draw events 70/72.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/own-exposed-r10-round1.json"))
	var actions: Array = data.actions
	var view = _recorded_table()
	var host: Host = view.table
	var positions := []
	for count in [32, 33, 34]:
		data.actions = actions.slice(0, count)
		var state := REPLAY.replay(data)
		t.expect(state.ok, "the real round replays to action %d" % count)
		if not state.ok: break
		host.round = state.round
		t.expect(host.round.players[1].melds.size() == 1 and host.round.players[1].melds[0].from_seat == 2, "own pung still has its original source")
		view.set_round(host.round, 1)
		view._sort_started = true
		view.refresh()
		await process_frame
		t.expect(view._wall_layer.get_child_count() == 28 - (count - 32), "the wall loses a real tile after each recorded draw")
		if count > 32:
			var draw: Dictionary = data.events[1 if count == 33 else 3]
			view.animate_draw(int(draw.seat), str(draw.tile), int(draw.wall_index), Callable())
			positions.append(_recorded_exposed_positions(view))
			view._finish_pending_draw(int(draw.seat))
		positions.append(_recorded_exposed_positions(view))
	for i in range(1, positions.size()):
		for piece in positions[0]:
			var before: Rect2 = positions[0][piece]
			var after: Rect2 = positions[i][piece]
			t.expect(before.is_equal_approx(after),
				"stationary %s stays beside the hand during recorded draws (%s -> %s)" % [piece, before, after])
	host.free()

func _recorded_own_discards() -> void:
	# Real R11 Android round 1, first 26 actions; own pungs 41/49 and discards 42/50.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/own-exposed-r11-round1.json"))
	var actions: Array = data.actions
	var view = _recorded_table()
	var host: Host = view.table
	var renderer = view._table_3d
	var previous := {}
	for count in [20, 21, 25, 26]:
		data.actions = actions.slice(0, count)
		var state := REPLAY.replay(data)
		t.expect(state.ok, "real R11 prefix %d replays" % count)
		if not state.ok: break
		host.round = state.round
		view.set_round(host.round, 1)
		view._sort_started = true
		view.refresh()
		await process_frame
		renderer.sync_tiles()
		view._layout_meld_badges()
		var dealer: Label = view._dealer_meld_badges[1]
		var hand_count: int = view.hand_boxes[1].get_child_count()
		t.expect(hand_count == {20: 11, 21: 10, 25: 8, 26: 7}[count], "the local hand loses one tile on each ordinary discard")
		var poses := {}
		for source in view._meld_layer.get_children():
			if int(source.get_meta("v2_seat", -1)) != 1: continue
			poses[view._render_key(source)] = renderer.project_tile(source)
			_check_recorded_face(renderer, source, dealer)
		t.expect(poses.size() == (3 if count <= 21 else 6), "complete own pung(s) present")
		if dealer.visible: poses.dealer = dealer.get_rect()
		if count in [21, 26]:
			for key in previous:
				t.expect(previous[key].is_equal_approx(poses[key]),
					"ordinary discard after %d actions keeps %s at its legal position (%s -> %s)" % [count, key, previous[key], poses[key]])
		previous = poses
	var revision: int = renderer.geometry_revision
	renderer.sync_tiles()
	renderer.sync_tiles()
	t.expect(renderer.geometry_revision == revision, "two idle syncs with two exposed pungs do not redraw")
	# A separated opponent draw can extend the hand's bounding box across the
	# pung while leaving every actual tile clear (also seen in R10 action 45).
	var first: TileView = view._meld_layer.get_children().filter(func(s): return int(s.get_meta("v2_seat", -1)) == 1)[0]
	var side: MeshInstance3D = renderer.tile_nodes[view.hand_boxes[2].get_child(0).get_instance_id()]
	var side_pose := side.transform
	var second: TileView = view._meld_layer.get_children().filter(func(s): return view._render_key(s) == "meld:1:1:0")[0]
	var second_rect: Rect2 = renderer.project_tile(second)
	side.position = renderer._at_height(second_rect.get_center() + Vector2.DOWN * second_rect.size.y * 2.0, side.position.y)
	var moved: Array[MeshInstance3D] = []
	renderer._clear_own_exposed_faces(moved)
	t.expect(renderer._own_exposed_left_hand.intersects(second_rect) and not renderer._project_mesh(side).intersects(second_rect), "the separated hand spans an empty gap over the second pung")
	t.expect(renderer.project_tile(second).is_equal_approx(second_rect), "empty space inside a hand's bounding box preserves the landing")
	side.transform = side_pose
	# An actual landed river tile across the artwork must invalidate the cache.
	renderer._clear_own_exposed_faces(moved)
	var before: Rect2 = renderer.project_tile(first)
	var river: TileView = view._discard_layer.get_child(0)
	renderer.tile_nodes[river.get_instance_id()].transform = renderer.tile_nodes[first.get_instance_id()].transform
	renderer._clear_own_exposed_faces(moved)
	var after: Rect2 = renderer.project_tile(first)
	t.expect(not before.is_equal_approx(after) and renderer.pick_tile(after.get_center(), false) == first, "a real occupied position is repacked and readable")
	host.free()

func _recorded_opponent_melds(number: int, seat: int, counts: Array) -> void:
	# R13 real rounds. The left seat draws/discards while the north seat's
	# existing pungs stay clear of the right river as it grows from five to six.
	var fixture := "res://tests/fixtures/side-exposed-r13-%02d.json" % number
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture))
	var actions: Array = data.actions
	var view = _recorded_table()
	var host: Host = view.table
	var baseline := {}
	for count in counts:
		data.actions = actions.slice(0, count)
		var state := REPLAY.replay(data)
		if not t.expect(state.ok, "real R13 round %d replays through %d actions" % [number, count]): break
		host.round = state.round
		view.set_round(host.round, 1)
		view._sort_started = true
		view.refresh()
		await process_frame
		view._table_3d.sync_tiles()
		var poses := {}
		for source in view._meld_layer.get_children() + view._red_layer.get_children():
			if int(source.get_meta("v2_seat", -1)) != seat: continue
			poses[view._render_key(source)] = view._table_3d.project_tile(source)
			_check_recorded_face(view._table_3d, source, view._dealer_meld_badges[seat])
		if baseline.is_empty(): baseline = poses.duplicate()
		t.expect(poses.size() == baseline.size() and poses.size() >= 6, "original exposed groups present")
		for key in baseline:
			t.expect(poses.has(key) and baseline[key].is_equal_approx(poses[key]),
				"R13 round %d seat %d piece %s stays put through ordinary action %d" % [number, seat, key, count])
	host.free()

func _recorded_exposed_positions(view) -> Dictionary:
	var renderer = view._table_3d
	renderer.sync_tiles()
	view._layout_meld_badges()
	var dealer: Label = view._dealer_meld_badges[1]
	t.expect(dealer.visible, "the dealer badge is visible in the recorded round")
	var result := {"dealer": dealer.get_rect()}
	var hand_left := INF
	for tile in view.hand_boxes[1].get_children():
		hand_left = minf(hand_left, renderer.project_tile(tile).position.x)
	for source in view._meld_layer.get_children() + view._red_layer.get_children():
		if int(source.get_meta("v2_seat", -1)) != 1: continue
		var tile_rect: Rect2 = renderer.project_tile(source)
		t.expect(tile_rect.get_center().x < hand_left, "the exposed group stays on the hand's left")
		result["%s_%d" % [source.tile, source.get_meta("meld_slot", -1)]] = tile_rect
		_check_recorded_face(renderer, source, dealer)
	t.expect(result.size() == 5 and result.has("wan7_0") and result.has("tong8_-1"), "all three pung tiles and the chicken are present")
	return result

func _check_recorded_face(renderer, source: TileView, dealer: Label) -> void:
	var mesh: MeshInstance3D = renderer.tile_nodes[source.get_instance_id()]
	var sideways: bool = int(source.get_meta("meld_sideways", -1)) >= 0
	for x in ([-0.45, 0.0, 0.45] if sideways else [-0.38, 0.0, 0.38]):
		for z in ([-0.60, 0.0, 0.60] if sideways else [-0.50, 0.0, 0.50]):
			var point: Vector2 = renderer.camera.unproject_position(mesh.transform * Vector3(x, 0.311, z)) / Vector2(renderer.viewport.size) * renderer.size
			var picked: TileView = renderer.pick_tile(point, false)
			t.expect(picked == source and not (dealer.visible and dealer.get_rect().has_point(point)),
				"recorded %s face at %s is visible (picked %s)" % [source.tile, Vector2(x, z), picked.tile if picked != null else "none"])

func _case(screen: Vector2i, from_seat: int, cancel: bool = false, existing: bool = false) -> void:
	root.get_node("UpdateManager").auto_check = false
	var config = root.get_node("GameConfig")
	var old_duration: float = config.tile_motion_seconds()
	config.set_tile_animation_seconds(0.30, false)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	Engine.max_fps = 60
	root.size = screen
	var host := Host.new()
	host.size = G.DESIGN_SIZE
	host.scale = Vector2(root.size) / G.DESIGN_SIZE
	root.add_child(host)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
	view.test_touch_height = 150.0
	host.add_child(view)
	view.table = host
	view.auto_sort_hands = false
	view._sort_started = true
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/own-exposed-round1.json"))
	var prefix := data.duplicate(true)
	prefix.actions = prefix.actions.slice(0, 3)
	var before: Dictionary = REPLAY.replay(prefix)
	var after: Dictionary = REPLAY.replay(data)
	t.expect(before.ok and after.ok, "real Android record replays through discard and kong")
	# Opposite is the exact record; left/right permute AI seats for geometry coverage.
	if from_seat != 3:
		for state in [before.round, after.round]:
			var other: PlayerState = state.players[from_seat]
			state.players[from_seat] = state.players[3]
			state.players[3] = other
			state.players[from_seat].seat = from_seat
			state.players[3].seat = 3
		after.round.players[1].melds[0].from_seat = from_seat
	if existing:
		# Geometry fixture: add a previous pung and remove three non-kong hand
		# cards from both states. Exact record provenance remains the case above.
		var removed := []
		for card in before.round.players[1].concealed:
			if card != "wan9" and card != after.round.players[1].just_drew and removed.size() < 3: removed.append(card)
		for state in [before.round, after.round]:
			for card in removed: state.players[1].concealed.erase(card)
			state.players[1].melds.push_front({"kind": "pung", "tile": "tiao9", "from_seat": 2, "revealed": true})
	host.round = before.round
	for player in host.round.players: player.ready = true
	view.set_round(host.round, 1)
	view._sort_started = true
	view.refresh()
	await process_frame
	var event: Dictionary = data.events.filter(func(e): return e.type == "meld")[0]
	event.hand_indices = event.hand_indices.map(func(index): return int(index))
	event.source = from_seat
	if existing:
		event.index = 1
		event.hand_indices = []
		for index in before.round.players[1].concealed.size():
			if before.round.players[1].concealed[index] == "wan9": event.hand_indices.append(index)
	var moving: Array = []
	for source in view.hand_boxes[1].get_children():
		if event.hand_indices.has(int(source.get_meta("concealed_index", -1))): moving.append(source)
	for source in view._discard_layer.get_children():
		if int(source.get_meta("v2_seat", -1)) == int(event.source) and int(source.get_meta("discard_id", -1)) == int(event.source_discard_id): moving.append(source)
	t.expect(moving.size() == 4, "four actual origin entities exist before kong")
	var remaining: Array = view.hand_boxes[1].get_children().filter(func(source): return not moving.has(source))
	var saved := []
	for source in remaining:
		var meta := {}
		for key in source.get_meta_list(): meta[key] = source.get_meta(key)
		saved.append({"position": source.position, "meta": meta, "interactive": source.interactive})
	var all_ids := _tile_ids(view)
	host.round = after.round
	for player in host.round.players: player.ready = true
	view.round = host.round
	var fingerprint: String = REPLAY.fingerprint(host.round)
	var complete := {"count": 0, "sound": 0}
	var audio = root.get_node("AudioManager")
	var heard := func(): complete.sound += 1
	audio.discard_impact_played.connect(heard)
	var samples := []
	var renderer = view._table_3d
	var previous := {}
	var landing_max := 0.0
	var first := {}
	for source in moving:
		var mesh: MeshInstance3D = renderer.tile_nodes.get(source.get_instance_id())
		if mesh != null: first[source.get_instance_id()] = renderer.camera.unproject_position(mesh.position) / Vector2(renderer.viewport.size) * renderer.size
	view.animate_meld(event, func(): complete.count += 1)
	# Inspect the return state before any test-driven sync can hide a preview flash.
	for id in first:
		t.expect(renderer.tile_nodes[id].position.is_equal_approx(renderer._own_exposed_origins[id]), "animate returns with the moving mesh at its real origin, not the preview land pose")
	for id in renderer._own_exposed_targets:
		if not first.has(id): t.expect(renderer.tile_nodes[id].transform.is_equal_approx(renderer._own_exposed_previous[id]), "existing groups retain their original pose at flight t=0")
	_assert_terminal_pose(view, moving, event)
	t.expect(_tile_ids(view) == all_ids, "preview creates and removes no tile entities")
	t.expect(complete.count == 0 and view._visual_actions.size() == 1, "preview does not consume or complete the native action")
	t.expect(view.hand_boxes[1].get_children() == remaining, "preview restores remaining-hand child order")
	for index in remaining.size():
		var source: TileView = remaining[index]
		var meta := {}
		for key in source.get_meta_list(): meta[key] = source.get_meta(key)
		t.expect(source.position == saved[index].position and meta == saved[index].meta and source.interactive == saved[index].interactive, "preview restores remaining hand position, metadata and interactivity")
	var started := Time.get_ticks_msec()
	var late_max := 0.0
	var out := OS.get_environment("OWN_EXPOSED_FLIGHT_CAPTURE")
	var label := "%dx%d-source%d%s" % [screen.x, screen.y, from_seat, "-second-group" if existing else ""]
	var pictures := 0
	var existing_previous := {}
	var existing_max := 0.0
	while (Time.get_ticks_msec() - started < 800 or complete.count == 0) and Time.get_ticks_msec() - started < 5000:
		await process_frame
		if cancel and Time.get_ticks_msec() - started > 100:
			view._reset_round_visual_state()
			await create_timer(0.45).timeout
			t.expect(complete.count == 0 and not view.native_actions_pending(), "cancelled preview cannot fire a stale completion")
			t.expect(renderer._own_exposed_targets.is_empty() and renderer._own_exposed_origins.is_empty() and renderer._own_exposed_previous.is_empty(), "cancel clears all temporary target caches")
			t.expect(complete.sound == 0 and REPLAY.fingerprint(host.round) == fingerprint, "cancel preserves authority and emits no sound")
			audio.discard_impact_played.disconnect(heard)
			config.set_tile_animation_seconds(old_duration, false)
			host.queue_free()
			await process_frame
			return
		renderer.sync_tiles()
		for id in renderer._own_exposed_targets:
			if first.has(id): continue
			var point: Vector2 = renderer.camera.unproject_position(renderer.tile_nodes[id].position) / Vector2(renderer.viewport.size) * renderer.size
			if existing_previous.has(id): existing_max = maxf(existing_max, point.distance_to(existing_previous[id]))
			existing_previous[id] = point
			var progress: float = moving[0].flight_progress if moving[0].get_parent() == view._deal_layer else 1.0
			var amount := 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 3.0)
			var expected: Transform3D = renderer._own_exposed_previous[id].interpolate_with(renderer._own_exposed_targets[id], amount)
			t.expect(renderer.tile_nodes[id].transform.is_equal_approx(expected), "existing group follows the shared continuous progress, not an immediate final pose")
		var capture := false
		for source in moving:
			var id: int = source.get_instance_id()
			var mesh: MeshInstance3D = renderer.tile_nodes.get(id)
			if mesh == null: continue
			var point: Vector2 = renderer.camera.unproject_position(mesh.position) / Vector2(renderer.viewport.size) * renderer.size
			var flying: bool = source.get_parent() == view._deal_layer
			var row := {"id": id, "ms": Time.get_ticks_msec() - started, "flying": flying, "progress": source.flight_progress, "xy": [point.x, point.y]}
			if previous.has(id):
				var distance := point.distance_to(Vector2(previous[id].xy[0], previous[id].xy[1]))
				if previous[id].flying and not flying: landing_max = maxf(landing_max, distance)
				if not previous[id].flying or previous[id].progress > 0.85: late_max = maxf(late_max, distance)
			if pictures == 0 and flying and source.flight_progress > 0.85: capture = true
			if pictures in [1,2] and not flying: capture = true
			samples.append(row)
			previous[id] = row
		if capture and not out.is_empty() and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(out)
			root.get_texture().get_image().save_png(out.path_join("%s-%d.png" % [label, pictures]))
			pictures += 1
	t.expect(complete.count == 1 and not view.native_actions_pending(), "kong completes once and releases the action queue")
	t.expect(landing_max < 30.0 and late_max < 30.0, "last flight, landing and hand-centering frames remain continuous")
	for source in moving:
		var id: int = source.get_instance_id()
		var last: Dictionary = previous.get(id, {})
		if not last.is_empty(): t.expect(first[id].distance_to(Vector2(last.xy[0], last.xy[1])) > 200.0, "own and claimed tiles retain their complete origin-to-meld path")
	t.expect(renderer._own_exposed_targets.is_empty() and renderer._own_exposed_origins.is_empty() and renderer._own_exposed_previous.is_empty(), "completion invalidates all preview target caches")
	t.expect(complete.sound == 0, "preview emits no extra impact sound")
	t.expect(REPLAY.fingerprint(host.round) == fingerprint, "preview and animation preserve authoritative rules and score")
	print("[own-exposed-flight] ", label, " landing=", landing_max, " late=", late_max, " existing=", existing_max)
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		var file := FileAccess.open(out.path_join(label + ".json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"landing_max_design_units": landing_max, "late_max_design_units": late_max, "samples": samples}))
	audio.discard_impact_played.disconnect(heard)
	view._reset_round_visual_state()
	config.set_tile_animation_seconds(old_duration, false)
	host.queue_free()
	await process_frame

func _chicken_case(screen: Vector2i, footer: float, cancel: bool = false) -> void:
	var config = root.get_node("GameConfig")
	var old_duration: float = config.tile_motion_seconds()
	config.set_tile_animation_seconds(0.30, false)
	root.size = screen
	var host := Host.new()
	host.size = G.DESIGN_SIZE
	host.scale = Vector2(screen) / G.DESIGN_SIZE
	root.add_child(host)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
	view.test_touch_height = footer
	host.add_child(view)
	view.table = host
	view.auto_sort_hands = false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/own-exposed-round1.json"))
	var prefix := data.duplicate(true)
	prefix.actions = []
	var before: Dictionary = REPLAY.replay(prefix)
	prefix.actions = data.actions.slice(0, 1)
	var after: Dictionary = REPLAY.replay(prefix)
	t.expect(before.ok and after.ok, "real rooster discard replays")
	host.round = before.round
	for player in host.round.players: player.ready = true
	view.set_round(host.round, 1)
	view._sort_started = true
	view.refresh()
	await process_frame
	var event: Dictionary = data.events.filter(func(e): return e.type == "discard" and int(e.seat) == 1)[0]
	var moving: TileView
	for source in view.hand_boxes[1].get_children():
		if int(source.get_meta("concealed_index", -1)) == int(event.discard_index): moving = source
	t.expect(moving != null and view.draw_boxes[1].get_child_count() == 1, "actual rooster starts in the hand with the original draw entity")
	var saved := []
	for source in view.hand_boxes[1].get_children() + view.draw_boxes[1].get_children():
		if source == moving: continue
		var meta := {}
		for key in source.get_meta_list(): meta[key] = source.get_meta(key)
		# The discard legitimately leaves the hand before preview takes its snapshot.
		var index: int = source.get_index() - (1 if source.get_parent() == moving.get_parent() and source.get_index() > moving.get_index() else 0)
		saved.append({"source": source, "parent": source.get_parent(), "index": index, "position": source.position, "meta": meta, "interactive": source.interactive})
	var all_ids := _tile_ids(view)
	host.round = after.round
	for player in host.round.players: player.ready = true
	view.round = host.round
	var fingerprint: String = REPLAY.fingerprint(host.round)
	var complete := {"count": 0, "sound": 0}
	var audio = root.get_node("AudioManager")
	var heard := func(): complete.sound += 1
	audio.discard_impact_played.connect(heard)
	view.animate_draw_insert(1, "tiao1", str(event.draw_tile), func(): complete.count += 1, int(event.discard_index), event.hand_slot_map)
	var renderer = view._table_3d
	var id: int = moving.get_instance_id()
	var origin: Vector3 = renderer._own_exposed_origins[id]
	t.expect(renderer.tile_nodes[id].position.is_equal_approx(origin), "rooster preview returns at the real origin before any test sync")
	t.expect(_tile_ids(view) == all_ids and complete.count == 0, "rooster preview neither replaces entities nor completes the action")
	for state in saved:
		var meta := {}
		for key in state.source.get_meta_list(): meta[key] = state.source.get_meta(key)
		t.expect(state.source.get_parent() == state.parent and state.source.get_index() == state.index and state.source.position == state.position and meta == state.meta and state.source.interactive == state.interactive, "rooster preview restores remaining and drawn child order, state and interaction: %s index=%s/%s pos=%s meta=%s parent=%s" % [state.source.tile, state.source.get_index(), state.index, state.source.position == state.position, meta == state.meta, state.source.get_parent() == state.parent])
	var flight: Dictionary = view._discard_flights.values()[0]
	var pose := [moving.position, moving.scale, moving.rotation, moving.flight_pitch, moving.flight_progress]
	moving.position = Vector2(flight.target) - moving.size / 2.0
	moving.scale = view._exposed_size(1) / moving.size
	moving.rotation = flight.angle
	moving.flight_pitch = 0.0
	moving.flight_progress = 1.0
	renderer.sync_tiles()
	t.expect(renderer.tile_nodes[id].transform.is_equal_approx(renderer._own_exposed_targets[id]), "rooster t=1 full mesh pose equals its final land pose")
	moving.position = pose[0]
	moving.scale = pose[1]
	moving.rotation = pose[2]
	moving.flight_pitch = pose[3]
	moving.flight_progress = pose[4]
	renderer.sync_tiles()
	var previous := {}
	var samples := []
	var landing := 0.0
	var late := 0.0
	var pictures := 0
	var out := OS.get_environment("OWN_EXPOSED_FLIGHT_CAPTURE")
	var label := "chicken-%dx%d-footer%d" % [screen.x, screen.y, footer]
	var started := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - started < 800 or complete.count == 0) and Time.get_ticks_msec() - started < 5000:
		await process_frame
		if cancel and Time.get_ticks_msec() - started > 100:
			view._reset_round_visual_state()
			await create_timer(0.45).timeout
			break
		renderer.sync_tiles()
		var point: Vector2 = renderer.camera.unproject_position(renderer.tile_nodes[id].position) / Vector2(renderer.viewport.size) * renderer.size
		var flying: bool = moving.get_parent() == view._deal_layer
		if not previous.is_empty():
			var distance := point.distance_to(Vector2(previous.xy[0], previous.xy[1]))
			if previous.flying and not flying: landing = maxf(landing, distance)
			if not previous.flying or previous.progress > 0.85: late = maxf(late, distance)
		previous = {"ms": Time.get_ticks_msec() - started, "flying": flying, "progress": moving.flight_progress, "xy": [point.x, point.y]}
		samples.append(previous)
		if not out.is_empty() and DisplayServer.get_name() != "headless" and ((pictures == 0 and flying and moving.flight_progress > 0.85) or (pictures in [1, 2] and not flying)):
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute(out)
			root.get_texture().get_image().save_png(out.path_join("%s-%d.png" % [label, pictures]))
			pictures += 1
	t.expect(complete.count == (0 if cancel else 1) and not view.native_actions_pending(), "rooster completes once, or cancels without a stale callback")
	t.expect(renderer._own_exposed_targets.is_empty() and renderer._own_exposed_origins.is_empty() and renderer._own_exposed_previous.is_empty(), "rooster completion/cancel invalidates every preview cache")
	t.expect(complete.sound == 0 and REPLAY.fingerprint(host.round) == fingerprint, "rooster preview adds no sound and preserves authoritative state")
	if not cancel:
		t.expect(landing < 30.0 and late < 30.0, "rooster flight/land/hand-centering remain continuous")
		t.expect(renderer.tile_nodes[id].position.distance_to(origin) > 1.0, "rooster retains its full hand-to-exposed travel")
		print("[own-chicken-flight] ", label, " landing=", landing, " late=", late)
		if not out.is_empty():
			DirAccess.make_dir_recursive_absolute(out)
			var file := FileAccess.open(out.path_join(label + ".json"), FileAccess.WRITE)
			file.store_string(JSON.stringify({"landing_max_design_units": landing, "late_max_design_units": late, "samples": samples}))
	audio.discard_impact_played.disconnect(heard)
	view._reset_round_visual_state()
	config.set_tile_animation_seconds(old_duration, false)
	host.queue_free()
	await process_frame

func _tile_ids(view) -> Array:
	var ids := []
	for layer in view._render_layers() + [view._deal_layer]:
		for source in layer.get_children():
			if source is TileView: ids.append(source.get_instance_id())
	ids.sort()
	return ids

func _assert_terminal_pose(view, moving: Array, event: Dictionary) -> void:
	var renderer = view._table_3d
	var ordered := moving.duplicate()
	if G.exposed_kong_source_slot(1, int(event.source)) == 0: ordered.push_front(ordered.pop_back())
	var layout: Array = view._live_exposed_layout(1).filter(func(spec): return int(spec.meld_index) == int(event.index))
	var saved := []
	for slot in ordered.size():
		var source: TileView = ordered[slot]
		saved.append({"node": source, "position": source.position, "scale": source.scale, "rotation": source.rotation, "pitch": source.flight_pitch, "progress": source.flight_progress})
		var spec: Dictionary = layout.filter(func(row): return int(row.meld_slot) == slot)[0]
		source.position = Vector2(spec.center) - source.size / 2.0
		source.scale = view._exposed_size(1) / source.size
		source.rotation = PI / 2.0 if spec.sideways else 0.0
		source.flight_pitch = 0.0
		source.flight_progress = 1.0
	renderer.sync_tiles()
	for source in ordered:
		var id: int = source.get_instance_id()
		var mesh: MeshInstance3D = renderer.tile_nodes[id]
		var target: Transform3D = renderer._own_exposed_targets[id]
		t.expect(mesh.transform.is_equal_approx(target), "flight t=1 mesh transform equals actual cached land transform")
		for x in [-0.45, 0.45]:
			for z in [-0.60, 0.60]:
				var face := Vector3(x, 0.31, z)
				var before: Vector2 = renderer.camera.unproject_position(mesh.transform * face) / Vector2(renderer.viewport.size) * renderer.size
				var after: Vector2 = renderer.camera.unproject_position(target * face) / Vector2(renderer.viewport.size) * renderer.size
				t.expect(before.distance_to(after) < 0.01, "flight t=1 and land artwork corners coincide")
	for state in saved:
		state.node.position = state.position
		state.node.scale = state.scale
		state.node.rotation = state.rotation
		state.node.flight_pitch = state.pitch
		state.node.flight_progress = state.progress
	renderer.sync_tiles()

func _endpoint_case(screen: Vector2i, footer: float) -> void:
	root.get_node("UpdateManager").auto_check = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = screen
	var config = root.get_node("GameConfig")
	var old: float = config.tile_motion_seconds()
	config.set_tile_animation_seconds(0.3, false)
	var host := Host.new()
	host.size = G.DESIGN_SIZE
	host.scale = Vector2(root.size) / G.DESIGN_SIZE
	root.add_child(host)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
	view.test_touch_height = footer
	host.add_child(view)
	view.table = host
	view.auto_sort_hands = false
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/own-exposed-round1.json"))
	data.actions = []
	host.round = REPLAY.replay(data).round
	for player in host.round.players: player.ready = true
	view.set_round(host.round, 1)
	view._sort_started = true
	view.refresh()
	await process_frame
	var renderer = view._table_3d
	var source: TileView = view.hand_boxes[1].get_child(0)
	var id: int = source.get_instance_id()
	var initial: Transform3D = renderer.tile_nodes[id].transform
	var origin: Vector2 = renderer.camera.unproject_position(renderer.tile_nodes[id].position) / Vector2(renderer.viewport.size) * renderer.size
	host.round.players[1].discards.append(source.tile)
	host.round.players[1].discard_ids.append(999)
	view._fly_discard(source, 1, source.tile, func(): pass)
	renderer.sync_tiles()
	var start: Vector2 = renderer.camera.unproject_position(renderer.tile_nodes[id].position) / Vector2(renderer.viewport.size) * renderer.size
	print("[endpoint-probe] ordinary_discard_t0_design=", origin.distance_to(start))
	t.expect(renderer.tile_nodes[id].transform.is_equal_approx(initial), "ordinary discard t0 full transform matches its static hand mesh")
	view._reset_round_visual_state()
	view.refresh()
	await process_frame
	view.animate_draw(1, "tong1", 0, func(): pass)
	var moving: TileView = view._deal_layer.get_child(view._deal_layer.get_child_count()-1)
	moving.position = view._draw_center(1, 13) - moving.size / 2.0
	moving.scale = Vector2.ONE
	moving.rotation = 0.0
	moving.flight_pitch = deg_to_rad(63)
	moving.flight_progress = 1.0
	renderer.sync_tiles()
	var terminal: Transform3D = renderer.tile_nodes[moving.get_instance_id()].transform
	view._finish_pending_draw(1)
	renderer.sync_tiles()
	var landed: Transform3D = renderer.tile_nodes[view.draw_boxes[1].get_child(0).get_instance_id()].transform
	var a: Vector2 = renderer.camera.unproject_position(terminal.origin) / Vector2(renderer.viewport.size) * renderer.size
	var b: Vector2 = renderer.camera.unproject_position(landed.origin) / Vector2(renderer.viewport.size) * renderer.size
	print("[endpoint-probe] own_draw_t1_land_design=", a.distance_to(b), " scale=", terminal.basis.get_scale(), "/", landed.basis.get_scale())
	t.expect(terminal.is_equal_approx(landed), "own draw t1 full transform equals the actual landed draw")
	view._reset_round_visual_state()
	host.queue_free()
	config.set_tile_animation_seconds(old, false)
	await process_frame
