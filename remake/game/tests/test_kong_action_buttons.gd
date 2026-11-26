extends SceneTree

const Main = preload("res://scenes/Main.tscn")
const Settings = preload("res://src/app/AppSettings.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Wall = preload("res://src/domain/Wall.gd")
const TileArt = preload("res://src/presentation/TileArt.gd")
const AudioRetirement = preload("res://tests/AudioRetirement.gd")

var _app
var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL kong buttons: ", message)

func _run() -> void:
	var folder := "user://kong-buttons-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_absolute(folder)
	var profile := folder.path_join("profile.cfg")
	_app = Main.instantiate()
	_app._settings = Settings.new(profile)
	_check(_app._settings.save_profile("杠牌检查", 1), "isolated profile is saved")
	root.add_child(_app)
	await process_frame
	var solo: Button
	for button in _app.find_children("*", "Button", true, false):
		if button.text == "单机":
			solo = button
			break
	_check(is_instance_valid(solo), "the real lobby offers solo play")
	if not is_instance_valid(solo):
		await _finish(folder, profile)
		return
	_click(solo)
	var host = _app._client._host
	_check(is_instance_valid(host), "solo button starts the real local authority")
	if not is_instance_valid(host):
		await _finish(folder, profile)
		return
	# Change only the test's wall. The real dice, deal, draw, presentation and action submit still run.
	host._dice.result_ready.disconnect(host._dice_settled)
	host._dice.result_ready.connect(func(red: int, _white: int):
		host._roll_valid = false
		host._last_locked_dice = host._dice.snapshot()
		_check(host._session.start_round(host._dice, _deck(red), host._now(), 1), "real dice starts a legal fixed-wall round")
		host._refresh(), CONNECT_ONE_SHOT)
	await _until(func(): return _app._choices().get("concealed_kong_ids", []).size() == 2)
	var choices: Dictionary = _app._choices()
	_check(choices.get("concealed_kong_ids", []).size() == 2, "authority offers two distinct concealed kongs on the same turn")
	if _failures:
		await _finish(folder, profile)
		return

	var round_state = host._session._round
	var wan_id := _option_id(round_state, choices, "wan9")
	var tong_id := _option_id(round_state, choices, "tong6")
	var wan := _kong_button("wan9")
	var tong := _kong_button("tong6")
	var buttons: Array = _app._buttons.get_children()
	_check(buttons.filter(func(button): return button.text == "暗杠").size() == 2, "there are exactly two concealed-kong buttons")
	_check(is_instance_valid(wan) and is_instance_valid(tong) and wan != tong, "each button uses the corresponding existing small tile image")
	if _failures:
		await _finish(folder, profile)
		return
	await process_frame
	_check(not wan.disabled and not tong.disabled and not wan.get_global_rect().intersects(tong.get_global_rect()), "both candidates have separate enabled hit areas")
	_check(wan.tooltip_text == "9万暗杠" and wan.accessibility_name == wan.tooltip_text and tong.tooltip_text == "6筒暗杠" and tong.accessibility_name == tong.tooltip_text, "tooltip and accessibility names distinguish the two values")
	var first_prompt: int = choices.prompt_id
	var now: int = host._now()
	host.clock_msec = func(): return now
	await _capture()

	var reversed: Array = _app._order.view().slots.duplicate()
	reversed.reverse()
	_app._order.apply_auto_slots(reversed)
	_app._apply_order()
	_check(not _app._table.own_hand_stable() and _app._choices().concealed_kong_ids == choices.concealed_kong_ids, "the own hand moves during the same legal authority window")
	await process_frame
	tong = _kong_button("tong6")
	_check(tong.disabled and _app._buttons.get_children().all(func(button): return button.disabled), "own-turn action buttons are disabled while the hand moves")
	var point := tong.get_global_rect().get_center()
	_mouse(point, true)
	_app._pick_kong("concealed_kong", tong_id, first_prompt)
	_app._submit_action("concealed_kong", tong_id)
	_app._pick_action("discard")
	_check(_last_submit(host).is_empty() and _app._tile_action.is_empty(), "action callbacks cannot submit or preselect before landing")
	await _until(func(): return _app._table.own_hand_stable() and not _kong_button("tong6").disabled)
	_mouse(point, false)
	_check(_last_submit(host).is_empty(), "a press begun during movement cannot submit on release after landing")
	wan = _kong_button("wan9")
	tong = _kong_button("tong6")
	_check(not wan.disabled and not tong.disabled, "both legal choices return as soon as the hand lands")

	_app._order.tap(wan_id)
	_app._apply_order()
	_click(tong)
	var submitted := _last_submit(host)
	_check(submitted.get("action") == "concealed_kong" and submitted.get("tile_id") == tong_id and submitted.get("prompt_id") == first_prompt, "clicking six dots submits its own entity ID even with nine characters selected")
	_check(round_state.players[1].melds.any(func(meld): return meld.tile == "tong6" and meld.concealed) and _app._tile_action.is_empty(), "the first click immediately declares the chosen kong")
	wan.pressed.emit()
	_check(_last_submit(host) == submitted, "an old callback from the previous prompt cannot declare the other kong")
	await _until(func(): return _app._choices().get("concealed_kong_ids", []).has(wan_id))
	wan = _kong_button("wan9")
	_check(is_instance_valid(wan) and _kong_button("tong6") == null, "after the replacement draw only the still-legal kong is offered")
	if is_instance_valid(wan):
		await process_frame
		_click(wan)
		_check(_last_submit(host).get("tile_id") == wan_id and round_state.players[1].melds.any(func(meld): return meld.tile == "wan9" and meld.concealed), "the remaining button submits the other physical ID")
	await _finish(folder, profile)

func _deck(red: int) -> Array:
	var stock := Catalog.values(7234)
	var wall := Wall.new(stock)
	wall.open(1, red)
	var fixed := {}
	for value in ["wan9", "tong6"]:
		for i in 4:
			fixed[wall.take_head()] = value
			stock.erase(value)
		for i in 12:
			wall.take_head()
	var cards := []
	for id in range(Catalog.COUNT):
		cards.append(fixed[id] if fixed.has(id) else stock.pop_back())
	return cards

func _option_id(round_state, choices: Dictionary, value: String) -> int:
	for id in choices.concealed_kong_ids:
		if round_state.wall.value(id) == value:
			return int(id)
	return -1

func _kong_button(value: String) -> Button:
	for button in _app._buttons.get_children():
		if button.text == "暗杠" and button.icon == TileArt.face(value):
			return button
	return null

func _last_submit(host) -> Dictionary:
	var inputs: Array = host._session._record._data.inputs
	for index in range(inputs.size() - 1, -1, -1):
		var entry: Dictionary = inputs[index]
		if entry.type == "submit":
			return entry
	return {}

func _until(predicate: Callable) -> void:
	for frame in 1800:
		if predicate.call():
			return
		await process_frame

func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	_mouse(point, true)
	_mouse(point, false)

func _mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	root.push_input(event, true)

func _capture() -> void:
	var folder := OS.get_environment("DONGXIU_KONG_BUTTON_SCREENS")
	if folder.is_empty() or DisplayServer.get_name() == "headless":
		return
	await _until(func(): return _app._table._opening == null and _app._table._motions.is_empty())
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var filename := "kong-buttons-%dx%d.png" % [image.get_width(), image.get_height()]
	var made := DirAccess.make_dir_recursive_absolute(folder)
	_check(made == OK and image.save_png(folder.path_join(filename)) == OK, "save the native multi-kong HUD")

func _finish(folder: String, profile: String) -> void:
	_app._back_home()
	_check(await AudioRetirement.release_app(_app, self), "stopped application audio is released")
	DirAccess.remove_absolute(profile)
	DirAccess.remove_absolute(folder.path_join("dongxiu-muted-players-v1.cfg"))
	DirAccess.remove_absolute(folder)
	print("Kong action buttons: ", _checks, " checks, ", _failures, " failures")
	quit(1 if _failures else 0)
