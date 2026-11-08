extends SceneTree
## Explicit integration test against a local dedicated room directory.
const H = preload("res://tests/test_harness.gd")
var t = H.new()
var table
var room := {}
var error_text := ""
var first_action := false
var premature := false
var started := 0
var baseline := false

func _initialize(): call_deferred("_run")

func _arg(key: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(key + "="): return arg.substr(key.length() + 1)
	return ""

func _wait(predicate: Callable, seconds := 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return bool(predicate.call())

func _event(event: Dictionary):
	if event.type == "dice":
		started = Time.get_ticks_msec()
	if event.type in ["draw", "discard"] and not first_action:
		first_action = true
		var controller = table._table_animation_controller
		premature = controller.deal_sequence_active() or controller.sorting_active() or table._new_areas._sort_animating
		print("[opening-clock] first action at %dms, opening busy=%s, scale=%.6f" % [Time.get_ticks_msec() - started, premature, controller.opening_deal_scale()])
		call_deferred("_capture")

func _capture():
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/opening-clock"))
	root.get_texture().get_image().save_png("res://build/opening-clock/" + ("before" if baseline else "after") + ".png")

func _run():
	var url := _arg("--directory")
	if not url.begins_with("http://127.0.0.1:"): quit(2); return
	baseline = OS.get_cmdline_user_args().has("--baseline")
	Engine.max_fps = 12
	root.get_node("UpdateManager").auto_check = false
	root.get_node("GameConfig").set_tile_animation_seconds(1.0, false)
	var network = root.get_node("Network")
	network.persist_settings = false
	var directory := OnlineDirectory.new()
	directory.persist_settings = false
	root.add_child(directory)
	directory.base_url = url
	directory.room_created.connect(func(created): room = created)
	directory.directory_error.connect(func(message): error_text = message)
	var number := str(70000000 + Time.get_ticks_usec() % 9000000)
	directory.create_room(number, "开局时序验收", "1.00")
	t.expect(await _wait(func(): return not directory.busy), "test room creation finishes")
	t.expect(not room.is_empty() and error_text.is_empty(), "isolated room is created")
	if room.is_empty(): await H.quit_cleanly(self, t.finish("online_opening_clock")); return
	network.start_client(str(room.host), int(room.port), str(room.number), str(room.owner_token))
	var net = network.net_node
	t.expect(await _wait(func(): return not net.lobby.is_empty()), "room handshake completes")
	net.set_ai_speed("0.00")
	table = load("res://scenes/GameTable.tscn").instantiate()
	net.game.visual_event.connect(_event)
	root.add_child(table)
	net.set_ready(true)
	if await _wait(func():return net.game.phase == RoundState.Phase.DEALING):
		started = Time.get_ticks_msec()
	t.expect(await _wait(func(): return first_action, 55.0), "first draw arrives after the opening")
	t.expect(not premature, "server action never overtakes client dealing or sorting")
	t.expect(net._opening_ack_session == net.game.audio_session, "first authoritative action follows the client's rendered-opening confirmation")
	await create_timer(0.5).timeout
	table.queue_free()
	await network.leave_room()
	directory.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("online_opening_clock"))
