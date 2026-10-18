extends SceneTree
## Event generation, hidden-information boundary and visual lifetime regression.
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var table

func _initialize() -> void: call_deferred("_run")

func _round() -> RoundState:
	var game := RoundState.new()
	game.set_rng_seed(37)
	game.start_round(0, 1)
	game._presentation.events.clear()
	return game

func _event(game: RoundState, type: String) -> Dictionary:
	for event in game.visual_events:
		if event.type == type: return event
	return {}

func _run() -> void:
	var game := _round()
	game.players[0].concealed = ["tiao1", "wan2"]
	game._discard(0, "tiao1")
	t.expect(_event(game, "discard").get("tile", "") == "tiao1", "Discard emits the public tile after ownership is updated")
	t.expect(_event(game, "discard").get("charge", false), "Charge chicken keeps its presentation marker")
	game = _round()
	game.players[0].concealed = ["wan5", "wan5", "wan5", "wan5", "wan2"]
	game._do_concealed_kong(0, "wan5", game.players[0])
	var hidden := _event(game, "meld")
	t.expect(hidden.get("kind", "") == "concealed" and hidden.get("tile", "missing") == "", "Concealed-kong event never includes a secret tile name")
	t.expect(game.visual_events[0].type == "meld" and game.visual_events[1].type == "draw", "Kong moves before its replacement draw in the event stream")
	game.players[0].concealed.append("wan2")
	game._discard(0, "wan2")
	t.expect(_event(game, "meld_reveal").is_empty(), "Concealed kong stays face-down on the first discard")
	game.players[0].concealed.append("wan2")
	game._discard(0, "wan2")
	t.expect(_event(game, "meld_reveal").get("tile", "") == "wan5", "Concealed kong flips only on the next personal discard")
	game = _round()
	game.players[0].concealed = ["wan5", "wan2"]
	game.players[0].melds = [{"kind": "pung", "tile": "wan5", "from_seat": 1}]
	game._pending_kong = {"seat": 0, "tile": "wan5", "index": 0}
	game._complete_add_kong()
	t.expect(_event(game, "meld").get("kind", "") == "add_kong", "Only completed add-kongs emit the group animation")
	for action in ["pong", "kong"]:
		game = _round()
		game.players[0].discards = ["tong4"]
		game.players[0].discard_ids = [0]
		game.players[1].concealed = ["tong4", "tong4", "tong4", "wan1"]
		game._response_stage = RoundState.ResponseStage.MELD
		game._process_response(1, 0, "tong4", {"action": action})
		t.expect(_event(game, "meld").get("source", -1) == 0 and _event(game, "meld").get("source_discard_id", -1) == 0 and _event(game, "meld").get("kind", "") == ("pung" if action == "pong" else "kong"), "Pong/exposed-kong includes the source discard identity and completed group")
	game = _round()
	game._emit_visual_event("draw", {"seat": 1, "tile": "wan7"})
	game._emit_visual_event("discard", {"seat": 1, "tile": "tong3"})
	game._emit_visual_event("meld", {"seat": 1, "tile": "tong4", "kind": "pung"})
	var wire := game.serialize_for_seat(0)
	t.expect(wire.visual_events[0].tile == "hidden0", "Opponent draw is masked at the network boundary")
	t.expect(wire.visual_events[1].tile == "tong3" and wire.visual_events[2].tile == "tong4", "Public discard and meld tiles remain visible on clients")
	t.expect(game.visual_events[0].tile == "wan7", "Masking never mutates the authoritative events")
	var client := RoundState.new()
	var played: Array = []
	client.visual_event.connect(func(event): played.append(event.type))
	client.apply_sync(wire)
	t.expect(played.is_empty(), "Initial/resume snapshot sets a baseline without replaying old actions")
	game._emit_visual_event("discard", {"seat": 2, "tile": "wan3"})
	client.apply_sync(game.serialize_for_seat(0))
	client.apply_sync(game.serialize_for_seat(0))
	t.expect(played == ["discard"], "Repeated snapshots play new events once")
	client._presentation.sync_initialized = false
	game._emit_visual_event("discard", {"seat": 2, "tile": "wan4"})
	client.apply_sync(game.serialize_for_seat(0))
	t.expect(played == ["discard"], "Reconnect baseline skips actions performed during the interruption")
	game = _round()
	game._do_self_win(0)
	t.expect(_event(game, "win").get("self_draw", false) and game.phase == RoundState.Phase.SETTLED, "Winning animation is emitted after the settlement has completed")
	var wins := game.visual_event_id
	game._finish()
	t.expect(game.visual_event_id == wins, "Repeated settlement never repeats the winning animation")
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	table.round.controllers = [null, null, null, null]
	var controller = table._table_animation_controller
	controller.reset()
	var original := var_to_bytes(table.round.serialize())
	var order: Array = []
	table._animation_layer.finished.connect(func(_id): order.append(controller._event.get("seat", -1)))
	controller._on_visual_event({"id": 800, "type": "deal_batch", "deals": [{"seat": 0, "cards": ["wan1"]}, {"seat": 1, "cards": ["wan2"]}, {"seat": 2, "cards": ["wan3"]}, {"seat": 3, "cards": ["wan4"]}]})
	await create_timer(0.1).timeout
	t.expect(order == [0,1,2,3], "Deal batches retain clockwise order")
	t.expect(not controller._animation_busy and controller._animation_queue.is_empty(), "Headless presentation drains without waiting for Tween")
	t.expect(var_to_bytes(table.round.serialize()) == original, "Animation playback cannot change scores, wall or turn state")
	controller.cancel()
	var first_tile: TileView = table.hand_box[table.human_seat].get_child(0)
	first_tile.set_interactive(true)
	t.expect(first_tile._has_point(Vector2(20,-10)), "Tile touch zone extends vertically")
	t.expect(not first_tile._has_point(Vector2(first_tile.size.x+3,20)), "Adjacent tile faces cannot steal each other's taps")
	var local = table.draw_box[table.human_seat].get_child(0)
	t.expect(controller._animation_target_for_seat(table.human_seat).is_equal_approx(controller._position(local)), "Draw target uses the actual rendered slot")
	controller._on_visual_event({"id": 1, "session": "new_round", "type": "draw", "seat": 0, "tile": "wan2"})
	t.expect(controller._animation_last_id == 1, "New session permits event IDs to restart")
	controller.cancel()
	table.queue_free()
	await process_frame
	# UI bounds and non-overlap are independent of the selected volume/AI speed.
	var settings = load("res://scripts/ui/SoundSettings.gd").new()
	settings.table_mode = true
	root.add_child(settings)
	await process_frame
	for speed in settings.speed_buttons.values():
		for animation in (settings.draw_speed_buttons.values() + settings.discard_speed_buttons.values()):
			t.expect(not speed.get_rect().intersects(animation.get_rect()), "AI and animation speed buttons cannot overlap")
	settings.queue_free()
	var guide = load("res://scripts/ui/RuleGuide.gd").new()
	root.add_child(guide)
	root.size = Vector2i(960,540)
	await process_frame
	guide.open()
	t.expect(Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(guide.panel.get_global_rect()), "Small-screen rule panel stays inside the viewport")
	guide.queue_free()
	await process_frame
	quit(t.finish("ui_presentation"))
