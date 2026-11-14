extends SceneTree
## Real shuffled round, actual turn/response submissions and GUI clicks; one capture per second.
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var table
var folder := "res://build/sort-audit-20261115/live-before"
var started := 0
var frames: Array = []
var actions: Array = []
var capturing := false
var sort_on_turn := 0
var sort_off_turn := 0
var restores := 0
var next_capture := 0

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	var seed_value := 2026111283
	var viewer := 1
	var claim_first := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): folder = "res://" + arg.substr(6)
		if arg.begins_with("--seed="): seed_value = int(arg.substr(7))
		if arg.begins_with("--viewer="): viewer = int(arg.substr(9))
		if arg == "--claims": claim_first = true
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_node("GameConfig").set_tile_animation_seconds(0.3, false)
	root.get_node("GameConfig").set_settlement_speed("fast", false)
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.human_seat = viewer
	table._table_actions.auto_ready_enabled = false
	table._new_areas._sort_button.pressed.connect(func():
		if table.round.allowed_actions(table.human_seat).get("kind", "") == "turn": sort_on_turn += 1
		else: sort_off_turn += 1)
	table._new_areas._restore_button.pressed.connect(func(): restores += 1)
	var actor = load("res://scripts/ai/AiPlayer.gd")
	for seat in 4:
		table.round.controllers[seat] = null if seat == table.human_seat else actor.new("live%d" % seat, "low")
	table.round.ai_delay_seconds = 0.8
	table.round.ai_response_delay_seconds = 0.8
	table.round.set_rng_seed(seed_value)
	table.round.next_dealer_seat = 2
	table.round.visual_event.connect(func(event): actions.append({"ms": Time.get_ticks_msec() - started, "event": event.duplicate(true)}))
	started = Time.get_ticks_msec()
	next_capture = started + 1000
	var timer := Timer.new()
	timer.wait_time = 0.05
	timer.timeout.connect(func():
		if not capturing and Time.get_ticks_msec() >= next_capture:
			next_capture += 1000
			_capture())
	root.add_child(timer)
	timer.start()
	table.round.start_round(table.human_seat, 2, 6)
	_capture()
	var local_actor = actor.new("local", "low")
	var tick := 0
	var prompt_since := 0
	var prompt := -1
	var deadline := started + 240000
	while table.round.phase != RoundState.Phase.SETTLED and Time.get_ticks_msec() < deadline:
		await create_timer(0.4).timeout
		var view = table._new_areas
		if view.native_presentation_pending() or table._table_animation_controller.input_locked(): continue
		var window: Dictionary = table.round.allowed_actions(table.human_seat)
		if not window.is_empty() and int(window.prompt_id) != prompt:
			prompt = int(window.prompt_id)
			prompt_since = Time.get_ticks_msec()
		var button: Button = view._sort_button
		var restoring: bool = tick % 5 == 3 and view._restore_button.visible
		if restoring: button = view._restore_button
		if button.visible and not button.disabled:
			var on_turn: bool = window.get("kind", "") == "turn"
			var old := str(view._local_arrangement.get("key", ""))
			await _click(button)
			actions.append({"ms": Time.get_ticks_msec()-started, "click": "restore" if restoring else "sort", "on_turn": on_turn,
				"before": old, "after": view._local_arrangement.get("key", ""), "hand": table.round.players[table.human_seat].concealed.duplicate()})
			tick += 1
		window = table.round.allowed_actions(table.human_seat)
		if window.is_empty() or Time.get_ticks_msec()-prompt_since < 900 or table._table_actions.input_locked(): continue
		if window.kind == "turn":
			var decision: Dictionary = local_actor.decide_turn(table.round, table.human_seat)
			if claim_first:
				if not window.options.kong_declares.is_empty(): decision = {"kong_declares": [window.options.kong_declares[0]]}
				elif not window.options.add_kong.is_empty(): decision = {"add_kong": [window.options.add_kong[0]]}
				elif decision.has("discard"): decision["ready"] = false
			if decision.has("discard"):
				if bool(decision.get("ready", false)) and not table._table_actions._declaring_ready: table._toggle_ready()
				var matching: Array = (view.hand_boxes[table.human_seat].get_children() + view.draw_boxes[table.human_seat].get_children()).filter(
					func(node): return node is TileView and str(node.tile) == str(decision.discard) and node.interactive)
				if not matching.is_empty(): await _click(matching.back())
				else: table._commit_turn(decision)
			else: table._commit_turn(decision)
		else:
			var pending: Dictionary = table.round._awaiting_response
			var decision: Dictionary = local_actor.decide_response(table.round, table.human_seat, int(pending.disc_seat), str(pending.tile), window.options)
			if claim_first and not window.options.can_win:
				if window.options.can_kong: decision = {"action": "kong"}
				elif window.options.can_pong: decision = {"action": "pong"}
			table._commit_response(str(decision.get("action", "pass")))
	t.expect(table.round.phase == RoundState.Phase.SETTLED, "real shuffled round reaches a legal settlement")
	if table.round.phase == RoundState.Phase.SETTLED:
		var until := Time.get_ticks_msec() + 15000
		while not table._new_areas.native_settlement_complete() and Time.get_ticks_msec() < until: await process_frame
		await create_timer(1.2).timeout
		t.expect(is_zero_approx(float(table.round.last_result.total_delta)), "real settlement remains zero sum")
	timer.stop()
	while capturing: await process_frame
	t.expect(sort_on_turn > 0 and sort_off_turn > 0 and restores > 0, "actual GUI sorting and Restore tested both on and off turn")
	_save_trace()
	print("LIVE seed=", seed_value, " frames=", frames.size(), " on_turn=", sort_on_turn, " off_turn=", sort_off_turn, " restore=", restores)
	if table._ai_service != null: table._ai_service.stop()
	table.queue_free()
	timer.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("sort_live_round"))

func _click(control: Control) -> void:
	var position := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		event.global_position = position
		root.push_input(event, true)
		await process_frame

func _capture() -> void:
	if capturing or not is_instance_valid(table): return
	capturing = true
	await RenderingServer.frame_post_draw
	var view = table._new_areas
	var player: PlayerState = table.round.players[table.human_seat]
	var visible: Array = []
	for node in view.hand_boxes[table.human_seat].get_children() + view.draw_boxes[table.human_seat].get_children():
		visible.append({"tile": node.tile, "index": node.get_meta("concealed_index", -1), "drawn": node.get_meta("drawn", false), "interactive": node.interactive})
	var stable: bool = not view.native_presentation_pending() and not table._table_animation_controller.has_pending()
	if stable and table.round.phase == RoundState.Phase.PLAYING:
		t.expect(Tiles.sort_hand(visible.map(func(node): return node.tile)) == Tiles.sort_hand(player.concealed), "real stable visible hand contains exactly the authoritative tiles")
		var indices := {}
		for node in visible:
			t.expect(int(node.index) in range(player.concealed.size()) and str(player.concealed[int(node.index)]) == str(node.tile) and not indices.has(node.index), "real sorted hit targets refer to unique correct authoritative tiles")
			indices[node.index] = true
		var window: Dictionary = table.round.allowed_actions(table.human_seat)
		for node in visible:
			if node.interactive:
				t.expect(window.get("kind", "") == "turn" and window.options.discards.has(node.tile) and (not player.ready or node.drawn), "sorting never enables off-turn or locked hand input")
	var name := "%04d.png" % frames.size()
	root.get_texture().get_image().save_png(folder + "/" + name)
	Shanten._thread_cache_mutex.lock()
	var caches := Shanten._thread_caches.size()
	Shanten._thread_cache_mutex.unlock()
	frames.append({"file": name, "ms": Time.get_ticks_msec()-started, "turn": table.round.current_turn, "phase": table.round.phase,
		"stable": stable, "hand": player.concealed.duplicate(), "melds": player.melds.duplicate(true), "draw": player.just_drew,
		"visible": visible, "caption": view._arrangement_caption.text, "sort_disabled": view._sort_button.disabled,
		"choices": view._arrangement_choices.size(), "thread_caches": caches})
	_save_trace()
	if frames.size() % 10 == 0: print("LIVE frames=", frames.size(), " wall=", table.round.wall.remaining, " on=", sort_on_turn, " off=", sort_off_turn, " restores=", restores)
	capturing = false

func _save_trace() -> void:
	var output := FileAccess.open(folder + "/trace.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"frames": frames, "actions": actions,
		"on_turn": sort_on_turn, "off_turn": sort_off_turn, "restores": restores}, "\t"))
	output.close()
