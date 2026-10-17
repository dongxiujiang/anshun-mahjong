extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var submissions: Array = []
class CountingActor extends RefCounted:
	var calls := 0
	func decide_turn(game: RoundState, seat: int) -> Dictionary:
		calls += 1
		return {"discard": game.players[seat].just_drew}

func _initialize() -> void: call_deferred("_run")

func _click(table, tile: TileView, drag: bool = false, touch: bool = false) -> void:
	var down: InputEvent = InputEventScreenTouch.new() if touch else InputEventMouseButton.new()
	down.pressed = true
	down.position = Vector2(20, 20)
	if not touch: down.button_index = MOUSE_BUTTON_LEFT
	table._on_human_tile_gui(down, tile)
	if drag:
		var motion := InputEventMouseMotion.new()
		motion.position = Vector2(80, 20)
		table._on_human_tile_gui(motion, tile)
	down.pressed = false
	table._on_human_tile_gui(down, tile)

func _run() -> void:
	var game := RoundState.new()
	game.controllers = [null, null, null, null]
	game.opening_delay_seconds = 0.12
	game.start_round(0, 6)
	t.expect(game.phase == RoundState.Phase.DEALING and not game.awaiting and game.wall.remaining == 56, "Opening generates exactly 52 dealt tiles but no first draw/prompt")
	t.expect(game.allowed_actions(0).is_empty() and not game.submit_turn(0, {"discard": game.players[0].concealed[0]}), "Authority rejects early discard while dealing")
	var client := RoundState.new()
	client.apply_sync(game.serialize_for_seat(0))
	t.expect(client.phase == RoundState.Phase.DEALING and client.allowed_actions(0).is_empty(), "Network dealing snapshot cannot enable client actions")
	await create_timer(0.16).timeout
	t.expect(game.phase == RoundState.Phase.PLAYING and game.awaiting and game.wall.remaining == 55 and game.players[0].concealed.size() == 14, "Authority unlocks and draws the dealer's 14th tile once")
	var actor := CountingActor.new()
	game = RoundState.new()
	game.controllers = [actor, null, null, null]
	game.opening_delay_seconds = 0.12
	game.start_round(0, 1)
	t.expect(actor.calls == 0, "AI cannot decide before opening deadline")
	await create_timer(0.16).timeout
	t.expect(actor.calls == 1 and game.players[0].discard_count == 1, "AI acts only after dealing")
	game = RoundState.new()
	game.opening_delay_seconds = 0.12
	game.start_round(0, 1)
	await create_timer(0.06).timeout
	game.start_round(0, 2)
	await create_timer(0.08).timeout
	t.expect(game.phase == RoundState.Phase.DEALING and game.wall.remaining == 56, "Old opening timer cannot advance a replacement round")
	game.cancel_opening()
	await create_timer(0.12).timeout
	t.expect(game.phase == RoundState.Phase.IDLE and game.wall.remaining == 56, "Leaving cancels pending first draw")
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	table.round.controllers = [null, null, null, null]
	table._table_animation_controller.cancel()
	table.enable_net(func(decision): submissions.append(decision), Callable())
	var tile: TileView = table.draw_box[0].get_child(0)
	table._on_require_turn(0)
	table._update_interactivity()
	for button in table.action_bar.get_children(): t.expect(button.text != "出牌", "No explicit discard button")
	_click(table, tile, true)
	t.expect(submissions.is_empty(), "Dragging never discards")
	var controller = table._table_animation_controller
	controller.cancel()
	controller._opening = true
	_click(table, tile)
	table._commit_turn({"discard": tile.tile})
	t.expect(submissions.is_empty(), "Opening locks both tapping and direct action submission")
	table.round.phase = RoundState.Phase.PLAYING
	controller._opening = false
	controller._animation_busy = true
	controller._event = {"type": "draw", "seat": 0}
	_click(table, tile)
	t.expect(submissions.is_empty(), "A tile in its draw animation cannot be discarded")
	controller.cancel()
	table._update_interactivity()
	var held := InputEventScreenTouch.new()
	held.pressed = true
	held.position = Vector2(20,20)
	table._on_human_tile_gui(held, tile)
	controller._opening = true
	table._update_interactivity()
	held.pressed = false
	table._on_human_tile_gui(held, tile)
	controller.cancel()
	table._update_interactivity()
	t.expect(table._table_actions._touch_index == -1 and submissions.is_empty(), "An interrupted touch resets its pointer and cannot trap future taps")
	_click(table, tile, false, true)
	_click(table, tile)
	t.expect(submissions.size() == 1 and submissions[0].discard == tile.tile, "Native touch discards once; simulated mouse cannot double-submit")
	var settings: Rect2 = table._settings_button.get_rect()
	t.expect(Rect2(Vector2.ZERO, table._design_size()).encloses(settings) and settings.end.y <= table._table_bounds().position.y, "Compact settings stays in the header and outside the tile area")
	t.expect(table._settings_button.size == table.UI.SETTINGS_BUTTON_SIZE, "Settings size is independent of action-button size")
	var hot: Rect2 = table._settings_button.touch_rect()
	t.expect(hot.size.y >= 108 and Rect2(Vector2.ZERO, table._design_size()).encloses(Rect2(settings.position + hot.position, hot.size)), "Invisible settings touch target is large and remains inside the canvas")
	table.queue_free()
	await process_frame
	quit(t.finish("table_interaction"))
