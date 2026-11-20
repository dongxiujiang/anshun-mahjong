extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
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

func _fixture(screen: Vector2i):
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = screen
	var host := Host.new()
	host.size = G.DESIGN_SIZE
	host.scale = Vector2(screen) / G.DESIGN_SIZE
	root.add_child(host)
	host.round = RoundState.new()
	host.round.build_players(1)
	host.round.controllers = [null, null, null, null]
	host.round.phase = RoundState.Phase.PLAYING
	host.round.wall = WallRing.new(TileSetFactory.create_deck())
	for index in WallRing.N: host.round.wall.draw_head()
	for player in host.round.players:
		player.concealed.assign(["wan1", "wan2", "wan3", "wan4", "wan6", "wan7", "wan8", "wan9", "tong1", "tong2"])
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	host.add_child(view)
	view.table = host
	view.auto_sort_hands = false
	view._sort_started = true
	view.set_round(host.round, 1)
	view.refresh()
	return view

func _opening(screen: Vector2i, seat: int, existing: int) -> void:
	var view = _fixture(screen)
	var renderer = view._table_3d
	for node in view.hand_boxes[seat].get_children(): view._release_visual_node(node)
	var cards := ["wan1"] if existing == 12 else ["wan1", "wan2", "wan3", "wan4"]
	var count := existing + cards.size()
	for slot in existing:
		var node: TileView = view._tile(view.hand_boxes[seat], "wan6", seat == 1,
			G.hand_slot_center(seat, slot, 1, count), G.hand_unit(seat, 1), UI.ROTATIONS[G.relative_seat(1, seat)])
		node.set_meta("new_kind", "hand")
		node.set_meta("v2_seat", seat)
		node.standing_back_view = G.relative_seat(1, seat) if seat != 1 else -1
	view.animate_deal_group(seat, cards, range(existing, count), existing, Callable())
	view._deal_tween.pause()
	var moving: Array = view._deal_moving.duplicate()
	t.expect(moving.size() == cards.size(), "opening creates the packet's physical deal entities")
	for slot in moving.size():
		var tile: TileView = moving[slot]
		t.expect(tile.get_meta("new_kind", "") == "hand" and tile.get_meta("v2_draw_flight", false),
			"opening seat %d uses the destination hand projection" % seat)
		tile.position = G.hand_slot_center(seat, existing + slot, 1, count, false) - tile.size / 2.0
		tile.scale = Vector2.ONE
		tile.rotation = UI.ROTATIONS[G.relative_seat(1, seat)]
		tile.flight_pitch = deg_to_rad(63) if seat == 1 else PI / 2.0
		tile.flight_progress = 1.0
	renderer.sync_tiles()
	var endpoint := {}
	for tile in moving: endpoint[tile.get_instance_id()] = renderer.tile_nodes[tile.get_instance_id()].transform
	for tile in moving:
		tile.reparent(view.hand_boxes[seat], false)
		tile.flight_progress = -1.0
		tile.flight_pitch = -1.0
		tile.remove_meta("v2_draw_flight")
	renderer.sync_tiles()
	for tile in moving:
		var before: Transform3D = endpoint[tile.get_instance_id()]
		var after: Transform3D = renderer.tile_nodes[tile.get_instance_id()].transform
		t.expect(before.is_equal_approx(after), "opening seat %d lands on its actual persistent hand transform at %s" % [seat, screen])
	view._reset_round_visual_state()
	view.table.free()

func _added(screen: Vector2i, seat: int, card: String, cancel_at: float = -1.0, existing: bool = false) -> void:
	var view = _fixture(screen)
	var state: RoundState = view.round
	state.players[seat].melds = [{"kind": "pung", "tile": card, "from_seat": posmod(seat + 1, 4)}]
	if existing:
		state.players[seat].melds.append({"kind": "pung", "tile": "tong9", "from_seat": posmod(seat + 2, 4)})
		state.players[seat].concealed.resize(7)
	state.players[seat].concealed.append(card)
	state.players[seat].just_drew = card
	view.refresh()
	var renderer = view._table_3d
	renderer.sync_tiles()
	var layer: Control = view._red_layer if Tiles.is_chicken(card) else view._meld_layer
	var originals: Array = layer.get_children().filter(func(tile): return tile.get_meta("v2_seat", -1) == seat and tile.get_meta("meld_index", -1) == 0)
	var neighbors: Array = view._meld_layer.get_children().filter(func(tile): return tile.get_meta("v2_seat", -1) == seat and tile.get_meta("meld_index", -1) == 1)
	originals.sort_custom(func(a, b): return a.get_meta("meld_slot") < b.get_meta("meld_slot"))
	# Deliberately scramble traversal order; meld_slot owns the physical binding.
	layer.move_child(originals[2], 0)
	var incoming: TileView = view.draw_boxes[seat].get_child(0)
	var incoming_origin: Transform3D = renderer.tile_nodes[incoming.get_instance_id()].transform
	state.players[seat].melds[0].kind = "add_kong"
	state.players[seat].concealed.pop_back()
	state.players[seat].just_drew = ""
	var completed := {"count": 0}
	view.animate_meld({"seat": seat, "tile": card, "kind": "add_kong", "index": 0, "hand_indices": [state.players[seat].concealed.size()]},
		func(): completed.count += 1)
	var tween: Tween = view._motion_tweens.back()
	tween.pause()
	var duration := float(root.get_node("GameConfig").tile_motion_seconds())
	var step := duration * 0.15 if cancel_at < 0.0 else duration * cancel_at
	tween.custom_step(step)
	renderer.sync_tiles()
	if cancel_at < 0.3:
		t.expect(renderer.tile_nodes[incoming.get_instance_id()].transform.is_equal_approx(incoming_origin),
			"added kong holds the fourth physical tile until the original group makes room")
	else:
		t.expect(float(incoming.get_meta("meld_room_3d").progress) > 0.0, "resume can interrupt the incoming stage")
	for slot in originals.size():
		var tile: TileView = originals[slot]
		var pose: Dictionary = tile.get_meta("meld_room_3d", {})
		t.expect(not pose.is_empty() and float(pose.progress) > 0.0 and float(pose.lift) == 0.0,
			"original slot %d slides without a flight arc" % slot)
		if not pose.is_empty():
			var expected: Transform3D = Transform3D(pose.origin).interpolate_with(pose.target, pose.progress)
			t.expect(renderer.tile_nodes[tile.get_instance_id()].transform.is_equal_approx(expected),
				"original slot %d follows its real 3D room transform" % slot)
	for tile in neighbors:
		var pose: Dictionary = tile.get_meta("meld_room_3d", {})
		t.expect(not pose.is_empty() and float(pose.progress) > 0.0, "neighboring group shifts in the same room stage")
	t.expect(completed.count == 0 and view.native_actions_pending(), "room stage retains the existing visual action gate")
	if cancel_at >= 0.0:
		view.recover_after_resume()
		view.refresh()
		t.expect(completed.count == 0 and not view.native_presentation_pending(), "resume cancels an unfinished added kong without stale completion")
		for tile in originals + [incoming]:
			t.expect(not tile.has_meta("meld_room_3d"), "cancel clears presentation metadata before pooling")
	else:
		tween.custom_step(duration * 0.20)
		renderer.sync_tiles()
		t.expect(float(incoming.get_meta("meld_room_3d").progress) > 0.0, "fourth tile starts only after the room stage")
		for tile in originals:
			t.expect(is_equal_approx(float(tile.get_meta("meld_room_3d").progress), 1.0), "original group finishes making room before incoming flight")
		var endpoints := {}
		for tile in originals + [incoming] + neighbors: endpoints[tile.get_instance_id()] = tile.get_meta("meld_room_3d").target
		tween.custom_step(duration)
		for pending in view._motion_tweens.duplicate():
			if pending.is_valid():
				pending.pause()
				pending.custom_step(1.0)
		renderer.sync_tiles()
		t.expect(completed.count == 1 and not view.native_actions_pending(), "added kong completes once within its existing motion duration plus hand centering")
		for slot in originals.size():
			var tile: TileView = originals[slot]
			t.expect(tile.get_parent() == layer and int(tile.get_meta("meld_slot")) == slot,
				"added kong preserves original slot %d node identity despite traversal order" % slot)
		t.expect(incoming.get_parent() == layer and incoming.get_meta("meld_slot") == 3, "actual fourth tile occupies the final slot")
		for tile in neighbors: t.expect(tile.get_meta("meld_index") == 1, "neighboring group keeps its original group identity")
		for tile in originals + [incoming] + neighbors:
			t.expect(not tile.has_meta("meld_room_3d"), "landing clears temporary presentation metadata")
			t.expect(renderer.tile_nodes[tile.get_instance_id()].transform.is_equal_approx(endpoints[tile.get_instance_id()]),
				"added kong lands at its previewed final transform without a snap")
	view._reset_round_visual_state()
	view.table.free()

func _run() -> void:
	var config := root.get_node("GameConfig")
	var previous: float = config.tile_motion_seconds()
	config.set_tile_animation_seconds(0.30, false)
	for screen in [Vector2i(1920, 1080), Vector2i(2400, 1080)]:
		for seat in 4:
			for existing in [0, 4, 8, 12]: _opening(screen, seat, existing)
	for seat in 4:
		for card in ["wan5", "tiao1"]: _added(Vector2i(1920, 1080), seat, card)
	for seat in 4: _added(Vector2i(2400, 1080), seat, "tiao1", -1.0, true)
	_added(Vector2i(1920, 1080), 1, "wan5", 0.15)
	_added(Vector2i(2400, 1080), 0, "tiao1", 0.15)
	_added(Vector2i(1920, 1080), 1, "tiao1", 0.50)
	_added(Vector2i(2400, 1080), 0, "wan5", 0.50)
	config.set_tile_animation_seconds(previous, false)
	await H.quit_cleanly(self, t.finish("table_v2_opening_added_room"))
