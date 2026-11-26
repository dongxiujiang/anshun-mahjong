extends SceneTree

const Match = preload("res://src/session/MatchSession.gd")
const Dice = preload("res://src/runtime/DiceRoll.gd")
const Wall = preload("res://src/domain/Wall.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Order = preload("res://src/presentation/HandOrder.gd")
const Arrangement = preload("res://src/presentation/HandArrangement.gd")
const Record = preload("res://src/session/RoundRecord.gd")
const Mirror = preload("res://src/presentation/SharedHandDisplay.gd")
const Table = preload("res://src/presentation/TableView.gd")
const Host = preload("res://src/runtime/GameHost.gd")

var checks := 0
var failures := 0
var game := Match.new("9234")
var instance := ""
var connections := ["c0", "c1", "c2", "c3"]
var tickets := [{}, {}, {}, {}]
var published := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(description)

func view(seat: int) -> Dictionary:
	return game.view_for(connections[seat], 20).round

func send_layout(seat: int, layout: Dictionary) -> int:
	return game.set_hand_display(connections[seat], instance, 1, game._round.prompt_id, layout, 20)

func submit(seat: int, action: String, id := -1) -> bool:
	return game.submit(connections[seat], instance, 1, game._round.prompt_id, action, id, 20)

func deck(red: int) -> Array:
	var stock := Catalog.values(813)
	var w := Wall.new(stock)
	w.open(0, red)
	var assigned := {}
	var hands := [[], [], [], []]
	for count in [4, 4, 4, 1]:
		for seat in [0, 3, 2, 1]:
			for j in count:
				hands[seat].append(w.take_head())
	for i in 4:
		assigned[hands[0][i]] = "wan1"
	assigned[hands[0][4]] = "tiao9"
	for i in 2:
		assigned[hands[3][i]] = "tiao9"
	assigned[w.take_tail()] = "tong5"
	for value in assigned.values():
		stock.erase(value)
	var result := []
	for id in 108:
		result.append(assigned[id] if assigned.has(id) else stock.pop_back())
	return result

func _run() -> void:
	for seat in [1, 0, 3, 2]:
		var profile := {"suit_order": ["tong", "tiao", "wan"], "novice": true, "hand_priority": "pattern"} if seat == 2 else {}
		var joined := game.join("human" + str(seat), "人" + str(seat), connections[seat], 0, profile)
		tickets[seat] = joined.ticket
		check(joined.view.seat == seat and game.set_ready(connections[seat], true, 0), "four authenticated humans occupy real seats")
	instance = tickets[0].room_instance_id
	var dice := Dice.new()
	root.add_child(dice)
	dice.roll(778)
	for tick in 1800:
		await physics_frame
		if dice.phase == "settled":
			break
	check(dice.phase == "settled" and game.start_round(dice, deck(dice.snapshot().result[0]), 10, 0), "start from actual dice and legal 108-tile wall")
	var initial := view(0)
	var own: Dictionary = initial.players[0].display
	var all_keys := {}
	for seat in 4:
		var dealt: Dictionary = view(seat).players[seat]
		var lookup: Dictionary = dealt.display.own_keys
		var sorted: Array = dealt.hand.duplicate()
		sorted.sort_custom(func(a, b):
			var sa: int = Catalog.SUITS.find(a.value.left(-1))
			var sb: int = Catalog.SUITS.find(b.value.left(-1))
			return sa < sb if sa != sb else (a.value < b.value if a.value != b.value else a.id < b.id))
		if seat == 2:
			var custom := Order.new()
			custom.set_suit_order(["tong", "tiao", "wan"])
			custom.sync_hand(instance, 1, initial.prompt_id, dealt.hand)
			var expected := Arrangement.new().arrange(view(seat), custom.view(), "pattern", true)
			check(dealt.display.slots == expected.slots.map(func(id): return lookup[str(id)]), "session initializes custom novice sorting before publishing the first deal")
		else:
			check(dealt.display.slots == sorted.map(func(face): return lookup[str(face.id)]), "canonical initial order")
		check(dealt.display.deal_keys == dealt.hand.map(func(face): return lookup[str(face.id)]), "fixed opaque deal path is independent of sorted row")
		for key in lookup.values():
			check(key is String and key.length() == 32 and not all_keys.has(key), "opaque hand keys distinct across all wall sources")
			all_keys[key] = true
		for other in 4:
			if other != seat:
				var masked: Dictionary = view(other).players[seat]
				check(masked.hand.is_empty() and not masked.display.has("own_keys") and masked.display.slots == dealt.display.slots, "all viewers see identical backs without owner lookup")
	var second := Mirror.new()
	second.sync(game._round)
	var another := game._round.snapshot_for(0)
	second.project(game._round, another)
	check(another.players[0].display.own_keys != own.own_keys, "a fresh round mints a fresh namespace")
	var preferences := []
	for seat in 4:
		preferences.append({"suit_order": ["tong", "tiao", "wan"], "novice": seat % 2 == 0, "hand_priority": "multiple"})
	var personalized := Mirror.new()
	personalized.sync(game._round, preferences)
	for seat in 4:
		var visible := game._round.snapshot_for(seat)
		var local_order := Order.new()
		local_order.set_suit_order(preferences[seat].suit_order)
		local_order.sync_hand(instance, 1, visible.prompt_id, visible.players[seat].hand)
		var desired := Arrangement.new().arrange(visible, local_order.view(), "multiple", preferences[seat].novice)
		personalized.project(game._round, visible)
		var display: Dictionary = visible.players[seat].display
		check(display.slots == desired.slots.map(func(tile): return display.own_keys[str(tile)]), "first server projection already uses owner's selected opening order")
		for observer in 4:
			var other := game._round.snapshot_for(observer)
			personalized.project(game._round, other)
			check(other.players[seat].display.slots == display.slots, "all opening observers receive same personalized sorting targets before animation")
	check(game.begin_dealer_turn(instance, 1, initial.prompt_id, 12), "dealer initial independent draw")
	var before := view(0)
	var actor: Dictionary = before.players[0]
	var draw_test := Order.new()
	draw_test.sync_hand(instance, 1, before.prompt_id, actor.hand, actor.draw_id)
	var draw_mirror := Mirror.new()
	draw_mirror.sync(game._round)
	check(draw_test.begin_drag(actor.draw_id), "separate draw starts a drag")
	draw_test.move_gap(3)
	check(draw_mirror.accept(0, draw_test.view()) == 1, "draw drag preview is accepted")
	draw_test.cancel_drag()
	check(draw_mirror.accept(0, draw_test.view()) == 1 and not draw_test.view().draw_merged, "cancel restores the separate draw on both sides")
	draw_test.begin_drag(actor.draw_id)
	draw_test.move_gap(3)
	check(draw_mirror.accept(0, draw_test.view()) == 1, "draw preview can be repeated")
	draw_test.commit_drag(3)
	check(draw_mirror.accept(0, draw_test.view()) == 1 and draw_test.view().slots[3] == actor.draw_id and draw_test.view().draw_merged, "draw insertion commits and synchronizes")
	var order := Order.new()
	order.sync_hand(instance, 1, before.prompt_id, actor.hand, actor.draw_id)
	order.tap(actor.draw_id)
	check(send_layout(0, order.view()) == 1 and send_layout(0, order.view()) == 0, "draw selection published once")
	var drawn: String = actor.display.draw
	check(view(1).players[0].display.selected == drawn and not drawn.is_empty(), "others see selected independent draw")
	var id: int = order.view().slots[1]
	var origin: String = actor.display.own_keys[str(id)]
	order.begin_drag(id)
	order.move_gap(4)
	var gesture := order.view()
	gesture.drag_position = [2.5, 9.0]
	var raw := game._round.snapshot_for(0)
	var wall: Dictionary = game._round.wall.snapshot()
	var tape := game._round.events.duplicate(true)
	check(send_layout(0, gesture) == 1, "drag and gap accepted")
	for observer in 4:
		var seen: Dictionary = view(observer).players[0].display
		check(seen.slots[4] == "" and seen.dragged == origin and seen.selected == "" and seen.drag_position == [2.5, 9.0], "identical drag endpoint and empty slot at all seats")
	var stable := view(1)
	for field in ["duplicate", "foreign", "draw", "hidden", "nan", "outside", "malformed", "gap", "fraction", "unknown"]:
		var bad := gesture.duplicate(true)
		match field:
			"duplicate": bad.slots[0] = bad.slots[2]
			"foreign": bad.slots[0] = view(1).players[1].hand[0].id
			"draw": bad.slots[0] = actor.draw_id
			"hidden": bad.pending_insert_ids = [999]
			"nan": bad.drag_position = [NAN, 0]
			"outside": bad.drag_position = [0, 100]
			"malformed": bad.drag_position = [4, "5"]
			"gap": bad.gap_slot = 1
			"fraction": bad.dragged_id = 2.5
			"unknown": bad.selected_id = 77
		check(send_layout(0, bad) == -1 and view(1) == stable, "bad display request leaves all state intact: " + field)
	check(game.set_hand_display("intruder", instance, 1, before.prompt_id, gesture, 20) == -1 and game.set_hand_display("c0", instance, 1, initial.prompt_id, gesture, 20) == -1 and game.set_hand_display("c0", instance, 2, before.prompt_id, gesture, 20) == -1 and game.set_hand_display("c0", "other", 1, before.prompt_id, gesture, 20) == -1, "authentication, instance, round and prompt guards")
	order.commit_drag(4)
	check(send_layout(0, order.view()) == 1, "manual drop commits real IDs in new order")
	var committed: Array = view(1).players[0].display.slots
	check(committed[4] == origin and view(1).players[0].display.manual, "other clients follow actual committed slot")
	order.begin_drag(id)
	order.move_gap(0)
	send_layout(0, order.view())
	check(game.disconnect_human("c0", 20), "disconnect")
	var resumed := game.resume(instance, tickets[0].player_id, tickets[0].member_token, "new0", 20)
	connections[0] = "new0"
	check(resumed.round.players[0].display.slots == committed and resumed.round.players[0].display.dragged == "" and resumed.round.players[0].display.own_keys == actor.display.own_keys, "resume restores committed order and cancels abandoned preview")
	check(game.set_hand_display("c0", instance, 1, before.prompt_id, gesture, 20) == -1, "retired connection cannot move tiles")
	check(wall == game._round.wall.snapshot() and raw == game._round.snapshot_for(0) and tape == game._round.events, "arrangement never touches authoritative tiles, events, choices or wall")
	var kong_id: int = before.choices.concealed_kong_ids.filter(func(k): return game._round.wall.value(k) == "wan1")[0]
	var table := Table.new()
	root.add_child(table)
	table.apply_view(view(1))
	var old_nodes: Dictionary = table.tiles.duplicate()
	check(submit(0, "concealed_kong", kong_id), "real concealed kong, tail draw")
	var concealed: Dictionary = view(0).players[0].melds[0]
	var backs: Dictionary = view(1).players[0].melds[0]
	table.apply_view(view(1))
	for back_key in backs.display_keys:
		check(table.tiles.get(back_key) == old_nodes.get(back_key) and table.tiles[back_key].get_meta("zone") == "meld" and table.tiles[back_key].get_meta("value") == "", "hidden kong reuses all four original concealed meshes")
	check(not backs.has("tile_ids") and not backs.has("tile") and backs.display_keys == concealed.display_keys and backs.display_keys.size() == 4, "four original opaque keys fly into hidden kong")
	check(concealed.tile_ids.all(func(k): return not view(1).public_origins.has(str(k))), "unrevealed kong physical IDs have no public bridge")
	var disc: int = view(0).players[0].hand.filter(func(face): return face.value == "tiao9")[0].id
	var discarded_key: String = actor.display.own_keys[str(disc)]
	var tail_id: int = view(0).players[0].draw_id
	var tail_key: String = view(0).players[0].display.draw
	check(submit(0, "discard", disc), "discard old tile with retained supplement")
	check(view(2).public_origins[str(disc)] == discarded_key and view(2).players[0].display.pending.has(tail_key) and not view(2).public_origins.has(str(tail_id)), "publish exact old source and keep new tile in manual pending list")
	var response_prompt: int = view(3).prompt_id
	for seat in [3, 2, 1]:
		var response := view(seat)
		if response.prompt_id == response_prompt and not response.choices.is_empty():
			check(submit(seat, "pong" if seat == 3 else "pass", disc), "single real response window")
	var pong: Dictionary = view(2).players[3].melds[0]
	check(pong.display_keys.has(discarded_key) and pong.display_keys == pong.tile_ids.map(func(k): return view(2).public_origins[str(k)]), "claimed source and both former hand keys used by meld")
	var steps := 0
	var saw_reveal := false
	while game._round.phase != "settled" and steps < 900:
		steps += 1
		for seat in 4:
			var choices: Dictionary = view(seat).choices
			if choices.get("actions", []).has("discard"):
				submit(seat, "discard", choices.discard_ids.back())
				break
			if choices.get("actions", []).has("pass"):
				submit(seat, "pass", choices.get("tile_id", -1))
				break
		if not saw_reveal and game._round.players[0].discard_count == 2:
			var shown: Dictionary = view(1).players[0].melds[0]
			check(shown.get("tile_ids", []) == concealed.tile_ids and shown.display_keys == backs.display_keys and shown.tile_ids.all(func(k): return view(1).public_origins.has(str(k))), "second discard exposes existing kong identities once")
			saw_reveal = true
	check(saw_reveal, "legal play reached concealed-kong reveal")
	table.free()
	check(game._round.phase == "settled" and Record.replay(game.last_completed_record()).get("ok", false), "actual completed round replays unaffected by display metadata")
	await _host_integration()
	print("SharedHandDisplay: %d checks, %d failures" % [checks, failures])
	dice.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _host_integration() -> void:
	var host := Host.new()
	host.clock_msec = func(): return 10000
	root.add_child(host)
	host.configure("3888", "solo", 1, {"external_presentation": true})
	var joined := host.join("local", "甲", "local")
	host.set_ready("local", true)
	for tick in 1800:
		await physics_frame
		if host.view_for("local").round.phase == "dealt":
			break
	var state := host.view_for("local")
	if state.round.phase != "dealt":
		check(false, "host did not deal")
		host.shutdown()
		host.queue_free()
		return
	var other := host.join("newperson", "乙", "other")
	check(other.ticket.seat != joined.ticket.seat, "fresh member takes the live AI hand")
	var row: Dictionary = state.round.players[state.seat]
	var order := Order.new()
	order.sync_hand(state.room.room_instance_id, state.room.round_number, state.round.prompt_id, row.hand, row.draw_id)
	order.tap(row.hand[3].id)
	host.view_changed.connect(func(_conn, _state): published += 1)
	var id: String = state.room.room_instance_id
	var p: int = state.round.prompt_id
	check(host.set_hand_display("local", id, 1, p, order.view()) and published == 2, "one changed gesture publishes to both authenticated members")
	check(host.set_hand_display("local", id, 1, p, order.view()) and published == 2, "idempotent request sends no redundant snapshot")
	check(not host.set_hand_display("retired", id, 1, p, order.view()) and published == 2, "unbound connection cannot broadcast a display")
	var observer := host.view_for("other")
	check(observer.round.prompt_id == p and observer.round.players[state.seat].display.selected == row.display.own_keys[str(row.hand[3].id)], "live takeover sees correct moving opaque tile without advancing prompt")
	host.shutdown()
	host.queue_free()
