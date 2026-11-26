extends SceneTree

const Table = preload("res://src/presentation/TableView.gd")
const Deal = preload("res://src/presentation/OpeningDeal.gd")
const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Mirror = preload("res://src/presentation/SharedHandDisplay.gd")
var checks := 0
var failures := 0
var finished := []
var capture_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL opening: ", label)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	var game := Round.new()
	check(game.start(1, 5, 2, Catalog.values(167)), "legal 108 tile opening")
	var shared := Mirror.new(false)
	shared.sync(game)
	var tables := []
	var original := []
	var snapshots := []
	for seat in [1, 3, 2, 0]:
		var table := Table.new(false)
		if seat == 1:
			root.add_child(table)
		else:
			var viewport := SubViewport.new()
			viewport.own_world_3d = true
			root.add_child(viewport)
			viewport.add_child(table)
		table.show_full_wall(seat)
		var snapshot := game.snapshot_for(seat)
		shared.project(game, snapshot)
		snapshot.deal_styles = ["b", "a", "a", "b"]
		original.append(table.tiles.duplicate())
		table.apply_view(snapshot)
		tables.append(table)
		snapshots.append(snapshot)
		for track: Tween in table._opening.tracks.values(): track.pause()
	var owner: Table = tables[0]
	var observer: Table = tables[1]
	owner.presentation_finished.connect(func(id): finished.append(id))
	var dealer := 1
	var a: Array = game.events[0].ids
	var dealer_keys: Array = snapshots[1].players[dealer].display.deal_keys
	for group in game.events:
		var cards: Array = snapshots[1].players[group.seat].display.deal_keys
		for id in group.ids:
			var index: int = game.players[group.seat].hand.find(id)
			var key = id if group.seat == 3 else cards[index]
			check(observer.tiles.get(key) == original[1][id], "observer reuses the exact wall mesh for each deal")
	check(observer.tiles.size() == 108 and owner.tiles.size() == 108, "both observers preserve 108 meshes")
	for key in dealer_keys:
		check(observer.tiles[key].get_meta("value") == "", "dealer face stays private")
	var a_time:=Deal.pickup_scale(4,"a")
	var b_time:=Deal.pickup_scale(4,"b")
	_step(tables, Deal.CARRY*a_time)
	var row_front := Table.Layout.EDGE - 2.0
	for i in 4:
		var p: Vector3 = owner.tiles[a[i]].position
		check(is_equal_approx(p.z, row_front) and is_equal_approx(p.x, -6.0 + floori(i / 2.0)) and is_equal_approx(p.y, Table.Layout.THICK * (1.5 if i % 2 == 0 else 0.5)), "two actual stacks arrive intact")
	await _capture("A-two-stacks")
	_step(tables, Deal.SPREAD*a_time)
	for i in 4:
		var p: Transform3D = owner.tiles[a[i]].transform
		check(is_equal_approx(p.origin.x, -6 + floori(i / 2.0) + (2 if i % 2 == 0 else 0)) and p.basis.y.y < -0.99, "A places the top two to the right face-down")
		for viewer in range(1, tables.size()):
			check(p.is_equal_approx(tables[viewer].tiles[dealer_keys[i]].transform), "all four cameras see the same physical sequence")
	await _capture("A-spread-before-turn")
	var next_start := Deal.CADENCE + (Deal.CARRY + Deal.FLIP + Deal.RACK)*b_time
	_step(tables, next_start - (Deal.CARRY + Deal.SPREAD)*a_time)
	var next_face: Basis = Table.Layout.hand_pose(0, 0, 13, false, false, false).basis
	var b: Array = game.events[1].ids
	var b_keys: Array = snapshots[0].players[0].display.deal_keys
	for i in 4:
		var node: Node3D = owner.tiles[b_keys[i]]
		for viewer in range(1, tables.size()):
			var key = b[i] if tables[viewer].viewer == 0 else b_keys[i]
			check(node.transform.is_equal_approx(tables[viewer].tiles[key].transform), "seat B performs the same top-before-bottom gesture from all views")
		if i % 2 == 0:
			check(node.basis.is_equal_approx(next_face) and (Table.Layout.facing(0).inverse() * node.position).z > row_front + 1.0, "B upper pair is upright and already in hand")
		else:
			check(node.basis.y.y < -0.99 and is_equal_approx((Table.Layout.facing(0).inverse() * node.position).z, row_front), "B lower pair has not started its flip")
	await _capture("B-upper-in-hand-lower-still-down")
	_step(tables, 4 * Deal.CADENCE - next_start)
	var before := []
	for id in a: before.append(owner.tiles[id].transform)
	var next: Array = game.events[4].ids
	var source: Transform3D = owner.tiles[next[0]].transform
	check(before.any(func(pose): return pose.origin.y > Table.Layout.LONG * 0.5 + 0.01), "the interrupted insertion is physically in flight")
	_step(tables, Deal.CARRY * a_time * 0.6)
	check(not owner.tiles[next[0]].transform.is_equal_approx(source), "next pickup starts on cadence")
	for i in 4:
		check(before[i].is_equal_approx(owner.tiles[a[i]].transform), "prior insertion freezes during the next pickup")
	var active: Tween = owner._opening.tracks[dealer]
	owner.apply_view(snapshots[0])
	check(owner._opening.tracks[dealer] == active, "identical projection keeps exact track and mesh positions")
	# Hold the last seat's thirteenth tile just before its receipt, after the dealer is fully sorted.
	var now := 4 * Deal.CADENCE + Deal.CARRY * a_time * 0.6
	var observer_finished := []
	observer.presentation_finished.connect(func(id): observer_finished.append(id))
	for seat in 4:
		if seat != dealer: observer._opening.tracks[seat].custom_step(20.0)
	observer._opening.tracks[dealer].custom_step(12 * Deal.CADENCE + Deal.Pace.ACTION_SECONDS - now + 0.01)
	await process_frame
	check(observer._opening.received.min() == 13 and observer_finished.is_empty(), "all 13 receipts still wait for dealer's own sorting")
	observer._opening.tracks[dealer].custom_step(20.0)
	await process_frame
	check(observer_finished == [game.prompt_id], "observer completes on the actual dealer sort")
	var last: int = game.events[15].seat
	for seat in 4:
		var track: Tween = owner._opening.tracks[seat]
		track.custom_step(15 * Deal.CADENCE + Deal.Pace.ACTION_SECONDS - now - 0.02 if seat == last else 20.0)
	await process_frame
	check(finished.is_empty() and owner._opening.received[last] == 12, "gate waits for the actual fourth thirteenth tile")
	owner._opening.tracks[last].custom_step(0.021)
	await process_frame
	check(finished == [game.prompt_id] and owner._opening != null and owner._opening.tracks.has(last), "dealer can start while last seat is still sorting")
	for id in game.players[dealer].hand:
		check(owner.tiles[id].transform.is_equal_approx(owner._destinations[id]), "every dealer tile physically finishes in its true sorted slot")
	check(game.begin_dealer_turn(), "authority advances independently to its first draw")
	var turn := game.snapshot_for(dealer)
	shared.sync(game)
	shared.project(game, turn)
	owner.apply_view(turn)
	check(owner._opening != null and owner._opening.tracks.has(last), "ordinary dealer draw preserves opponent sorting")
	var draw_id: int = game.players[dealer].draw_id
	var draw_motion: Tween = owner._motions[draw_id]
	draw_motion.pause()
	for motion: Tween in owner._motions.values():
		if motion != draw_motion: motion.custom_step(1.0)
	await process_frame
	check(finished.size() == 1, "paused independent draw blocks turn cue after every other normal movement completes")
	draw_motion.custom_step(1.0)
	await process_frame
	check(finished == [game.prompt_id - 1, game.prompt_id], "draw cue follows actual wall mesh landing while another player continues sorting")
	var last_track: Tween = owner._opening.tracks[last]
	last_track.custom_step(20.0)
	var elapsed := Deal.nominal_gate_seconds()
	check(elapsed >= 15 * Deal.CADENCE + Deal.Pace.ACTION_SECONDS, "network fallback covers the final physical receipt")
	for table in tables:
		table.free()
	print("Opening deal motion: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _step(tables: Array, duration: float) -> void:
	for table in tables:
		for track: Tween in table._opening.tracks.values():
			track.custom_step(duration)

func _capture(label: String) -> void:
	if capture_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	var file := capture_dir.path_join(label + ".png")
	check(root.get_texture().get_image().save_png(file) == OK, "capture actual GPU frame")
