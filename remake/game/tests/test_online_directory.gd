extends SceneTree
## When launched by remake/server/test_room_directory.py this exercises HTTP and a separate Godot authority.
const Directory = preload("res://src/network/RoomDirectory.gd")
const Client = preload("res://src/network/GameClient.gd")
const Preferences = preload("res://src/app/AppSettings.gd")
const Main = preload("res://scenes/Main.tscn")
var checks := 0
var failures := 0
var rooms := []
var received := {}
var errors := []
var clients := []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL online: ", label)

func until(test: Callable, milliseconds: int = 12000) -> bool:
	var deadline := Time.get_ticks_msec() + milliseconds
	while not test.call() and Time.get_ticks_msec() < deadline:
		await process_frame
		OS.delay_msec(2)
	return test.call()

func _run() -> void:
	var directory := Directory.new()
	root.add_child(directory)
	directory.rooms_received.connect(func(items): rooms = items)
	directory.room_received.connect(func(item): received = item)
	directory.failed.connect(func(message): errors.append(message))
	check(not directory.configure("") and not directory.list_rooms(), "no fabricated unconfigured rooms")
	check(not directory.configure("http://example.org"), "external HTTP rejected")
	check(not directory.configure("http://localhost.example.org"), "loopback match has exact host boundary")
	check(directory.configure("https://example.org"), "external HTTPS accepted")
	check(not directory.find_room("../room"), "number must be numeric")
	var url := OS.get_environment("DONGXIU_DIRECTORY_TEST_URL")
	if url.is_empty():
		_finish()
		return
	check(directory.configure(url), "set test service address")
	check(directory.create_room("真实在线桌", {"difficulty": "low"}, "004291"), "POST create room")
	if not await until(func(): return not received.is_empty()):
		check(false, "directory yielded actual live room: " + str(errors))
		_finish()
		return
	var room := received.duplicate()
	var owner_token: String = room.owner_token
	room.erase("owner_token")
	check(room.number == "004291" and room.name == "真实在线桌" and room.players == 0 and not room.started, "room advertised before play")
	directory.list_rooms()
	check(await until(func(): return rooms.has(room)), "list returns room from actual authority")
	received = {}
	directory.find_room(room.number)
	check(await until(func(): return received == room), "resolve by exact leading-zero room number")
	for seat in 2:
		var client := Client.new()
		client.view_changed.connect(func(state):
			if state.has("presentation"):client.finish_presentation.call_deferred(state.presentation))
		client.name = "Online" + str(seat)
		root.add_child(client)
		clients.append(client)
		var profile := _profile(seat)
		if seat == 0: profile.owner_token = owner_token
		check(client.connect_room(room.host, int(room.port), profile), "real ENet join")
		if not await until(func(): return not client.view.is_empty()):
			check(false, "real room accepted member")
			_finish()
			return
	var south = clients[0]
	var east = clients[1]
	check(south.view.seat == 1 and east.view.seat == 0, "normal south/east seat assignment")
	south.set_ready(true)
	east.set_ready(true)
	south.start_first_round()
	if not await until(func(): return south.view.round.phase == "dealt", 22000):
		check(false, "finished physical roll and deal")
		_finish()
		return
	check(south.view.round.players[0].hand.is_empty() and east.view.round.players[1].hand.is_empty(), "private views on both real devices")
	check(south.request_record_submission(), "connected seat authorizes record while playing")
	check(await until(func(): return south.view.get("record_submission", {}).get("status") == "queued"), "submission stays queued until settlement")
	var saved: Dictionary = south.ticket.duplicate(true)
	check(room.room_instance_id == saved.room_instance_id, "directory returns the authority's exact public instance")
	var hand: Array = south.view.round.players[1].hand.duplicate(true)
	var nonce := Crypto.new().generate_random_bytes(20).hex_encode()
	var signed: Dictionary = await _voice(url, saved, 1, nonce)
	check(signed.code == 200 and signed.data.voice_room == "dx-" + str(saved.room_instance_id) and not Marshalls.base64_to_raw(signed.data.auth).is_empty(), "fresh GME buffer bound to this member and instance")
	check((await _voice(url, saved, 1, nonce)).code == 409, "voice nonce replay rejected")
	check((await _voice(url, saved, 0, nonce)).code == 403, "other seat cannot use this token")
	south._reset() # Unexpected disconnection retains the recovery ticket.
	await create_timer(0.6).timeout
	check((await _voice(url, saved, 1, nonce)).code == 403, "offline membership cannot request voice")
	await _check_cold_resume(url, room, saved, hand)
	south.connect_room(room.host, int(room.port), _profile(0), saved)
	check(await until(func(): return not south.view.is_empty()), "resume with issued token")
	if south.view.is_empty():
		_finish()
		return
	check(south.view.room.room_instance_id == saved.room_instance_id and south.view.round.players[1].hand == hand, "same seated hand on reconnect")
	south._reset()
	var live_app = Main.instantiate()
	root.add_child(live_app)
	await _check_hot_online(live_app, url, saved)
	live_app.queue_free()
	await process_frame
	south.connect_room(room.host, int(room.port), _profile(0), saved)
	if not await until(func(): return not south.view.is_empty()):
		check(false, "original player returns after the online reconnect UI scenario")
		_finish()
		return
	var sent := {}
	var deadline := Time.get_ticks_msec() + 100000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		for player in clients:
			if player.view.is_empty():
				continue
			var state: Dictionary = player.view.round
			var choice: Dictionary = state.choices
			var key := "%d-%d" % [int(player.view.seat), int(state.prompt_id)]
			if choice.is_empty() or sent.has(key):
				continue
			var action := "win" if "win" in choice.actions else ("self_win" if "self_win" in choice.actions else ("pass" if "pass" in choice.actions else "discard"))
			var id := int(choice.discard_ids[0]) if action == "discard" else -1
			if player.submit(state.prompt_id, action, id):
				sent[key] = true
		if south.view.round.phase == "settled" and east.view.round.phase == "settled":
			break
	check(south.view.has("settlement") and east.view.has("settlement"), "real online game reaches settlement")
	if south.view.has("settlement") and east.view.has("settlement"):
		check(south.view.settlement.scores == east.view.settlement.scores, "identical scores")
		check(await until(func(): return south.view.get("record_submission", {}).get("status") == "stored", 16000), "only real persisted HTTP acknowledgement marks submitted")
		check(not south.view.record_submission.has("record") and not south.view.record_submission.has("wall"), "private replay is never part of UI receipt")
	for client in clients:
		client._reset()
	await create_timer(0.4).timeout
	received = {}
	directory.find_room(room.number)
	check(await until(func(): return not received.is_empty()), "last human leaving does not immediately destroy room")
	await _check_unavailable_resume(url, saved)
	_finish()

func _check_cold_resume(url: String, room: Dictionary, saved: Dictionary, hand: Array) -> void:
	var fresh = Main.instantiate()
	root.add_child(fresh)
	if fresh._screen == "profile_setup":
		for node in fresh._profile_setup.find_children("*", "Button", true, false):
			if node.text == "保存":
				node.pressed.emit()
				break
	check(fresh._settings.profile_complete() and fresh._screen == "connect", "online recovery starts in the new lobby with an actual completed local profile")
	fresh.queue_free()
	await process_frame
	var cached := saved.duplicate()
	cached.port = 1
	var prefs := Preferences.new()
	check(prefs.update({"directory_url": url}) and prefs.remember_room(cached), "store old-format ticket with stale UDP endpoint")
	var app = Main.instantiate()
	root.add_child(app)
	check(app._client.view.is_empty(), "boot opens no game controls from cached data")
	if await until(func(): return not app._client.view.is_empty()):
		var view: Dictionary = app._client.view
		check(view.room.room_instance_id == saved.room_instance_id and view.seat == 1 and view.room.seats[1].player_id == saved.player_id, "fresh Main preflights exact room and authenticates the original seat")
		check(view.round.players[1].hand == hand and view.round.players[0].hand.is_empty() and app._client.ticket.port == int(room.port), "restore reaches the directory endpoint with the exact private hand")
		check(app._settings.remembered_room().directory_url == url, "refreshed ticket remembers its originating directory")
	else:
		check(false, "fresh Main did not recover live room: " + str(app._status_text))
	app._client._reset()
	app.queue_free()
	await process_frame

func _check_hot_online(app, url: String, saved: Dictionary) -> void:
	if not await until(func(): return app._screen == "play" and not app._foreground_shade.visible):
		check(false, "Main received playable online table before socket loss")
		return
	var unavailable := TCPServer.new()
	check(unavailable.listen(0, "127.0.0.1") == OK, "reserve unavailable directory endpoint")
	var offline_url := "http://127.0.0.1:%d" % unavailable.get_local_port()
	unavailable.stop()
	app._live_ticket.directory_url = offline_url
	var prior_id: int = app._client._api.get_unique_id()
	app._client._peer.get_peer(1).peer_disconnect()
	for attempt in 3:
		if not await until(func(): return app._recovery_retries > attempt and not app._recovery_timer.is_stopped()):
			check(false, "hot online table continued scheduling directory retry %d" % attempt)
			return
		check(app._screen == "play" and app._foreground_shade.visible and app._choices().is_empty() and app._table.tiles.size() > 0, "actual directory outage retains the current table and blocks old input")
		if attempt < 2: app._recovery_timer.start(0.01)
	check(app._client._peer == null, "offline directory never blindly connects the saved UDP address")
	app._recovery_ticket.directory_url = url
	var verified := []
	app._directory.room_verified.connect(func(room): verified.append(room.room_instance_id), CONNECT_ONE_SHOT)
	app._foreground_shade.retry.pressed.emit()
	app._foreground_shade.retry.pressed.emit()
	check(await until(func(): return not app._foreground_shade.visible and not app._client.view.is_empty()), "immediate retry uses the real HTTP directory and new ENet connection")
	check(verified == [saved.room_instance_id] and app._client._api.get_unique_id() != prior_id and app._view.seat == saved.seat and app._view.room.seats[saved.seat].player_id == saved.player_id, "double retry restores only the authenticated original member and instance")
	app._client._peer.get_peer(1).peer_disconnect()
	if await until(func(): return app._foreground_shade.visible and app._directory._request != null):
		app._foreground_shade.go_back.pressed.emit()
		check(await until(func():return not app._leaving and not app._transition.active), "explicit return completes the actual reverse camera")
		check(app._screen == "connect" and app._mode == "online" and app._view.is_empty() and app._client.view.is_empty() and app._recovery_ticket.is_empty(), "explicit return cancels in-flight directory recovery without a late rejoin")
	else:
		check(false, "second online socket loss starts a new directory verification")

func _check_unavailable_resume(url: String, saved: Dictionary) -> void:
	var prefs := Preferences.new()
	for profile in [{"room_instance_id": "0".repeat(64)}, {"room_number": "9999"}]:
		var cached := saved.duplicate()
		cached.merge(profile, true)
		cached.directory_url = url
		check(prefs.remember_room(cached), "save an obsolete private ticket")
		var app = Main.instantiate()
		root.add_child(app)
		check(await until(func(): return app._settings.remembered_room().is_empty()), "retired or reused room silently clears original ticket")
		check(app._screen == "connect" and app._status_text.is_empty() and app._client._peer == null, "obsolete ticket remains in the new lobby without opening ENet or offering the old room")
		app.queue_free()
		await process_frame
	var unavailable := TCPServer.new()
	check(unavailable.listen(0, "127.0.0.1") == OK, "reserve an ephemeral port for offline recovery test")
	var port := unavailable.get_local_port()
	unavailable.stop()
	var cached := saved.duplicate()
	cached.directory_url = "http://127.0.0.1:%d" % port
	check(prefs.remember_room(cached), "save existing seat with temporarily unavailable HTTP directory")
	var app = Main.instantiate()
	root.add_child(app)
	check(await until(func(): return not app._recovery_timer.is_stopped()), "temporary outage schedules a retry")
	app.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(app._recovery_timer.is_stopped() and app._directory._request == null and app._settings.remembered_room() == cached, "background cancels requests and retry timer while keeping the private ticket")
	app.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(await until(func(): return app._recovery_ticket.is_empty(), 16000), "foreground wake performs bounded retry")
	check(app._recovery_retries == 2 and app._recovery_timer.is_stopped() and app._settings.remembered_room() == cached and app._client._peer == null, "exhausted outage retries preserve ticket and never join the cached endpoint")
	app._restore_recent_room()
	check(await until(func(): return not app._recovery_timer.is_stopped()), "retry remains available for a later explicit fresh start")
	app._choose_mode("lan")
	check(app._recovery_ticket.is_empty() and app._recovery_timer.is_stopped() and app._directory._request == null, "choosing a new game cancels old-room retry")
	app.queue_free()
	await process_frame

func _profile(index: int) -> Dictionary:
	return {"room_number": "004291", "player_id": "online-integration-" + str(index), "nickname": "南家" if index == 0 else "东家", "mode": "online"}

func _voice(url: String, ticket: Dictionary, seat: int, nonce: String) -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.timeout = 3
	var endpoint := "%s/v1/gme-auth?room=004291&instance=%s&openid=004291%d&nonce=%s" % [url, ticket.room_instance_id, seat, nonce]
	http.request(endpoint, PackedStringArray(["X-Room-Token: " + str(ticket.member_token)]))
	var reply: Array = await http.request_completed
	http.queue_free()
	return {"code": reply[1], "data": JSON.parse_string(reply[3].get_string_from_utf8())}

func _finish() -> void:
	print("Online directory: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
