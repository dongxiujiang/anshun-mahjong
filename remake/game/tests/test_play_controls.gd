extends SceneTree

const Main = preload("res://scenes/Main.tscn")
const Settings = preload("res://src/app/AppSettings.gd")
const Client = preload("res://src/network/GameClient.gd")
const Room = preload("res://src/session/RoomSession.gd")
const AudioRetirement = preload("res://tests/AudioRetirement.gd")
var app
var checks := 0
var failures := 0
var raw_ms := 1000

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

func button(label: String, under: Node = app) -> Button:
	for node in under.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and node.text == label:
			return node
	return null

func capture(name: String) -> void:
	var folder := OS.get_environment("DONGXIU_CONTROL_SCREENS")
	if folder.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(folder)
	var prefix := "phone-mode-" if app.table_play_only else "desktop-diagnostic-"
	root.get_texture().get_image().save_png(folder.path_join(prefix + name + ".png"))

func _mouse_button(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	event.position = point
	event.global_position = point
	root.push_input(event, true)

func _check_held_hud(label: String, unchanged: Callable, target: Button = null) -> void:
	await process_frame
	if target==null:target=button(label)
	check(is_instance_valid(target) and not target.disabled, label + " is an enabled HUD target")
	if not is_instance_valid(target) or target.disabled:
		return
	var point := target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var presses := []
	target.button_down.connect(func(): presses.append(true), CONNECT_ONE_SHOT)
	_mouse_button(point, true)
	check(presses.size() == 1, label + " receives a real mouse press before Android back")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var overlay: Control = app._leave_overlay
	check(is_instance_valid(overlay), "Android back opens confirmation with the HUD button held")
	_mouse_button(point, false)
	check(app._leave_overlay == overlay and unchanged.call(), label + " cannot act when released under confirmation")
	if is_instance_valid(app._leave_overlay):
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)

func _run() -> void:
	var folder := "user://play-controls-" + str(Time.get_ticks_usec())
	check(DirAccess.make_dir_absolute(folder) == OK, "create isolated test data")
	var path := folder.path_join("profile.cfg")
	app = Main.instantiate()
	app._settings = Settings.new(path)
	check(app._settings.save_profile("操作检查甲乙", 1), "save the test profile")
	root.add_child(app)
	app._show("home")
	# Exercise the optional teaching control after explicitly restoring it in the layout.
	app._table.custom_profile.data.hud.teaching.visible=true
	await process_frame
	if failures:
		await finish(folder, path)
		return
	button("设置").pressed.emit()
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app._screen == "home" and not is_instance_valid(app._leave_overlay), "home settings back never asks to leave a game")
	button("单机").pressed.emit()
	check(await until(func(): return app._round_projection.get("phase") == "dice"), "real solo opening reaches the dice roll")
	check(app._screen == "play" and app._auto_play_button.disabled, "AI delegation is unavailable during the dice roll")
	check(await until(func(): return app._choices().get("actions", []).has("discard")), "real solo opening completes to a human turn")
	if failures:
		await finish(folder, path)
		return
	var host = app._client._host
	var instance: String = app._view.room.room_instance_id
	var prompt: int = app._choices().prompt_id
	var own: int = app._view.seat
	var hand: Array = app._round_projection.players[own].hand.duplicate(true)
	var tile: int = app._choices().discard_ids[0]
	button("开启教打").pressed.emit()
	check(not app._auto_play_active(), "teaching toggle never authorizes automatic play")
	button("关闭教打").pressed.emit()
	check(button("出牌") == null, "the redundant manual discard button is removed in favor of tap/swipe discard")
	app._tile_clicked(tile)
	check(app._order.view().selected_id == tile, "first tap selects a tile before delegation")
	button("AI代打").pressed.emit()
	check(app._auto_play_active() and button("取消代打") != null and app._view.room.seats[own].ai_id == -1, "explicit AI button authorizes the same human seat")
	check(app._tile_action.is_empty() and not app._table_message.text.begins_with("请选择"), "AI delegation clears the old manual selection prompt")
	check(app._buttons.get_children().all(func(control): return control.disabled), "manual action controls are disabled while AI is authorized")
	if not OS.get_environment("DONGXIU_CONTROL_SCREENS").is_empty() and DisplayServer.get_name() != "headless":
		host.set_solo_paused(true)
		await capture("ai-authorized")
		host.set_solo_paused(false)
		check(app._choices().prompt_id == prompt and host._paused_at < 0, "capturing delegation resumes the same solo turn")
	app._submit_action("discard", tile)
	check(app._choices().prompt_id == prompt, "manual discard cannot race an authorized AI decision")
	button("取消代打").pressed.emit()
	check(not app._auto_play_active() and app._buttons.get_children().all(func(control): return not control.disabled), "cancel restores the latest manual buttons without changing the prompt")
	check(app._round_projection.players[own].hand == hand, "immediate cancellation leaves the real hand unchanged")
	await _check_held_hud("设置", func(): return app._screen == "play" and host._paused_at < 0)
	await _check_held_hud("开启教打", func(): return not app._teaching_enabled)
	app._drag_started(tile)
	check(app._order.view().dragged_id == tile, "real hand can be lifted before opening confirmation")
	button("离开").pressed.emit()
	await process_frame
	check(is_instance_valid(app._leave_overlay) and app._client._host == host and app._view.room.room_instance_id == instance, "leave button first opens confirmation and keeps the original session")
	check(app._order.view().dragged_id == -1 and not app._table.is_processing_input() and not app._table.is_processing_unhandled_input(), "confirmation cancels temporary drag and prevents input reaching the table")
	check(root.gui_get_focus_owner() == button("继续打牌"), "safe continue choice is focused")
	app._submit_action("discard", tile)
	app._tile_clicked(tile)
	app._tile_clicked(tile)
	check(app._choices().prompt_id == prompt and app._round_projection.players[own].hand == hand, "modal blocks delayed tile clicks and manual action callbacks")
	await capture("leave-confirmation")
	var overlay = app._leave_overlay
	app._request_leave()
	check(app._leave_overlay == overlay, "repeated leave requests do not stack dialogs")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(not is_instance_valid(app._leave_overlay) and app._client._host == host and app._table.is_processing_input(), "Android back dismisses confirmation without disconnecting")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(is_instance_valid(app._leave_overlay), "Android back from play uses the same confirmation")
	button("继续打牌").pressed.emit()
	check(not is_instance_valid(app._leave_overlay) and app._view.room.room_instance_id == instance, "continue returns to the current game")
	button("设置").pressed.emit()
	check(host._paused_at >= 0, "solo settings retain the existing pause contract")
	app._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app._screen == "play" and host._paused_at < 0 and not is_instance_valid(app._leave_overlay), "settings back resumes solo without leave confirmation")
	app._request_leave()
	var previous_overlay: Control = app._leave_overlay
	app._show("room")
	await process_frame
	check(not is_instance_valid(previous_overlay) and app._screen == "room" and app._view.room.room_instance_id == instance, "switching pages removes the old confirmation without leaving the current match")
	app._update_screen()
	check(app._screen == "play" and app._table.is_processing_input(), "the current round restores its playable screen after the page switch")
	app._request_leave()
	button("离开", app._leave_overlay).pressed.emit()
	await until(func():return app._view.is_empty() and not app._leaving)
	check(app._screen == "connect" and app._view.is_empty() and app._client._host == null, "only confirmed leave closes the solo game and returns to the new lobby")
	await _network_leave()
	await finish(folder, path)

func _network_leave() -> void:
	var authority := Client.new()
	authority.name = "PlayControlsAuthority"
	root.add_child(authority)
	check(authority.start_server("918263", 0, {"difficulty": "low"}, "lan"), "real LAN authority starts")
	authority._host.clock_msec = func(): return raw_ms
	app._mode = "lan"
	var profile: Dictionary = app._profile()
	profile.room_number = "918263"
	app._client.connect_room("127.0.0.1", authority.local_port, profile)
	check(await until(func(): return not app._view.is_empty()), "real Main receives its authenticated LAN seat")
	check(await until(func():return not app._transition.active),"complete actual entry before using room controls")
	await _network_settings_without_speaker_switches(authority, profile.room_number)
	var room_leave: Callable = button("离开房间").pressed.get_connections()[0].callable
	app._client.set_ready(true)
	check(await until(func(): return authority._host._prepare_at >= 0 or authority._host._roll_valid or app._screen == "play"), "LAN preparation begins immediately when all humans are ready")
	check(await until(func(): return app._screen == "play"), "real LAN game reaches the playing screen without waiting delay")
	var instance: String = app._view.room.room_instance_id
	var own: int = app._view.seat
	room_leave.call()
	check(is_instance_valid(app._leave_overlay) and app._view.room.room_instance_id == instance, "a late preparation leave callback asks for confirmation once the game starts")
	if is_instance_valid(app._leave_overlay):
		app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await _check_held_hud("玩家姓名", func(): return not app._voice.recording and not app._voice.microphone_requested(),app._identities[0])
	app._request_leave()
	check(is_instance_valid(app._leave_overlay) and authority._host._connections.size() == 1, "LAN leave confirmation keeps the authenticated connection")
	button("继续打牌").pressed.emit()
	check(app._view.room.room_instance_id == instance and authority._host._paused_at < 0, "cancel keeps the same LAN round and never pauses its authority")
	app._request_leave()
	button("离开", app._leave_overlay).pressed.emit()
	check(await until(func(): return authority._host._connections.is_empty()), "confirmed LAN leave actually disconnects")
	var room: Dictionary = authority._host.public_room()
	check(room.is_empty() and authority._host._closed, "all explicit human departures close the LAN room immediately")
	check(await until(func(): return app._screen == "connect" and not is_instance_valid(app._leave_overlay)), "confirmed LAN leave returns to the LAN list after authority acknowledgement")
	authority.queue_free()
	await process_frame

func _network_settings_without_speaker_switches(authority: Node, number: String) -> void:
	app._open_settings()
	check(app._frame.find_children("*","Label",true,false).all(func(label): return label.text != "收听其他玩家"), "settings remove the separate listener entry")
	var members := []
	for nickname in ["操作检查甲乙", "一二三四五六", "七八九十甲乙"]:
		var peer := Client.new()
		root.add_child(peer)
		members.append(peer)
		peer.connect_room("127.0.0.1", authority.local_port, {"mode": "lan", "room_number": number,
			"player_id": "play-controls-" + nickname, "nickname": nickname})
		check(await until(func(): return not peer.view.is_empty()), "another real member joins while settings are open")
	check(app._frame.find_children("*","CheckButton",true,false).all(func(control): return not control.text.contains("收听")), "joining members do not recreate old listener switches")
	await process_frame
	var card: Control = app._frame.get_child(0)
	check(app._safe.get_global_rect().encloses(card.get_global_rect()), "settings stay inside the current window safe area")
	check(button("保存") != null and button("取消") != null, "save and cancel remain available")
	await capture("settings-without-speaker-switches")
	for peer in members:
		await peer.leave()
		peer.queue_free()
	check(await until(func(): return authority._host._connections.size() == 1), "other members leave before opening the LAN game")
	app.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(app._screen == "room" and authority._host._paused_at < 0, "return from settings preserves the LAN authority")

func finish(folder: String, path: String) -> void:
	check(await AudioRetirement.release_app(app, self), "stopped application audio is released by the mixer")
	DirAccess.remove_absolute(path)
	var muted_path := folder.path_join("dongxiu-muted-players-v1.cfg")
	if FileAccess.file_exists(muted_path):
		DirAccess.remove_absolute(muted_path)
	DirAccess.remove_absolute(folder)
	print("Play controls: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
