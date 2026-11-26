extends SceneTree

const Main := preload("res://scenes/Main.tscn")
const Settings := preload("res://src/app/AppSettings.gd")
const Client := preload("res://src/network/GameClient.gd")
const Voice := preload("res://src/audio/VoiceController.gd")
const Badge := preload("res://src/app/PlayerBadge.gd")
var app
var authority
var remote
var remote_voice
var checks := 0
var failures := 0
var raw_ms := 1000
var folder := ""
var _phone_viewport: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func until(predicate: Callable, timeout_ms: int = 20000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
		OS.delay_msec(1)
	return predicate.call()

func mouse(point: Vector2, down: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	app.get_viewport().push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	app.get_viewport().push_input(event, true)

func click(badge: Button, score: bool = false) -> void:
	var target: Control = badge.score_label if score else badge.name_label
	var point := target.get_global_rect().get_center()
	mouse(point, true)
	mouse(point, false)

func badge_for(seat: int):
	return app._identities[posmod(int(app._view.seat) - seat, 4)]

func lit(badge: Button, color: Color = Badge.ACTIVE) -> bool:
	return badge.mic_dot.modulate.a>0.99 and badge.mic_dot.self_modulate==color and badge.name_label.get_theme_color("font_color")==Color.WHITE

func capture(name: String) -> void:
	var path := OS.get_environment("DONGXIU_VOICE_SCREENS")
	if path.is_empty() or DisplayServer.get_name() == "headless": return
	var applied = load("res://src/presentation/TableLayoutProfile.gd").new()
	var valid: bool = app.table_play_only and applied.load_file(app._table.LAYOUT_PATH)
	if valid:
		for key in ["table_side","regions","presentation","hud","hand_tolerance"]:
			valid = valid and app._table.custom_profile.data.get(key)==applied.data.get(key)
	check(valid, "phone screenshot requires the real game, phone display path and applied layout")
	if not valid: return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path)
	var image:Image = app.get_viewport().get_texture().get_image()
	check(image.get_size()==Vector2i(2670,1200), "Xiaomi 15 capture must actually be 2670 by 1200, without window-manager size clamping")
	if image.get_size()!=Vector2i(2670,1200):return
	check(image.save_png(path.path_join(name + ".png")) == OK, "save phone-path game screenshot")
	var manifest := FileAccess.open(path.path_join(name + ".json"),FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"kind":"desktop_phone_mode_live_game","host_os":OS.get_name(),
		"phone_display":app.table_play_only,
		"layout":app._table.LAYOUT_PATH,"layout_sha256":FileAccess.get_sha256(app._table.LAYOUT_PATH),
		"pixels":[image.get_width(),image.get_height()],"logical_size":[app.size.x,app.size.y],
		"network_mode":app._mode,"round":app._view.room.round_number,"prompt":app._round_projection.prompt_id,
		"actions":app._choices().get("actions",[])}))

func _run() -> void:
	folder = "user://voice-names-" + str(Time.get_ticks_usec())
	check(DirAccess.make_dir_absolute(folder) == OK, "isolated profile and mute storage")
	# Fixed offscreen phone viewport avoids desktop window-manager limits without resizing a screenshot.
	_phone_viewport=SubViewport.new()
	_phone_viewport.size=Vector2i(2670,1200)
	_phone_viewport.size_2d_override=Vector2i(1602,720)
	_phone_viewport.size_2d_override_stretch=true
	_phone_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(_phone_viewport)
	app = Main.instantiate()
	app.table_play_only=false
	app._settings = Settings.new(folder.path_join("profile.cfg"))
	check(app._settings.save_profile("声音检查甲乙", 1), "six-character local name")
	_phone_viewport.add_child(app)
	authority = Client.new()
	root.add_child(authority)
	check(authority.start_server("918264", 0, {"difficulty": "low"}, "lan"), "real ENet LAN authority")
	authority._host.clock_msec = func(): return raw_ms
	app._mode = "lan"
	var profile: Dictionary = app._profile()
	profile.room_number = "918264"
	app._client.connect_room("127.0.0.1", authority.local_port, profile)
	check(await until(func(): return not app._view.is_empty()), "Main receives authenticated room")
	remote = Client.new()
	root.add_child(remote)
	remote.connect_room("127.0.0.1", authority.local_port,
		{"mode": "lan", "room_number": profile.room_number, "player_id": "name-test-remote", "nickname": profile.nickname})
	check(await until(func(): return not remote.view.is_empty()), "same-name real player joins separately")
	remote_voice = Voice.new(folder.path_join("remote.cfg"))
	root.add_child(remote_voice)
	remote_voice.bind_client(remote)
	remote.set_application_away(true)
	check(await until(func(): return app._seat_choices[remote.view.seat].text.contains("暂离")) and app._view.room.seats[remote.view.seat].connected, "real seating page marks a connected background guest absent")
	remote.set_application_away(false)
	await until(func(): return not remote.waiting_for_foreground_view())
	app._client.set_ready(true)
	remote.set_ready(true)
	app._client.start_first_round()
	check(await until(func(): return authority._host._prepare_at >= 0), "two humans ready")
	raw_ms += 3001
	check(await until(func(): return app._screen == "play"), "real opening enters play HUD")
	check(await until(func(): return app._round_projection.get("phase") == "dealt"), "physical dice produce a real deal")
	raw_ms += 9000
	check(await until(func(): return app._round_projection.get("phase") == "turn"), "opening reaches a real draw/discard turn")
	raw_ms += ceili(app._table.MOVE_SECONDS*1000)+1
	check(await until(func(): return app._table._opening == null and app._table._motions.is_empty()), "actual table finishes pickup and insertion before inspecting the HUD")
	if failures:
		await finish()
		return
	# Seat-page checks above remain desktop diagnostics; all play/capture checks use the phone path.
	app.table_play_only = true
	app._fit_safe_area()
	await process_frame
	await process_frame
	check(app.table_play_only, "play screenshots use the same phone display branch as Android")
	var own: int = app._view.seat
	var other: int = remote.view.seat
	var local_badge: Button = badge_for(own)
	var other_badge: Button = badge_for(other)
	check(local_badge.name_label.text == profile.nickname and other_badge.name_label.text == profile.nickname,
		"same-named people display their own name without a local-player alias")
	check(not lit(local_badge) and not lit(other_badge), "new room names are white with actual microphones off")
	check(local_badge.turn_dot.modulate.a == 1.0 and not lit(local_badge), "turn dot is separate from microphone name color")
	for badge in app._identities:
		check(app._safe.get_global_rect().encloses(badge.get_global_rect()) and badge.size.y >= 48,
			"each real HUD name/score area fits the safe area and minimum tap height")
	var score: String = local_badge.score_label.text
	click(local_badge)
	check(await until(func(): return app._voice.recording and lit(local_badge) and remote.view.room.seats[own].mic_active),
		"actual local name click starts Dummy-driver capture and publishes it over ENet")
	check(local_badge.score_label.text == score and local_badge.score_label.get_theme_color("font_color") == Color.WHITE,
		"microphone state does not change score value or color")
	click(local_badge, true)
	check(await until(func(): return not app._voice.recording and not lit(local_badge) and not remote.view.room.seats[own].mic_active),
		"score-line click stops the same microphone")
	remote_voice.set_microphone(true)
	check(await until(func(): return lit(other_badge)), "remote actual capture lights its green dot")
	click(other_badge)
	check(lit(other_badge,Badge.MUTED) and not app._voice.speaker_enabled(other) and remote_voice.recording,
		"muting turns this listener's microphone dot solid red without stopping the sender")
	await capture("names-muted")
	remote_voice.set_microphone(false)
	check(await until(func():return other_badge.mic_dot.modulate.a==0.0), "sender closing microphone hides the dot without resetting mute preference")
	remote_voice.set_microphone(true)
	check(await until(func():return lit(other_badge,Badge.MUTED)) and not app._voice.speaker_enabled(other), "sender reopening microphone restores the red dot and stays muted")
	click(other_badge, true)
	check(lit(other_badge) and app._voice.speaker_enabled(other), "remote score-line restores listening and the green dot")
	var point := other_badge.get_global_rect().get_center()
	mouse(point, true)
	app._request_leave()
	mouse(point, false)
	check(app._voice.speaker_enabled(other) and is_instance_valid(app._leave_overlay), "held name cannot mute behind the leave modal")
	app._dismiss_leave()
	mouse(point, true)
	app._open_settings()
	app._close_settings()
	await process_frame
	mouse(point, false)
	check(app._screen == "play" and app._voice.speaker_enabled(other), "settings round trip invalidates an earlier held name")
	var mute_path: String = app._voice._mute_path
	app._voice._mute_path = mute_path.path_join("cannot-save.cfg")
	click(other_badge)
	check(app._voice.speaker_enabled(other) and lit(other_badge) and app._voice_status_text.contains("未能保存"),
		"failed local mute persistence keeps actual playback and reports a visible error")
	app._refresh_hud()
	check(app._voice_status_text.contains("未能保存"), "ordinary turn refresh does not erase the mute error")
	app._voice._mute_path = mute_path
	click(local_badge)
	check(app._voice.recording and lit(local_badge) and not app._voice_status_text.contains("未能保存"),
		"a new microphone operation replaces stale unrelated mute error with its actual state")
	await capture("names-speaking")
	click(local_badge)
	# Permission outcome is injected, not evidence of Android permission or real microphone quality.
	var backend = app._voice._backend
	backend.permission_pending = true
	backend._last_permission_request = Time.get_ticks_msec()
	backend.status_changed.emit(false, "等待麦克风权限")
	check(not lit(local_badge) and app._voice_status_text == "等待麦克风权限", "pending permission keeps name white and shows nonmodal status")
	click(local_badge)
	backend.permission_result(true)
	check(not app._voice.microphone_requested() and not app._voice.recording and not lit(local_badge)
		and app._voice_status_text == "麦克风已关闭", "same name cancels pending permission and ignores later permission response")
	backend.permission_pending = true
	backend.permission_result(false)
	check(not lit(local_badge) and app._voice_status_text == "麦克风权限未授予", "permission rejection never reports actual capture")
	click(local_badge)
	check(app._voice.recording and lit(local_badge) and app._voice_status_text == "麦克风已开启", "retry clears rejected permission text only after capture succeeds")
	await capture("names-mic-restored")
	await _foreground_return(own, other)
	remote._reset() # Temporary transport loss must retain the human listener identity.
	check(await until(func(): return not app._view.room.seats[other].connected and not lit(other_badge)), "actual transport loss makes remote name white")
	check(not other_badge.disabled and other_badge.score_label.text.contains("暂离"), "temporary absence retains the real player's listener control")
	click(other_badge)
	check(not app._voice.speaker_enabled_for("name-test-remote") and not lit(other_badge), "a listener may mute an absent identity before it reconnects")
	await capture("names-remote-absent")
	await finish()

func _foreground_return(own: int, other: int) -> void:
	raw_ms += ceili(app._table.MOVE_SECONDS*1000)+1
	check(await until(func(): return not app._choices().is_empty()), "dealer has an actual released action before the lifecycle event")
	if app._choices().is_empty(): return
	var tile: int = app._choices().discard_ids[0]
	var old_prompt: int = app._choices().prompt_id
	var old_hand: Array = app._view.round.players[own].hand.duplicate(true)
	remote.set_application_away(true)
	check(await until(func(): return badge_for(other).score_label.text.contains("暂离")) and app._view.room.seats[other].connected, "other connected player's background state appears on the live Main table")
	remote.set_application_away(false)
	await until(func(): return not badge_for(other).score_label.text.contains("暂离"))
	app._tile_clicked(tile)
	check(app._order.view().selected_id == tile, "actual owned tile selected before background")
	var held: Button = app._teaching_button
	# The default phone layout hides this optional control; restore it for the lifecycle press check.
	var teaching_layout:Dictionary=app._table.custom_profile.data.hud.teaching.duplicate(true)
	app._table.custom_profile.data.hud.teaching.visible=true
	app._apply_hud_layout()
	var point := held.get_global_rect().get_center()
	var teaching: bool = app._teaching_enabled
	var pressed := []
	held.button_down.connect(func(): pressed.append(true), CONNECT_ONE_SHOT)
	mouse(point, true)
	check(pressed.size() == 1, "the ordinary HUD button receives a real press before suspension")
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(await until(func(): return remote.view.room.seats[own].away and not remote.view.room.seats[own].mic_active), "Main application notification reaches real authority and suspends the actual local voice backend")
	check(app._order.view().selected_id < 0 and app._foreground_shade.visible and app._choices().is_empty(), "background clears lifted tile, hides manual actions and keeps a synchronization notice")
	var samples := []
	var on_view := func(state: Dictionary):
		if state.presence.needs_ack:
			app._tile_clicked(tile)
			app._drag_started(tile)
			samples.append(app._foreground_shade.visible and app._choices().is_empty() and not app._table.is_processing_input() and app._order.view().selected_id < 0 and app._order.view().dragged_id < 0 and not app._voice.recording)
	app._client.view_changed.connect(on_view)
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(app._foreground_shade.visible and app._screen == "play", "system resume alone leaves the game visible but gated")
	check(await until(func(): return not app._foreground_shade.visible and not remote.view.room.seats[own].away and app._voice.recording), "private snapshot receipt reopens the table and restores the prior mic consent")
	app._client.view_changed.disconnect(on_view)
	mouse(point, false)
	check(not samples.is_empty() and not samples.has(false) and app._teaching_enabled == teaching, "pending snapshot blocks late card events, and pre-background button release cannot toggle teaching")
	check(app._choices().prompt_id == old_prompt and app._view.round.players[own].hand == old_hand, "resumed Main presents the current unchanged hand and prompt")
	var table_point: Vector2 = app._table.camera.unproject_position(app._table.tiles[tile].global_position)
	check(app._table._press(table_point, 0, false), "start a real hold on the projected tile")
	check(await until(func(): return app._order.view().dragged_id == tile and remote.view.round.players[own].display.dragged != ""), "held tile and gap reach the other ENet endpoint")
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(await until(func(): return remote.view.room.seats[own].away and remote.view.round.players[own].display.dragged == "") and app._table._pointer == -2, "background cancels table touch, local drag and remote preview together")
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await until(func(): return not app._foreground_shade.visible)
	app._request_leave()
	var confirmation: Control = app._leave_overlay
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	await until(func(): return not app._foreground_shade.visible)
	check(is_instance_valid(confirmation) and app._leave_overlay == confirmation and not app._table.is_processing_input(), "foreground acknowledgement preserves the existing leave confirmation input lock")
	app._dismiss_leave()
	check(await until(func(): return app._table.can_play_hand()), "canceled drag has physically returned before the next successful tap")
	app._tile_clicked(tile)
	app._tile_clicked(tile)
	check(await until(func(): return remote.view.round.players[own].discards.size() == 1) and app._screen == "play", "fresh human taps produce exactly one real discard after synchronization")
	app._table.custom_profile.data.hud.teaching=teaching_layout
	app._apply_hud_layout()

func finish() -> void:
	var playbacks := []
	if is_instance_valid(app):
		for player in [app._sound._effects, app._sound._speech, app._sound._bell]:
			if player.playing: playbacks.append(weakref(player.get_stream_playback()))
	if is_instance_valid(app): app.queue_free()
	if is_instance_valid(remote_voice): remote_voice.queue_free()
	if is_instance_valid(remote): remote.queue_free()
	if is_instance_valid(authority): authority.queue_free()
	await process_frame
	# The audio mixer retires stopped streams in wall-clock time, independently of accelerated test frames.
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 250 or (playbacks.any(func(ref): return ref.get_ref() != null) and Time.get_ticks_msec() - start < 2000):
		OS.delay_msec(4)
		await process_frame
	check(playbacks.all(func(ref): return ref.get_ref() == null), "the real mixer released all active table announcement playbacks on teardown")
	_phone_viewport.queue_free()
	for path in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(path))
	DirAccess.remove_absolute(folder)
	print("Voice names: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
