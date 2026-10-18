extends Control
const STYLE := preload("res://scripts/ui/UiStyle.gd")
const MOTION := preload("res://scripts/ui/UiMotion.gd")
## 搜索与等待房间共用横屏画布；所有发牌由 NetGameNode 准备状态控制。
const DESIGN := Vector2(1480, 860)
const WINDS := ["东", "南", "西", "北"]
var content: Control
var browser: Control
var waiting: Control
var status: Label
var room_input: LineEdit
var room_name_input: LineEdit
var player_input: LineEdit
var filter_input: LineEdit
var room_rows: VBoxContainer
var room_heading: Label
var seat_buttons: Array[Button] = []
var ready_button: Button
var dealer_button: CheckButton
var swap_row: HBoxContainer
var swap_label: Label
var waiting_hint: Label
var create_button: Button
var search_button: Button
var lan_button: Button
var online_button: Button
var server_button: Button
var server_dialog: ConfirmationDialog
var server_input: LineEdit
var resume_button: Button
var online := false
var _in_room := false
var _connecting := false
var _creating := false
var _transitioning := false
var _leaving := false
var _refresh := 0.0
var _connection_attempt := 0
var _creation_attempt := 0
var update_panel: UpdatePanel

func _ready() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font = TileView._font()
	ui_theme.default_font_size = 26
	theme = ui_theme
	var bg := ColorRect.new()
	bg.color = Color("#123e30")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	content = Control.new()
	content.size = DESIGN
	add_child(content)
	_label(content, "联机房间", Vector2(36, 22), Vector2(900, 58), 42)
	update_panel = UpdatePanel.new()
	add_child(update_panel)
	_button(content, "检查更新", Vector2(1200, 24), Vector2(244, 58), update_panel.open)
	lan_button = _button(content, "局域网", Vector2(36, 100), Vector2(200, 80), func(): _set_mode(false))
	online_button = _button(content, "在线", Vector2(250, 100), Vector2(200, 80), func(): _set_mode(true))
	server_button = _button(content, "服务器设置", Vector2(1200, 100), Vector2(244, 80), _open_server)
	resume_button = _button(content, "返回上次房间", Vector2(480, 100), Vector2(660, 80), _resume_saved_room)
	resume_button.name = "ResumeRoomButton"
	resume_button.visible = Network.has_saved_session()
	browser = Control.new()
	browser.position = Vector2(36, 194)
	browser.size = Vector2(1408, 530)
	content.add_child(browser)
	_panel(browser, Vector2.ZERO, Vector2(422, 530))
	_label(browser, "创建房间", Vector2(24, 16), Vector2(370, 48), 32)
	_label(browser, "昵称", Vector2(24, 80), Vector2(370, 34), 24)
	player_input = _field(browser, Vector2(24, 118), Vector2(374, 56), "你的昵称", GameConfig.player_name, 16)
	player_input.text_changed.connect(func(value): GameConfig.set_player_name(value))
	_label(browser, "房间号 · 4～8 位数字", Vector2(24, 188), Vector2(374, 34), 24)
	var previous_number := str(Network.lobby_preferences.number)
	room_input = _field(browser, Vector2(24, 228), Vector2(374, 56), "输入房间号", previous_number if NetGameNode.valid_room_number(previous_number) else str(randi_range(100000, 999999)), 8)
	room_input.text_changed.connect(func(_value): _save_lobby_preferences())
	_label(browser, "房间名称", Vector2(24, 300), Vector2(374, 34), 24)
	room_name_input = _field(browser, Vector2(24, 340), Vector2(374, 56), "朋友麻将局", str(Network.lobby_preferences.name), 24)
	room_name_input.text_changed.connect(func(_value): _save_lobby_preferences())
	create_button = _button(browser, "创建房间", Vector2(24, 438), Vector2(374, 80), _create)
	_panel(browser, Vector2(446, 0), Vector2(962, 530))
	filter_input = _field(browser, Vector2(470, 20), Vector2(530, 60), "搜索房间号或名称", "", 32)
	filter_input.text_changed.connect(func(_value): _render_rooms())
	search_button = _button(browser, "刷新房间", Vector2(1024, 20), Vector2(360, 80), _search)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(470, 118)
	scroll.size = Vector2(914, 386)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	browser.add_child(scroll)
	room_rows = VBoxContainer.new()
	room_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_rows.add_theme_constant_override("separation", 14)
	scroll.add_child(room_rows)
	waiting = Control.new()
	waiting.position = Vector2(36, 194)
	waiting.size = Vector2(1408, 530)
	content.add_child(waiting)
	waiting.hide()
	_panel(waiting, Vector2.ZERO, Vector2(1408, 530))
	room_heading = _label(waiting, "", Vector2(28, 14), Vector2(1352, 48), 32)
	var locations := [Vector2(484, 326), Vector2(936, 166), Vector2(484, 94), Vector2(32, 166)]
	for seat in 4:
		var index := seat
		var button := _button(waiting, "", locations[seat], Vector2(440, 168), func(): Network.net_node.select_seat(index))
		button.add_theme_font_size_override("font_size", 25)
		seat_buttons.append(button)
	waiting_hint = _label(waiting, "", Vector2(484, 266), Vector2(440, 54), 23)
	waiting_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dealer_button = CheckButton.new()
	dealer_button.text = "我想当庄"
	dealer_button.position = Vector2(32, 380)
	dealer_button.size = Vector2(300, 64)
	dealer_button.toggled.connect(func(value): Network.net_node.set_wants_dealer(value))
	waiting.add_child(dealer_button)
	ready_button = _button(waiting, "准备", Vector2(1010, 388), Vector2(366, 78), _toggle_ready)
	swap_row = HBoxContainer.new()
	swap_row.position = Vector2(32, 478)
	swap_row.size = Vector2(1344, 48)
	swap_row.add_theme_constant_override("separation", 16)
	waiting.add_child(swap_row)
	swap_label = Label.new()
	swap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swap_row.add_child(swap_label)
	var accept := _button(null, "同意换座", Vector2.ZERO, Vector2(180, 48), func(): Network.net_node.respond_swap(true))
	var decline := _button(null, "暂不换座", Vector2.ZERO, Vector2(180, 48), func(): Network.net_node.respond_swap(false))
	swap_row.add_child(accept)
	swap_row.add_child(decline)
	swap_row.hide()
	status = _label(content, "", Vector2(36, 738), Vector2(1408, 44), 24)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(content, "返回 / 离开房间", Vector2(36, 780), Vector2(304, 78), _back)
	_label(content, "选座后点击准备 · 人机默认准备 · 全部准备后开局", Vector2(376, 800), Vector2(1068, 48), 24)
	_build_server_dialog()
	Network.discovery.rooms_updated.connect(_render_rooms)
	Network.discovery.discovery_error.connect(_message)
	Network.directory.rooms_updated.connect(_online_rooms_updated)
	Network.directory.directory_error.connect(_directory_error)
	Network.directory.room_created.connect(_online_created)
	resized.connect(_layout)
	_layout()
	_set_mode(bool(Network.lobby_preferences.online))
	if Network.resume_on_lobby:
		Network.resume_on_lobby = false
		_resume_saved_room.call_deferred()

func _save_lobby_preferences() -> void:
	if room_input != null and room_name_input != null:
		Network.save_lobby_preferences(online, room_input.text, room_name_input.text)

func _resume_saved_room() -> void:
	if _connecting or _creating or _in_room or not Network.has_saved_session(): return
	online = bool(Network.saved_session.get("online", false))
	Network.lobby_preferences.online = online
	Network.discovery.stop_search()
	Network.directory.cancel()
	Network.reset()
	_bind_net()
	_connecting = true
	create_button.disabled = true
	search_button.disabled = true
	lan_button.disabled = true
	online_button.disabled = true
	resume_button.disabled = true
	_message("正在返回房间 %s…" % Network.saved_session.number)
	if not Network.resume_saved_session(): _connection_failed("上次房间信息无效，请重新加入")

func _layout() -> void:
	var available := STYLE.usable_rect(self)
	var factor := minf((available.size.x - 28.0) / DESIGN.x, (available.size.y - 28.0) / DESIGN.y)
	content.scale = Vector2.ONE * maxf(0.1, factor)
	content.position = available.position + (available.size - DESIGN * content.scale) / 2.0

func _panel(parent: Control, position_value: Vector2, dimensions: Vector2) -> void:
	var panel := Panel.new()
	panel.position = position_value
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#205341")
	style.border_color = Color("#5b826d")
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", STYLE.panel(Color("#1c4738")))
	parent.add_child(panel)

func _label(parent: Control, text_value: String, pos: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#edf3ee"))
	parent.add_child(label)
	return label

func _field(parent: Control, pos: Vector2, dimensions: Vector2, placeholder: String, value: String, limit: int) -> LineEdit:
	var field := LineEdit.new()
	field.position = pos
	field.size = dimensions
	field.placeholder_text = placeholder
	field.text = value
	field.max_length = limit
	STYLE.field(field)
	parent.add_child(field)
	return field

func _button(parent: Control, text_value: String, pos: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = pos
	button.size = dimensions
	button.custom_minimum_size = dimensions
	STYLE.button(button, text_value in ["创建房间", "准备", "加入"])
	button.pressed.connect(callback)
	if parent != null: parent.add_child(button)
	return button

func _set_mode(value: bool) -> void:
	if _in_room or _connecting or _creating: return
	online = value
	_save_lobby_preferences()
	lan_button.disabled = not online
	online_button.disabled = online
	server_button.visible = online
	if online: Network.discovery.stop_search()
	_message("搜索在线房间…" if online else "自动搜索同一 Wi-Fi 或手机热点内的房间，电脑建房后保持等待")
	_search()
	_render_rooms()

func _search() -> void:
	if _in_room or _connecting: return
	if online: Network.directory.search()
	else: Network.discovery.search()
	_refresh = 5.0

func _process(delta: float) -> void:
	if online and not _in_room and not _connecting and not _creating:
		_refresh -= delta
		if _refresh <= 0.0: _search()

func _render_rooms() -> void:
	if room_rows == null or _in_room: return
	for child in room_rows.get_children():
		room_rows.remove_child(child)
		child.queue_free()
	var list: Array = Network.directory.rooms if online else Network.discovery.rooms.values()
	list = list.duplicate()
	list.sort_custom(func(a, b): return str(a.number) < str(b.number))
	var shown := 0
	var query := filter_input.text.strip_edges().to_lower()
	for room in list:
		if query != "" and not (str(room.number).contains(query) or str(room.name).to_lower().contains(query)): continue
		shown += 1
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", STYLE.panel(Color("#244e3c")))
		room_rows.add_child(card)
		var margin := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
		card.add_child(margin)
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 90
		margin.add_child(row)
		var label := Label.new()
		label.text = "%s  ·  房间 %s\n真人 %d / 4  ·  %s" % [room.name, room.number, int(room.get("players", 0)), "游戏中" if room.get("started", false) else "等待准备"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 25)
		label.clip_text = true
		row.add_child(label)
		var selected: Dictionary = room.duplicate()
		var join := _button(null, "加入", Vector2.ZERO, Vector2(170, 78), func(): _join(selected))
		join.disabled = _connecting or _creating or bool(room.get("started", false)) or int(room.get("players", 0)) >= 4
		row.add_child(join)
	if shown == 0:
		var empty := Label.new()
		empty.text = "没有匹配的房间" if query != "" else ("暂无在线房间，可创建新房间" if online and Network.directory.base_url != "" else ("先配置房间服务器，再搜索在线房间" if online else "正在搜索 Wi-Fi 和手机热点内的房间…\n请先在另一台设备创建房间并保持等待，发现后会自动显示。"))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size = Vector2(870, 294)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", STYLE.MUTED)
		empty.add_theme_font_size_override("font_size", 26)
		room_rows.add_child(empty)

func _create() -> void:
	if _creating or _connecting: return
	var number := room_input.text.strip_edges()
	if not NetGameNode.valid_room_number(number):
		_message("房间号请输入 4～8 位数字")
		return
	GameConfig.set_player_name(player_input.text)
	_save_lobby_preferences()
	_creating = true
	_creation_attempt += 1
	var creation := _creation_attempt
	create_button.disabled = true
	if online:
		# A background list refresh must not swallow the create request.
		Network.directory.cancel()
		_message("正在创建在线房间…")
		Network.directory.create_room(number, room_name_input.text)
		return
	_message("检查房间号…")
	Network.discovery.search()
	await get_tree().create_timer(1.8).timeout
	if not is_inside_tree() or not _creating or creation != _creation_attempt: return
	if Network.discovery.has_number(number):
		_creation_failed("这个房间号已在使用，请换一个")
		return
	Network.reset()
	_bind_net()
	var opened := false
	var first := randi_range(7600, 8600)
	for attempt in 24:
		if Network.start_host(false, true, first + attempt, number, room_name_input.text):
			opened = true
			break
	if not opened or not Network.discovery.advertise(Network.net_node):
		Network.reset()
		_creation_failed("无法创建局域网房间，请稍后重试")
		return
	_creating = false
	_show_waiting()

func _join(room: Dictionary) -> void:
	if _connecting or _creating: return
	# 已选定端点后停止网段扫描，把热点和主线程留给连接握手。
	Network.discovery.stop_search()
	GameConfig.set_player_name(player_input.text)
	_save_lobby_preferences()
	Network.reset()
	_bind_net()
	_connecting = true
	_connection_attempt += 1
	var attempt := _connection_attempt
	create_button.disabled = true
	search_button.disabled = true
	_message("正在加入房间 %s…" % room.number)
	_render_rooms()
	if not Network.start_client(str(room.host), int(room.port), str(room.number), str(room.get("owner_token", ""))):
		_connection_failed("无法连接房间，请刷新后重试")
		return
	await get_tree().create_timer(12.0).timeout
	if is_inside_tree() and _connecting and attempt == _connection_attempt: _connection_failed("加入超时，请刷新房间后重试")

func _bind_net() -> void:
	var net := Network.net_node
	net.room_ready.connect(func(_seat):
		if _connecting:
			_connecting = false
			_show_waiting())
	net.lobby_updated.connect(_render_waiting)
	net.lobby_notice.connect(_message)
	net.game_started.connect(_enter_table)
	net.connection_error.connect(_connection_failed)
	net.reconnecting.connect(func(attempt, maximum): _message("连接中断，正在重连（%d/%d）…" % [attempt, maximum]))
	net.room_ready.connect(func(_seat):
		if _in_room: _message("连接已恢复"))

func _show_waiting() -> void:
	_in_room = true
	browser.hide()
	waiting.show()
	lan_button.disabled = true
	online_button.disabled = true
	server_button.hide()
	resume_button.hide()
	Network.discovery.stop_search()
	_message("点击人机位置直接选座，点击真人位置申请交换；准备好后开局")
	_render_waiting()

func _render_waiting() -> void:
	if not _in_room: return
	var net := Network.net_node
	var data := net.lobby
	if data.is_empty(): return
	room_heading.text = "%s  ·  房间 %s  ·  %s" % [data.name, data.number, "在线" if online else "局域网"]
	for seat in 4:
		var member: Dictionary = data.seats[seat]
		var mine := seat == net.my_seat
		var tags := " · 我" if mine else ""
		if int(member.peer) == int(data.owner): tags += " · 房主"
		seat_buttons[seat].text = "%s位  %s%s\n%s%s\n%s" % [WINDS[seat], member.name, tags, "已准备" if member.ready else "未准备", " · 想当庄" if member.wants_dealer else "", "你的位置" if mine else ("点击选座" if member.ai else "点击申请换座")]
		seat_buttons[seat].disabled = mine or bool(data.started) or bool(member.get("disconnected", false))
		if bool(member.get("disconnected", false)): seat_buttons[seat].text += "\n断线 · 等待重连"
		seat_buttons[seat].add_theme_color_override("font_disabled_color", Color("#edcc80") if mine else Color("#aac5b9"))
	if net.my_seat >= 0:
		var me: Dictionary = data.seats[net.my_seat]
		ready_button.text = "取消准备" if me.ready else "准备"
		dealer_button.set_pressed_no_signal(bool(me.wants_dealer))
	var seconds := int(data.countdown)
	waiting_hint.text = "%d 秒后开局" % seconds if seconds >= 0 else "等待大家准备"
	var pending: Dictionary = data.swap
	swap_row.visible = not pending.is_empty() and int(pending.get("to", -1)) == net._local_peer()
	if swap_row.visible:
		var name_value := "玩家"
		for member in data.seats:
			if int(member.peer) == int(pending.from): name_value = str(member.name)
		swap_label.text = "%s 想和你交换座位" % name_value
	elif not pending.is_empty(): _message("换座请求已发出，等待对方同意（20 秒内有效）")

func _toggle_ready() -> void:
	var net := Network.net_node
	if net.my_seat >= 0 and net.lobby.has("seats"):
		net.set_ready(not bool(net.lobby.seats[net.my_seat].ready))

func _enter_table() -> void:
	if _transitioning: return
	_transitioning = true
	get_tree().call_deferred("change_scene_to_file", "res://scenes/GameTable.tscn")

func _connection_failed(message: String) -> void:
	if _transitioning: return
	Network.reset()
	if _creating and online: Network.directory.cancel()
	_connection_attempt += 1
	_creation_attempt += 1
	_connecting = false
	_creating = false
	_in_room = false
	waiting.hide()
	browser.show()
	create_button.disabled = false
	search_button.disabled = false
	resume_button.disabled = false
	resume_button.visible = Network.has_saved_session()
	_set_mode(online)
	_message(message)

func _creation_failed(message: String) -> void:
	_creating = false
	create_button.disabled = false
	_message(message)

func _online_rooms_updated() -> void:
	if online and not _in_room:
		_render_rooms()
		_message("已更新在线房间")

func _directory_error(message: String) -> void:
	if online:
		_creation_failed(message)
		_render_rooms()

func _online_created(room: Dictionary) -> void:
	if not _creating or not online or _in_room: return
	_creating = false
	_join(room)

func _message(message: String) -> void:
	if status != null: status.text = message

func _build_server_dialog() -> void:
	server_dialog = ConfirmationDialog.new()
	server_dialog.title = "在线服务器设置"
	server_dialog.min_size = Vector2i(800, 260)
	server_dialog.ok_button_text = "保存并搜索"
	server_dialog.theme = theme.duplicate()
	server_dialog.theme.set_constant("buttons_min_height", "AcceptDialog", 76)
	server_dialog.theme.set_constant("buttons_min_width", "AcceptDialog", 240)
	server_dialog.add_theme_stylebox_override("panel", STYLE.panel())
	server_dialog.cancel_button_text = "取消"
	add_child(server_dialog)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	server_dialog.add_child(box)
	var label := Label.new()
	label.text = "填写房间服务地址，保存后所有在线房间由服务器运行。"
	label.add_theme_font_size_override("font_size", 24)
	box.add_child(label)
	server_input = LineEdit.new()
	server_input.placeholder_text = "https://你的房间服务器"
	server_input.custom_minimum_size = Vector2(760, 60)
	box.add_child(server_input)
	STYLE.field(server_input)
	for button in [server_dialog.get_ok_button(), server_dialog.get_cancel_button()]:
		button.custom_minimum_size = Vector2(240, 76)
		STYLE.button(button, button == server_dialog.get_ok_button())
	server_dialog.confirmed.connect(func():
		if Network.directory.configure(server_input.text): _search())

func _open_server() -> void:
	server_input.text = Network.directory.base_url
	server_dialog.popup_centered(Vector2i(880, 360))
	_refresh_server_buttons.call_deferred()

func _refresh_server_buttons() -> void:
	server_dialog.get_ok_button().add_theme_color_override("font_color", Color("#283a2e"))

func _back() -> void:
	if _transitioning or _leaving: return
	if _in_room or _connecting or _creating:
		_leaving = true
		await Network.leave_room()
		_connection_failed("已离开房间")
		_leaving = false
	else:
		Network.discovery.stop_search()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if update_panel != null and update_panel.is_open(): update_panel.close()
		else: _back()
