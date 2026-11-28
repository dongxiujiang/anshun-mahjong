extends SceneTree

const Main := preload("res://scenes/Main.tscn")
const AudioRetirement := preload("res://tests/AudioRetirement.gd")

var _app
var _screen_dir := ""
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_screen_dir = OS.get_environment("DONGXIU_SMOKE_SCREENS")
	_app = Main.instantiate()
	root.add_child(_app)
	await process_frame
	if _app._screen == "profile_setup":
		await _capture("profile-setup")
		_press("进入大厅")
	_check(_find_button(_app, "单机") != null and _find_button(_app, "创建房间") != null and _find_button(_app, "加入房间") != null, "Solo and online home entrances are present")
	_app._mode = "online"
	_app._voice._status(false, "麦克风权限未开启")
	_app._show_table_notice()
	_check(_app._voice_status_text == "麦克风权限未开启" and _find_button(_app,"开启麦克风")==null, "Actual microphone status is retained without a standalone microphone button")
	_app._mode = "solo"
	_app._refresh_voice_status()
	_check(not _app.editable_hud_controls().has("microphone"), "Solo has no standalone microphone control")
	await _capture("menu")
	_press("设置")
	_check(_app._screen == "settings" and _find_button(_app, "保存") != null, "Settings opens from the live home menu")
	await _capture("settings")
	_press("个人资料")
	_check(_app._screen == "profile_edit", "Profile opens from lobby settings as its own screen")
	await _capture("profile-edit")
	_press("取消")
	_press("取消")
	_press("在线")
	_check(_app._screen == "connect" and _find_button(_app, "创建房间") != null, "Online shows a real directory form")
	_press("加入房间")
	_check(_app._view.is_empty() and _app._status_text.contains("请填写"), "Missing endpoint cannot simulate a joined room")
	var directory := OS.get_environment("DONGXIU_UI_DIRECTORY_TEST_URL")
	if not directory.is_empty():
		await _verify_online(directory)
	_press("返回")
	_press("单机")
	var until := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < until and _app._choices().is_empty():
		await process_frame
	_check(_app._screen == "play" and _app._choices().get("actions", []).has("discard"), "Solo reaches a real human discard prompt")
	if _failures:
		_finish()
		return
	await _capture("solo-turn")
	var first_prompt: int = _app._choices().prompt_id
	var tiles: Array = _app._round_projection.players[int(_app._view.seat)].hand.duplicate(true)
	_press("开启教打")
	var until_hint := Time.get_ticks_msec() + 4500
	while Time.get_ticks_msec() < until_hint and _app._teaching_status.text in ["", "正在分析"]:
		await process_frame
	_check(not _app._teaching_status.text.is_empty() and _app._teaching_status.text != "正在分析", "The real AI returns a teaching hint")
	_check(_app._choices().get("prompt_id", -1) == first_prompt and _app._round_projection.players[int(_app._view.seat)].hand == tiles, "The teaching overlay leaves the real hand and prompt unchanged")
	await _capture("solo-teaching")
	_press("关闭教打")
	var discard_id: int = _app._choices().discard_ids[0]
	var choices: Dictionary = _app._choices()
	var expected_buttons := 0
	for action in choices.actions:
		expected_buttons += choices.get(action + "_ids", []).size() if action in ["concealed_kong", "add_kong"] else 1
	_check(_app._buttons.get_child_count() == expected_buttons, "Action HUD displays precisely the authoritative choices")
	if DisplayServer.get_name() != "headless":
		var point: Vector2 = _app._table.camera.unproject_position(_app._table.tiles[discard_id].global_position)
		_check(_app._table.tile_at(point) == discard_id, "The native camera projects the actual selectable tile")
		await _click_pointer(point)
		_check(_app._order.view().selected_id == discard_id, "The native first tap lifts the actual entity through the viewport")
		await _wait_for_hand()
		point = _app._table.camera.unproject_position(_app._table.tiles[discard_id].global_position)
		await _click_pointer(point)
	else:
		_app._table.tile_clicked.emit(discard_id)
		_check(_app._order.view().selected_id == discard_id, "First tile tap only lifts the actual entity")
		await _wait_for_hand()
		_app._table.tile_clicked.emit(discard_id)
	_check(_app._round_projection.prompt_id > first_prompt and not _app._round_projection.players[int(_app._view.seat)].hand.any(func(face): return face.id == discard_id), "Second tap submits the selected identity to the actual game")
	if OS.get_environment("DONGXIU_SMOKE_SETTLEMENT") == "1":
		await _complete_round()
	_finish()


func _wait_for_hand() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while not _app._table.can_play_hand() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(_app._table.can_play_hand(), "Actual hand animation finishes before the confirming tap")


func _verify_online(address: String) -> void:
	_app._directory_url.text = address
	_press("刷新房间")
	var until := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < until and _app._status_text == "正在读取房间列表…":
		await process_frame
	_check(_app._status_text.is_empty(), "The configured online directory returned a real room list")
	await _capture("online-directory")
	_app._room_number.text = "00" + str(randi_range(1000, 9999))
	_app._online_name.text = "东秀麻将原生窗口验证"
	var number: String = _app._room_number.text
	_press("创建房间")
	until = Time.get_ticks_msec() + 14000
	while Time.get_ticks_msec() < until and _app._screen != "room":
		await process_frame
	_check(_app._screen == "room" and not _app._view.is_empty(), "Online creation connects to the separate ENet authority")
	if _app._screen != "room":
		return
	_check(_app._view.room.room_number == number and _app._settings.remembered_room().mode == "online", "Online join uses the selected room and saves its real recovery ticket")
	await _capture("online-preparation")
	_press("离开房间")
	_press("在线")


func _click_pointer(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point + _app._board.position
		event.global_position = event.position
		root.push_input(event, true)
		await process_frame


func _complete_round() -> void:
	var until := Time.get_ticks_msec() + 85000
	while Time.get_ticks_msec() < until and _app._screen != "settlement":
		var available: Dictionary = _app._choices()
		var actions: Array = available.get("actions", [])
		if actions.has("win"):
			_press("胡")
		elif actions.has("self_win"):
			_press("自摸")
		elif actions.has("pass"):
			_press("过")
		elif actions.has("discard"):
			var id: int = available.discard_ids[0]
			_app._table.tile_clicked.emit(id)
			_app._table.tile_clicked.emit(id)
		await process_frame
	_check(_app._screen == "settlement" and _app._view.get("settlement", {}).get("scores", []).size() == 4, "A real completed round opens the four-seat settlement")
	if _app._screen != "settlement":
		return
	await _capture("solo-settlement")
	_press("提交本局记录")
	_check(not _app._record_status.text.is_empty(), "Record submission reports a real outcome or a queued state")
	_press("返回座位")
	_check(_app._screen == "room" and not _app._view.room.seats[int(_app._view.seat)].ready, "Returning to the room leaves preparation to the player")
	_press("准备")
	_check(_app._view.room.seats[int(_app._view.seat)].ready, "An explicit prepare acts on the real seat")


func _capture(name: String) -> void:
	if _screen_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var shot := root.get_texture().get_image()
	_check(shot != null and not shot.is_empty() and shot.save_png(_screen_dir.path_join(name + ".png")) == OK, "Save native frame " + name)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _press(text: String) -> void:
	var button := _find_button(_app, text)
	_check(button != null and not button.disabled, "The enabled button is reachable " + text)
	if button != null and not button.disabled:
		button.pressed.emit()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)


func _finish() -> void:
	_check(await AudioRetirement.release_app(_app, self), "Stopped application audio is released by the mixer")
	print("Application smoke failures: %d" % _failures)
	quit(_failures)
