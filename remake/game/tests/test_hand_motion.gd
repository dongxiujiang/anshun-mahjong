extends SceneTree

const Table = preload("res://src/presentation/TableView.gd")
const Round = preload("res://src/domain/Round.gd")
const Wall = preload("res://src/domain/Wall.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Order = preload("res://src/presentation/HandOrder.gd")
const Arrange = preload("res://src/presentation/HandArrangement.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL hand motion: ", note)

func _run() -> void:
	# Construct one legal deal: every physical tile still comes from the fixed wall.
	var wall := Wall.new(Catalog.ordered_values())
	wall.open(1, 5)
	var dealt := [[], [], [], []]
	for amount in [4, 4, 4, 1]:
		for offset in 4:
			for index in amount:
				dealt[posmod(1 - offset, 4)].append(wall.take_head())
	var drawn := wall.take_head()
	var fixed := {drawn: "wan3"}
	var values := ["wan1", "wan2", "wan4", "wan6", "wan7", "wan8", "tiao2", "tiao3", "tiao4", "tiao5", "tong2", "tong4", "tong6"]
	for index in values.size(): fixed[dealt[1][index]] = values[index]
	var stock := Catalog.ordered_values()
	for value in fixed.values(): stock.erase(value)
	var deck := []
	for id in 108: deck.append(fixed[id] if fixed.has(id) else stock.pop_back())
	var round := Round.new()
	check(round.start(1, 5, 2, deck) and round.begin_dealer_turn(), "legal deal and draw")
	var table := Table.new()
	root.add_child(table)
	await process_frame
	var order := Order.new()
	var advice := Arrange.new()
	var before := round.snapshot_for(1)
	order.sync_hand("motion", 1, round.prompt_id, before.players[1].hand, drawn)
	table.apply_view(before)
	table.set_hand_order(order.view())
	table._render(false)
	var source: Transform3D = table.tiles[drawn].transform
	var discard: int = dealt[1][4]
	check(round.submit(1, round.prompt_id, "discard", discard), "discard an old hand tile")
	var after := round.snapshot_for(1)
	order.sync_hand("motion", 1, round.prompt_id, after.players[1].hand, -1)
	var arrangement := advice.arrange(after, order.view())
	check(not arrangement.insertion.is_empty() and not arrangement.insertion.make_room.is_empty(), "actual arrangement needs a gap")
	order.apply_auto_slots(arrangement.slots)
	var display := order.view()
	display.insertion = arrangement.insertion
	var moving: int = arrangement.insertion.make_room[0].id
	var start: Transform3D = table.tiles[moving].transform
	# Use the app's current two-call path as well as the atomic path introduced by the fix.
	table.apply_view(after)
	table.set_hand_order(display)
	for frame in 120:
		if not table._motions.has(moving) or table._motions[moving].get_total_elapsed_time() > 0.0: break
		await process_frame
	await create_timer(Table.MOVE_SECONDS * 0.25).timeout
	check(table.tiles[drawn].transform.is_equal_approx(source), "draw waits while other tiles open a slot")
	check(not table.tiles[moving].transform.is_equal_approx(start), "existing tiles are already making room")
	await create_timer(Table.MOVE_SECONDS * 0.85).timeout
	check(table.tiles[moving].transform.is_equal_approx(table._destinations[moving]), "gap is open before insertion completes")
	var active = table._motions.get(drawn)
	check(active != null, "draw insertion is still animated after gap opens")
	table.apply_view(after)
	table.set_hand_order(display)
	check(table._motions.get(drawn) == active, "duplicate snapshot does not restart insertion")
	for frame in 120:
		if not table._motions.has(moving) or table._motions[moving].get_total_elapsed_time() > 0.0: break
		await process_frame
	await create_timer(Table.MOVE_SECONDS * 0.25).timeout
	check(table.tiles[drawn].position.y - Table.Layout.LONG * 0.5 > Table.Layout.LONG, "inserting card crosses above the upright row")
	await create_timer(Table.MOVE_SECONDS * 0.8).timeout
	check(table.tiles[drawn].transform.is_equal_approx(table._destinations[drawn]), "draw ends in the calculated sorted slot")
	check(table.tiles.size() == 108 and table._motions.is_empty(), "no duplicate tiles or leftover animations")
	check(table._destinations[drawn].origin.x < table._destinations[moving].origin.x, "draw has inserted before the shifted tile")
	table.apply_view({})
	table.apply_view(before)
	table._render(false)
	source = table.tiles[drawn].transform
	table.apply_view(after, display)
	for frame in 120:
		if not table._motions.has(moving) or table._motions[moving].get_total_elapsed_time() > 0.0: break
		await process_frame
	await create_timer(Table.MOVE_SECONDS * 0.25).timeout
	check(table.tiles[drawn].transform.is_equal_approx(source), "atomic hand snapshot also waits for the gap")
	table.set_flat_hands(true)
	check(table._motions.is_empty(), "posture change cancels outstanding hand motion")
	table.apply_view({})
	check(table.tiles.is_empty() and table._last_insert_discard == -1, "new round clears insertion history")
	table.free()
	print("Hand motion: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
