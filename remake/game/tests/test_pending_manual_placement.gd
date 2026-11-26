extends SceneTree

const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Hand = preload("res://src/presentation/HandOrder.gd")
const Shared = preload("res://src/presentation/SharedHandDisplay.gd")
const Table = preload("res://src/presentation/TableView.gd")
var failures := 0
var checks := 0
var game := Round.new()
var hand := Hand.new()
var shared := Shared.new(false)
var tables := []
var owner: Table
var position_on_table := []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL pending placement: ", note)

func _sync() -> void:
	shared.sync(game)
	var own: Dictionary = game.snapshot_for(1).players[1]
	hand.sync_hand("pending", 1, game.prompt_id, own.hand, own.draw_id)

func _view(seat: int) -> Dictionary:
	var snapshot := game.snapshot_for(seat)
	shared.project(game, snapshot)
	return snapshot

func _publish() -> void:
	var packet := hand.view()
	if packet.dragged_id >= 0: packet.drag_position = position_on_table
	check(shared.accept(1, packet) >= 0, "valid player gesture reaches the authority")
	owner.set_hand_order(packet)
	for seat in [0, 2, 3]:
		tables[seat].apply_view(_view(seat))

func _settle(motion_time: float) -> void:
	for table in tables:
		for tween: Tween in table._motions.values():
			tween.custom_step(motion_time)

func _run() -> void:
	check(game.start(1, 5, 2, Catalog.values(541)) and game.begin_dealer_turn(), "legal opening and separate draw")
	_sync()
	var draw: int = game.players[1].draw_id
	hand.begin_drag(hand.view().slots.back())
	hand.commit_drag(0)
	check(shared.accept(1, hand.view()) == 1, "commit deliberately unsorted manual row")
	check(game.submit(1, game.prompt_id, "discard", hand.view().slots[5]), "discard old physical tile")
	_sync()
	var original := hand.view()
	check(original.pending_insert_ids == [draw], "retained draw explicitly awaits the player's choice")
	for seat in 4:
		var table := Table.new(false)
		tables.append(table)
		if seat == 1:
			owner = table
			root.add_child(owner)
			owner.apply_view(_view(1), original)
		else:
			var viewport := SubViewport.new()
			viewport.own_world_3d = true
			root.add_child(viewport)
			viewport.add_child(table)
			table.apply_view(_view(seat))
	owner.drag_started.connect(func(id):
		check(hand.begin_drag(id), "held physical pending ID can be dragged")
		position_on_table = []
		_publish())
	owner.drag_slot_changed.connect(func(slot):
		hand.move_gap(slot)
		_publish())
	owner.hand_drag_position.connect(func(point):
		position_on_table = point
		_publish())
	owner.drag_finished.connect(func(slot):
		hand.commit_drag(slot)
		position_on_table = []
		_publish())
	var before := game.snapshot_for(1)
	var tape := game.events.duplicate(true)
	var source: Vector2 = owner.camera.unproject_position(owner.tiles[draw].position)
	var target: Vector2 = owner.camera.unproject_position(owner._hand_slots[3].origin)
	var untouched: int = original.slots[1]
	var moved: int = original.slots[4]
	var still: Transform3D = owner.tiles[untouched].transform
	var start: Transform3D = owner.tiles[moved].transform
	var opaque: String = _view(1).players[1].display.own_keys[str(draw)]
	var pickup_position: Vector3 = owner.tiles[draw].position
	check(owner._press(source, 0, false), "normal hit testing finds the actual pending mesh")
	owner._hold.custom_step(1.0)
	check(owner.tiles[draw].position.is_equal_approx(pickup_position + Vector3.UP * 0.45), "holding immediately lifts the tile")
	check(hand.view().gap_slot == 12 and hand.view().slots.back() == -1, "pickup opens exactly the thirteenth slot")
	for seat in [0, 2, 3]:
		var other: Dictionary = _view(seat).players[1]
		check(other.display.slots[12] == "" and other.display.dragged == opaque and other.display.pending.is_empty() and not other.display.has("own_keys") and other.hand.is_empty(), "each viewer sees only the empty slot and concealed moving mesh")
	owner._motion(target)
	check(hand.view().gap_slot == 3 and owner.tiles[draw].position.is_equal_approx(owner._held_point(target) + owner._carry_offset) and not owner._motions.has(draw), "held card follows the finger without a competing tween")
	_settle(Table.MOVE_SECONDS * 0.5)
	check(owner.tiles[moved].basis.is_equal_approx(start.basis) and not owner.tiles[moved].position.is_equal_approx(start.origin), "crossed cards slide without tilting")
	check(owner.tiles[untouched].transform.is_equal_approx(still), "uncrossed card stays in place")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--capture=")) == OK, "capture real intermediate drag and tilted neighbors")
	_settle(Table.MOVE_SECONDS)
	for seat in [0, 2, 3]:
		var table: Table = tables[seat]
		var local: Vector3 = Table.Layout.facing(1).inverse() * owner.tiles[draw].position
		var shared_position: Vector3 = Table.Layout.facing(1) * Vector3(clampf(local.x, -owner.table_edge(), owner.table_edge()), 1.9, clampf(local.z, -owner.table_edge(), owner.table_edge()))
		check(table.tiles[opaque].position.is_equal_approx(shared_position) and table.tiles[opaque].get_meta("value") == "", "remote backs use protocol-clamped coordinates")
	owner._release(source)
	_settle(Table.MOVE_SECONDS * 2)
	check(hand.view() == original and owner.tiles[moved].transform.is_equal_approx(start), "drop at origin restores pending marker, crossed positions and upright pose")
	check(owner._press(source, 0, false), "pending tile remains available after cancellation")
	owner._hold.custom_step(1.0)
	owner._motion(target)
	owner._release(Vector2(-1000, -1000))
	_settle(Table.MOVE_SECONDS * 2)
	check(hand.view() == original, "invalid drop also restores signed-off manual order")
	owner._press(source, 0, false)
	owner._hold.custom_step(1.0)
	owner._motion(target)
	owner._release(target)
	_settle(Table.MOVE_SECONDS * 2)
	var expected: Array = original.slots.duplicate()
	expected.insert(3, draw)
	check(hand.view().slots == expected and hand.view().pending_insert_ids.is_empty() and hand.view().manual, "only the chosen retained draw joins the chosen slot")
	for seat in 4:
		var table: Table = tables[seat]
		var key = draw if seat == 1 else opaque
		check(table.tiles.size() == 108 and table.tiles[key].transform.is_equal_approx(Table.Layout.hand_pose(1, 3, 13, false, false, false)), "four rendered views show the identical physical landing with all 108 tiles")
	check(game.snapshot_for(1) == before and game.events == tape, "all gestures leave authority and legal actions unchanged")
	_multiple_pending()
	for table in tables: table.free()
	print("Pending manual placement: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _multiple_pending() -> void:
	for pass_index in 2:
		while game.phase == "response" or game.turn != 1:
			if game.phase == "response":
				game.expire_responses(game.prompt_id)
			else:
				game.submit(game.turn, game.prompt_id, "discard", game.players[game.turn].draw_id)
			_sync()
		check(game.submit(1, game.prompt_id, "discard", hand.view().slots.back()), "another legal old-hand discard retains a new pending tile")
		_sync()
	var original := hand.view()
	check(original.pending_insert_ids.size() == 2, "two separately retained entities await placement")
	var first: int = original.pending_insert_ids[0]
	var second: int = original.pending_insert_ids[1]
	hand.begin_drag(second)
	check(shared.accept(1, hand.view()) == 1 and shared.accept(1, hand.view()) == 0, "multiple-pending preview is idempotent")
	hand.move_gap(0)
	var malformed := hand.view()
	var unrelated: int = malformed.slots[2]
	malformed.slots[2] = malformed.slots[3]
	malformed.slots[3] = unrelated
	check(shared.accept(1, malformed) == -1, "cannot shuffle unrelated committed or pending identities during a pending drag")
	check(shared.accept(1, hand.view()) == 1, "crossing from the second pending slot is accepted")
	shared.clear_gesture(1)
	check(_view(3).players[1].display.pending.size() == 2, "disconnect during preview restores both original pending slots")
	hand.commit_drag(-1)
	check(hand.view() == original, "cancel restores both pending identities and ordering")
	hand.begin_drag(second)
	hand.move_gap(1)
	hand.commit_drag(1)
	var expected: Array = original.slots.duplicate()
	expected.insert(1, second)
	check(hand.view().slots == expected and hand.view().pending_insert_ids == [first], "placing one pending entity leaves the other unresolved")
	check(shared.accept(1, hand.view()) == 1 and _view(0).players[1].display.pending.size() == 1, "authority stores exactly the remaining pending slot")
