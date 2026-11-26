extends SceneTree

const Table = preload("res://src/presentation/TableView.gd")
const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Order = preload("res://src/presentation/HandOrder.gd")
const DiceRoll = preload("res://src/runtime/DiceRoll.gd")

var _table := Table.new()
var _round := Round.new()
var _order := Order.new()
var _checks := 0
var _failures := 0
var _blank_taps := 0
var _wall_taps := 0
var _finished_drags := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, note: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL blank table tap: ", note)

func _run() -> void:
	var board := SubViewportContainer.new()
	var world := SubViewport.new()
	board.stretch = true
	root.add_child(board)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.own_world_3d = true
	board.add_child(world)
	world.add_child(_table)
	var dice := DiceRoll.new()
	dice.authoritative = false
	world.add_child(dice)
	await process_frame
	_check(_round.start(1, 4, 2, Catalog.values(22411)) and _round.begin_dealer_turn(), "legal dealer turn")
	var snapshot := _round.snapshot_for(1)
	_order.sync_hand("blank-tap", 1, _round.prompt_id, snapshot.players[1].hand, snapshot.players[1].draw_id)
	_table.apply_view(snapshot, _order.view())
	_table.tile_clicked.connect(_tile_clicked)
	_table.blank_tapped.connect(func():
		_blank_taps += 1
		_order.clear_selection()
		_table.set_hand_order(_order.view()))
	_table.wall_center_requested.connect(func(_seat): _wall_taps += 1)
	_table.drag_started.connect(func(id: int):
		_order.begin_drag(id)
		_table.set_hand_order(_order.view()))
	_table.drag_finished.connect(func(slot: int):
		_finished_drags += 1
		_order.commit_drag(slot)
		_table.set_hand_order(_order.view()))

	var a: int = _order.view().slots[2]
	var b: int = _order.view().slots[9]
	var prompt := _round.prompt_id
	var blank := _table.camera.unproject_position(Vector3(2.2, 0, 1.9))
	var wall := _wall_point()
	_check(_table._blank_at(blank) and _table._pick(wall, true) >= 0, "fixture has empty felt and a visible wall")
	_check(_table.tile_at(_tile_point(a)) == a and _table.tile_at(_tile_point(b)) == b, "A and B are physical selectable tiles")
	_tap(_tile_point(a))
	_check(_selected() == a, "first tap raises A")
	_mouse(blank, true)
	_check(_selected() == a and _blank_taps == 0, "blank press waits for release")
	_mouse(blank, false)
	_check(_selected() == -1 and _blank_taps == 1 and _round.prompt_id == prompt, "blank click lowers A without issuing a game action")
	_tap(_tile_point(a))
	_check(_selected() == a and _round.prompt_id == prompt, "A after blank is a first tap")
	_tap(_tile_point(b))
	_check(_selected() == b and _round.prompt_id == prompt, "different tile changes selection")

	_tap(wall)
	_tap(wall, true)
	_check(_wall_taps == 1 and _blank_taps == 1 and _selected() == b, "wall double-click only moves the wall view")
	_tap(_table.camera.unproject_position(dice.dice[0].global_position))
	_check(_blank_taps == 1 and _selected() == b, "visible dice occupy the felt")
	var opponent := _opponent_point()
	_check(opponent != Vector2.ZERO, "fixture exposes an opaque opponent tile")
	_tap(opponent)
	_check(_blank_taps == 1 and _selected() == b, "opponent tile is occupied")
	_tap(Vector2(3, 3))
	_check(_blank_taps == 1 and _selected() == b, "outside the table is not felt")
	var rail := _table.camera.unproject_position(Vector3(8, 0.05, _table.table_edge() + 0.015))
	var beside_rail := rail - Vector2(0, 5)
	# Locate the visible felt boundary under the current camera and foreground layout.
	var previous := blank
	for i in range(1, 1001):
		var candidate := blank.lerp(rail, i / 1000.0)
		if not _table._blank_at(candidate) and _table._blank_at(previous) and _table.tile_at(previous) < 0:
			rail = candidate
			beside_rail = previous
			break
		previous = candidate
	_check(_table._blank_at(beside_rail), "fixture has felt beside the edge of the rail")
	_mouse(beside_rail, true)
	_mouse(rail, false)
	_check(_blank_taps == 1 and _selected() == b, "a release on the rail is occupied even within tap tolerance")

	var hud := Button.new()
	hud.position = blank - Vector2(24, 20)
	hud.size = Vector2(48, 40)
	root.add_child(hud)
	var hud_pressed := [false]
	hud.pressed.connect(func(): hud_pressed[0] = true)
	await process_frame
	_tap(blank)
	_check(hud_pressed[0] and _blank_taps == 1 and _selected() == b, "a GUI button over felt consumes the click")
	hud.free()
	_mouse(blank, true)
	_move(wall)
	_move(blank)
	_mouse(blank, false)
	_check(_blank_taps == 1 and _selected() == b, "moving away then returning does not cancel selection")
	_touch(blank, 3, true)
	_touch(blank, 4, true)
	_touch(blank, 4, false)
	_check(_blank_taps == 1 and _selected() == b, "second finger cannot end the captured tap")
	_touch(blank, 3, false, true)
	_check(_blank_taps == 1 and _selected() == b, "canceled first finger does not emit a tap")
	_touch(blank, 3, true)
	_touch(blank, 3, false)
	_check(_blank_taps == 2 and _selected() == -1, "matching touch release cancels the selection")

	_mouse(_tile_point(b), true)
	_check(_table._hold != null and _table._hold.is_running(), "physical hand press starts existing drag hold")
	if _table._hold:
		_table._hold.custom_step(Table.HOLD_SECONDS + 0.01)
	var drop := _outer_felt_point()
	_check(_table._dragging and drop != Vector2.ZERO, "long press begins real drag with an empty felt release point outside the discard area")
	_move(drop)
	_mouse(drop, false)
	_check(_finished_drags == 1 and _blank_taps == 2 and _round.prompt_id == prompt, "drag release over blank is neither a blank tap nor a discard")

	_tap(_tile_point(a))
	_check(_selected() == -1, "a canceled drag still returning to its slot blocks premature selection")
	var deadline := Time.get_ticks_msec() + 2000
	while not _table.can_play_hand() and Time.get_ticks_msec() < deadline:
		await process_frame
	_tap(_tile_point(a))
	_check(_selected() == a and _round.prompt_id == prompt, "first A tap after drag only selects")
	_tap(_tile_point(a))
	_check(not _round.players[1].hand.has(a) and _round.prompt_id > prompt, "second A tap still submits an authoritative discard")
	print("Blank table tap: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures else 0)

func _tile_clicked(id: int) -> void:
	var discard := _order.tap(id)
	if discard >= 0:
		_round.submit(1, _round.prompt_id, "discard", discard)
	else:
		_table.set_hand_order(_order.view())

func _selected() -> int:
	return int(_order.view().selected_id)

func _tile_point(id: int) -> Vector2:
	return _table.camera.unproject_position(_table.tiles[id].global_position)

func _wall_point() -> Vector2:
	for id in _table.view.wall_slots:
		var point := _tile_point(id)
		if _table._pick(point, true) >= 0 and _table.tile_at(point) < 0:
			return point
	return Vector2.ZERO

func _opponent_point() -> Vector2:
	for key in _table.tiles:
		var tile: Node3D = _table.tiles[key]
		if key is String and tile.get_meta("zone") == "hand":
			var point := _table.camera.unproject_position(tile.global_position)
			if _table.tile_at(point) < 0 and _table._pick(point, true) < 0:
				return point
	return Vector2.ZERO

func _outer_felt_point() -> Vector2:
	var edge := int(_table.table_edge())
	for x in range(-edge + 1, edge):
		var point := _table.camera.unproject_position(Vector3(x, 0, edge - 2))
		if _table._blank_at(point) and _table._slot_at(point) < 0:
			return point
	return Vector2.ZERO

func _tap(point: Vector2, double := false) -> void:
	_mouse(point, true, double)
	_mouse(point, false)

func _mouse(point: Vector2, pressed: bool, double := false) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = double
	root.push_input(event, true)

func _move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func _touch(point: Vector2, index: int, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)
