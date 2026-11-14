extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var r := RoundState.new()
	r.next_dealer_seat = 2
	r.set_rng_seed(2026111283)
	r.pause_after_opening = true
	r.start_round(1, 2, 6)
	r.controllers = [null, null, null, null]
	r.resume_after_opening()
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.auto_sort_hands = false
	view.set_round(r, 1)
	var reserved: Rect2 = view.reserved_action_rect()
	for i in 9: view._hand_groups.add_child(ColorRect.new())
	t.expect(view.reserved_action_rect() == reserved, "sorting group decorations do not enlarge the claim-button exclusion area")
	var before := Shanten._thread_caches.size()
	view._sort_own_hand()
	await _finish_search(view)
	t.expect(view._arrangement_done_key == view._arrangement_key, "first click completes its own background search")
	t.expect(Shanten._thread_caches.size() <= before, "finished sorting workers release their private Shanten caches")
	view._restore_own_hand()
	# Hold the previous job until the user has already restored and sorted again.
	var gate := Semaphore.new()
	view._arrangement_thread = Thread.new()
	view._arrangement_job_key = "old-hand-job"
	view._arrangement_thread.start(func(): gate.wait(); return [])
	view._sort_own_hand()
	var key: String = view._arrangement_key
	gate.post()
	await _finish_search(view)
	t.expect(view._arrangement_done_key == key, "a new sorted hand automatically gets its search after an obsolete job exits")
	t.expect(view._arrangement_choices.all(func(choice): return Tiles.sort_hand(choice.cards) == Tiles.sort_hand(r.players[1].concealed)), "obsolete work never replaces the current hand")
	await _merged_discard(view, true)
	await _merged_discard(view, false)
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("hand_arrangement_lifecycle"))

func _merged_discard(view, from_draw: bool) -> void:
	var r := RoundState.new()
	r.next_dealer_seat = 1
	r.set_rng_seed(2026111283)
	r.pause_after_opening = true
	r.start_round(1, 2, 6)
	r.controllers = [null, null, null, null]
	view.set_round(r, 1)
	r.resume_after_opening()
	var p: PlayerState = r.players[1]
	var draw := str(p.just_drew)
	var done := {"value": false}
	view.animate_draw(1, draw, int(r.wall.draw_log.back().index), func(): done.value = true)
	while not done.value: await process_frame
	view.refresh()
	view._sort_own_hand()
	var index := p.concealed.size() - 1 if from_draw else 0
	var discard := str(p.concealed[index])
	t.expect(r.submit_turn(1, {"discard": discard, "discard_index": index}), "real post-sort discard is accepted")
	done.value = false
	if from_draw: view.animate_draw_discard(1, func(): done.value = true, discard)
	else: view.animate_draw_insert(1, discard, draw, func(): done.value = true, index)
	while not done.value: await process_frame
	view.refresh()
	t.expect(view._pending_draws[1] == "" and view.draw_boxes[1].get_child_count() == 0, "merged discard clears pending draw rather than restoring a ghost tile")
	var visible: Array = view.hand_boxes[1].get_children().map(func(node): return str(node.tile))
	t.expect(Tiles.sort_hand(visible) == Tiles.sort_hand(p.concealed), "after either kind of merged discard, exactly the real remaining tiles stay visible")
	await _finish_search(view)

func _finish_search(view) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while view._arrangement_thread != null and Time.get_ticks_msec() < deadline:
		await process_frame
	t.expect(view._arrangement_thread == null, "sorting worker finishes without blocking the interface")
