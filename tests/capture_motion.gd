extends SceneTree
## Real renderer motion review. Run without --headless; saves frames and timings.
const H := preload("res://tests/test_harness.gd")
var t := H.new()
var table
var event_id := 900
var timings: Array = []
var directory := "res://build/ui_review/motion"

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
	controller._on_visual_event(data)
	await process_frame
	await process_frame
	for frame in 5:
		await _shot(label + "_%02d" % frame)
		await create_timer(0.06).timeout
	while controller._animation_busy:
		await process_frame
	timings.append({"effect": label, "duration_ms": Time.get_ticks_msec() - started})
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
	table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
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
	await _play("04_pong", {"type": "meld", "seat": 0, "source": 1, "tile": "tiao1", "kind": "pung", "index": 0})
	await _play("05_kong", {"type": "meld", "seat": 0, "source": 1, "tile": "tong8", "kind": "kong", "index": 1})
	await _play("06_concealed", {"type": "meld", "seat": 0, "tile": "", "kind": "concealed", "index": 1})
	await _play("07_reveal", {"type": "meld_reveal", "seat": 0, "tile": "tong8", "index": 1})
	await _play("08_win", {"type": "win", "seat": 0, "tile": "tong5", "self_draw": true})
	# Fast/slow settings really change Tween duration, independent of AI clocks.
	for speed in ["fast", "slow"]:
		root.get_node("GameConfig").animation_speed = speed
		var layer = table._animation_layer
		# Capturing a GPU frame can stall the window; measure fresh frames after it.
		await process_frame
		await create_timer(0.05).timeout
		await process_frame
		var started := Time.get_ticks_msec()
		layer.play({"type": "draw", "tile": "wan1", "from": Vector2(100,100), "to": Vector2(600,400)})
		await layer.finished
		timings.append({"effect": speed, "duration_ms": Time.get_ticks_msec() - started})
	t.expect(timings[-2].duration_ms >= 100, "Fast animation still has a visible transition")
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
