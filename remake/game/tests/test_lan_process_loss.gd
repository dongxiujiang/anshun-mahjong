extends SceneTree
## Start a separate LAN host process, kill it after a visible round action, then
## verify that the surviving peer resumes the same hand with the same ticket.
const Client = preload("res://src/network/GameClient.gd")
var network
var failures := 0
var checks := 0
var host_pid := -1
var rendezvous := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(label)

func until(condition: Callable, timeout_ms: int = 20000) -> bool:
	var end := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < end:
		if condition.call(): return true
		await process_frame
	return false

func _run() -> void:
	network = Client.new()
	network.view_changed.connect(func(state):
		if state.has("presentation"):network.finish_presentation.call_deferred(state.presentation))
	network.name = "Client"
	root.add_child(network)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		await _host(args[0])
		return
	rendezvous = OS.get_temp_dir().path_join("mahjong-test-" + Crypto.new().generate_random_bytes(12).hex_encode())
	var project := ProjectSettings.globalize_path("res://")
	host_pid = OS.create_process(OS.get_executable_path(), ["--headless", "--path", project,
		"--script", "res://tests/test_lan_process_loss.gd", "--", rendezvous])
	check(host_pid > 0 and await until(func(): return FileAccess.file_exists(rendezvous)), "independent authority opened its port")
	if failures:
		await finish()
		return
	var port := FileAccess.get_file_as_string(rendezvous).to_int()
	var profile := {"player_id": "backup", "nickname": "南家", "mode": "lan", "room_number": "876543"}
	check(network.connect_room("127.0.0.1", port, profile), "successor connects through ENet")
	check(await until(func(): return not network.view.is_empty() and not network._standby_state.is_empty()), "successor authenticated and replicated")
	if failures:
		await finish()
		return
	network.set_ready(true)
	check(await until(func(): return not network.view.get("round", {}).get("last_discard", {}).is_empty()), "dealer discard became visible on the surviving peer")
	if failures:
		await finish()
		return
	var ticket: Dictionary = network.ticket.duplicate(true)
	var discard: Dictionary = network.view.round.last_discard.duplicate(true)
	var prompt: int = network.view.round.prompt_id
	var wall: int = network.view.round.wall_remaining
	var hand: Array = network.view.round.players[network.view.seat].hand.duplicate(true)
	check(OS.kill(host_pid) == OK, "host process killed")
	host_pid = -1
	check(await until(func(): return promoted_service() != null and network.view.get("room", {}).get("room_instance_id") == ticket.room_instance_id), "successor recovered the same room after OS process loss")
	check(network.ticket.get("member_token") == ticket.member_token and network.ticket.get("seat") == ticket.seat, "ticket and seat survived")
	if not network.view.is_empty():
		check(network.view.round.last_discard == discard and network.view.round.prompt_id >= prompt and network.view.round.wall_remaining <= wall and hand.all(func(tile): return tile in network.view.round.players[ticket.seat].hand), "acknowledged prompt, wall and concealed hand survived")
	await finish()

func promoted_service():
	for child in root.get_children():
		if str(child.name).begins_with("PromotedRoom_"): return child
	return null

func _host(path: String) -> void:
	if not network.host_lan({"player_id": "original", "nickname": "房主", "mode": "lan"}, "876543", 0,
			{"discard_ms": 60000, "response_ms": 60000, "ai_delay_ms": 60000, "presentation_ms": {"dealt": 5, "turn": 5, "ready_draw": 60000, "response": 60000}}):
		quit(1)
		return
	if not await until(func(): return not network.view.is_empty()):
		quit(1)
		return
	network.set_ready(true)
	network.start_first_round()
	var marker := FileAccess.open(path, FileAccess.WRITE)
	marker.store_string(str(network.local_port))
	marker.close()
	if not await until(func(): return not network.view.get("round", {}).get("choices", {}).get("discard_ids", []).is_empty()):
		quit(1)
		return
	network.submit(network.view.round.prompt_id, "discard", network.view.round.choices.discard_ids[0])
	await create_timer(70.0).timeout
	quit(1)

func finish() -> void:
	if host_pid > 0 and OS.is_process_running(host_pid): OS.kill(host_pid)
	if FileAccess.file_exists(rendezvous): DirAccess.remove_absolute(rendezvous)
	network.leave()
	var service = promoted_service()
	if service != null: service.queue_free()
	await process_frame
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
