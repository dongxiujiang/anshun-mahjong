extends SceneTree
## Real Windows render and injected viewport touch; does not measure a phone's panel.
const H := preload("res://tests/test_harness.gd")
const OUT := "res://build/qa/action-feedback"
var t := H.new()
var table
var view
var actions
var round_state: RoundState
var audio
var submissions: Array[Dictionary] = []
var impacts: Array[int] = []
var dice_frames: Array[int] = []
var dice_mesh_counts: Array[int] = []

func _initialize() -> void: call_deferred("_run")

func _touch(at: Vector2, pressed: bool, canceled: bool = false, index: int = 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func _point(tile: TileView) -> Vector2:
	return view._table_3d.get_global_transform() * view._table_3d.project_tile(tile).get_center()

func _visible_outline(image: Image, rect: Rect2) -> bool:
	var transform := root.get_final_transform()
	for offset in [1.0, 2.0, 3.0]:
		var p := Vector2i(transform * Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y + offset))
		if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(p): continue
		var color := image.get_pixelv(p)
		if color.r > 0.92 and color.g > 0.79 and color.b > 0.52 and color.b < 0.71: return true
	return false

func _fixture() -> void:
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.cancel_opening()
	round_state = RoundState.new()
	round_state.build_players(1)
	round_state._reset_audio_events()
	round_state._reset_visual_events()
	round_state.controllers = [null, null, null, null]
	round_state.phase = RoundState.Phase.PLAYING
	round_state.current_turn = 1
	round_state.wall = WallRing.new(TileSetFactory.create_deck())
	for player in round_state.players:
		player.concealed = ["wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4",
			"tong2", "tong3", "tong4", "wan8", "wan9"]
	round_state.players[1].discards = ["wan7"]
	round_state.players[1].discard_ids = [0]
	round_state.players[1].discard_count = 1
	table.round = round_state
	table._connect_audio_round()
	table._opening_primed = true
	table._table_animation_controller._session = round_state._presentation.session
	table._table_animation_controller._dealt = [13, 13, 13, 13]
	view = table._new_areas
	view._sort_started = true
	actions = table._table_actions
	table.enable_net(func(decision): submissions.append(decision), Callable())
	_new_prompt()
	for i in 5: await RenderingServer.frame_post_draw

func _new_prompt() -> void:
	round_state.current_turn = 1
	round_state._ask_turn_actor()
	table._on_require_turn(1)
	table._refresh()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("[table_action_feedback_acceptance] Requires graphical driver")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 720)
	Engine.max_fps = 60
	root.get_node("GameConfig").set_tile_animation_seconds(0.3, false)
	audio = root.get_node("AudioManager")
	audio.enabled.effects = true
	audio.volumes.effects = 0.65
	await _fixture()
	audio.discard_impact_played.connect(func(): impacts.append(Time.get_ticks_usec()))
	audio.dice_played.connect(func():
		dice_frames.append(Engine.get_frames_drawn())
		dice_mesh_counts.append(view._table_3d.dice_nodes.size()))
	var tile: TileView = view.hand_boxes[1].get_child(2)
	var at := _point(tile)
	var sample_ms: Array[float] = []
	var feedback_rect: Rect2
	for i in 60:
		# Input reaches the viewport on the main loop. Screen scan-out is outside this timing.
		await create_timer(float(i % 3) * 0.005, true, false, true).timeout
		var started := Time.get_ticks_usec()
		_touch(at, true)
		t.expect(actions._pressed_tile == tile, "touch picks the projected tile")
		if not is_instance_valid(actions._press_outline): break
		feedback_rect = actions._press_outline.get_global_rect()
		await RenderingServer.frame_post_draw
		var rendered := Time.get_ticks_usec()
		var frame := root.get_texture().get_image()
		if t.expect(_visible_outline(frame, feedback_rect), "first completed frame contains the pressed tile outline"):
			sample_ms.append(float(rendered - started) / 1000.0)
		if i == 0: frame.save_png(OUT.path_join("tile-press.png"))
		_touch(at, false, true)
		await RenderingServer.frame_post_draw
	t.expect(not actions._press_outline.visible and submissions.is_empty(),
		"touch cancellation removes feedback and never submits")

	# A prompt change retires an in-progress press even when the board is reused.
	_touch(at, true)
	_new_prompt()
	_touch(at, false)
	t.expect(not actions._press_outline.visible and submissions.is_empty(), "old prompt cannot submit into a new prompt")
	_touch(at, true)
	_touch(at, false)
	_touch(at, true)
	_touch(at, false)
	t.expect(submissions.size() == 1 and view._discard_flights.is_empty() and impacts.is_empty(),
		"rapid taps submit once; awaiting authority does not move a tile or play impact")
	await RenderingServer.frame_post_draw
	t.expect(_visible_outline(root.get_texture().get_image(), feedback_rect),
		"a complete tap delivered between frames still gives visible feedback")
	await RenderingServer.frame_post_draw
	t.expect(not actions._press_outline.visible, "quick tap does not leave a stale outline")
	if not submissions.is_empty():
		await _confirm_discard(tile)

	view.animate_dice(3, 4)
	view.clear_dice_visual()
	view.animate_dice(5, 6)
	t.expect(dice_frames.is_empty(), "dice are silent until rendering")
	await RenderingServer.frame_post_draw
	t.expect(dice_frames.size() == 1 and dice_mesh_counts == [2], "exactly one cue after rendering both current dice")
	root.get_texture().get_image().save_png(OUT.path_join("dice-first-frame.png"))
	round_state.dealer_seat = 1
	table._table_animation_controller._dice_pending = true
	table._table_animation_controller._dispatch_visual_event({"type": "draw", "seat": 1, "tile": "wan6"})
	t.expect(view._dice_red == null and view._dice_white == null, "dealer's first draw clears dice before play")
	view.animate_dice(1, 2)
	table.queue_free()
	await process_frame
	await RenderingServer.frame_post_draw
	t.expect(dice_frames.size() == 1, "exiting before the next draw cancels that dice cue")

	var p95 := -1.0
	var sorted := sample_ms.duplicate()
	sorted.sort()
	if not sorted.is_empty(): p95 = sorted[ceili(float(sorted.size()) * 0.95) - 1]
	var report := FileAccess.open(OUT.path_join("desktop-input-timing.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"platform": OS.get_name(), "renderer": DisplayServer.get_name(),
		"method": "viewport touch injection to first frame_post_draw with pixel-confirmed outline",
		"resolution": str(root.size), "p95_ms": p95, "samples_ms": sample_ms,
		"target_ms": 50, "sample_count": sample_ms.size()}, "  "))
	print("[animation-latency] %d desktop samples, P95 %.2f ms (Android physical tap not measured)" % [sample_ms.size(), p95])
	await H.quit_cleanly(self, t.finish("table_action_feedback_acceptance"))

func _confirm_discard(tile: TileView) -> void:
	var initial_center: Vector2 = view.get_global_transform().affine_inverse() * tile.get_global_rect().get_center()
	round_state.submit_turn(1, submissions[0])
	t.expect(view._discard_flights.size() == 1 and impacts.is_empty(), "authoritative confirmation starts flight without impact")
	if view._discard_flights.is_empty(): return
	var flight: Dictionary = view._discard_flights.values()[0]
	t.expect(flight.node_id == tile.get_instance_id() and tile.get_rect().get_center().distance_to(initial_center) < 1.0,
		"the exact tile starts the flight from its original hand slot")
	var event := round_state.visual_events.filter(func(item): return item.type == "discard").back() as Dictionary
	table._on_visual_event(event)
	t.expect(view._discard_flights.size() == 1, "redelivered confirmation cannot start another flight")
	var started := Time.get_ticks_usec()
	var next_shot := started
	var shown := 0
	while Time.get_ticks_usec() - started < 1500000 and view.native_presentation_pending():
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		if now >= next_shot:
			root.get_texture().get_image().save_png(OUT.path_join("discard-%02d.png" % shown))
			shown += 1
			next_shot += 100000
		if is_instance_valid(tile) and tile.flight_progress >= 0.0 and tile.flight_progress < 0.999:
			t.expect(impacts.is_empty(), "impact is silent in flight")
	t.expect(impacts.size() == 1 and tile.get_parent() == view._discard_layer,
		"only one impact during landing and river slide, with the tile in its river")
	t.expect(not view.native_presentation_pending(), "finished discard releases the animation lock")
	_new_prompt()
	var next_tile: TileView = view.hand_boxes[1].get_child(0)
	var at := _point(next_tile)
	_touch(at, true)
	_touch(at, false)
	t.expect(submissions.size() == 2, "next legal turn accepts an ordinary tap")
	if submissions.size() == 2:
		round_state.submit_turn(1, submissions[1])
		table._table_animation_controller.cancel()
		await create_timer(0.35).timeout
		t.expect(impacts.size() == 1 and not view.native_presentation_pending(), "cancelling a flight has no late impact or stuck tile")
