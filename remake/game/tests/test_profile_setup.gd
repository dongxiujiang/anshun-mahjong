extends SceneTree

const Main := preload("res://scenes/Main.tscn")
const Client := preload("res://src/network/GameClient.gd")
const Settings := preload("res://src/app/AppSettings.gd")
const Room := preload("res://src/session/RoomSession.gd")
const SettingsPanel := preload("res://src/app/SettingsPanel.gd")
var _app
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var folder := "user://profile-setup-" + str(Time.get_ticks_usec())
	check(DirAccess.make_dir_absolute(folder) == OK, "create isolated cold-start preferences")
	var path := folder.path_join("profile.cfg")
	_start(path)
	await process_frame
	var editor = _app._profile_setup
	check(_app._screen == "profile_setup" and not _app._settings.profile_complete() and _button("单机") == null, "fresh boot requires an explicitly saved profile")
	var picker = editor._picker
	var cards: Array = picker._cards
	check(picker.selected_id == 1 and cards[0].button_pressed and picker._markers[0].visible, "01 and its checkmark are selected by default")
	check(cards.size() == 15 and cards.all(func(card): return not card.accessibility_name.is_empty()), "all 15 voice-named characters are actual selectable controls")
	check(root.gui_get_focus_owner() == cards[0] and cards[0].get_node(cards[0].focus_neighbor_right) == cards[1] and cards[0].get_node(cards[0].focus_neighbor_bottom) == cards[8], "keyboard starts on selected card and follows two rows")
	cards[8].pressed.emit()
	var default_name: String = editor._nickname.text
	_press("随机换名")
	check(picker.selected_id == 9 and picker._markers[8].visible and cards[8].button_pressed and not cards[0].button_pressed and editor._nickname.text != default_name and Room.is_valid_nickname(editor._nickname.text), "random nickname keeps the chosen portrait")
	for invalid in ["", "甲乙丙丁戊己庚", "牌 友", "甲!", "牌😀"]:
		editor._nickname.text = invalid
		_press("保存")
		check(_app._screen == "profile_setup" and not _app._settings.profile_complete() and not editor._error.text.is_empty() and editor._nickname.text == invalid and picker.selected_id == 9, "invalid nickname preserves the full draft")
	editor._nickname.text = "模拟牌友A1"
	editor.fit(Vector2(800, 200), true)
	await process_frame
	var compact: Rect2 = editor.get_global_rect()
	check(not editor._gallery.is_visible_in_tree() and compact.encloses(editor._nickname.get_global_rect()) and compact.encloses(_button("保存").get_global_rect()), "compact keyboard layout keeps nickname and completion within the panel: panel=%s nickname=%s save=%s gallery=%s"%[compact,editor._nickname.get_global_rect(),_button("保存").get_global_rect(),editor._gallery.is_visible_in_tree()])
	editor.fit(Vector2(850, 650), false)
	check(editor._gallery.is_visible_in_tree() and editor._nickname.text == "模拟牌友A1" and picker.selected_id == 9, "closing keyboard layout keeps the draft")
	_app._settings._path = folder.path_join("missing/profile.cfg")
	_press("保存")
	check(_app._screen == "profile_setup" and not _app._settings.profile_complete() and not Settings.new(path).profile_complete() and editor._error.text.contains("保存"), "failed disk write does not confirm onboarding or replace saved profile")
	_app._settings._path = path
	var identity: String = _app._settings.player_id()
	_press("保存")
	check(_app._screen == "connect" and _app._online_results!=null and [_button("单机"), _button("局域网")].all(func(button): return button != null), "successful first save opens online room selection and retains other modes")
	check(Settings.new(path).profile_complete() and Settings.new(path).profile().avatar == 9, "completion flag and avatar were written together")
	await _close()
	_start(path)
	await process_frame
	check(_app._screen == "connect" and _app._settings.player_id() == identity and _app._settings.profile().nickname == "模拟牌友A1", "restart goes straight to lobby with the saved name and identity")
	_press("设置")
	var panel = _settings_panel()
	panel._fields.voice_pack.select(3)
	_press("个人资料")
	editor = _app._profile_setup
	check(_app._screen == "profile_edit" and editor._picker.selected_id == 9 and editor._nickname.text == "模拟牌友A1", "lobby profile editor opens independently with saved values")
	editor._picker._cards[1].pressed.emit()
	editor._nickname.text = "临时"
	_press("取消")
	check(_app._screen == "settings" and _app._settings.profile().avatar == 9 and _app._settings.profile().nickname == "模拟牌友A1" and _settings_panel()._fields.voice_pack.selected == 3, "cancel preserves saved profile and the settings draft")
	_press("个人资料")
	editor = _app._profile_setup
	editor._picker._cards[4].pressed.emit()
	editor._nickname.text = "中"
	_press("保存")
	check(_app._screen == "settings" and _app._settings.profile().nickname == "中" and _app._settings.profile().avatar == 5 and _app._settings.profile().voice_pack == Settings.DEFAULTS.voice_pack, "saving profile returns to settings and leaves voice unchanged")
	_press("保存")
	check(_app._screen == "connect" and _app._settings.profile().voice_pack == "gaoxiaonv" and _app._settings.profile().nickname == "中", "saving voice preference leaves the nickname and character independent")
	_press("单机")
	check(not _app._view.is_empty(), "lobby still starts a real game")
	_app._open_settings()
	check(_app._screen == "settings" and _button("个人资料") == null and _settings_panel()._fields.has("voice_pack"), "room settings allow voice but never profile edits")
	await _close()
	await _check_pending_lan_restore(path)
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	print("Profile setup: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)

func _check_pending_lan_restore(path: String) -> void:
	var authority := Client.new()
	authority.name = "ProfileLanAuthority"
	root.add_child(authority)
	var number := "272601"
	if not authority.start_server(number, 0, {}, "lan"):
		check(false, "start real LAN authority")
		authority.queue_free()
		return
	var previous := Client.new()
	previous.name = "PreviousProfileClient"
	root.add_child(previous)
	var prefs := Settings.new(path)
	var profile := prefs.profile()
	profile.merge({"player_id": prefs.player_id(), "mode": "lan", "room_number": number})
	previous.connect_room("127.0.0.1", authority.local_port, profile)
	if not await _until(func(): return not previous.view.is_empty()):
		check(false, "seed an authenticated LAN seat")
		previous.queue_free()
		authority.queue_free()
		return
	var ticket := previous.ticket.duplicate(true)
	check(prefs.remember_room(ticket), "persist actual LAN recovery ticket")
	previous._reset() # Preserve the original seat for the authenticated recovery scenario.
	check(await _until(func(): return authority._host._connections.is_empty()), "original client disconnects while LAN authority stays up")
	previous.queue_free()
	multiplayer_poll = false
	_start(path)
	check(await _until(func(): return _app._restoring), "startup begins real LAN recovery with ENet polling delayed")
	check(_app._screen == "connect" and _app._view.is_empty(), "delayed recovery has no seat projection yet")
	_press("设置")
	multiplayer_poll = true
	for frame in 8:
		await process_frame
	check(_app._screen == "settings" and not _app._restoring and _app._client._peer == null and _app._view.is_empty(), "opening lobby settings cancels the LAN connection before a view arrives")
	check(_button("个人资料") != null and _app._settings.remembered_room() == ticket, "cancellation keeps the ticket and lobby edit permission")
	_app._client.connect_room("127.0.0.1", authority.local_port, profile, ticket)
	check(await _until(func(): return not _app._view.is_empty()), "a later real authenticated snapshot can still arrive while settings are open")
	_press("个人资料")
	check(_app._screen == "settings" and _button("个人资料") == null and _app._settings.profile().nickname == profile.nickname, "stale lobby settings cannot open a profile editor after the room view arrives")
	await _close()
	authority.queue_free()
	await process_frame

func _until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 3000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
		OS.delay_msec(1)
	return predicate.call()

func _start(path: String) -> void:
	_app = Main.instantiate()
	_app._settings = Settings.new(path)
	root.add_child(_app)

func _close() -> void:
	_app.queue_free()
	await process_frame

func _settings_panel() -> SettingsPanel:
	for child in _app.find_children("*", "VBoxContainer", true, false):
		if child is SettingsPanel:
			return child
	return null

func _button(label: String) -> Button:
	for child in _app.find_children("*", "Button", true, false):
		if child.is_visible_in_tree() and child.text == label:
			return child
	return null

func _press(label: String) -> void:
	var button := _button(label)
	if is_instance_valid(button):
		button.pressed.emit()
	else:
		check(false, "find visible button " + label)

func check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr(description)
