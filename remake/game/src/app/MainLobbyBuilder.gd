extends RefCounted

const UI := preload("res://src/app/AppTheme.gd")
const CharacterArt := preload("res://src/app/CharacterArt.gd")
const SettingsPanel := preload("res://src/app/SettingsPanel.gd")
const ProfileSetup := preload("res://src/app/ProfileSetup.gd")
const PlayerBadge := preload("res://src/app/PlayerBadge.gd")
const CareerPanel := preload("res://src/app/CareerPanel.gd")
const TitleTile := preload("res://src/app/TitleTile.gd")
const TurnClockView := preload("res://src/app/TurnClockView.gd")
const SettlementView := preload("res://src/app/SettlementView.gd")
const LanDiscovery := preload("res://src/network/LanDiscovery.gd")
const RoomBrowser := preload("res://src/app/RoomBrowser.gd")
const WINDS := ["东", "南", "西", "北"]
const MODE_NAMES := {"solo": "单机", "lan": "局域网", "online": "在线"}

static func build_home(app) -> void:
	var content = app._panel(860)
	var hero = HBoxContainer.new()
	hero.alignment = BoxContainer.ALIGNMENT_CENTER
	hero.add_theme_constant_override("separation", 18)
	content.add_child(hero)
	var left_tile = TitleTile.new(); left_tile.value = "tiao1"; hero.add_child(left_tile)
	var title_col = VBoxContainer.new()
	title_col.alignment = BoxContainer.ALIGNMENT_CENTER
	title_col.add_theme_constant_override("separation", 4)
	var h1 = UI.label("东秀麻将", 46, UI.GOLD_BRIGHT)
	h1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var h2 = UI.label("安顺捉鸡 · 新中式 2.5D 实感牌桌", 20, UI.MUTED)
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_col.add_child(h1)
	title_col.add_child(h2)
	hero.add_child(title_col)
	var right_tile = TitleTile.new(); right_tile.value = "tong8"; hero.add_child(right_tile)
	var modes = HBoxContainer.new()
	content.add_child(modes)
	for mode in ["solo", "lan", "online"]:
		var button = UI.button(MODE_NAMES[mode], app._choose_mode.bind(mode), mode == "solo")
		button.custom_minimum_size.y = 82
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(button)
	UI.focus_later(modes.get_child(0))
	var bottom = HBoxContainer.new()
	content.add_child(bottom)
	var streak_note = " · 🔥%d连胜" % int(app._progress.stats.streak) if int(app._progress.stats.streak) >= 2 else ""
	var nickname = UI.label("%s · %s%s" % [app._settings.profile().nickname, app._progress.rank_title(), streak_note], 18, UI.GOLD)
	nickname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(nickname)
	bottom.add_child(UI.button("战绩", app._open_career))
	bottom.add_child(UI.button("设置", app._open_settings))
	app._add_status(content)


static func build_career(app) -> void:
	var content = app._panel(960)
	var career = CareerPanel.new()
	content.add_child(career)
	career.build(app._progress, app._settings.profile().nickname)
	career.closed.connect(func(): app._show(app._before_career))



static func build_connection(app) -> void:
	if app._mode == "lan":
		app._build_lan_lobby()
		return
	var content = app._panel(1500)
	var profile = app._settings.profile()
	var title = HBoxContainer.new()
	title.set_meta("page_id", "lobby_navigation")
	title.add_theme_constant_override("separation", 12)
	content.add_child(title)

	# 左侧玩家身份铭牌（2D 头像 + 昵称 + 段位连胜）
	var id_card = PanelContainer.new()
	id_card.add_theme_stylebox_override("panel", UI.card(Color("#0c201be8"), 12, 8, Color("#4c7462"), 1))
	title.add_child(id_card)
	var id_row = HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 10)
	id_card.add_child(id_row)
	var avatar_frame = PanelContainer.new()
	avatar_frame.custom_minimum_size = Vector2(42, 42)
	avatar_frame.add_theme_stylebox_override("panel", UI.card(Color("#122a22"), 9, 2, UI.GOLD_BORDER, 1))
	id_row.add_child(avatar_frame)
	var avatar_rect = TextureRect.new()
	avatar_rect.texture = CharacterArt.avatar(int(profile.avatar))
	avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_frame.add_child(avatar_rect)
	var id_col = VBoxContainer.new()
	id_col.alignment = BoxContainer.ALIGNMENT_CENTER
	id_col.add_theme_constant_override("separation", 1)
	id_row.add_child(id_col)
	var nick_label = UI.label(str(profile.nickname), 17, UI.INK)
	id_col.add_child(nick_label)
	var streak_note = " · %d连胜" % int(app._progress.stats.streak) if int(app._progress.stats.streak) >= 2 else ""
	var rank_label = UI.label("%s%s" % [app._progress.rank_title(), streak_note], 13, UI.GOLD)
	id_col.add_child(rank_label)

	# 中央茶馆匾额标题
	var brand = HBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	brand.add_theme_constant_override("separation", 10)
	title.add_child(brand)
	brand.add_child(UI.label("东秀麻将", 28, UI.GOLD_BRIGHT))
	brand.add_child(UI.label("·  安顺捉鸡茶馆", 16, UI.MUTED))

	# 右侧三个精简功能入口
	var nav_right = HBoxContainer.new()
	nav_right.add_theme_constant_override("separation", 8)
	title.add_child(nav_right)
	for pair in [["战绩", app._open_career], ["资料", app._open_profile_from_lobby], ["设置", app._open_settings]]:
		var btn = UI.button(pair[0], pair[1])
		btn.custom_minimum_size = Vector2(74, 42)
		nav_right.add_child(btn)

	var divider = ColorRect.new()
	divider.custom_minimum_size.y = 1
	divider.color = Color("#b9954c44")
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)

	# 主体双栏：左侧模式与开桌操作卡片 + 右侧实时 3D 茶馆桌台
	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)

	var left_deck = VBoxContainer.new()
	left_deck.custom_minimum_size.x = 256
	left_deck.add_theme_constant_override("separation", 12)
	body.add_child(left_deck)

	# 卡片 1：单机主打入口
	var solo_card = PanelContainer.new()
	solo_card.add_theme_stylebox_override("panel", UI.elevated_card(Color("#18372cf2"), 14, 14, UI.GOLD_BORDER, 1, 6))
	left_deck.add_child(solo_card)
	var solo_col = VBoxContainer.new()
	solo_col.add_theme_constant_override("separation", 6)
	solo_card.add_child(solo_col)
	var solo_head = HBoxContainer.new()
	solo_col.add_child(solo_head)
	var solo_title = UI.label("单机开局", 20, UI.GOLD_BRIGHT)
	solo_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	solo_head.add_child(solo_title)
	solo_head.add_child(UI.label("随时开搓", 12, UI.GOLD))
	var solo_desc = UI.label("智能 AI 对局 · 完整安顺捉鸡与冲锋鸡规则", 13, UI.MUTED)
	solo_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	solo_col.add_child(solo_desc)
	var solo_btn = UI.button("单机", app._choose_mode.bind("solo"), true)
	solo_btn.custom_minimum_size.y = 48
	solo_col.add_child(solo_btn)

	# 卡片 2：局域网约局入口
	var lan_card = PanelContainer.new()
	lan_card.add_theme_stylebox_override("panel", UI.elevated_card(Color("#122a23eb"), 14, 14, Color("#49705e"), 1, 4))
	left_deck.add_child(lan_card)
	var lan_col = VBoxContainer.new()
	lan_col.add_theme_constant_override("separation", 6)
	lan_card.add_child(lan_col)
	lan_col.add_child(UI.label("局域网约局", 18, UI.INK))
	var lan_desc = UI.label("同 Wi-Fi 自动发现 · 亲友面对面零延迟", 13, UI.MUTED)
	lan_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lan_col.add_child(lan_desc)
	var lan_btn = UI.button("局域网", app._choose_mode.bind("lan"))
	lan_btn.custom_minimum_size.y = 44
	lan_col.add_child(lan_btn)

	# 卡片 3：在线茶馆房间工具箱（2×2）
	var room_card = PanelContainer.new()
	room_card.add_theme_stylebox_override("panel", UI.elevated_card(Color("#10251fe6"), 14, 12, Color("#3f6454"), 1, 4))
	left_deck.add_child(room_card)
	var room_col = VBoxContainer.new()
	room_col.add_theme_constant_override("separation", 8)
	room_card.add_child(room_col)
	room_col.add_child(UI.label("在线开桌", 15, UI.GOLD))
	var actions = GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	actions.set_meta("page_id", "lobby_actions")
	room_col.add_child(actions)

	# 右侧：折叠选项区 + 3D 茶馆房间台面
	var right_hall = VBoxContainer.new()
	right_hall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_hall.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_hall.add_theme_constant_override("separation", 10)
	body.add_child(right_hall)

	var options_card = PanelContainer.new()
	options_card.add_theme_stylebox_override("panel", UI.card(Color("#0c1f1ae8"), 12, 12, Color("#567e6a"), 1))
	options_card.set_meta("page_id", "lobby_options")
	options_card.visible = false
	right_hall.add_child(options_card)
	app._online_options = options_card
	var fields = GridContainer.new()
	fields.columns = 4
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("h_separation", 10)
	fields.add_theme_constant_override("v_separation", 8)
	options_card.add_child(fields)
	app._directory_url = app._entry(fields, "服务地址", "HTTPS 在线房间服务")
	app._directory_url.text = app._online_url()
	app._room_number = app._entry(fields, "房间号", "4–8 位数字")
	app._online_name = app._entry(fields, "新房间名称", "")
	app._online_name.text = profile.nickname + "麻将局"
	app._online_name.max_length = 24
	app._online_filter = app._entry(fields, "筛选房间", "房间号或名称")
	app._online_filter.text_changed.connect(func(_text): app._draw_online_rooms())
	app._add_host_clocks(fields)

	for spec in [
		["创建房间", app._create_online, true],
		["加入房间", app._find_online, false],
		["刷新房间", app._search_online, false],
		["房间选项", func(): options_card.visible = not options_card.visible; app._fit_menu_panel(), false],
	]:
		var b = UI.button(spec[0], spec[1], spec[2])
		b.custom_minimum_size.y = 42
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(b)

	var stage_card = PanelContainer.new()
	stage_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_card.add_theme_stylebox_override("panel", UI.card(Color("#0a1c17d8"), 14, 8, Color("#3a5d4f"), 1))
	right_hall.add_child(stage_card)
	app._online_results = RoomBrowser.new()
	app._online_results.set_meta("page_id", "room_browser")
	app._online_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app._online_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app._online_results.set_meta("page_label", "房间列表")
	app._online_results.seat_selected.connect(app._select_room_seat)
	app._online_results.inspection_requested.connect(app._inspect_endpoint)
	stage_card.add_child(app._online_results)
	app._online_results.apply_quality(profile.quality)
	app._add_status(right_hall)
	app._refresh_online(app._online_rooms)
	if not app._directory_url.text.is_empty():
		app._search_online()
	UI.focus_later(solo_btn)



static func build_lan_lobby(app) -> void:
	var content = app._panel(1500)
	var profile = app._settings.profile()
	var title = HBoxContainer.new()
	title.add_theme_constant_override("separation", 12)
	content.add_child(title)
	var back_btn = UI.button("返回", app._choose_mode.bind("online"))
	back_btn.custom_minimum_size = Vector2(82, 42)
	title.add_child(back_btn)
	var head_col = VBoxContainer.new()
	head_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_col.add_theme_constant_override("separation", 2)
	title.add_child(head_col)
	head_col.add_child(UI.label("局域网约局", 26, UI.GOLD_BRIGHT))
	head_col.add_child(UI.label("连接同一 Wi-Fi 自动发现附近牌桌，点击空座即可入桌", 14, UI.MUTED))
	var set_btn = UI.button("设置", app._open_settings)
	set_btn.custom_minimum_size = Vector2(74, 42)
	title.add_child(set_btn)

	var divider = ColorRect.new()
	divider.custom_minimum_size.y = 1
	divider.color = Color("#b9954c44")
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(divider)

	var body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)

	var left_deck = VBoxContainer.new()
	left_deck.custom_minimum_size.x = 256
	left_deck.add_theme_constant_override("separation", 12)
	body.add_child(left_deck)

	var host_card = PanelContainer.new()
	host_card.add_theme_stylebox_override("panel", UI.elevated_card(Color("#18372cf2"), 14, 14, UI.GOLD_BORDER, 1, 6))
	left_deck.add_child(host_card)
	var host_col = VBoxContainer.new()
	host_col.add_theme_constant_override("separation", 6)
	host_card.add_child(host_col)
	host_col.add_child(UI.label("做房主开桌", 20, UI.GOLD_BRIGHT))
	var host_desc = UI.label("在本机开启局域网牌桌，同网亲友可免输地址直接加入", 13, UI.MUTED)
	host_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	host_col.add_child(host_desc)
	var create_btn = UI.button("创建房间", app._host_lan, true)
	create_btn.custom_minimum_size.y = 48
	host_col.add_child(create_btn)

	var tools_card = PanelContainer.new()
	tools_card.add_theme_stylebox_override("panel", UI.elevated_card(Color("#10251fe6"), 14, 14, Color("#49705e"), 1, 4))
	left_deck.add_child(tools_card)
	var tools_col = VBoxContainer.new()
	tools_col.add_theme_constant_override("separation", 8)
	tools_card.add_child(tools_col)
	tools_col.add_child(UI.label("搜索与直连", 15, UI.GOLD))
	var refresh_btn = UI.button("刷新房间", app._search_lan)
	refresh_btn.custom_minimum_size.y = 44
	tools_col.add_child(refresh_btn)
	var find_btn = UI.button("查找地址", app._inspect_lan_address)
	find_btn.custom_minimum_size.y = 44
	tools_col.add_child(find_btn)

	var right_hall = VBoxContainer.new()
	right_hall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_hall.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_hall.add_theme_constant_override("separation", 10)
	body.add_child(right_hall)

	var options_card = PanelContainer.new()
	options_card.add_theme_stylebox_override("panel", UI.card(Color("#0c1f1ae8"), 12, 12, Color("#567e6a"), 1))
	options_card.visible = false
	right_hall.add_child(options_card)
	app._lan_options = options_card
	var options = VBoxContainer.new()
	options.add_theme_constant_override("separation", 8)
	options_card.add_child(options)

	var opt_btn = UI.button("房间选项", func(): options_card.visible = not options_card.visible; app._fit_menu_panel())
	opt_btn.custom_minimum_size.y = 42
	tools_col.add_child(opt_btn)

	var filter_row = GridContainer.new()
	filter_row.columns = 2
	filter_row.add_theme_constant_override("h_separation", 10)
	options.add_child(filter_row)
	app._lan_filter = app._entry(filter_row, "查找房间", "房间号或名称")
	app._lan_filter.text_changed.connect(func(_text): app._refresh_lan())
	var fields = GridContainer.new()
	fields.columns = 4
	fields.add_theme_constant_override("h_separation", 10)
	fields.add_theme_constant_override("v_separation", 8)
	options.add_child(fields)
	app._room_number = app._entry(fields, "新房间号", "4–8 位数字")
	app._lan_name = app._entry(fields, "房间名称", "")
	app._lan_name.text = profile.nickname + "麻将局"
	app._lan_name.max_length = 24
	app._add_host_clocks(fields)
	var manual = GridContainer.new()
	manual.columns = 2
	manual.add_theme_constant_override("h_separation", 10)
	options.add_child(manual)
	app._lan_address = app._entry(manual, "房间地址", "例如 192.168.1.8:7499")
	options.add_child(UI.label("需连接同一局域网；输入房主显示的地址，查到房间后选择空座。", 14, UI.MUTED))

	var stage_card = PanelContainer.new()
	stage_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage_card.add_theme_stylebox_override("panel", UI.card(Color("#0a1c17d8"), 14, 8, Color("#3a5d4f"), 1))
	right_hall.add_child(stage_card)
	app._lan_results = RoomBrowser.new()
	app._lan_results.empty_hint = "点击左侧「创建房间」做房主开桌\n或点击「刷新房间」搜索同网牌桌"
	app._lan_results.set_meta("page_id", "room_browser")
	app._lan_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app._lan_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	app._lan_results.set_meta("page_label", "房间列表")
	app._lan_results.seat_selected.connect(app._select_room_seat)
	app._lan_results.inspection_requested.connect(app._inspect_endpoint)
	stage_card.add_child(app._lan_results)
	app._lan_results.apply_quality(profile.quality)
	app._add_status(right_hall)
	app._search_lan()
	UI.focus_later(create_btn)



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
	if app._mode == "lan":
		var addresses: Array = []
		if app._client._address == "127.0.0.1":
			for address in LanDiscovery._interface_addresses(IP.get_local_interfaces()):
				addresses.append(address + ":" + str(app._client._port))
		else:
			addresses.append(app._client._address + ":" + str(app._client._port))
		if not addresses.is_empty():
			subtitle += "\n连接地址：" + " / ".join(addresses)
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
			button.add_theme_stylebox_override("disabled", UI.elevated_card(Color("#193b30"), 12, 10, UI.GOLD_BORDER, 2, 4))
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
	editor.theme=UI.menu_theme()
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
	nav.add_child(UI.button("离开", app._request_leave))
	app._auto_play_button = UI.button("AI代打", app._toggle_auto_play)
	nav.add_child(app._auto_play_button)
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
		app._safe.add_child(app._peek_return_button)
		app._peek_return_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		app._peek_return_button.offset_left = -62; app._peek_return_button.offset_right = 62
		app._peek_return_button.offset_top = -54; app._peek_return_button.offset_bottom = -12
		app._peek_return_button.hide()
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


