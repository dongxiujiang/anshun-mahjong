class_name SoundSettings
extends CanvasLayer
const STYLE := preload("res://scripts/ui/UiStyle.gd")
const MOTION := preload("res://scripts/ui/UiMotion.gd")
signal exit_requested
signal exit_confirmed
signal ai_speed_selected(speed_key: String)
signal ai_strength_selected(strength_key: String)
signal replay_export_requested
signal auto_test_requested(rounds: int)
signal voice_pack_open_requested
## 主菜单和牌桌共用的声音面板，独立于旋转、缩放的牌桌。

const PANEL_SIZE := Vector2(680, 560)
const TABLE_PANEL_SIZE := Vector2(1120, 840)
const SLIDER_HEIGHT := 56.0
const SLIDER_KNOB := 48
const UI_CHANNELS := ["voice", "effects"]
const TITLES := {"voice": "出牌 / 动作语音", "effects": "落桌 / 结算音效"}
var overlay: Control
var panel: Panel
var sliders := {}
var switches := {}
var percentages := {}

var persist_changes := true
var ai_strength_buttons := {}
var tile_speed_slider: HSlider
var ai_speed_slider: HSlider
var settlement_speed_slider: HSlider
var _timing_labels := {}
var _timing_drags := {}
var table_mode := false
var exit_confirmation: Panel
var confirm_exit_button: Button
var cancel_exit_button: Button
var replay_export_button: Button
var replay_status: Label
var _slider_knob: Texture2D
var _slider_knob_hot: Texture2D
var mic_gain_slider: HSlider
var remote_volume_slider: HSlider
var mic_gain_percent: Label
var remote_volume_percent: Label
var continue_button: Button
var debug_button: Button
var auto_test_button: Button
var auto_test_500_button: Button
var exit_room_button: Button
var score_details_button: Button
var hand_sort_button: Button
var replay_exporter: Node

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay = Control.new()
	overlay.name = "SoundOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.04, 0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	_slider_knob = _make_knob(Color("#e8d29a"), Color("#7d6435"))
	_slider_knob_hot = _make_knob(Color("#ffe6a1"), Color("#c59b4f"))
	panel = Panel.new()
	panel.size = TABLE_PANEL_SIZE if table_mode else PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1e4234")
	style.border_color = Color("#cbb279")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", STYLE.panel())
	var ui_theme := Theme.new()
	ui_theme.default_font = TileView._font()
	ui_theme.default_font_size = 24
	panel.theme = ui_theme
	overlay.add_child(panel)
	_label("设置" if table_mode else "声音设置", Vector2(36, 24), Vector2(608, 42), 32)
	if table_mode:
		_label("音量", Vector2(36, 80), Vector2(500, 36), 27).modulate = STYLE.GOLD
		_label("速度", Vector2(584, 80), Vector2(500, 36), 27).modulate = STYLE.GOLD
		var divider := ColorRect.new()
		divider.color = Color(STYLE.MUTED, 0.25)
		divider.position = Vector2(559, 84)
		divider.size = Vector2(2, 566)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(divider)
	for index in UI_CHANNELS.size():
		var channel: String = UI_CHANNELS[index]
		var y := 126.0 + index * (100.0 if table_mode else 88.0)
		if table_mode:
			var row := _slider_row(TITLES[channel], Vector2(36, y), 100.0, 1.0)
			sliders[channel] = row[0]
			percentages[channel] = row[1]
		else:
			_label(TITLES[channel], Vector2(28, y), Vector2(280, 62), 24)
			sliders[channel] = _slider(Vector2(324, y), 234, 100.0, 1.0)
			percentages[channel] = _label("", Vector2(574, y + 12), Vector2(78, 42), 24)
		sliders[channel].value_changed.connect(_on_slider.bind(channel))
	if table_mode:
		var mic := _slider_row("麦克风音量", Vector2(36, 326), 200.0, 1.0)
		mic_gain_slider = mic[0]
		mic_gain_percent = mic[1]
		mic_gain_slider.value_changed.connect(_on_mic_gain_changed)
		var remote := _slider_row("他人语音音量", Vector2(36, 426), 200.0, 1.0)
		remote_volume_slider = remote[0]
		remote_volume_percent = remote[1]
		remote_volume_slider.value_changed.connect(_on_remote_volume_changed)
	debug_button = _button("关闭debug" if GameConfig.debug_enabled else "开启debug",
		Vector2(296, 552) if table_mode else Vector2(36, 320), Vector2(240 if table_mode else 300, 64), _toggle_debug)
	debug_button.name = "DebugToggleButton"
	auto_test_button = _button("自动跑100局", Vector2(36, 622), Vector2(240, 52), func(): auto_test_requested.emit(100))
	auto_test_button.name = "AutoTestButton"
	auto_test_button.visible = table_mode and GameConfig.debug_enabled
	auto_test_500_button = _button("自动跑500局", Vector2(296, 622), Vector2(240, 52), func(): auto_test_requested.emit(500))
	var voice_pack_button := _button("座位音色", Vector2(36, 552), Vector2(240, 64), func(): voice_pack_open_requested.emit())
	voice_pack_button.name = "VoicePackButton"
	voice_pack_button.visible = table_mode
	auto_test_500_button.name = "AutoTest500Button"
	auto_test_500_button.visible = table_mode and GameConfig.debug_enabled
	continue_button = _button("继续游戏" if table_mode else "关闭", Vector2(348, 682) if table_mode else Vector2(404, 422), Vector2(296, 80) if table_mode else Vector2(240, 72), close)
	continue_button.name = "ContinueGameButton"
	if table_mode:
		score_details_button = _button("", Vector2(584, 552), Vector2(240, 64), _toggle_score_details)
		score_details_button.name = "ScoreDetailsButton"
		hand_sort_button = _button("", Vector2(844, 552), Vector2(240, 64), _toggle_hand_sort_priority)
		hand_sort_button.name = "HandSortPriorityButton"
		tile_speed_slider = _timing_slider("牌面动画 · 摸牌 / 出牌 / 发牌", 126, _set_tile_speed)
		ai_speed_slider = _timing_slider("人机出牌等待", 226, _set_ai_speed)
		settlement_speed_slider = _timing_slider("结算速度 · 每项计分", 326, _set_settlement_speed)
		_label("人机强度", Vector2(584, 426), Vector2(500, 30), 24)
		for item in [["弱", "weak"], ["中", "medium"], ["强", "strong"]]:
			var strength_key: String = item[1]
			var strength_button := _button(item[0], Vector2(584 + ai_strength_buttons.size() * 170, 462),
				Vector2(160, 58), func(): _set_ai_strength(strength_key))
			strength_button.disabled = strength_key == "strong"
			strength_button.tooltip_text = "中档已启用：加强防守，兼顾报听速度和得分" if strength_key == "medium" \
				else ("强档策略后续接入" if strength_key == "strong" else "基础 AI")
			ai_strength_buttons[strength_key] = strength_button
		exit_room_button = _button("退出房间", Vector2(716, 682), Vector2(368, 80), func(): exit_requested.emit())
		exit_room_button.name = "ExitRoomButton"
		replay_export_button = _button("提交本局记录", Vector2(36, 682), Vector2(296, 80), func(): replay_export_requested.emit())
		replay_export_button.name = "SaveRoundButton"
		replay_status = _label("", Vector2(36, 766), Vector2(660, 60), 18)
		replay_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		replay_status.max_lines_visible = 2
		replay_status.clip_text = true
		replay_exporter = preload("res://scripts/ui/ReplayExport.gd").new()
		add_child(replay_exporter)
		replay_exporter.status_changed.connect(_on_export_status)
		exit_confirmation = Panel.new()
		exit_confirmation.name = "ExitConfirmation"
		exit_confirmation.size = TABLE_PANEL_SIZE
		var dim := StyleBoxFlat.new()
		dim.bg_color = Color(0, 0, 0, 0.62)
		exit_confirmation.add_theme_stylebox_override("panel", dim)
		panel.add_child(exit_confirmation)
		# Compact confirm dialog: the old version reused the full 1180x820
		# settings panel, leaving two buttons floating in a huge empty sheet.
		var dialog := Panel.new()
		dialog.name = "ExitDialog"
		dialog.size = Vector2(720, 330)
		dialog.position = (TABLE_PANEL_SIZE - dialog.size) * 0.5
		dialog.add_theme_stylebox_override("panel", style)
		exit_confirmation.add_child(dialog)
		var question := _label("确定退出当前房间？\n退出后返回主菜单", Vector2(40, 42), Vector2(640, 100), 30)
		question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		question.reparent(dialog, false)
		confirm_exit_button = _button("退出房间", Vector2(48, 176), Vector2(288, 126), func(): exit_confirmed.emit())
		confirm_exit_button.reparent(dialog, false)
		var return_label := "继续游戏"
		cancel_exit_button = _button(return_label, Vector2(384, 176), Vector2(288, 126), _cancel_exit)
		cancel_exit_button.reparent(dialog, false)
		exit_confirmation.hide()
	AudioManager.settings_changed.connect(_sync)
	GameConfig.voice_chat_settings_changed.connect(_sync_voice_settings)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_sync()
	sync_timing_controls()
	_sync_ai_strength()
	overlay.hide()

func _exit_tree() -> void:
	if GameConfig.voice_chat_settings_changed.is_connected(_sync_voice_settings):
		GameConfig.voice_chat_settings_changed.disconnect(_sync_voice_settings)

func _make_knob(fill: Color, border: Color) -> Texture2D:
	var image := Image.create(SLIDER_KNOB, SLIDER_KNOB, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var center := Vector2(SLIDER_KNOB * 0.5 - 0.5, SLIDER_KNOB * 0.5 - 0.5)
	var outer := SLIDER_KNOB * 0.5 - 2.0
	var inner := outer - 4.0
	for y in SLIDER_KNOB:
		for x in SLIDER_KNOB:
			var distance := Vector2(x, y).distance_to(center)
			if distance <= inner:
				image.set_pixel(x, y, fill)
			elif distance <= outer:
				image.set_pixel(x, y, border)
	return ImageTexture.create_from_image(image)

func _style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#102e27")
	track.border_color = Color("#526c58")
	track.set_border_width_all(1)
	track.set_corner_radius_all(7)
	track.content_margin_top = 10.0
	track.content_margin_bottom = 10.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#d7b56e")
	fill.set_corner_radius_all(7)
	fill.content_margin_top = 10.0
	fill.content_margin_bottom = 10.0
	var highlight := fill.duplicate() as StyleBoxFlat
	highlight.bg_color = Color("#f1d28a")
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", highlight)
	slider.add_theme_icon_override("grabber", _slider_knob)
	slider.add_theme_icon_override("grabber_highlight", _slider_knob_hot)
	slider.add_theme_icon_override("grabber_disabled", _slider_knob)
	slider.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	slider.focus_mode = Control.FOCUS_ALL

func _slider(pos: Vector2, width: float, maximum: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.position = pos
	slider.size = Vector2(width, SLIDER_HEIGHT)
	slider.custom_minimum_size = slider.size
	slider.max_value = maximum
	slider.step = step
	_style_slider(slider)
	panel.add_child(slider)
	return slider

func _slider_row(title: String, pos: Vector2, maximum: float, step: float) -> Array:
	_label(title, pos, Vector2(500, 30), 24)
	var slider := _slider(pos + Vector2(0, 34), 408, maximum, step)
	var value := _label("", pos + Vector2(420, 34), Vector2(80, SLIDER_HEIGHT), 24)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return [slider, value]

func _timing_slider(title: String, y: float, apply: Callable) -> HSlider:
	var row := _slider_row(title, Vector2(584, y), GameConfig.MAX_SPEED_SECONDS, GameConfig.SPEED_STEP_SECONDS)
	var slider: HSlider = row[0]
	var label: Label = row[1]
	_timing_labels[slider] = label
	slider.drag_started.connect(func(): _timing_drags[slider] = true)
	slider.drag_ended.connect(func(changed: bool):
		_timing_drags.erase(slider)
		if changed and slider.editable: apply.call(slider.value))
	slider.value_changed.connect(func(seconds: float):
		label.text = "%.1f s" % seconds
		if not _timing_drags.has(slider) and slider.editable: apply.call(seconds))
	return slider

func _label(text: String, pos: Vector2, dimensions: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#f1e7cb"))
	panel.add_child(label)
	return label

func _button(text: String, pos: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = dimensions
	button.add_theme_font_size_override("font_size", 25)
	STYLE.button(button, text == "继续游戏")
	button.pressed.connect(callback)
	panel.add_child(button)
	return button

func _layout() -> void:
	MOTION.stop(panel)
	var viewport_size := get_viewport().get_visible_rect().size
	# 牌桌使用横屏拉伸画布；按实际屏幕大小调整面板，
	# 避免手机上再被整个游戏的缩放缩小一次。
	var screen_scale := get_viewport().get_screen_transform().get_scale().abs()
	var available := STYLE.usable_rect(overlay)
	if not available.has_area(): available = Rect2(Vector2.ZERO, viewport_size)
	var physical_size := available.size * screen_scale
	var dimensions := TABLE_PANEL_SIZE if table_mode else PANEL_SIZE
	var physical_factor := minf(1.0, minf((physical_size.x - 32) / dimensions.x, (physical_size.y - 32) / dimensions.y))
	panel.scale = Vector2.ONE * maxf(0.1, physical_factor / maxf(0.01, screen_scale.x))
	panel.position = available.position + (available.size - dimensions * panel.scale) / 2.0

func _sync() -> void:
	for channel in sliders:
		sliders[channel].set_value_no_signal(roundf(float(AudioManager.volumes[channel]) * 100.0))
		percentages[channel].text = "%d%%" % roundi(float(AudioManager.volumes[channel]) * 100.0)
	_sync_voice_settings()
	_sync_score_details_button()
	if hand_sort_button != null:
		hand_sort_button.text = "排序：宽张" if GameConfig.hand_sort_priority == "wide" else "排序：牌型"

func _toggle_hand_sort_priority() -> void:
	GameConfig.set_hand_sort_priority("pattern" if GameConfig.hand_sort_priority == "wide" else "wide", persist_changes)
	_sync()

func _sync_voice_settings() -> void:
	if mic_gain_slider == null or remote_volume_slider == null:
		return
	mic_gain_slider.set_value_no_signal(roundf(GameConfig.voice_chat_mic_gain * 100.0))
	remote_volume_slider.set_value_no_signal(roundf(GameConfig.voice_chat_remote_volume * 100.0))
	mic_gain_percent.text = "%d%%" % roundi(GameConfig.voice_chat_mic_gain * 100.0)
	remote_volume_percent.text = "%d%%" % roundi(GameConfig.voice_chat_remote_volume * 100.0)

func _on_mic_gain_changed(value: float) -> void:
	GameConfig.set_voice_chat_mic_gain(value / 100.0, persist_changes)
	_sync_voice_settings()

func _on_remote_volume_changed(value: float) -> void:
	GameConfig.set_voice_chat_remote_volume(value / 100.0, persist_changes)
	_sync_voice_settings()

func _on_slider(value: float, channel: String) -> void:
	AudioManager.set_volume(channel, value / 100.0, persist_changes)

func _toggle_debug() -> void:
	GameConfig.set_debug_enabled(not GameConfig.debug_enabled, persist_changes)
	if debug_button != null:
		debug_button.text = "关闭debug" if GameConfig.debug_enabled else "开启debug"
	if auto_test_button != null:
		auto_test_button.visible = table_mode and GameConfig.debug_enabled
	if auto_test_500_button != null:
		auto_test_500_button.visible = table_mode and GameConfig.debug_enabled

func _set_ai_speed(seconds: float) -> void:
	ai_speed_selected.emit("%.2f" % seconds)

func _set_ai_strength(strength_key: String) -> void:
	var network := get_node_or_null("/root/Network")
	if network != null and network.mode != "" and network.net_node != null:
		if not network.net_node.is_room_owner(): return
		network.net_node.set_ai_strength(strength_key)
	GameConfig.set_ai_strength(strength_key, persist_changes)
	_sync_ai_strength()
	ai_strength_selected.emit(strength_key)

func _set_tile_speed(seconds: float) -> void:
	GameConfig.set_tile_animation_seconds(seconds, persist_changes)
	var network := get_node_or_null("/root/Network")
	if network != null and network.mode != "" and network.net_node != null:
		network.net_node.set_opening_speed(GameConfig.opening_speed_key())

func _set_settlement_speed(seconds: float) -> void:
	var network := get_node_or_null("/root/Network")
	if network != null and network.mode != "" and network.net_node != null:
		if not network.net_node.is_room_owner(): return
		network.net_node.set_settlement_speed("%.2f" % seconds)
	GameConfig.set_settlement_speed("%.2f" % seconds, persist_changes)

func _toggle_score_details() -> void:
	GameConfig.set_score_details_enabled(not GameConfig.score_details_enabled, persist_changes)
	_sync_score_details_button()

func _sync_score_details_button() -> void:
	if score_details_button == null:
		return
	score_details_button.text = "详细：开" if GameConfig.score_details_enabled else "详细：关"
	score_details_button.modulate = Color("#f4df9f") if GameConfig.score_details_enabled else Color.WHITE

func _sync_ai_strength() -> void:
	var network := get_node_or_null("/root/Network")
	var editable: bool = network == null or network.mode == "" or network.net_node == null or network.net_node.is_room_owner()
	for speed_key in ai_strength_buttons:
		ai_strength_buttons[speed_key].disabled = not editable or speed_key == "strong"
		ai_strength_buttons[speed_key].modulate = Color("#f4df9f") if speed_key == GameConfig.effective_ai_strength() else Color.WHITE

func sync_timing_controls() -> void:
	if not table_mode: return
	var ai_key: String = GameConfig.ai_speed
	var network := get_node_or_null("/root/Network")
	var editable := true
	if network != null and network.mode != "" and network.net_node != null:
		ai_key = str(network.net_node.lobby.get("ai_speed", "fast"))
		editable = network.net_node.is_room_owner()
	for slider in [tile_speed_slider, ai_speed_slider, settlement_speed_slider]:
		slider.editable = editable
		slider.modulate = Color.WHITE if editable else Color(1.0, 1.0, 1.0, 0.55)
		slider.tooltip_text = "联机房间速度由房主设置" if not editable else ""
	_sync_timing_value(tile_speed_slider, GameConfig.tile_motion_seconds())
	_sync_timing_value(ai_speed_slider, GameConfig.ai_speed_seconds(ai_key))
	_sync_timing_value(settlement_speed_slider, GameConfig.settlement_step_seconds())
	_sync_ai_strength()

func _sync_timing_value(slider: HSlider, seconds: float) -> void:
	if _timing_drags.has(slider): return
	slider.set_value_no_signal(seconds)
	_timing_labels[slider].text = "%.1f s" % seconds

func open() -> void:
	_sync()
	sync_timing_controls()
	_sync_ai_strength()
	_layout()
	MOTION.appear(overlay)
	MOTION.slide_in(panel)

func confirm_exit() -> void:
	open()
	if exit_confirmation != null: exit_confirmation.show()

func submit_replay(round_state: RoundState) -> void:
	if replay_exporter != null: replay_exporter.submit_round(round_state)

func _on_export_status(busy: bool, message: String) -> void:
	replay_export_button.disabled = busy
	replay_export_button.text = ("已登记提交" if message.contains("结束后") else "正在提交…") if busy else "提交本局记录"
	replay_status.text = message
	replay_status.tooltip_text = message

func close(persist: bool = true) -> void:
	if persist and persist_changes:
		AudioManager.save_settings()
	MOTION.stop(overlay)
	MOTION.stop(panel)
	overlay.hide()
	if exit_confirmation != null: exit_confirmation.hide()

func _cancel_exit() -> void:
	# 取消退出时直接回牌桌，不再停留在设置页。
	if exit_confirmation != null:
		exit_confirmation.hide()
	close()

func is_open() -> bool:
	return overlay != null and overlay.visible

func _unhandled_key_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		if exit_confirmation != null and exit_confirmation.visible: exit_confirmation.hide()
		else: close()
		get_viewport().set_input_as_handled()
