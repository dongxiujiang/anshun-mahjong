extends SceneTree

const Main := preload("res://scenes/Main.tscn")
const Settings := preload("res://src/app/AppSettings.gd")
const Client := preload("res://src/network/GameClient.gd")
const AudioRetirement := preload("res://tests/AudioRetirement.gd")
var checks := 0
var failures := 0
var now_ms := 1000
var app
var authority := Client.new()
var other := Client.new()
var folder := ""

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL hot reconnect: ", message)
	return ok

func until(test: Callable, limit: int = 12000) -> bool:
	var deadline := Time.get_ticks_msec() + limit
	while not test.call() and Time.get_ticks_msec() < deadline:
		await process_frame
		OS.delay_msec(1)
	return test.call()

func capture(name: String) -> void:
	var path := OS.get_environment("DONGXIU_RECONNECT_SCREENS")
	if path.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path.path_join(name + ".png"))

func _run() -> void:
	folder = "user://hot-reconnect-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_absolute(folder)
	app = Main.instantiate()
	app._settings = Settings.new(folder.path_join("profile.cfg"))
	app._settings.save_profile("局中恢复", 1)
	root.add_child(app)
	root.add_child(authority)
	root.add_child(other)
	check(authority.start_server("284913", 0, {"difficulty": "low"}, "lan"), "start real LAN authority")
	authority._host.clock_msec = func(): return now_ms
	app._mode = "lan"
	var profile: Dictionary = app._profile()
	profile.room_number = "284913"
	app._client.connect_room("127.0.0.1", authority.local_port, profile)
	if not check(await until(func(): return app._screen == "room"), "Main enters original room"):
		await finish()
		return
	other.connect_room("127.0.0.1", authority.local_port, {"mode": "lan", "room_number": profile.room_number, "nickname": "见证", "player_id": "observer"})
	if not check(await until(func(): return not other.view.is_empty()), "second live human joins"):
		await finish()
		return
	app._client.set_ready(true)
	other.set_ready(true)
	app._client.start_first_round()
	await until(func(): return authority._host._prepare_at >= 0)
	now_ms += 3001
	await until(func(): return app._round_projection.get("phase") == "dealt")
	now_ms += 9000
	await until(func(): return app._round_projection.get("phase") == "turn")
	now_ms += 300
	if not check(await until(func(): return not app._choices().get("discard_ids", []).is_empty()), "live dealer has a legal physical tile"):
		await finish()
		return
	var seat: int = app._view.seat
	var instance: String = app._view.room.room_instance_id
	var number: int = app._view.room.round_number
	var original: Array = app._view.round.players[seat].hand.duplicate(true)
	var prompt: int = app._view.round.prompt_id
	var tile: int = app._choices().discard_ids[0]
	await until(func(): return app._table._opening == null and app._table._motions.is_empty())
	var slots: Array = app._order.view().slots.duplicate()
	var point: Vector2 = app._table.camera.unproject_position(app._table.tiles[tile].global_position)
	check(app._table._press(point, 0, false), "hold real tile before opening settings")
	check(await until(func(): return app._order.view().dragged_id == tile and other.view.round.players[seat].display.dragged != ""), "remote receives the dragged tile's anonymous slot")
	app._open_settings()
	check(await until(func(): return other.view.round.players[seat].display.dragged == "") and app._table._pointer == -2 and app._order.view().slots == slots, "settings restores order and clears the captured hold on both clients")
	app._close_settings()
	var release := InputEventScreenTouch.new()
	release.position = app._table.camera.unproject_position(Vector3.ZERO)
	app._table._input(release)
	check(app._choices().prompt_id == prompt and app._order.view().selected_id == -1 and app._view.round.players[seat].discards.is_empty(), "old touch release after settings cannot submit an action")
	check(await until(func(): return app._table.can_play_hand()), "physical return of the canceled held tile finishes before a new selection")
	app._tile_clicked(tile)
	check(app._order.view().selected_id == tile, "tile is raised before actual socket loss")
	var disconnects := []
	app._client.session_ended.connect(func(reason):
		if reason == "disconnected":
			disconnects.append(true)
			app._tile_clicked(tile)
			check(app._screen == "play" and app._board.visible and app._table.tiles.has(tile) and app._foreground_shade.visible and app._foreground_shade.is_processing(), "original table remains under the moving reconnect indicator")
			check(app._foreground_shade.message.text == "重连中" and app._foreground_shade.retry.visible and app._foreground_shade.go_back.visible, "retry and mode lobby are offered immediately")
			check(not app._table.is_processing_input() and app._order.view().selected_id == -1 and app._choices().is_empty(), "stale taps cannot select or submit while disconnected"))
	var acks := []
	var withheld := []
	app._client.view_changed.connect(func(view):
		if view.presence.needs_ack:
			acks.append(true)
			check(app._foreground_shade.visible and app._choices().is_empty(), "authenticated new socket still waits for full private snapshot acknowledgement")
			# Drop the first receipt on an otherwise live ENet connection; advance only the transport watchdog.
			if withheld.is_empty():
				withheld.append(app._client._api.get_unique_id())
				app._recovery_timer.start(0.05)
			if app._client._api.get_unique_id() == withheld[0]:
				app._client._acknowledged_view = app._client._presence_revision)
	app._voice.set_microphone(true)
	check(await until(func(): return other.view.room.seats[seat].mic_active), "original microphone choice published by the test audio driver")
	var old_peer: int = app._client._api.get_unique_id()
	var old_connection: String = authority._peer_connections[old_peer]
	authority._peer.disconnect_peer(old_peer)
	if not check(await until(func(): return disconnects.size() == 1 and not acks.is_empty() and not app._foreground_shade.visible), "automatic same-table reconnect completes"):
		await finish()
		return
	check(app._view.room.room_instance_id == instance and app._view.room.round_number == number and app._view.seat == seat and app._view.round.players[seat].hand == original and app._choices().prompt_id == prompt, "retains exact member, round, physical hand, and current prompt")
	check(not authority._host.submit(old_connection, instance, number, prompt, "discard", tile), "retired connection cannot submit a queued old action")
	check(app._view.round.players[other.view.seat].hand.is_empty() and app._client._api.get_unique_id() != old_peer, "new authenticated socket receives only its own private hand")
	check(app._client._api.get_unique_id() != withheld[0] and await until(func(): return other.view.room.seats[seat].mic_active), "missing state receipt retries on another socket and preserves same-room mic consent")
	app._tile_clicked(tile)
	app._tile_clicked(tile)
	if not check(await until(func(): return other.view.round.players[seat].discards.any(func(card): return card.id == tile)), "real Main discards the chosen physical tile after recovery"):
		await finish()
		return
	# Suspend inside the next real transport loss, then let the live room close by its own rule.
	app._client.session_ended.connect(func(reason):
		if reason == "disconnected": app.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED), CONNECT_ONE_SHOT)
	authority._peer.disconnect_peer(app._client._api.get_unique_id())
	check(await until(func(): return app._application_paused and not other.view.room.seats[seat].connected), "second disconnect retires its socket and suspends retry")
	await capture("lan-reconnecting")
	var retained_prompt: int = app._round_projection.prompt_id
	# Release the next seat's presentation, then advance the normal clock while the first seat is offline.
	for i in 5:
		now_ms += 16001
		if await until(func(): return other.view.round.prompt_id != retained_prompt, 300):
			break
	check(other.view.round.prompt_id != retained_prompt and app._round_projection.prompt_id == retained_prompt, "live players continue beyond the disconnected screen's retained prompt")
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(await until(func(): return not app._foreground_shade.visible and app._round_projection.prompt_id == other.view.round.prompt_id), "resync adopts the authority's advanced prompt")
	check(app._table._opening == null and app._table._motions.is_empty(), "no offline tile movements are replayed")
	app._client.submit(prompt, "discard", tile)
	check(await until(func(): return app._status_text.contains("已过期")), "new socket cannot submit a stale action to the real authority")
	app._client.session_ended.connect(func(reason):
		if reason == "disconnected": app.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED), CONNECT_ONE_SHOT)
	authority._peer.disconnect_peer(app._client._api.get_unique_id())
	await until(func(): return app._application_paused and not other.view.room.seats[seat].connected)
	other.leave()
	await until(func(): return authority._host._session._room._close_at_ms >= 0)
	now_ms += 300001
	await until(func(): return authority._host._closed)
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(await until(func(): return app._foreground_shade.message.text == "房间已关闭"), "real authority rejects expired original room after all people leave")
	check(app._foreground_shade.visible and not app._foreground_shade.retry.visible and app._recovery_timer.is_stopped() and app._settings.remembered_room().is_empty(), "explains closure on retained table and stops retries")
	await capture("lan-room-closed")
	app._foreground_shade.go_back.pressed.emit()
	await until(func():return not app._leaving)
	check(app._screen == "connect" and app._mode == "lan" and app._view.is_empty() and not app._foreground_shade.visible, "explicit return opens this mode's table list")
	await finish()

func finish() -> void:
	for node in [other, authority]:
		if is_instance_valid(node): node.queue_free()
	check(await AudioRetirement.release_app(app, self), "stopped application audio is released by the mixer")
	for filename in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(filename))
	DirAccess.remove_absolute(folder)
	print("Hot reconnect: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
