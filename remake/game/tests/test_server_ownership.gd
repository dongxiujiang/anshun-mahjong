extends SceneTree

const Client = preload("res://src/network/GameClient.gd")
const SCRIPT := "res://tests/test_server_ownership.gd"
const NUMBER := "731529"
var checks := 0
var failures := 0
var server_pid := -1
var creator_pid := -1
var work_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr(description)
	return ok

func wait_until(predicate: Callable, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
		OS.delay_msec(1)
	return false

func profile(id: String) -> Dictionary:
	return {"player_id": id, "nickname": "南家" if id == "creator" else "东家", "room_number": NUMBER,
		"mode": OS.get_environment("DONGXIU_ROOM_MODE") if OS.has_environment("DONGXIU_ROOM_MODE") else "online"}

func connect_client(id: String, port: int, saved: Dictionary = {}):
	var endpoint := Client.new()
	endpoint.view_changed.connect(func(state):
		if state.has("presentation"):endpoint.finish_presentation.call_deferred(state.presentation))
	root.add_child(endpoint)
	if not endpoint.connect_room("127.0.0.1", port, profile(id), saved):
		endpoint.queue_free()
		return null
	return endpoint

func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return result if result is Dictionary else {}

func child(script_path: String, args: PackedStringArray = []) -> int:
	var log_path := work_dir.path_join("room-server.log" if args.is_empty() else "creator.log")
	var command := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", log_path, "--script", script_path])
	if not args.is_empty():
		command.append("--")
		command.append_array(args)
	return OS.create_process(OS.get_executable_path(), command)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 3 and args[0] == "creator":
		await _creator(int(args[1]), args[2])
		return
	var base := args[0] if not args.is_empty() else ProjectSettings.globalize_path("user://server-ownership-tests")
	work_dir = base.path_join(str(OS.get_process_id()))
	if check(DirAccess.make_dir_recursive_absolute(work_dir) == OK, "create an isolated process status directory"):
		await _verify()
	for pid in [creator_pid, server_pid]:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	for filename in ["creator.json", "creator.json.tmp"]:
		var credential_path := work_dir.path_join(filename)
		if FileAccess.file_exists(credential_path):
			DirAccess.remove_absolute(credential_path)
	print("Server ownership: %d checks, %d failures (%s)" % [checks, failures, work_dir])
	quit(1 if failures else 0)

func _verify() -> void:
	var status_path := work_dir.path_join("server.json")
	var creator_path := work_dir.path_join("creator.json")
	OS.set_environment("DONGXIU_ROOM_STATUS", status_path)
	OS.set_environment("DONGXIU_ROOM_NUMBER", NUMBER)
	OS.set_environment("DONGXIU_ROOM_PORT", "0")
	OS.set_environment("DONGXIU_ROOM_SETTINGS", JSON.stringify({
		"difficulty": "low", "ai_delay_ms": 50, "discard_ms": 10000, "response_ms": 700,
		"presentation_ms": {"dealt": 70, "turn": 50, "response": 50, "ready_draw": 50}}))
	server_pid = child("res://src/network/RoomServer.gd")
	if not check(server_pid > 0 and await wait_until(func(): return read_json(status_path).has("port"), 9000), "independent RoomServer starts"):
		return
	var status := read_json(status_path)
	var port := int(status.port)
	var instance: String = status.instance
	creator_pid = child(SCRIPT, ["creator", str(port), creator_path])
	if not check(creator_pid > 0 and await wait_until(func(): return read_json(creator_path).has("ticket"), 8000), "creating player joins from a separate process"):
		return
	var metadata := read_json(creator_path)
	DirAccess.remove_absolute(creator_path)
	var saved: Dictionary = metadata.ticket
	var creator_seat: int = int(metadata.seat)
	check(metadata.client_only and saved.room_instance_id == instance and creator_seat == 1, "creating client has no authority or backup")
	var observer = connect_client("observer", port)
	if not check(observer != null and await wait_until(func(): return not observer.view.is_empty() and not observer.waiting_for_foreground_view(), 8000), "observer joins the same server"):
		return
	check(_client_only(observer) and observer.view.seat == 0, "observer has a seat view and no authority or backup")
	var online_ticket: Dictionary = observer.ticket.duplicate(true)
	observer.request_backup_key()
	observer.standby_state({"sequence": 1, "instance": instance, "payload": PackedByteArray([1])})
	check(_client_only(observer) and observer.ticket == online_ticket and observer.view.room.room_instance_id == instance,
		"an online peer ignores the LAN backup handler without altering its active session")
	check(observer.set_ready(true), "observer readies")
	var passes := {}
	var has_turn := func():
		var state: Dictionary = observer.view.round
		var actions: Array = state.get("choices", {}).get("actions", [])
		var prompt := int(state.get("prompt_id", -1))
		if actions.has("pass") and not passes.has(prompt):
			passes[prompt] = observer.submit(prompt, "pass")
		return actions.has("discard") and state.phase == "turn" and int(observer.view.clock.get("remaining_ms", 0)) >= 2000
	if not check(await wait_until(has_turn, 28000), "two clients finish real dice, dealing and the creator's first discard"):
		return
	var before: Dictionary = observer.view.duplicate(true)
	var observer_seat: int = before.seat
	check(before.round.wall_remaining < 56 and before.round.players[creator_seat].discard_count > 0
		and before.room.round_number == 1 and before.room.room_instance_id == instance, "observer holds the live wall after the creator's opening draw and discard")
	check(_private_view(before), "the observer never receives other concealed hands")
	var killed_pid := creator_pid
	if not check(OS.is_process_running(creator_pid) and OS.kill(creator_pid) == OK, "kill the creating player process"):
		return
	creator_pid = -1
	var creator_exited := func() -> bool:
		if OS.get_name() == "Linux":
			return not FileAccess.file_exists("/proc/%d/stat" % killed_pid)
		if OS.get_name() == "Windows":
			return not OS.is_process_running(killed_pid)
		return OS.execute("kill", ["-0", str(killed_pid)]) != 0
	check(await wait_until(creator_exited, 3000), "creating process has exited")
	if not check(await wait_until(func():
		return observer.view.round.get("prompt_id") == before.round.prompt_id and observer.view.clock.get("phase") == "countdown" and int(observer.view.clock.get("remaining_ms", 0)) < before.clock.remaining_ms, 1500), "the same observer clock keeps counting after the creator dies"):
		return
	check(OS.is_process_running(server_pid) and observer.view.room.room_instance_id == instance, "original server PID and room instance stay alive")
	check(observer.view.round.wall_slots == before.round.wall_slots and observer.view.round.players[observer_seat].hand == before.round.players[observer_seat].hand, "same wall and private hand stay in place")
	var id: int = before.round.choices.discard_ids[0]
	check(observer.submit(before.round.prompt_id, "discard", id), "observer submits against the same prompt after creator loss")
	check(await wait_until(func():
		var state: Dictionary = observer.view.round
		return (state.get("prompt_id") != before.round.prompt_id and state.get("last_discard", {}).get("tile_id") == id
			and observer.view.room.round_number == before.room.round_number), 2500), "the surviving server accepts the exact post-crash discard and advances the same round")
	var resumed = connect_client("creator", port, saved)
	if not check(resumed != null and await wait_until(func(): return not resumed.view.is_empty() and not resumed.waiting_for_foreground_view(), 8000), "creator's original ticket reconnects to the running server"):
		return
	check(resumed.view.seat == creator_seat and resumed.view.room.room_instance_id == instance and resumed.view.room.round_number == 1, "original ticket recovers the original seat in the same round")
	check(resumed.view.room.seats[creator_seat].score == before.room.seats[creator_seat].score, "creator's score persists across the process loss")
	check(_client_only(resumed) and _private_view(resumed.view) and OS.is_process_running(server_pid), "resumed endpoint still only receives its private seat view")
	resumed.queue_free()
	observer.queue_free()

func _creator(port: int, path: String) -> void:
	var endpoint = connect_client("creator", port)
	if endpoint == null or not await wait_until(func(): return not endpoint.view.is_empty() and not endpoint.waiting_for_foreground_view(), 8000):
		quit(2)
		return
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		quit(3)
		return
	file.store_string(JSON.stringify({"ticket": endpoint.ticket, "seat": endpoint.view.seat, "client_only": _client_only(endpoint)}))
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		quit(4)
		return
	endpoint.set_ready(true)
	endpoint.start_first_round()
	var sent := {}
	await wait_until(func():
		var state: Dictionary = endpoint.view.round
		var choices: Dictionary = state.get("choices", {})
		var prompt := int(state.get("prompt_id", -1))
		var actions: Array = choices.get("actions", [])
		if sent.has(prompt):
			return false
		if actions.has("discard"):
			sent[prompt] = endpoint.submit(prompt, "discard", choices.discard_ids[0])
		elif "pass" in actions:
			sent[prompt] = endpoint.submit(prompt, "pass")
		return false, 55000)
	quit()

func _client_only(endpoint) -> bool:
	var key_job: Thread = endpoint._backup_key_job
	return (endpoint.mode == "online" and endpoint._host == null and endpoint._standby_state.is_empty()
		and endpoint._backup_private == null and (key_job == null or not key_job.is_started()))

func _private_view(state: Dictionary) -> bool:
	for player in state.round.players:
		if player.seat != state.seat and (not player.hand.is_empty() or player.display.has("own_keys")):
			return false
	return true
