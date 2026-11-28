extends RefCounted

const UI := preload("res://src/app/AppTheme.gd")
const CharacterArt := preload("res://src/app/CharacterArt.gd")
const SettingsPanel := preload("res://src/app/SettingsPanel.gd")
const ProfileSetup := preload("res://src/app/ProfileSetup.gd")
const PlayerBadge := preload("res://src/app/PlayerBadge.gd")
const CareerPanel := preload("res://src/app/CareerPanel.gd")
const MotionConfig := preload("res://src/presentation/MotionConfig.gd")
const TurnClockView := preload("res://src/app/TurnClockView.gd")
const SettlementView := preload("res://src/app/SettlementView.gd")
const RoomBrowser := preload("res://src/app/RoomBrowser.gd")
const WINDS := ["东", "南", "西", "北"]
const MODE_NAMES := {"solo": "单机", "online": "在线"}

static func menu_theme() -> Theme:
	var result := UI.menu_theme()
	if not MotionConfig.value("panel", "shadow_enabled"):
		for type in result.get_type_list():
			for key in result.get_stylebox_list(type):
				var box := result.get_stylebox(key, type) as StyleBoxFlat
				if box:
					box.shadow_size = 0
	return result


static func build_home(app) -> void:
	app._mode = "online"
	build_connection(app)


static func build_career(app) -> void:
	var content = app._panel(960)
	var career = CareerPanel.new()
	content.add_child(career)
	career.build(app._progress, app._settings.profile().nickname)
	career.closed.connect(func(): app._show(app._before_career))



static func build_connection(app) -> void:
	var content := _lobby_page(app)
	var profile: Dictionary = app._settings.profile()
	var title := _toolbar(content)
	title.set_meta("page_id", "lobby_navigation")
	var streak := int(app._progress.stats.streak)
	var identity := UI.button("%s · %s%s" % [profile.nickname, app._progress.rank_title(),
		" · %d连胜" % streak if streak >= 2 else ""], app._open_profile_from_lobby)
	identity.icon = CharacterArt.avatar(profile.avatar)
	identity.add_theme_constant_override("icon_max_width", 28)
	identity.add_theme_font_size_override("font_size", 16)
	title.add_child(identity)
	_heading(title, "东秀麻将 · 安顺捉鸡")
	title.add_child(UI.button("战绩", app._open_career))
	title.add_child(UI.button("设置", app._open_settings))
	app._lobby_update_button = UI.button("更新", app._open_update_dialog.bind(true))
	title.add_child(app._lobby_update_button)
	app._update_state_changed(app._update_manager.snapshot())

	var center := CenterContainer.new()
	app._lobby_home = center
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(center)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 20)
	center.add_child(cards)
	var solo := _mode_card(cards, "单机开局", "随时开搓 · 完整安顺捉鸡", true)
	var solo_button := UI.button("单机", app._choose_mode.bind("solo"), true)
	solo.add_child(solo_button)
	var online := _mode_card(cards, "在线茶馆", "当前开放 0 桌")
	app._online_count = online.get_child(1)
	online.add_child(UI.button("创建房间", app._create_online, true))
	var links := _toolbar(online)
	links.add_child(UI.button("加入房间", app._open_join_dialog))
	links.add_child(UI.button("浏览牌桌", app._set_browser_visible.bind(true)))
	for action in links.get_children():
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var tools := _toolbar(content)
	app._lobby_tools = tools
	tools.add_child(UI.button("← 返回首页", app._set_browser_visible.bind(false)))
	tools.add_child(UI.button("单机", app._choose_mode.bind("solo")))
	tools.add_spacer(false)
	tools.add_child(UI.button("创建房间", app._create_online, true))
	tools.add_child(UI.button("加入房间", app._open_join_dialog))
	tools.add_child(UI.button("刷新房间", app._search_online))

	app._online_results = _browser(app, content, "创建房间邀请好友，或返回首页开始单机对局")
	var footer := _toolbar(content)
	app._add_status(footer)
	var drawer := Drawer.new()
	app._online_options = drawer
	content.add_child(drawer)
	drawer.add_toggle(tools)
	drawer.add_toggle(footer)
	var fields := drawer.fields
	app._online_name = app._entry(fields, "新房间名称", "")
	app._online_name.text = profile.nickname + "麻将局"
	app._online_name.max_length = 24
	app._online_filter = app._entry(fields, "筛选房间", "房间号或名称")
	app._online_filter.text_changed.connect(func(_text): app._draw_online_rooms())
	app._room_number = app._entry(fields, "房间号", "4–8 位数字")
	app._directory_url = app._entry(fields, "服务地址", "HTTPS 在线房间服务")
	app._directory_url.text = app._online_url()
	app._add_host_clocks(fields)
	app._set_browser_visible(false, false)
	app._refresh_online(app._online_rooms)
	if not app._directory_url.text.is_empty():
		app._search_online()
	if center.visible:
		UI.MotionFX.animate_stagger_children(cards.get_children())



static func _focus_when_ready(target: WeakRef) -> void:
	var control: Control = target.get_ref()
	if is_instance_valid(control) and control.is_visible_in_tree() and control.get_focus_mode_with_override() != Control.FOCUS_NONE:
		control.grab_focus()


static func _lobby_page(app) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.theme = menu_theme()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22 if side in ["left", "right"] else 10)
	app._frame.add_child(margin)
	var content := VBoxContainer.new()
	margin.add_child(content)
	app._page_content = content
	app._fit_menu_panel()
	return content


static func _toolbar(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row


static func _heading(row: HBoxContainer, caption: String) -> void:
	var heading := UI.label(caption, 24, UI.GOLD_BRIGHT)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(heading)


static func _mode_card(parent: Control, caption: String, hint: String, featured := false) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 248)
	var shadow := 7 if MotionConfig.value("panel", "shadow_enabled") else 0
	panel.add_theme_stylebox_override("panel", UI.elevated_card(
		Color("#28382aeb") if featured else Color("#112d25e8"), 16, 18,
		UI.GOLD_BORDER if featured else UI.BORDER, 1, shadow))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	column.add_child(UI.label(caption, 26, UI.GOLD_BRIGHT if featured else UI.INK))
	column.add_child(UI.label(hint, 16, UI.MUTED))
	column.add_spacer(false)
	return column


static func _browser(app, parent: Control, hint: String) -> RoomBrowser:
	var browser := RoomBrowser.new()
	browser.empty_hint = hint
	browser.set_meta("page_id", "room_browser")
	browser.set_meta("page_label", "房间列表")
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.seat_selected.connect(app._select_room_seat)
	browser.inspection_requested.connect(app._inspect_endpoint)
	parent.add_child(browser)
	browser.apply_quality(MotionConfig.current_quality)
	return browser


class Drawer extends Control:
	var fields := GridContainer.new()
	var expanded := false
	var toggles: Array[Button] = []
	var motion: Tween

	func _ready() -> void:
		clip_contents = true
		fields.columns = 4
		add_child(fields)
		fields.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		hide()

	func add_toggle(row: Control) -> void:
		var button := UI.button("详细设置 ▾", func(): set_expanded(not expanded))
		toggles.append(button)
		row.add_child(button)

	func set_expanded(open: bool) -> void:
		if expanded == open:
			return
		expanded = open
		if motion:
			motion.kill()
		for button in toggles:
			button.text = "收起设置 ▴" if open else "详细设置 ▾"
		var spec := MotionConfig.section("panel")
		focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED if open else FOCUS_BEHAVIOR_DISABLED
		mouse_behavior_recursive = MOUSE_BEHAVIOR_INHERITED if open else MOUSE_BEHAVIOR_DISABLED
		if not visible:
			modulate.a = 0.0
		show()
		motion = create_tween().set_parallel(true).set_trans(spec.ease_trans).set_ease(Tween.EASE_OUT)
		motion.tween_property(self, "custom_minimum_size:y", fields.get_combined_minimum_size().y if open else 0.0, spec.drawer_duration)
		motion.tween_property(self, "modulate:a", 1.0 if open else 0.0, spec.drawer_duration)
		if not open:
			motion.finished.connect(hide)


class JoinDialog extends Control:
	signal submitted(number: String)
	var panel := PanelContainer.new()
	var shade := ColorRect.new()
	var number := LineEdit.new()
	var opened := false
	var previous_focus: Control
	var background: Control
	var valid_number: Callable

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(shade)
		shade.color = Color.BLACK
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.gui_input.connect(func(event: InputEvent):
			if opened and ((event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)):
				close())
		var holder := MarginContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# On Android/mobile, float the modal cleanly in the upper band so docked or floating numeric IME never obscures the input.
		var mobile := OS.has_feature("mobile")
		holder.add_theme_constant_override("margin_top", 56 if mobile else 0)
		var align_box := VBoxContainer.new()
		align_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		align_box.alignment = BoxContainer.ALIGNMENT_BEGIN if mobile else BoxContainer.ALIGNMENT_CENTER
		holder.add_child(align_box)
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		align_box.add_child(center)
		center.add_child(panel)
		panel.add_theme_stylebox_override("panel", UI.elevated_card(UI.PANEL, 16, 18, UI.GOLD_BORDER, 1,
			10 if MotionConfig.value("panel", "shadow_enabled") else 0))
		var row := HBoxContainer.new()
		panel.add_child(row)
		number.placeholder_text = "4–8 位数字房间号"
		number.accessibility_name = "房间号"
		number.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		number.max_length = 8
		number.custom_minimum_size = Vector2(220, 54)
		row.add_child(number)
		var cancel := UI.button("取消", close)
		var join := UI.button("立即加入", func(): submit(number.text), true)
		join.disabled = true
		number.text_changed.connect(func(value): join.disabled = not valid_number.call(value))
		row.add_child(cancel)
		row.add_child(join)
		number.text_submitted.connect(submit)
		for pair in [[number, cancel], [cancel, join], [join, number]]:
			pair[0].focus_next = pair[0].get_path_to(pair[1])
			pair[1].focus_previous = pair[1].get_path_to(pair[0])

	func open() -> void:
		if not opened:
			previous_focus = get_viewport().gui_get_focus_owner()
		opened = true
		background.mouse_behavior_recursive = MOUSE_BEHAVIOR_DISABLED
		background.focus_behavior_recursive = FOCUS_BEHAVIOR_DISABLED
		mouse_behavior_recursive = MOUSE_BEHAVIOR_INHERITED
		focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED
		show()
		UI.MotionFX.animate_modal_in(panel, shade)
		number.grab_focus()

	func submit(value: String) -> void:
		if not opened:
			return
		if not valid_number.call(value):
			number.select_all()
			number.placeholder_text = "请输入 4–8 位数字"
			number.grab_focus()
			return
		close()
		submitted.emit(value)

	func close() -> void:
		if not opened:
			return
		opened = false
		if OS.has_feature("mobile"):
			DisplayServer.virtual_keyboard_hide()
		focus_behavior_recursive = FOCUS_BEHAVIOR_DISABLED
		mouse_behavior_recursive = MOUSE_BEHAVIOR_DISABLED
		background.mouse_behavior_recursive = MOUSE_BEHAVIOR_INHERITED
		background.focus_behavior_recursive = FOCUS_BEHAVIOR_INHERITED
		if is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree():
			previous_focus.grab_focus()
		else:
			for action in background.find_children("*", "Button", true, false):
				if action.text == "加入房间" and action.is_visible_in_tree():
					action.grab_focus()
					break
		UI.MotionFX.animate_modal_out(panel, shade, hide)

	func _input(event: InputEvent) -> void:
		if opened and event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			close()


static func entry(app, fields: GridContainer, label: String, hint: String) -> LineEdit:
	fields.add_child(UI.label(label))
	var field = LineEdit.new()
	field.custom_minimum_size.y = 48
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.placeholder_text = hint
	field.accessibility_name = label
	fields.add_child(field)
	return field



static func add_host_clocks(app, fields: GridContainer) -> void:
	var profile = app._settings.profile()
	app._discard_seconds = app._seconds_field(fields, "主出牌时限（秒）", profile.discard_seconds)
	app._response_seconds = app._seconds_field(fields, "响应时限（秒）", profile.response_seconds)



static func seconds_field(app, fields: GridContainer, title: String, seconds: int) -> SpinBox:
	fields.add_child(UI.label(title))
	var field = SpinBox.new()
	field.min_value = 1
	field.max_value = 120
	field.step = 1
	field.value = seconds
	field.accessibility_name = title
	field.custom_minimum_size.y = 48
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(field)
	return field



static func build_room(app) -> void:
	var content = app._panel(780)
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	content.add_child(header)
	app._room_name = UI.label("", 26, UI.GOLD_BRIGHT)
	app._room_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(app._room_name)
	var set_btn = UI.button("设置", app._open_settings)
	set_btn.custom_minimum_size = Vector2(82, 42)
	set_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(set_btn)

	var divider = ColorRect.new()
	divider.custom_minimum_size.y = 1
	divider.color = Color("#b9954c44")
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)

	var positions = GridContainer.new()
	positions.columns = 3
	positions.add_theme_constant_override("h_separation", 12)
	positions.add_theme_constant_override("v_separation", 12)
	content.add_child(positions)
	app._seat_choices.resize(4)
	for slot in [-1, 3, -1, 2, -2, 0, -1, 1, -1]:
		if slot == -1:
			var space = Control.new()
			space.mouse_filter = Control.MOUSE_FILTER_IGNORE
			positions.add_child(space)
			continue
		if slot == -2:
			var center_card = PanelContainer.new()
			center_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			center_card.add_theme_stylebox_override("panel", UI.card(Color("#0c1f1ae0"), 12, 10, Color("#496e5d"), 1))
			var center_col = VBoxContainer.new()
			center_col.alignment = BoxContainer.ALIGNMENT_CENTER
			center_col.add_theme_constant_override("separation", 2)
			center_card.add_child(center_col)
			var c_title = UI.label("东秀牌桌", 17, UI.GOLD)
			c_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			center_col.add_child(c_title)
			var c_sub = UI.label("人齐准备即开局", 13, UI.MUTED)
			c_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			center_col.add_child(c_sub)
			positions.add_child(center_card)
			continue
		var target = UI.button("", app._move_seat.bind(slot))
		target.custom_minimum_size = Vector2(216, 76)
		target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target.expand_icon = true
		target.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		target.add_theme_font_size_override("font_size", 16)
		target.add_theme_color_override("font_disabled_color", UI.INK)
		positions.add_child(target)
		app._seat_choices[slot] = target
	var controls = HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	content.add_child(controls)
	var leave_btn = UI.button("离开房间", app._request_leave)
	leave_btn.custom_minimum_size = Vector2(128, 46)
	controls.add_child(leave_btn)
	var filler = Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(filler)
	app._ready_button = UI.button("准备", app._toggle_ready, true)
	app._ready_button.custom_minimum_size = Vector2(160, 48)
	controls.add_child(app._ready_button)
	UI.focus_later(app._ready_button)
	app._add_status(content)
	app._refresh_room()



static func refresh_room(app) -> void:
	var room: Dictionary = app._view.get("room", {})
	if room.is_empty() or not is_instance_valid(app._room_name):
		return
	var mine = int(app._view.seat)
	var subtitle = "%s · 房间 %s" % [MODE_NAMES.get(app._mode, ""), room.room_number]
	app._room_name.text = subtitle
	var dealer = int(room.get("next_dealer_seat", -1))
	for seat in 4:
		var member: Dictionary = room.seats[seat]
		var occupied = int(member.ai_id) < 0
		var badge = "可换入" if not occupied else ("暂离" if member.get("away", not member.connected) else ("已准备" if member.ready else "未准备"))
		if seat == mine:
			badge = "我 · " + badge
		var owner: String = member.nickname if occupied else "人机"
		var dealer_text = " · 庄" if seat == dealer else ""
		var button = app._seat_choices[seat]
		button.text = "%s家  %s%s\n%d 分 · %s" % [WINDS[seat], owner, dealer_text, int(member.score), badge]
		button.icon = CharacterArt.avatar(int(member.get("avatar", 1))) if occupied else null
		button.disabled = occupied
		if seat == mine:
			button.add_theme_stylebox_override("disabled", UI.elevated_card(Color("#193b30"), 12, 10, UI.GOLD_BORDER, 2, 4 if MotionConfig.value("panel", "shadow_enabled") else 0))
		elif occupied and member.ready:
			button.add_theme_stylebox_override("disabled", UI.card(Color("#16352b"), 12, 10, Color("#6e9e84"), 1))
		elif occupied:
			button.add_theme_stylebox_override("disabled", UI.card(Color("#132a23"), 12, 10, Color("#496e5e"), 1))
		else:
			button.remove_theme_stylebox_override("disabled")
	var countdown = int(room.get("preparation_remaining_ms", -1))
	if room.get("requires_start", false):
		app._ready_button.text = "开始" if room.seats[mine].player_id == room.owner_player_id else "等待房主开始"
		app._ready_button.disabled = room.seats[mine].player_id != room.owner_player_id
	else:
		app._ready_button.disabled = false
		app._ready_button.text = "取消准备" if room.seats[mine].ready else "准备"
	if countdown > 0:
		app._ready_button.text = "即将开局…"



static func build_profile_setup(app, first: bool) -> void:
	var editor = ProfileSetup.new()
	editor.theme=menu_theme()
	app._frame.add_child(editor)
	editor.resized.connect(app._queue_hud_layout)
	editor.build(app._settings.profile(), first)
	app._profile_setup = editor
	editor.cancelled.connect(func(): app._show(app._before_profile))
	editor.saved.connect(func(nickname, avatar):
		if app._profile_setup != editor:
			return
		if not first and not app._can_edit_profile():
			app._show(app._before_profile)
			return
		if not app._settings.save_profile(nickname, avatar):
			editor.show_error("资料未能保存，请重试。")
			return
		if first:
			app._enter_home()
		else:
			app._show(app._before_profile)
	)



static func build_settings(app) -> void:
	var content = app._panel(960)
	var settings_view = SettingsPanel.new()
	app._room_settings_panel = settings_view
	content.add_child(settings_view)
	var profile = app._settings.profile()
	profile.merge(app._settings_draft, true)
	app._settings_draft.clear()
	settings_view.build(profile, app._can_edit_profile())
	settings_view.check_update_requested.connect(app._open_update_dialog.bind(true))
	app._sync_room_settings()
	settings_view.edit_profile_requested.connect(func():
		if app._screen != "settings":
			return
		app._settings_draft = settings_view.values()
		app._before_profile = "settings"
		app._show("profile_edit" if app._can_edit_profile() else "settings")
	)
	settings_view.cancelled.connect(app._close_settings)
	settings_view.table_requested.connect(app._close_settings)
	settings_view.saved.connect(func(values):
		var personal: Dictionary = values.duplicate(true)
		if values.quality != app._settings.profile().quality:
			personal["quality_manual"] = true
		if not app._view.is_empty():
			personal.erase("difficulty")
			if app._can_edit_room_settings() and not app._client.set_difficulty(values.difficulty):
				settings_view.show_error("房间设置未能发送，请确认连接后重试。")
				return
		if not app._settings.update(personal):
			settings_view.show_error("保存失败，请重试。")
			return
		app._cancel_sort()
		app._restore_scope = {}
		app._order.set_suit_order(values.suit_order)
		app._teaching_enabled=values.get("teaching_enabled",false)
		app._teaching_button.text="关闭教打" if app._teaching_enabled else "开启教打"
		if not app._teaching_enabled:
			if is_instance_valid(app._teaching):app._teaching.cancel()
			app._teaching_status.text=""
		app._apply_sound(app._settings.profile())
		app._apply_quality(values.quality)
		app._apply_power_save(values.power_save)
		app._apply_table_theme(app._settings.profile())
		if is_instance_valid(app._client) and not app._view.is_empty():
			app._client.set_draw_style(values.draw_style)
			app._client.set_player_profile(values)
		if not app._round_projection.is_empty():
			app._arrange_hand(app._round_projection)
			app._apply_order()
		app._refresh_smart_assist()
		app._close_settings()
		app._request_teaching()
	)
	if not app._view.is_empty() and int(app._view.room.round_number) > 0:
		settings_view.content.add_child(app._record_controls())
	app._add_status(settings_view.content)
	app._sync_settings_operation()


static func build_hud(app) -> void:
	app._hud = Control.new()
	app._hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app._safe.add_child(app._hud)
	app._hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var nav = HBoxContainer.new()
	app._navigation=nav
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.add_theme_constant_override("separation", 6)
	app._hud.add_child(nav)
	nav.add_child(UI.button("设置", app._open_settings))
	var leave_button := UI.button("离开", app._request_leave)
	leave_button.add_theme_stylebox_override("normal", UI.card(Color("#2a1619e6"), 11, 12, Color("#8c4a50"), 1))
	leave_button.add_theme_stylebox_override("hover", UI.card(Color("#3a1d21f2"), 11, 12, Color("#b55c63"), 1))
	leave_button.add_theme_stylebox_override("pressed", UI.card(Color("#201012f2"), 11, 12, Color("#8c4a50"), 1))
	leave_button.add_theme_color_override("font_hover_color", UI.INK)
	nav.add_child(leave_button)
	app._auto_play_button = UI.button("AI代打", app._toggle_auto_play)
	nav.add_child(app._auto_play_button)
	var banner := Button.new()
	app._auto_play_banner = banner
	banner.text = "AI 托管中 · 点此恢复手动"
	banner.z_index = 12
	banner.add_theme_stylebox_override("normal", UI.elevated_card(Color("#243a25f5"), 20, 6, Color("#d9ad57"), 2, 4))
	banner.add_theme_stylebox_override("hover", UI.card(Color("#35492af5"), 20, 6, Color("#ffe195"), 2))
	banner.add_theme_stylebox_override("pressed", UI.card(Color("#172e22f5"), 20, 6, Color("#d9ad57"), 2))
	banner.add_theme_color_override("font_color", Color("#ffe5a3"))
	banner.pressed.connect(app._toggle_auto_play)
	banner.hide()
	app._hud.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	banner.offset_left = -148
	banner.offset_right = 148
	banner.offset_top = -182
	banner.offset_bottom = -142
	app._wall_pill = PanelContainer.new()
	app._wall_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app._wall_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	app._wall_pill.add_theme_stylebox_override("panel", UI.card(Color("#0c241ee8"), 10, 6, Color("#b9954c"), 1))
	app._wall_count_label = UI.label("余 108 张", 14, Color("#f4e5bc"))
	app._wall_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app._wall_pill.add_child(app._wall_count_label)
	app._wall_pill.hide()
	nav.add_child(app._wall_pill)
	app._teaching_button = UI.button("关闭教打" if app._teaching_enabled else "开启教打", app._toggle_teaching)
	app._teaching_button.visible = is_instance_valid(app._teaching)
	nav.add_child(app._teaching_button)
	for control in nav.get_children():
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nav.resized.connect(app._queue_hud_layout);nav.minimum_size_changed.connect(app._queue_hud_layout)

	# 排序 / 恢复排序独立放置于右下角拇指舒适区，不再挤在左上导航或左下窄角
	app._sort_button = UI.button("排序", app._sort_hand)
	app._sort_button.custom_minimum_size = Vector2(88, 38)
	app._sort_button.tooltip_text = "循环查看有效排法；可以自摸时点击会放弃本次自摸"
	app._hud.add_child(app._sort_button)
	app._sort_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	app._sort_button.offset_left = -96; app._sort_button.offset_right = -8; app._sort_button.offset_top = -94; app._sort_button.offset_bottom = -56

	app._restore_button = UI.button("恢复排序", app._restore_hand_order)
	app._restore_button.custom_minimum_size = Vector2(88, 38)
	app._restore_button.tooltip_text = "恢复默认牌序"
	app._hud.add_child(app._restore_button)
	app._restore_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	app._restore_button.offset_left = -96; app._restore_button.offset_right = -8; app._restore_button.offset_top = -48; app._restore_button.offset_bottom = -10
	app._restore_button.hide()

	# 倒计时钟彻底脱离动态文本容器，独立锚定固定位置，绝不随提示文字显隐跳动
	app._clock_face = TurnClockView.new()
	app._hud.add_child(app._clock_face)
	app._clock_face.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	app._clock_face.offset_left = -82; app._clock_face.offset_right = -14; app._clock_face.offset_top = -34; app._clock_face.offset_bottom = 34
	app._clock_face.hide()

	var notice = VBoxContainer.new()
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app._hud.add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	notice.offset_left = -242
	notice.offset_top = 7
	app._timer = UI.label("", 32)
	app._timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_child(app._timer)
	app._timer.hide()
	app._table_message = UI.label("", 16)
	app._table_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_child(app._table_message)
	app._teaching_status = UI.label("", 17, UI.INK)
	app._teaching_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app._teaching_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.add_child(app._teaching_status)
	app._sort_status = UI.label("", 16, UI.INK)
	app._sort_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	app._sort_status.max_lines_visible = 2
	app._sort_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_child(app._sort_status)
	app._sort_status.hide()
	for anchor in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_CENTER_RIGHT, Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_LEFT]:
		var badge = PlayerBadge.new()
		app._hud.add_child(badge)
		badge.set_anchors_and_offsets_preset(anchor)
		if anchor == Control.PRESET_CENTER_TOP:
			badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
			badge.offset_left = -80
			badge.offset_right = 80
		elif anchor == Control.PRESET_BOTTOM_LEFT:
			badge.offset_top = -68
			badge.offset_right = 170
		elif anchor == Control.PRESET_CENTER_RIGHT:
			badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			badge.offset_left = -130
			badge.offset_top = -31
			badge.offset_bottom = 31
		else:
			badge.offset_right = 130
			badge.offset_top = -31
			badge.offset_bottom = 31
		badge.player_pressed.connect(app._identity_pressed)
		badge.resized.connect(app._queue_hud_layout)
		app._identities.append(badge)
	app._buttons = HBoxContainer.new()
	app._buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	app._buttons.alignment = BoxContainer.ALIGNMENT_END
	app._hud.add_child(app._buttons)
	app._buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	app._buttons.offset_left = -780
	app._buttons.offset_top = -57
	app._buttons.add_theme_constant_override("separation",12)
	app._buttons.resized.connect(app._queue_hud_layout)
	app._buttons.minimum_size_changed.connect(app._queue_hud_layout)
	app._hud_controls = {"settings": nav.get_child(0), "leave": nav.get_child(1), "auto_play": app._auto_play_button,
		"teaching": app._teaching_button, "restore": app._restore_button,
		"clock": app._clock_face, "notice": app._table_message, "advice": app._teaching_status, "actions": app._buttons,
		"sorting":app._sort_button,"arrangement":app._sort_status}
	for index in 4: app._hud_controls["player/" + str(index)] = app._identities[index]
	app._hud.resized.connect(app._queue_hud_layout)



static func build_settlement(app) -> void:
	var result: Dictionary = app._view.get("settlement", {})
	if result.is_empty():
		return
	app._settlement_peeking = false
	app._retire_next_round()
	var final_view = SettlementView.new()
	app._frame.add_child(final_view)
	var record = app._record_controls() if not app.table_play_only and int(result.get("viewer_seat", -1)) >= 0 else null
	final_view.show_result(result, app._mode, app._request_leave, app._prepare_next_round, record, app.table_play_only, app._toggle_settlement_peek)
	app._next_round_button = final_view.next_button
	if app.table_play_only:
		final_view.minimum_size_changed.connect(app._queue_hud_layout)
		final_view.resized.connect(app._queue_hud_layout)
		app._peek_return_button = UI.button("返回结算", app._toggle_settlement_peek, true)
		app._peek_return_button.custom_minimum_size = Vector2(124, 42)
		var holder := MarginContainer.new()
		app._safe.add_child(holder)
		holder.add_child(app._peek_return_button)
		holder.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		holder.offset_left = -62; holder.offset_right = 62
		holder.offset_top = -54; holder.offset_bottom = -12
		holder.hide()
	app._fit_settlement()
	app._refresh_settlement_names()
	if is_instance_valid(app._progress) and not app._view.get("room", {}).is_empty():
		var rkey = "%s/%d" % [str(app._view.room.get("room_instance_id", "")), int(result.get("round_number", 0))]
		var milestone = app._progress.record_settlement(rkey, result, app._settlement_viewer())
		if not milestone.is_empty() and is_instance_valid(app._ting_overlay):
			var notes = PackedStringArray()
			if int(milestone.get("streak", 0)) >= 2:
				notes.append("%d 连胜" % int(milestone.streak))
			if bool(milestone.get("new_record", false)):
				notes.append("刷新最高单局 +%d 分" % int(milestone.delta))
			for badge_name in milestone.get("new_badges", []):
				notes.append("解锁图鉴「%s」" % str(badge_name))
			if not notes.is_empty():
				app._ting_overlay.show_toast("✦ " + " · ".join(notes), 3.0)



static func fit_play_badges(_app, badges:Array) -> void:
	if badges.size()!=4:return
	for badge in badges:badge.set_compact()
	badges[0].set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	badges[0].offset_left=8;badges[0].offset_right=128;badges[0].offset_top=-56;badges[0].offset_bottom=-6
	badges[1].set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	badges[1].offset_left=-126;badges[1].offset_right=-6;badges[1].offset_top=-25;badges[1].offset_bottom=25
	badges[2].set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	badges[2].anchor_left=0.775;badges[2].anchor_right=0.775;badges[2].offset_left=-60;badges[2].offset_right=60;badges[2].offset_top=6;badges[2].offset_bottom=54
	badges[3].set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	badges[3].offset_left=6;badges[3].offset_right=126;badges[3].offset_top=-25;badges[3].offset_bottom=25


