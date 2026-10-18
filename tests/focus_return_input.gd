extends SceneTree
## Fixed-state input regression: a lost mouse-emulated touch release must not
## consume the next click after Alt-Tab. UI recovery never changes the round.
const H := preload("res://tests/test_harness.gd")
const HAND := ["wan3", "wan1", "wan3", "wan2", "tiao1", "tiao2", "tiao3", "tong1", "tong2", "tong3", "wan7", "wan8", "wan9", "wan3"]
var t := H.new()
var table
var submissions: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _fixture() -> void:
	if table.round != null:
		table.round.cancel_opening()
		table.round.controllers = [null, null, null, null]
	var round := RoundState.new()
	round.set_rng_seed(20261018)
	round.build_players(0)
	round.controllers = [null, null, null, null]
	round.phase = RoundState.Phase.PLAYING
	round.current_turn = 0
	round.awaiting = true
	round.wall = WallRing.new(TileSetFactory.create_deck())
	round.wall.set_head(0)
	for player in round.players: player.concealed = HAND.slice(0, 13)
	round.players[0].concealed = HAND.duplicate()
	round.players[0].just_drew = "wan3"
	table.round = round
	table.human_seat = 0
	table._connect_audio_round()
	table._refresh()
	table._on_require_turn(0)
	table._update_interactivity()
	submissions.clear()
	table.enable_net(func(decision): submissions.append(decision), Callable())

func _tile(index: int) -> TileView:
	for box in [table.hand_box[0], table.draw_box[0]]:
		for tile in box.get_children():
			if int(tile.get_meta("concealed_index", -1)) == index: return tile
	return null

func _touch(tile: TileView, pressed: bool, index: int = 0, canceled: bool = false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = tile.size / 2.0
	event.pressed = pressed
	event.canceled = canceled
	table._on_human_tile_gui(event, tile)

func _mouse(tile: TileView, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = tile.size / 2.0
	event.pressed = pressed
	table._on_human_tile_gui(event, tile)

func _click(tile: TileView) -> void:
	# Desktop project enables emulate_touch_from_mouse. Both streams must still
	# yield one request, and a stale touch must not block the new down event.
	_touch(tile, true)
	_mouse(tile, true)
	_touch(tile, false)
	_mouse(tile, false)

func _snapshot() -> PackedByteArray:
	return var_to_bytes(table.round.serialize())

func _check_single(index: int, context: String) -> void:
	t.expect(submissions.size() == 1, context + ": first complete click submits once")
	if submissions.size() != 1: return
	t.expect(int(submissions[0].discard_index) == index and submissions[0].discard == HAND[index], context + ": exact newly clicked tile entity is retained")
	var scores: float = 0
	for player in table.round.players: scores += player.score
	t.expect(scores == 800.0, context + ": input cannot change cumulative scores")

func _test_focus() -> void:
	for pair in [[Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_APPLICATION_FOCUS_IN],
		[Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_RESUMED]]:
		for native_touch in [true, false]:
			_fixture()
			var before := _snapshot()
			var old := _tile(0)
			var target := _tile(2)
			if native_touch: _touch(old, true)
			else: _mouse(old, true)
			table.notification(pair[0])
			t.expect(table._table_actions._pressed_tile == null and table._table_actions._touch_index == -1, "focus loss clears a missing pointer release")
			# A release delivered later by the OS is cancellation, not a discard.
			if native_touch: _touch(old, false)
			else: _mouse(old, false)
			t.expect(submissions.is_empty(), "late release after focus loss cannot discard the old tile")
			table.notification(pair[1])
			_click(target)
			_check_single(2, "focus return")
			t.expect(_snapshot() == before, "focus changes and UI submissions do not mutate the snapshot")
	# Reproduce the exact lost-release failure without delivering an old up:
	# next click lands on a different tile and must not merely clear touch_index.
	_fixture()
	_touch(_tile(0), true)
	table.get_window().focus_exited.emit()
	table.get_window().focus_entered.emit()
	_click(_tile(13))
	_check_single(13, "window focus with lost emulated release")
	_fixture()
	_touch(_tile(0), true)
	# Some devices report only the resume/focus-in notification.
	table.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_click(_tile(2))
	_check_single(2, "focus-in alone clears stale press")

func _test_cancellation() -> void:
	_fixture()
	_touch(_tile(0), true)
	_touch(_tile(0), false, 0, true)
	t.expect(submissions.is_empty(), "OS-canceled touch is never a discard")
	_click(_tile(2))
	_check_single(2, "click after canceled touch")
	_fixture()
	_touch(_tile(2), true, 0)
	_touch(_tile(0), false, 1, true)
	_touch(_tile(2), false, 0)
	_check_single(2, "unrelated canceled finger does not steal primary tap")

func _test_locks_and_ready() -> void:
	_fixture()
	table._toggle_ready()
	var ready_mode: bool = table._declaring_ready
	var ready_discards: Array = table._ready_discards.duplicate()
	table.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	table.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	t.expect(table._declaring_ready == ready_mode and table._ready_discards == ready_discards, "focus recovery preserves chosen ready mode")
	for phase in [RoundState.Phase.DEALING, RoundState.Phase.SETTLED]:
		_fixture()
		table.round.phase = phase
		table.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		table.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		_click(_tile(2))
		t.expect(submissions.is_empty(), "focus recovery cannot bypass dealing or settled locks")
	_fixture()
	table._table_animation_controller._animation_busy = true
	table.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	table.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	_click(_tile(2))
	t.expect(submissions.is_empty() and table._table_animation_controller.input_locked(), "focus recovery preserves live animation lock")
	table._table_animation_controller.cancel()
	table._update_interactivity()
	_click(_tile(2))
	_check_single(2, "first click after animation unlock")

func _routed_pointer(tile: TileView, pressed: bool, touch: bool) -> void:
	var point := tile.get_global_transform_with_canvas() * (tile.size / 2.0)
	if touch:
		var event := InputEventScreenTouch.new()
		event.pressed = pressed
		event.position = point
		event.index = 0
		root.push_input(event, true)
	else:
		var event := InputEventMouseButton.new()
		event.pressed = pressed
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		root.push_input(event, true)

func _test_viewport_routing() -> void:
	# Traverse actual viewport hit testing and TileView.gui_input connections;
	# synthetic GUI calls alone cannot catch a stale focus/capture owner.
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = dimensions
		for touch in [false, true]:
			_fixture()
			await process_frame
			await process_frame
			var old := _tile(0)
			var target := _tile(2)
			var before := _snapshot()
			_routed_pointer(old, true, touch)
			t.expect(table._table_actions._pressed_tile == old, "viewport dispatch reaches the first tile before focus loss")
			table.get_window().focus_exited.emit()
			table.get_window().focus_entered.emit()
			# Normal WM focus cleanup releases the old viewport capture. Its late
			# up may still reach the old GUI node but must not submit that tile.
			_routed_pointer(old, false, touch)
			t.expect(submissions.is_empty(), "viewport late release cannot discard old tile")
			_routed_pointer(target, true, touch)
			_routed_pointer(target, false, touch)
			_check_single(2, "routed mouse/touch at " + str(dimensions))
			t.expect(_snapshot() == before, "routed click and focus recovery do not modify authority state")
	# Once a real callback is installed, one returning click removes exactly
	# the selected duplicate from the hand and adds exactly one river tile.
	_fixture()
	await process_frame
	table.enable_net(Callable(), Callable())
	table.round.state_update.connect(table._refresh)
	_routed_pointer(_tile(0), true, false)
	table.get_window().focus_exited.emit()
	table.get_window().focus_entered.emit()
	_routed_pointer(_tile(0), false, false)
	var target := _tile(2)
	_routed_pointer(target, true, false)
	_routed_pointer(target, false, false)
	t.expect(table.round.players[0].discards == ["wan3"], "first routed click after focus return really discards once")
	var expected := HAND.duplicate()
	expected.remove_at(2)
	t.expect(table.round.players[0].concealed == expected, "real submission removes the selected original index only")
	var total := 0.0
	for player in table.round.players: total += player.score
	t.expect(total == 800.0, "real resumed discard preserves score sum")

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	_test_focus()
	_test_cancellation()
	_test_locks_and_ready()
	await _test_viewport_routing()
	table.queue_free()
	await process_frame
	# 最后一笔真实出牌刚触发音效；让音频线程释放播放对象后再关闭引擎。
	await create_timer(0.1).timeout
	quit(t.finish("focus_return_input"))
