extends SceneTree
## Regression for exact duplicate-tile discard selection and presentation origins.
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var table

func _initialize() -> void:
	call_deferred("_run")

func _new_game() -> RoundState:
	var game := RoundState.new()
	game.build_players(0)
	game.controllers = [null, null, null, null]
	game.wall = WallRing.new(TileSetFactory.create_deck())
	game.wall.set_head(0)
	game.current_turn = 0
	game.phase = RoundState.Phase.PLAYING
	game.awaiting = true
	return game

func _run() -> void:
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	table._table_animation_controller.cancel()
	table.round = _new_game()
	table.round.require_turn.connect(table._on_require_turn)
	table.round.require_response.connect(table._on_require_response)
	table.round.state_update.connect(table._refresh)
	var hand := ["wan3", "wan1", "wan3", "wan2", "tiao1", "tiao2", "tiao3", "tong1", "tong2", "tong3", "wan7", "wan8", "wan9", "wan3"]
	for seat in 4:
		var player: PlayerState = table.round.players[seat]
		player.concealed = hand.duplicate()
		player.just_drew = "wan3"
	table._refresh()
	await process_frame
	var local_indices: Array = []
	for tile in table.hand_box[0].get_children():
		if tile.tile == "wan3": local_indices.append(int(tile.get_meta("concealed_index", -1)))
	local_indices.sort()
	t.expect(local_indices == [0, 2], "Sorted duplicate tiles keep distinct original hand indices; the drawn copy is separate")
	var local_draw: TileView = table.draw_box[0].get_child(0)
	t.expect(int(local_draw.get_meta("concealed_index", -1)) == 13, "The separate draw slot keeps its original concealed index")
	var hidden_indices: Array = []
	for tile in table.hand_box[1].get_children():
		if int(tile.get_meta("concealed_index", -1)) >= 0: hidden_indices.append(int(tile.get_meta("concealed_index", -1)))
	t.expect(hidden_indices.size() == table.hand_box[1].get_child_count(), "Hidden opponent tiles retain index-only metadata for their discard animation")
	var origin_tile: TileView
	for tile in table.hand_box[1].get_children():
		if int(tile.get_meta("concealed_index", -1)) == 0: origin_tile = tile
	t.expect(origin_tile != null and not origin_tile.face_up, "Opponent tile identity metadata does not reveal its face")
	if origin_tile != null:
		var expected_origin: Vector2 = table._table_animation_controller._position(origin_tile)
		var exact_origin: Vector2 = table._table_animation_controller._discard_origin(1, "wan3", 0)
		t.expect(exact_origin.is_equal_approx(expected_origin), "Opponent discard animation starts from the exact duplicate tile even when hidden")
	var submitted: Array = []
	table.enable_net(func(decision): submitted.append(decision), Callable())
	table._on_require_turn(0)
	table._refresh()
	var selected: TileView
	for tile in table.hand_box[0].get_children():
		if int(tile.get_meta("concealed_index", -1)) == 2: selected = tile
	t.expect(selected != null, "The second visible duplicate can be selected independently")
	if selected != null:
		table._submit_discard(selected.tile, int(selected.get_meta("concealed_index", -1)))
	t.expect(submitted.size() == 1 and int(submitted[0].get("discard_index", -1)) == 2, "The clicked duplicate index is sent to the authority unchanged")

	var source: PlayerState = table.round.players[0]
	source.discards = ["wan3", "wan3"]
	source.discard_ids = [10, 11]
	source.discard_count = 12
	source.discard_history = ["wan3", "wan3"]
	table._refresh()
	await process_frame
	var old_id_origin: Vector2 = table._table_animation_controller._discard_visual_origin(0, "wan3", 10)
	var new_id_origin: Vector2 = table._table_animation_controller._discard_visual_origin(0, "wan3", 11)
	t.expect(not old_id_origin.is_equal_approx(new_id_origin), "Repeated river tiles resolve to different positions by stable discard ID")
	table.round.last_discard = {"seat": 0, "tile": "wan3"}
	table.round._response_stage = RoundState.ResponseStage.MELD
	table.round.players[1].concealed = ["wan3", "wan3"]
	table.round._process_response(1, 0, "wan3", {"action": "pong"})
	var meld_event: Dictionary = {}
	for event in table.round.visual_events:
		if event.get("type", "") == "meld": meld_event = event
	t.expect(int(meld_event.get("source_discard_id", -1)) == 11, "Pong animation references the exact latest matching discard removed from the river")
	table.queue_free()
	await process_frame
	quit(t.finish("discard_identity"))
