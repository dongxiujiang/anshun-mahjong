extends SceneTree

const HandOrder := preload("res://src/presentation/HandOrder.gd")
const Round := preload("res://src/domain/Round.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")

var _failures := 0


func _initialize() -> void:
	_test_sorting_and_selection()
	_test_crossing_and_cancel()
	_test_refresh_during_drag()
	_test_round_and_room_changes()
	_test_invalid_tile_ids()
	_test_private_projection()
	_test_restore_shared()
	if _failures == 0:
		print("Hand order tests passed")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _faces(values: Array, first_id: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in values.size():
		result.append({"id": first_id + index, "value": values[index]})
	return result


func _test_sorting_and_selection() -> void:
	var hand := HandOrder.new()
	var faces := _faces(["tiao8", "wan9", "tong2", "wan1", "wan1", "wan1"])
	_check(hand.sync_hand("room", 1, 1, faces, 5), "Load own tile identities")
	_check(hand.view().slots == [3, 4, 1, 0, 2], "Default sorting groups suits, ranks and duplicate values")
	_check(hand.view().draw_id == 5, "The matching-value draw stays separate")
	_check(hand.begin_drag(5), "Independent draw can be dragged")
	hand.move_gap(2)
	_check(hand.view().draw_merged and hand.view().slots == [3, 4, -1, 1, 0, 2], "Draw preview includes the full row")
	hand.cancel_drag()
	_check(not hand.view().draw_merged and hand.view().slots == [3, 4, 1, 0, 2], "Cancel restores separate draw")
	_check(hand.begin_drag(5), "Draw can be picked up again")
	hand.commit_drag(2)
	_check(hand.view().draw_merged and hand.view().manual and hand.view().slots == [3, 4, 5, 1, 0, 2], "Draw insertion merges at the chosen slot")
	var refreshed := faces.duplicate(true)
	refreshed.remove_at(2)
	_check(hand.sync_hand("room", 1, 2, refreshed, 5) and hand.view().slots.has(5), "A hand refresh retains the manually merged draw")
	hand.sync_hand("room", 1, 3, faces, 5)
	hand.restore_order()
	hand.apply_sort_plan([3, 4, 1, 0, 2], false)
	hand.restore_order()
	_check(hand.tap(3) == -1 and hand.view().selected_id == 3, "Tap lifts the first physical tile")
	_check(hand.tap(4) == -1 and hand.view().selected_id == 4, "A different copy is a new selection")
	_check(hand.tap(5) == -1 and hand.tap(5) == 5, "Second tap returns the actual new draw ID")
	faces.pop_back()
	_check(hand.sync_hand("room", 1, 4, faces), "Apply the successful discard")
	_check(hand.view().selected_id == -1 and hand.view().slots.has(3) and hand.view().slots.has(4), "The discarded ID clears without touching other copies")
	_check(hand.set_suit_order(["tong", "tiao", "wan"]), "Choose another suit order")
	_check(hand.view().slots == [2, 0, 3, 4, 1], "Configured order applies in automatic mode")
	_check(not hand.set_suit_order(["tong", "tong", "wan"]), "Suit setting must be a permutation")
	_check(hand.view().slots == [2, 0, 3, 4, 1], "Invalid setting leaves the order intact")
	hand.tap(4)
	hand.clear_selection()
	_check(hand.view().selected_id == -1, "An accepted action or UI dismissal can explicitly clear the lift")


func _test_crossing_and_cancel() -> void:
	var hand := HandOrder.new()
	var faces := _faces(["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tiao7", "tong3", "tong7", "tong9"])
	var original := range(13)
	_check(hand.sync_hand("room", 1, 1, faces), "Load a thirteen-tile row")
	_check(hand.begin_drag(9), "Pick up the tenth tile")
	_check(hand.view().slots == [0, 1, 2, 3, 4, 5, 6, 7, 8, -1, 10, 11, 12], "Picking up only opens the original slot")
	_check(hand.move_gap(8) == [{"id": 8, "from_slot": 8, "to_slot": 9}], "The tiao3 tile moves toward the previous space")
	var left := hand.move_gap(2)
	_check(left.size() == 6 and left[0] == {"id": 7, "from_slot": 7, "to_slot": 8} and left[5] == {"id": 2, "from_slot": 2, "to_slot": 3}, "All six crossed tiles get one simultaneous slot change")
	_check(hand.view().slots == [0, 1, -1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12], "Uncrossed tiles stay in place after a long left move")
	var right := hand.move_gap(12)
	_check(right.size() == 10 and right[0] == {"id": 2, "from_slot": 3, "to_slot": 2} and right[9] == {"id": 12, "from_slot": 12, "to_slot": 11}, "A long right move uses the actual prior preview slots")
	_check(hand.view().slots == [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, -1], "Crossing back preserves every intervening tile order")
	_check(hand.cancel_drag() == [{"id": 9, "from_slot": -1, "to_slot": 9}, {"id": 10, "from_slot": 9, "to_slot": 10}, {"id": 11, "from_slot": 10, "to_slot": 11}, {"id": 12, "from_slot": 11, "to_slot": 12}], "Cancel returns both the held tile and every displaced tile")
	for target in original:
		_check(hand.begin_drag(9), "Each preview can start after cancellation")
		hand.move_gap(target)
		hand.commit_drag(9 if target % 2 == 0 else 13)
		_check(hand.view().slots == original and hand.view().gap_slot == -1 and hand.view().dragged_id == -1, "Release over the origin or outside restores the whole row from slot %d" % target)
	_check(hand.begin_drag(9), "Prepare a valid reorder")
	hand.move_gap(8)
	_check(hand.commit_drag(8) == [{"id": 9, "from_slot": -1, "to_slot": 8}], "Commit places the lifted tile into the remaining gap")
	_check(hand.view().slots == [0, 1, 2, 3, 4, 5, 6, 7, 9, 8, 10, 11, 12] and hand.view().manual, "Manual order persists with no residual gap")


func _test_refresh_during_drag() -> void:
	var hand := HandOrder.new()
	var faces := _faces(["wan1", "wan2", "tiao1", "tong3"])
	_check(hand.sync_hand("room", 1, 1, faces), "Load hand for refresh")
	_check(hand.begin_drag(3), "Start reordering")
	hand.commit_drag(0)
	_check(hand.view().slots == [3, 0, 1, 2], "Set a manual order")
	_check(hand.begin_drag(0), "Lift a tile from the manual row")
	hand.move_gap(3)
	faces.reverse()
	_check(hand.sync_hand("room", 1, 2, faces), "Receive a different prompt with the same tile identities")
	_check(hand.view().slots == [3, 1, 2, -1], "Unchanged ownership preserves the active drag across prompts")
	_check(hand.cancel_drag().size() == 3 and hand.view().slots == [3, 0, 1, 2], "Cancel restores the existing manual order")

	_check(hand.begin_drag(0), "Lift the tile again")
	hand.move_gap(3)
	faces.append({"id": 4, "value": "tiao1"})
	_check(hand.sync_hand("room", 1, 3, faces, 4), "A new draw changes membership")
	_check(hand.view().slots == [3, 0, 1, 2] and hand.view().draw_id == 4, "Changed membership cancels the transient movement safely")
	_check(hand.commit_drag(3).is_empty(), "A stale release cannot reorder the refreshed row")
	hand.tap(2)
	_check(hand.sync_hand("room", 1, 4, faces, 4), "Receive a later prompt without changing the held tiles")
	_check(hand.view().selected_id == -1 and hand.view().slots == [3, 0, 1, 2], "New prompt clears click selection and preserves manual order")

	_check(hand.begin_drag(0), "Lift a tile before it leaves the hand")
	hand.move_gap(3)
	faces = faces.filter(func(face): return face.id != 0)
	_check(hand.sync_hand("room", 1, 5, faces), "A server action removes the lifted tile and folds in the draw")
	var refreshed := hand.view()
	_check(refreshed.slots == [3, 1, 2] and refreshed.dragged_id == -1 and refreshed.draw_id == -1, "Only surviving original row tiles remain and the gesture ends")
	_check(refreshed.pending_insert_ids == [4], "Retained draw enters pending placement under manual ordering")
	_check(hand.set_suit_order(["tong", "tiao", "wan"]) and hand.view().slots == [3, 1, 2], "Changing the setting alone preserves manual order")
	hand.restore_order()
	_check(hand.view().slots == [3, 2, 4, 1] and hand.view().pending_insert_ids.is_empty() and not hand.view().manual, "Explicit restore sorts the whole current row using the setting")


func _test_round_and_room_changes() -> void:
	var hand := HandOrder.new()
	var faces := _faces(["wan1", "wan2", "tong1"])
	_check(hand.sync_hand("original", 1, 8, faces), "Initialize round context")
	_check(hand.begin_drag(2), "Start first round drag")
	hand.commit_drag(0)
	hand.tap(2)
	_check(not hand.sync_hand("original", 1, 7, faces), "A snapshot from an older prompt is ignored")
	_check(hand.view().selected_id == 2, "Stale input cannot erase the active selection")
	_check(hand.sync_hand("original", 2, 1, faces), "New round can have the same physical IDs")
	_check(hand.view().slots == [0, 1, 2] and hand.view().selected_id == -1 and not hand.view().manual, "New round resets order and click state")
	_check(not hand.sync_hand("original", 1, 9, faces), "An old round cannot reopen")
	_check(hand.begin_drag(0), "Begin a drag before joining a new room")
	hand.move_gap(2)
	_check(hand.sync_hand("new", 1, 1, _faces(["tong1", "wan2", "tiao1"])), "New room can reuse IDs with different values")
	_check(hand.view().slots == [1, 2, 0] and hand.view().dragged_id == -1, "New room resets drag state")


func _test_invalid_tile_ids() -> void:
	var hand := HandOrder.new()
	var valid := _faces(["wan1", "wan2", "tong1"])
	_check(hand.sync_hand("room", 1, 1, valid) and hand.begin_drag(1), "Start with an active drag")
	hand.move_gap(0)
	var before := hand.view()
	for invalid_id in [1.5, true, "1", -1.0, 108.0, INF, NAN]:
		var invalid := valid.duplicate(true)
		invalid[1].id = invalid_id
		_check(not hand.sync_hand("room", 1, 9, invalid) and hand.view() == before, "An invalid ID leaves the active drag unchanged")
	var duplicate := valid.duplicate(true)
	duplicate[1].id = 0.0
	_check(not hand.sync_hand("room", 1, 9, duplicate) and hand.view() == before, "Integer and floating representations of the same ID are duplicates")
	_check(hand.sync_hand("room", 1, 2, valid) and hand.view() == before, "Invalid packets do not advance the prompt")


func _test_private_projection() -> void:
	var round := Round.new()
	_check(round.start(0, 1, 2, Catalog.values(29)), "Start one authoritative round")
	var east := round.snapshot_for(0)
	var south := round.snapshot_for(1)
	_check(east.players[1].hand.is_empty() and south.players[0].hand.is_empty(), "Each player receives only their own concealed IDs")
	var hand := HandOrder.new()
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(south))
	var own: Dictionary = decoded.players[int(decoded.viewer_seat)]
	_check(own.hand[0].id is float, "JSON represents a genuine round snapshot's ID as a float")
	_check(hand.sync_hand("shared", 1, int(decoded.prompt_id), own.hand, int(own.draw_id)), "The current viewer's JSON-decoded hand loads")
	_check(hand.view().slots[0] is int, "Display state normalizes decoded IDs to integers")
	var east_id: int = east.players[0].hand[0].id
	_check(hand.tap(east_id) == -1 and not hand.begin_drag(east_id), "A different player's ID cannot be selected or dragged")
	var own_id: int = hand.view().slots.back()
	_check(hand.begin_drag(own_id), "A non-dealer can reorder during opening without a legal turn")
	hand.commit_drag(0)
	_check(hand.view().slots[0] == own_id and round.snapshot_for(1) == south, "A local reorder changes its display without changing authoritative facts")
	round.players[1].ready = true
	round.players[1].ready_ids = round.players[1].hand.duplicate()
	var ready := round.snapshot_for(1)
	_check(hand.sync_hand("shared", 1, ready.prompt_id, ready.players[1].hand, ready.players[1].draw_id), "Refresh a declared-ready hand")
	var locked_id: int = hand.view().slots.back()
	_check(ready.ready_ids.has(locked_id) and hand.begin_drag(locked_id), "A locked physical tile can be reordered for display")
	hand.commit_drag(0)
	_check(hand.view().slots[0] == locked_id and round.snapshot_for(1) == ready, "A declared-ready display reorder preserves the authority's locked IDs")

func _test_restore_shared() -> void:
	var hand := HandOrder.new()
	hand.sync_hand("room", 1, 2, _faces(["wan1", "wan2", "wan3", "wan4"]), 3)
	var shared := {"own_keys": {"0":"a", "1":"b", "2":"c", "3":"d"},
		"slots":["b","a","c"], "pending":[], "draw":"d", "manual":true}
	_check(hand.restore_shared(shared), "recover the authority's committed manual arrangement")
	_check(hand.view().slots == [1,0,2] and hand.view().manual and hand.view().draw_id == 3, "own opaque keys restore exact slots and preserve separate draw")
	var before := hand.view()
	for invalid in [["b","b","c"],["b","a","d"],["b","a","unknown"],["b","a"]]:
		var broken := shared.duplicate(true)
		broken.slots = invalid
		_check(not hand.restore_shared(broken) and hand.view() == before, "invalid shared state cannot lose, duplicate or import a tile")
