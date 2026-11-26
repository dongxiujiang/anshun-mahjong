extends "res://tests/test_round.gd"

const Table := preload("res://src/presentation/TableView.gd")
const Layout := preload("res://src/presentation/TableLayout.gd")
const Shared := preload("res://src/presentation/SharedHandDisplay.gd")
const EPS := 0.002 # Imported model edge tolerance, in tile widths.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for owner in 4:
		for offset in [1, -1, 2]:
			await _claim(owner, posmod(owner + offset, 4), offset)
	print("Legacy exposed kong: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fixture(owner: int, provider: int):
	var deal := Round.new()
	deal.start(provider, 5, 2, Catalog.ordered_values())
	deal.begin_dealer_turn()
	var copies: Array = deal.players[owner].hand.slice(0, 3)
	copies.append(deal.players[provider].draw_id)
	var pool := Catalog.values(8427)
	for id in copies: pool.erase("wan6")
	var deck := []
	for id in Catalog.COUNT:
		deck.append("wan6" if id in copies else pool.pop_back())
	var game := Round.new()
	check(game.start(provider, 5, 2, deck) and game.begin_dealer_turn(), "full legal wall and dealer draw")
	return game

func _claim(owner: int, provider: int, offset: int) -> void:
	var game = _fixture(owner, provider)
	var display := Shared.new(false)
	var source: int = game.players[provider].draw_id
	_discard(game, source)
	display.sync(game)
	var boards := []
	var old_tiles := []
	for observer in 4:
		var table := Table.new(false)
		root.add_child(table)
		table.hide()
		var state: Dictionary = game.snapshot_for(observer)
		display.project(game, state)
		table.apply_view(state)
		boards.append(table)
		old_tiles.append(table.tiles.duplicate())
		check(table.tiles[source].get_meta("zone") == "discard", "real source starts in provider's river")
	var stock: int = game.wall.remaining
	check(game.submit(owner, game.prompt_id, "kong"), "claimant can legally claim this discard")
	_pass_all(game)
	var meld: Dictionary = game.players[owner].melds[0]
	check(meld.source_id == source and meld.from_seat == provider and meld.tile_ids.size() == 4 and not game.players[provider].discards.has(source), "claim records the physical provider and three tiles from claimant")
	check(game.turn == owner and game.players[owner].draw_id >= 0 and game.wall.remaining == stock - 1 and _conserved(game), "legal supplement drawn and all 108 tiles conserved")
	display.sync(game)
	for observer in 4:
		var table = boards[observer]
		var state: Dictionary = game.snapshot_for(observer)
		display.project(game, state)
		var river: Transform3D = table.tiles[source].transform
		table.apply_view(state)
		check(table.tiles[source] == old_tiles[observer][source] and table._motions.has(source) and table.tiles[source].transform.is_equal_approx(river), "the same discarded mesh begins its actual flight from the river")
		for id in meld.tile_ids:
			var key = id if observer == owner or id == source else state.public_origins[str(id)]
			check(table.tiles[id] == old_tiles[observer][key] and table.tiles[id].get_meta("value") == "wan6", "each public face reuses its exact previous mesh")
	var limit := Time.get_ticks_msec() + 8000
	while boards.any(func(b): return not b._motions.is_empty()) and Time.get_ticks_msec() < limit:
		await process_frame
		OS.delay_msec(1)
	check(boards.all(func(b): return b._motions.is_empty()), "actual claim and supplement motions finish")
	for observer in 4:
		var table = boards[observer]
		_check_landing(table, owner, meld, offset)
		for id in meld.tile_ids:
			check(table.tiles[id].transform.is_equal_approx(boards[0].tiles[id].transform), "observer camera preserves world landing")
		check(table.tiles.size() == 108 and table.tiles.values().all(func(node): return node.get_meta("zone") != "hand" or node.get_meta("seat") == observer or node.get_meta("value") == ""), "claim reveals no other hand face")
		if owner == 1 and (observer == owner or (offset == 2 and observer == 3)):
			await _capture(table, "owner-%d_source-%d_view-%d" % [owner, provider, observer])
	for table in boards: table.free()

func _check_landing(table, owner: int, meld: Dictionary, offset: int) -> void:
	var owner_frame := Transform3D(Layout.facing(owner).inverse(), Vector3.ZERO)
	var upright := []
	var cross := Rect2()
	var covered := Rect2()
	var count := 0
	for id in meld.tile_ids:
		var tile: MeshInstance3D = table.tiles[id]
		var local: Transform3D = owner_frame * tile.global_transform
		var bounds := local * tile.mesh.get_aabb()
		var rect := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		covered = rect if count == 0 else covered.merge(rect)
		count += 1
		check(absf(bounds.position.y) < EPS and tile.get_meta("zone") == "meld", "printed face lands flat on the table")
		if id == meld.source_id:
			cross = rect
			check(local.basis.is_equal_approx(Basis(Vector3.UP, -PI / 2.0)), "provider's six-wan print follows the legacy negative quarter turn")
		else:
			upright.append(rect)
			check(local.basis.is_equal_approx(Basis.IDENTITY), "the three claimant prints stay upright to the owner")
	upright.sort_custom(func(a, b): return a.position.x < b.position.x)
	for i in 2:
		check(absf(upright[i].end.x - upright[i+1].position.x) < EPS and absf(upright[i].end.y - upright[i+1].end.y) < EPS, "three real upright meshes share one contiguous row")
	var row: Rect2 = upright[0].merge(upright[2])
	if offset == 2:
		check(absf(cross.get_center().x - row.get_center().x) < EPS and absf(cross.end.y - row.position.y) < EPS, "opposite source centered and touching the inner edge towards the table center")
	else:
		var gap: float = row.position.x - cross.end.x if offset == 1 else cross.position.x - row.end.x
		check(absf(gap) < EPS and absf(row.end.y - cross.end.y) < EPS, "side source touches correct end with its owner-facing edge flush")
	for other: Rect2 in upright:
		check(cross.intersection(other).get_area() < EPS, "provider mesh does not overlap any claimant mesh")
	var reserved: Rect2 = table.layout.anchors[owner].m0.rect
	check(absf(reserved.size.x - (3.0 if offset == 2 else 4.34)) < EPS and covered.position.distance_to(reserved.position) < EPS and covered.end.distance_to(reserved.end) < EPS, "measured final mesh envelope matches the public reservation")

func _capture(table, label: String) -> void:
	var folder := OS.get_environment("DONGXIU_EXPOSED_KONG_SCREENS")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	table.show()
	table.camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label + ".png")) == OK, "native camera capture")
	table.hide()
