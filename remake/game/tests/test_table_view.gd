extends SceneTree
const Table = preload("res://src/presentation/TableView.gd")
const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
var failures := 0
var checks := 0
var capture_dir := ""
var capture_size := Vector2i.ZERO

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL table: ", message)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
			DirAccess.make_dir_recursive_absolute(capture_dir)
		elif arg.begins_with("--capture-size="):
			var dimensions := arg.trim_prefix("--capture-size=").split("x")
			capture_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	var table := Table.new(false)
	if capture_size != Vector2i.ZERO:
		var viewport := SubViewport.new()
		viewport.size = capture_size
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		viewport.add_child(table)
	else:
		root.add_child(table)
	await process_frame
	var round = Round.new()
	check(round.start(1, 4, 2, Catalog.values(22411)), "legal opening")
	table.show_full_wall(1)
	check(table.tiles.size() == 108, "full wall is the only inventory before deal")
	if not capture_dir.is_empty():
		for seat in 4:
			table.set_viewer(seat)
			await _capture(table, "full-wall")
		table.set_viewer(1)
	var wall_first: Node3D = table.tiles[round.wall.peek_head()]
	table.apply_view(round.snapshot_for(1))
	check(table.tiles.size() == 108, "52 dealt, 56 remain, no duplicated rendered tiles")
	await table.presentation_finished
	if not capture_dir.is_empty():
		for seat in 4:
			table.apply_view(round.snapshot_for(seat))
			table._render(false)
			await _capture(table, "dealt")
		table.apply_view(round.snapshot_for(1))
		table._render(false)
	var known_id: int = round.players[1].hand[0]
	var known: Node3D = table.tiles[known_id]
	var spot := table.camera.unproject_position(known.global_position)
	check(table.tile_at(spot) == known_id, "real ray pick on actual owned card")
	table.apply_view(round.snapshot_for(1))
	check(table.tiles[known_id] == known, "snapshot refresh preserves physical node")
	check(round.begin_dealer_turn(), "dealer takes legal independent draw")
	table.apply_view(round.snapshot_for(1))
	check(table.tiles[round.players[1].draw_id] == wall_first, "wall -> draw preserves mesh instance")
	await create_timer(0.24).timeout
	check(table.tiles.size() == 108, "55 wall and 53 hand tiles")
	var settled_camera_fov := table.camera.fov
	table.set_safe_insets(Vector4(128, 48, 0, 36))
	check(table.camera.fov > settled_camera_fov, "asymmetric cutout reserves playing space")
	table.set_safe_insets(Vector4.ZERO)
	_wall_motion(table, round)
	var wall_spot: Transform3D = table.tiles[round.wall.peek_head()].transform
	var last_camera := Vector3.ZERO
	for seat in 4:
		table.apply_view(round.snapshot_for(seat))
		if not capture_dir.is_empty():
			table._render(false)
		await _capture(table, "dealer-draw")
		check(not last_camera.is_equal_approx(table.camera.position), "distinct camera " + str(seat))
		last_camera = table.camera.position
		check(table.tiles[round.wall.peek_head()].transform.is_equal_approx(wall_spot), "view rotation preserves world geometry")
		check(table.tiles.size() == 108, "108 tiles at seat " + str(seat))
		var faces := 0
		for key in table.tiles:
			if table.tiles[key].get_meta("zone") == "hand" and table.tiles[key].get_meta("value") != "":
				faces += 1
		check(faces == round.players[seat].hand.size(), "only viewer sees own hand")
	table.apply_view(round.snapshot_for(1))
	var choice := int(round.players[1].draw_id)
	check(round.submit(1, round.prompt_id, "discard", choice), "authorized discard")
	table.apply_view(round.snapshot_for(1))
	check(table.tiles[choice].get_meta("zone") in ["discard", "chicken"], "discard is physical source ID")
	for step in 160:
		if round.phase == "settled":
			break
		if round.phase == "response":
			round.expire_responses(round.prompt_id)
		else:
			var options: Dictionary = round.choices(round.turn)
			if options.actions.has("self_win"):
				round.submit(round.turn, round.prompt_id, "self_win")
			else:
				round.submit(round.turn, round.prompt_id, "discard", options.discard_ids.back())
		table.apply_view(round.snapshot_for(1))
		check(table.tiles.size() == 108, "108 tiles throughout a legal round")
	check(round.phase == "settled", "actual terminal phase")
	check(table.tiles.size() == 108 and table._selectable.is_empty(), "settlement reveals all without duplicate picks")
	var all_visible := true
	for entity in table.tiles.values():
		if entity.get_meta("zone") == "hand" and entity.get_meta("value") == "":
			all_visible = false
	check(all_visible, "all four finalized hands revealed")
	_kong_views(table)
	_flip_view(table)
	table.apply_view({})
	check(table.tiles.is_empty(), "clear previous round")
	table.free()
	print("Table renderer: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func _capture(table, phase: String) -> void:
	if capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var screen: Image = table.get_viewport().get_texture().get_image()
	if capture_size != Vector2i.ZERO:
		check(screen.get_size() == capture_size, "native render target has exact requested dimensions")
	var filename := capture_dir.path_join("%s-seat%d" % [phase, table.viewer])
	check(screen.save_png(filename + ".png") == OK, "save native table frame")
	var provenance := {}
	for path in ["res://src/presentation/TableView.gd", "res://src/presentation/TableLayout.gd", "res://src/presentation/TileArt.gd", "res://src/presentation/TileResin.gdshader", "res://src/presentation/TableFelt.gdshader", "res://assets/tiles/classic/provenance.json", "res://tests/test_table_view.gd"]:
		provenance[path] = FileAccess.get_sha256(path)
	var info := FileAccess.open(filename + ".json", FileAccess.WRITE)
	info.store_string(JSON.stringify({"phase": phase, "viewer_seat": table.viewer, "seed": 22411,
		"dealer": 1, "red": 4, "white": 2, "size": [screen.get_width(), screen.get_height()],
		"observed_window_safe_area": str(DisplayServer.get_display_safe_area()),
		"viewport_safe_insets": str(table._safe_insets), "world_tile_size": str(table.TILE_BOUNDS.size),
		"table_half_width": table.layout.EDGE, "wall_radius": table.layout.WALL_RADIUS,
		"public_radius": table.layout.PUBLIC_RADIUS, "camera_transform": str(table.camera.transform),
		"camera_fov": table.camera.fov, "flat_hands": table.flat_hands,
		"rendering_method": RenderingServer.get_current_rendering_method(), "default_layout": provenance}, "  "))

func _wall_motion(table, round) -> void:
	var before: Dictionary = table._destinations.duplicate()
	var shifted: Dictionary = round.snapshot_for(1)
	shifted.wall_offsets = [0.0, 0.0, 1.25, 0.0]
	table.apply_view(shifted)
	var moving := 0
	var fixed := 0
	for raw in shifted.wall_slots:
		var id := int(raw)
		var slot: Dictionary = table.layout.slots.slot_info(id)
		if slot.seat == 2:
			check(not before[id].is_equal_approx(table._destinations[id]), "only chosen wall translates")
			moving += 1
		else:
			check(before[id].is_equal_approx(table._destinations[id]), "other wall remains fixed")
			fixed += 1
	check(moving > 0 and fixed > 0, "tested both moved and unaffected slots")
	table.apply_view(round.snapshot_for(1))
	table._render(false)

func _fixed_round(hands: Dictionary, dealer_draw: String):
	var stock := Catalog.values(8427)
	var fixed := {62: dealer_draw} # South deals from index 10, initial deal uses 52.
	for seat in hands:
		var offset := posmod(1 - int(seat), 4)
		for i in hands[seat].size():
			var position: int = 48 + offset if i == 12 else (i / 4) * 16 + offset * 4 + i % 4
			fixed[10 + position] = hands[seat][i]
	for v in fixed.values():
		check(stock.has(v), "fixture respects four copies")
		stock.erase(v)
	var deck := []
	for id in 108:
		deck.append(fixed[id] if fixed.has(id) else stock.pop_back())
	var game = Round.new()
	check(game.start(1, 5, 2, deck) and game.begin_dealer_turn(), "legal fixed deal/draw")
	return game

func _kong_views(table) -> void:
	for claimant in [0, 2, 3]:
		table.apply_view({})
		var r = _fixed_round({claimant: ["wan5", "wan5", "wan5"]}, "wan5")
		var source := int(r.players[1].draw_id)
		table.apply_view(r.snapshot_for(claimant))
		check(r.submit(1, r.prompt_id, "discard", source), "discard offered tile")
		table.apply_view(r.snapshot_for(claimant))
		var physical: Node3D = table.tiles[source]
		check(r.submit(claimant, r.prompt_id, "kong"), "claim exposed kong")
		if r.phase == "response":
			r.expire_responses(r.prompt_id)
		table.apply_view(r.snapshot_for(claimant))
		check(table.tiles.size() == 108 and table.tiles[source] == physical, "discard -> kong keeps physical node")
		var anchor: Vector2 = table.layout.anchors[claimant]["m0"].center
		var cross: Vector3 = table.layout.facing(claimant).inverse() * table._destinations[source].origin
		var offset := cross.x - anchor.x
		if claimant == 3:
			check(absf(offset) < 0.001 and cross.z < anchor.y - 1, "opposite source in front, centered")
		else:
			check(offset < -1.0 if claimant == 0 else offset > 1.0, "provider on correct end")
		table.set_flat_hands(true)
		for id in r.players[claimant].melds[0].tile_ids:
			check(table.tiles[id].get_meta("value") == "wan5", "authorized face")
		check(table.layout.anchors[claimant]["m0"].center == anchor, "anchors survive flattening")
		table.set_flat_hands(false)
	var dark = _fixed_round({1: ["wan9", "wan9", "wan9", "wan9"]}, "tiao2")
	table.apply_view({})
	table.apply_view(dark.snapshot_for(0))
	check(dark.submit(1, dark.prompt_id, "concealed_kong", dark.choices(1).concealed_kong_ids[0]), "legal concealed kong")
	table.apply_view(dark.snapshot_for(0))
	var backs := 0
	for entity in table.tiles.values():
		if entity.get_meta("zone") == "meld" and entity.get_meta("value") == "":
			backs += 1
	check(backs == 4 and table.tiles.size() == 108, "concealed kong hides private values and IDs")
	table.apply_view(dark.snapshot_for(1))
	for id in dark.players[1].melds[0].tile_ids:
		check(table.tiles[id].get_meta("value") == "wan9", "owner sees own concealed kong")
	table.set_viewer(0)
	check(not table.tiles.has(dark.players[1].melds[0].tile_ids[0]), "switch masks private kong before next view")

func _flip_view(table) -> void:
	var hand := []
	for number in "1112344678999":
		hand.append("wan" + number)
	var r = _fixed_round({3: hand}, "wan5")
	var source := int(r.players[1].draw_id)
	r.submit(1, r.prompt_id, "discard", source)
	check(r.submit(3, r.prompt_id, "win"), "legal discard win")
	if r.phase == "response":
		r.expire_responses(r.prompt_id)
	table.apply_view({})
	var projection: Dictionary = r.snapshot_for(1)
	table.apply_view(projection)
	var id := int(projection.result.flip_wall_index)
	var landing: Dictionary = projection.result.flip_landing
	var expected: Transform3D = table.layout.wall_pose(int(landing.column) * 2, [], int(landing.stack_count) - 1)
	check(table.tiles[id].transform.is_equal_approx(expected), "flip uses authoritative support")
	check(table.tiles[id].get_meta("value") == projection.result.flip_tile, "winning flip shows original face")
	check(table.tiles.size() == 108 and table.tiles[source].get_meta("zone") == "hand", "winning discard belongs to one physical hand")
