extends "res://tests/test_round.gd"
## The inherited fixture builds a legal four-copy wall and drives the normal rules.
const Main := preload("res://scenes/Main.tscn")
const Settings := preload("res://src/app/AppSettings.gd")
const Table := preload("res://src/presentation/TableView.gd")
const Shared := preload("res://src/presentation/SharedHandDisplay.gd")
const AudioRetirement := preload("res://tests/AudioRetirement.gd")

func _initialize() -> void:
	_run.call_deferred()

func _until(predicate: Callable) -> bool:
	var limit := Time.get_ticks_msec() + 16000
	while not predicate.call() and Time.get_ticks_msec() < limit:
		await process_frame
		OS.delay_msec(1)
	return predicate.call()

func _run() -> void:
	await _live_hand()
	await _offered_fourth(false)
	await _offered_fourth(true)
	print("Hand play and rob: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _finger(table, point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = down
	if down: table._unhandled_input(event)
	else: table._input(event)

func _live_hand() -> void:
	var folder := "user://play-hand-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(folder)
	var app = Main.instantiate()
	app._settings = Settings.new(folder.path_join("profile.cfg"))
	app._settings.save_profile("摸打检查", 1)
	root.add_child(app)
	app._choose_mode("solo")
	if not await _until(func(): return app._table.can_play_hand()):
		check(false, "real solo dealer never received an open turn")
	else:
		var host = app._client._host
		var now: int = host._now()
		host.clock_msec = func(): return now
		var seat: int = app._view.seat
		var draw: int = app._round_projection.players[seat].draw_id
		var prompt: int = app._round_projection.prompt_id
		var point: Vector2 = app._table.camera.unproject_position(app._table.tiles[draw].global_position)
		# Reorder this owner's row without changing any legal action or the separate draw.
		var order: Array = app._order.view().slots.duplicate()
		order.reverse()
		app._order.apply_auto_slots(order)
		app._apply_order()
		check(not app._table.can_play_hand() and app._choices().discard_ids.has(draw), "actual moving hand blocks a legally available discard")
		_finger(app._table, point, true)
		check(await _until(func(): return app._table.can_play_hand()), "actual hand movement finishes")
		_finger(app._table, point, false)
		check(app._order.view().selected_id == -1 and app._round_projection.prompt_id == prompt, "tap begun before the row settles cannot become a preselection")
		for i in 2:
			_finger(app._table, point, true)
			_finger(app._table, point, false)
			if i == 0: check(app._order.view().selected_id == draw, "fresh tap after real stable motion lifts the exact separate draw")
		check(app._round_projection.prompt_id != prompt and not app._view.round.players[seat].hand.any(func(card): return card.id == draw), "second tap actually discards that physical tile")
		var id: int = app._order.view().slots[4]
		await _until(func(): return app._table._motions.is_empty())
		point = app._table.camera.unproject_position(app._table.tiles[id].global_position)
		_finger(app._table, point, true)
		_finger(app._table, point, false)
		app._tile_clicked(id)
		check(app._choices().get("discard_ids", []).is_empty() and app._order.view().selected_id == -1, "waiting for others blocks touch and Main's selection entry")
		_finger(app._table, point, true)
		check(await _until(func(): return app._order.view().dragged_id == id), "the same off-turn tile remains available for a real long hold")
		_finger(app._table, point, false)
		check(app._order.view().dragged_id == -1 and app._order.view().selected_id == -1, "off-turn sorting returns the held tile without selecting or discarding it")
		app._back_home()
		app._choose_mode("solo")
		if await _until(func(): return app._table.can_play_hand()):
			seat = app._view.seat
			id = app._order.view().slots[4]
			point = app._table.camera.unproject_position(app._table.tiles[id].global_position)
			_finger(app._table, point, true)
			check(await _until(func(): return app._order.view().dragged_id == id), "eligible owner starts real long press on an old hand tile")
			var drag := InputEventScreenDrag.new()
			drag.position = app._table.camera.unproject_position(Vector3(2, 0, 2))
			app._table._input(drag)
			_finger(app._table, drag.position, false)
			check(not app._round_projection.players[seat].hand.any(func(face): return face.id == id) and app._round_projection.players[seat].discards.any(func(face): return face.id == id), "legal long hold converted into a river swipe submits exactly the held physical ID")
		else:
			check(false, "second live game reached the hand-swipe fixture")
	check(await AudioRetirement.release_app(app, self), "solo test releases its audio")
	for filename in DirAccess.get_files_at(folder): DirAccess.remove_absolute(folder.path_join(filename))
	DirAccess.remove_absolute(folder)

func _projection(game, display, seat: int) -> Dictionary:
	var state: Dictionary = game.snapshot_for(seat)
	display.project(game, state)
	return state

func _capture(table, label: String) -> void:
	var folder := OS.get_environment("DONGXIU_ROB_KONG_SCREENS")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	table.camera.make_current()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label + ".png"))

func _offered_fourth(robbed: bool) -> void:
	var game = _game({0: "w55", 3: "w46 t111222 b33344", 2: "w46 t333444 b55566"}, "w5 b789 w5")
	_discard(game)
	game.submit(0, game.prompt_id, "pong")
	_pass_all(game)
	_discard(game)
	_pass_all(game)
	for i in 3:
		_discard(game)
		_pass_all(game)
	var display := Shared.new(false)
	display.sync(game)
	var fourth: int = game.players[0].draw_id
	var old_ids: Array = game.players[0].melds[0].tile_ids.duplicate()
	var stock: int = game.wall.remaining
	var tail: int = game.wall.tail_index
	var tables := []
	var meshes := []
	var draw_origins := []
	var old_group := {}
	for seat in 4:
		var table := Table.new(false)
		root.add_child(table)
		table.hide()
		tables.append(table)
		var initial := _projection(game, display, seat)
		table.apply_view(initial)
		var key = fourth if seat == 0 else initial.players[0].display.draw
		meshes.append(table.tiles[key])
		draw_origins.append(table.tiles[key].transform)
		for id in old_ids: old_group[id] = table._destinations[id]
	check(game.submit(0, game.prompt_id, "add_kong", fourth) and game.phase == "response", "real added kong opens its rob window")
	display.sync(game)
	for seat in 4:
		var table = tables[seat]
		var state := _projection(game, display, seat)
		table.apply_view(state)
		var key = fourth if seat == 0 else state.players[0].display.draw
		var offered: MeshInstance3D = table.tiles[key]
		check(offered == meshes[seat] and offered.get_meta("zone") == "hand" and offered.get_meta("value") == ("wan5" if seat == 0 else "") and offered.transform.is_equal_approx(draw_origins[seat]), "1.6.31: independent drawn tile stays in place, visible only to its owner while waiting")
		check(table.tiles.size() == 108 and old_ids.all(func(id): return table.tiles[id].transform.is_equal_approx(old_group[id]) and not table._motions.has(id)), "no duplicate tile and original three stay exactly still")
		check(table.tiles.values().all(func(tile): return tile.get_meta("zone") != "hand" or tile.get_meta("seat") == seat or tile.get_meta("value") == ""), "the fourth tile reveals no additional hand faces")
		check(table.tiles.values().filter(func(node): return node.get_meta("zone") == "meld").size() == 3 and (seat == 0 or not table.tiles.has(fourth)), "no public fourth is rendered beside the three-tile pung during the response window")
		table.apply_view(state)
		check(table.tiles[key] == offered and not state.response.submitted and game.wall.remaining == stock and game.wall.tail_index == tail, "refresh neither duplicates the offer nor takes its future supplement")
	check(tables.all(func(table): return table._motions.is_empty()), "no public offer flight starts on declaration")
	var restored := Table.new(false)
	root.add_child(restored)
	restored.apply_view(_projection(game, display, 2))
	check(restored.tiles.size() == 108 and not restored.tiles.has(fourth) and restored.tiles[restored.view.players[0].display.draw].get_meta("value") == "" and restored._motions.is_empty(), "fresh observer recovers original three-tile pung and private draw back")
	restored.apply_view({})
	check(restored.tiles.is_empty(), "closing the view removes the pending offer")
	restored.free()
	if not robbed:
		for seat in 4:
			tables[seat].show()
			await _capture(tables[seat], "pending-seat-%d" % seat)
			tables[seat].hide()
	if robbed: check(game.submit(2, game.prompt_id, "win") and game.submit(3, game.prompt_id, "win"), "two winners claim one offered tile")
	_pass_all(game)
	display.sync(game)
	for seat in 4:
		var table = tables[seat]
		var state := _projection(game, display, seat)
		table.apply_view(state)
		check(table.tiles.size() == 108 and table.tiles[fourth] == meshes[seat], "resolution reuses the original private draw mesh for the public fourth")
		if robbed:
			check(table.tiles[fourth].get_meta("zone") == "hand" and game.wall.remaining == stock and game.players[0].melds[0].tile_ids == old_ids, "robbed fourth goes to winner while original pung and wall remain intact")
		else:
			var draw = tail if seat == 0 else state.players[0].display.draw
			check(table.tiles[fourth].get_meta("zone") == "meld" and game.wall.remaining == stock - 1 and game.players[0].draw_id == tail, "all pass commits that physical fourth and draws the real logical tail")
			check(table._motions.has(draw) and not table._motions[draw].is_running() and table._motions[fourth].is_running(), "supplement waits on the real fourth-tile landing tween")
	if not robbed:
		# Sample the actual two-stage production tweens at the same time on every board.
		for seat in 4:
			var table = tables[seat]
			for id in old_ids: table._motions[id].custom_step(Table.ADDED_KONG_SECONDS * 0.15)
			table._motions[fourth].custom_step(Table.ADDED_KONG_SECONDS * 0.15)
			check(old_ids.all(func(id): return not table.tiles[id].transform.is_equal_approx(old_group[id])) and table.tiles[fourth].transform.is_equal_approx(draw_origins[seat]), "existing pung moves to make room while the fourth is physically stationary")
			var group: Array = old_ids + [fourth]
			var start: Transform3D = table._destinations[group[0]]
			for i in group.size():
				var target: Transform3D = table._destinations[group[i]]
				check(target.basis.is_equal_approx(start.basis) and target.origin.is_equal_approx(start.origin + Table.Layout.facing(0) * Vector3.RIGHT * i), "1.6.31 final slots form four contiguous upright prints along the owner's axis")
		check(await _until(func(): return tables.all(func(table): return not table._motions.has(fourth))), "fourth reaches its real final meld position")
		for seat in 4:
			var table = tables[seat]
			var draw = tail if seat == 0 else table.view.players[0].display.draw
			check(table.tiles[fourth].transform.is_equal_approx(table._destinations[fourth]) and not table.tiles[draw].transform.is_equal_approx(table._destinations[draw]), "supplement has not arrived when its prerequisite fourth lands")
	check(await _until(func(): return tables.all(func(table): return table._motions.is_empty())), "resolution finishes every live tween")
	if not robbed:
		for seat in 4:
			var table = tables[seat]
			var draw = tail if seat == 0 else table.view.players[0].display.draw
			check(table.tiles[draw].transform.is_equal_approx(table._destinations[draw]) and table.tiles[draw].get_meta("zone") == "hand", "actual tail tile finishes in the owner's draw slot")
	tables[0].show()
	await _capture(tables[0], "robbed-final" if robbed else "passed-final")
	for table in tables: table.free()
