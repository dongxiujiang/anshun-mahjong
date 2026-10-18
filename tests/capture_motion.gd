extends SceneTree
## Real renderer motion review. Run without --headless; saves frames and timings.
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var table
var event_id := 900
var timings: Array = []
var directory := "res://build/ui_review/motion"
var hand_old_nodes: Array = []
var hand_old_discard: TileView = null
var hand_old_draw: TileView = null
var hand_finish_reused_nodes := false
var hand_finish_discard_removed := false
var hand_finish_draw_transferred := false
var hand_finish_count := 0

func _log_hand_finish(event: Dictionary) -> void:
	var source = event.get("draw_node")
	hand_finish_draw_transferred = is_instance_valid(source) and source == hand_old_draw and source.get_parent() == table.hand_box[0] and table.draw_box[0].get_child_count() == 0
	hand_finish_reused_nodes = true
	for node in hand_old_nodes:
		if node == hand_old_discard: continue
		hand_finish_reused_nodes = hand_finish_reused_nodes and is_instance_valid(node) and node.get_parent() == table.hand_box[0]
	hand_finish_discard_removed = not is_instance_valid(hand_old_discard) or hand_old_discard.get_parent() == null or hand_old_discard.is_queued_for_deletion()
	for node in table.hand_box[0].get_children():
		if node is TileView: hand_finish_count += 1

func _initialize() -> void: call_deferred("_run")

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name + ".png"))

func _play(label: String, data: Dictionary) -> void:
	var controller = table._table_animation_controller
	controller.cancel()
	event_id += 1
	data["id"] = event_id
	var baseline := var_to_bytes(table.round.serialize())
	var started := Time.get_ticks_msec()
	var draw_tile: TileView = null
	if data.get("type", "") == "draw":
		var draw_seat := int(data.get("seat", 0))
		if draw_seat >= 0 and draw_seat < table.draw_box.size() and not table.draw_box[draw_seat].get_children().is_empty():
			draw_tile = table.draw_box[draw_seat].get_child(0)
	controller._on_visual_event(data)
	if draw_tile != null:
		# A real table shows the newly drawn tile in the draw slot immediately.
		# The animation then moves that visible tile into the hand; it must not
		# create a blank draw position before the movement starts.
		controller.refresh_masks()
		t.expect(is_zero_approx(draw_tile.modulate.a), "Persistent draw is hidden before flight starts: " + label)
	await process_frame
	await process_frame
	for frame in 5:
		await _shot(label + "_%02d" % frame)
		await create_timer(0.06).timeout
	while controller.has_pending():
		await process_frame
	timings.append({"effect": label, "duration_ms": Time.get_ticks_msec() - started})
	if draw_tile != null:
		t.expect(is_equal_approx(draw_tile.modulate.a, 1.0), "Drawn tile appears only after the draw animation finishes: " + label)
	t.expect(table._animation_layer._temporary.is_empty(), "Temporary nodes are removed after " + label)
	t.expect(var_to_bytes(table.round.serialize()) == baseline, "Presentation never advances gameplay: " + label)
	for node in controller._masked: t.expect(not is_instance_valid(node) or node.modulate.a == 1.0, "Masks restored after " + label)
	await _shot(label + "_final")

func _run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720)
	root.get_node("UpdateManager").auto_check = false
	var network = root.get_node("Network")
	var fixed_round := RoundState.new()
	fixed_round.set_rng_seed(20261018)
	fixed_round.controllers = [null,null,null,null]
	network.mode = "host"
	network.net_node.game = fixed_round
	network.net_node.my_seat = 0
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	network.mode = ""
	fixed_round.opening_delay_seconds = root.get_node("GameConfig").OPENING_WAIT_SECONDS
	fixed_round.start_round(0,3)
	await process_frame
	var controller = table._table_animation_controller
	table.round.controllers = [null,null,null,null]
	while table.round.phase == RoundState.Phase.DEALING or table._table_animation_controller.input_locked():
		await process_frame
	table._table_animation_controller.cancel()
	for seat in 4:
		table.round.players[seat].just_drew = "tong5"
		table.round.players[seat].concealed = ["wan1", "wan2", "wan3", "tong2", "tong3", "tong4", "tong5"]
		table.round.players[seat].discards = ["wan5", "tong6", "tong7"]
		table.round.players[seat].melds = [{"kind": "pung", "tile": "tiao1", "from_seat": posmod(seat+1,4)}, {"kind": "kong", "tile": "tong8", "from_seat": posmod(seat+1,4)}]
	table._refresh()
	await process_frame
	await _play("01_dice", {"type": "dice", "value": 5})
	await _play("02_deal", {"type": "deal", "seat": 0, "cards": ["wan1", "wan2", "wan3", "tong2"]})
	for seat in 4:
		await _play("02_draw_seat%d" % seat, {"type": "draw", "seat": seat, "tile": "tong5"})
		await _play("03_discard_seat%d" % seat, {"type": "discard", "seat": seat, "tile": "tong7"})
	# Exercise the authoritative hand-discard path.  It must publish the old
	# draw origin and a sorted insertion slot before the next seat starts moving.
	var motion_player: PlayerState = table.round.players[0]
	motion_player.concealed = ["wan1", "wan2", "wan3", "tong2", "tong3", "tong4", "tong5"]
	motion_player.just_drew = "tong5"
	table.round.current_turn = 0
	table.round.phase = RoundState.Phase.PLAYING
	table.round.awaiting = true
	table._refresh()
	await process_frame
	hand_old_nodes.clear()
	for node in table.hand_box[0].get_children():
		if node is TileView:
			hand_old_nodes.append(node)
	hand_old_discard = null
	for tile in table.hand_box[0].get_children():
		if int(tile.get_meta("concealed_index", -1)) == 3:
			hand_old_discard = tile
	hand_old_draw = table.draw_box[0].get_child(0) if not table.draw_box[0].get_children().is_empty() else null
	table.round._discard(0, "tong2", 3)
	t.expect(is_instance_valid(hand_old_discard) and hand_old_discard.get_parent() == table.hand_box[0] and is_instance_valid(hand_old_draw) and hand_old_draw.get_parent() == table.draw_box[0], "Hand discard keeps the pre-discard hand and draw slot in place before animation")
	var hand_event: Dictionary = {}
	var saw_hand_discard := false
	var hand_motion_data := false
	var held_old_row := false
	var discard_destination_ready := false
	var saw_hidden_draw_source := false
	var hand_timed_out := false
	var hand_deadline := Time.get_ticks_msec() + 8000
	while controller.has_pending() and Time.get_ticks_msec() < hand_deadline:
		for task in controller._discard_tasks.values():
			if task.event.get("seat", -1) == 0: hand_event = task.event
		if not hand_event.is_empty() and controller.holds_seat_refresh(0):
			saw_hand_discard = true
			hand_motion_data = not hand_event.get("hand_moves", []).is_empty() and not hand_event.get("hand_insert", {}).is_empty()
			held_old_row = controller.holds_seat_refresh(0)
			discard_destination_ready = not hand_event.get("destinations", []).is_empty()
			var insert: Dictionary = hand_event.get("hand_insert", {})
			var draw_source = insert.get("source_node")
			if not insert.is_empty() and is_instance_valid(draw_source) and draw_source is TileView and not draw_source.visible:
				saw_hidden_draw_source = true
		await process_frame
	_log_hand_finish(hand_event)
	hand_timed_out = Time.get_ticks_msec() >= hand_deadline
	t.expect(saw_hand_discard and hand_motion_data and held_old_row and discard_destination_ready and not controller.holds_seat_refresh(0), "Hand discard starts at the clicked slot, holds the old row, and ends with a real discard target")
	t.expect(saw_hidden_draw_source, "Draw-slot tile is hidden while the drawn tile is inserted into the hand")
	t.expect(not hand_timed_out and not controller._animation_busy and controller._animation_queue.is_empty(), "Hand discard animation completes before its deadline")
	t.expect(hand_finish_reused_nodes and hand_finish_discard_removed, "Discard reuses the remaining hand nodes and removes only the played tile")
	t.expect(hand_finish_draw_transferred, "Draw-slot tile transfers into the hand after insertion")
	t.expect(hand_finish_count == motion_player.concealed.size(), "Hand contains exactly the authoritative post-discard tile count")
	await _play("04_pong", {"type": "meld", "seat": 0, "source": 1, "tile": "tiao1", "kind": "pung", "index": 0})
	await _play("05_kong", {"type": "meld", "seat": 0, "source": 1, "tile": "tong8", "kind": "kong", "index": 1})
	await _play("06_concealed", {"type": "meld", "seat": 0, "tile": "", "kind": "concealed", "index": 1})
	await _play("07_reveal", {"type": "meld_reveal", "seat": 0, "tile": "tong8", "index": 1})
	await _play("08_win", {"type": "win", "seat": 0, "tile": "tong5", "self_draw": true})
	# Fast/slow settings really change Tween duration, independent of AI clocks.
	for speed in ["instant", "standard"]:
		root.get_node("GameConfig").animation_speed = speed
		var layer = table._animation_layer
		# Capturing a GPU frame can stall the window; measure fresh frames after it.
		await process_frame
		await create_timer(0.05).timeout
		await process_frame
		var started := Time.get_ticks_msec()
		layer.play({"type": "draw", "tile": "wan1", "from": Vector2(100,100), "to": Vector2(600,400)})
		if layer._active != null: await layer.finished
		timings.append({"effect": speed, "duration_ms": Time.get_ticks_msec() - started})
	t.expect(timings[-2].duration_ms < 100, "Instant animation completes without a visible transition")
	t.expect(timings[-1].duration_ms > timings[-2].duration_ms, "Slow animation takes longer than fast")
	# Cancellation during a real Tween prevents stale callbacks and ghost tiles.
	var completed: Array = []
	table._animation_layer.play({"type": "draw", "tile": "wan1"}, func(): completed.append(true))
	await process_frame
	table._table_animation_controller.cancel()
	await create_timer(0.4).timeout
	t.expect(completed.is_empty() and table._animation_layer._temporary.is_empty(), "Interrupted animations leave no ghost nodes or stale callbacks")
	var file := FileAccess.open(directory.path_join("timings.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(timings, "\t"))
	file.close()
	table.queue_free()
	await create_timer(0.2).timeout
	quit(t.finish("capture_motion"))
