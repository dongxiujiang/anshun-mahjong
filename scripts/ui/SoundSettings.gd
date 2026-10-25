class_name SoundSettings
extends CanvasLayer
const STYLE := preload("res://scripts/ui/UiStyle.gd")
const MOTION := preload("res://scripts/ui/UiMotion.gd")
signal exit_requested
signal exit_confirmed
signal ai_speed_selected(speed_key: String)
signal ai_strength_selected(strength_key: String)
signal replay_export_requested
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
var preview_button: Button
var voice_selector: OptionButton
var persist_changes := true
var speed_buttons := {}
var ai_strength_buttons := {}
var draw_speed_buttons := {}
var discard_speed_buttons := {}
var settlement_speed_buttons := {}
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
var exit_room_button: Button
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
	_label("设置自动保存，重启和更新后保留", Vector2(36, 78), Vector2(608, 30), 20)
	for index in UI_CHANNELS.size():
		var channel: String = UI_CHANNELS[index]
		var y := 126.0 + index * 88.0
		# Only the slider remains: playback is controlled by volume 0, with no
		# separate enable switch.
		_label(TITLES[channel], Vector2(28, y), Vector2(280, 62), 24)
		var slider := HSlider.new()
		slider.position = Vector2(324, y)
		slider.size = Vector2(234, SLIDER_HEIGHT)
		slider.custom_minimum_size = Vector2(234, SLIDER_HEIGHT)
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		_style_slider(slider)
		slider.value_changed.connect(_on_slider.bind(channel))
		panel.add_child(slider)
		sliders[channel] = slider
		percentages[channel] = _label("", Vector2(574, y + 12), Vector2(78, 42), 24)
	if table_mode:
		var mic_y := 126.0 + UI_CHANNELS.size() * 88.0
		_label("麦克风音量", Vector2(28, mic_y), Vector2(280, 62), 24)
		mic_gain_slider = HSlider.new()
		mic_gain_slider.position = Vector2(324, mic_y)
		mic_gain_slider.size = Vector2(234, SLIDER_HEIGHT)
		mic_gain_slider.custom_minimum_size = Vector2(234, SLIDER_HEIGHT)
		mic_gain_slider.min_value = 0
		mic_gain_slider.max_value = 200
		mic_gain_slider.step = 1
		_style_slider(mic_gain_slider)
		mic_gain_slider.value_changed.connect(_on_mic_gain_changed)
		panel.add_child(mic_gain_slider)
		mic_gain_percent = _label("", Vector2(574, mic_y + 12), Vector2(78, 42), 24)
		var remote_y := mic_y + 88.0
		_label("他人语音音量", Vector2(28, remote_y), Vector2(280, 62), 24)
		remote_volume_slider = HSlider.new()
		remote_volume_slider.position = Vector2(324, remote_y)
		remote_volume_slider.size = Vector2(234, SLIDER_HEIGHT)
		remote_volume_slider.custom_minimum_size = Vector2(234, SLIDER_HEIGHT)
		remote_volume_slider.min_value = 0
		remote_volume_slider.max_value = 200
		remote_volume_slider.step = 1
		_style_slider(remote_volume_slider)
		remote_volume_slider.value_changed.connect(_on_remote_volume_changed)
		panel.add_child(remote_volume_slider)
		remote_volume_percent = _label("", Vector2(574, remote_y + 12), Vector2(78, 42), 24)
	voice_selector = OptionButton.new()
	voice_selector.position = Vector2(36, 604 if table_mode else 422)
	voice_selector.size = Vector2(172, 62)
	for title in ["柔和女声", "轻朗男声", "清柔女声", "沉稳男声"]:
		voice_selector.add_item(title)
	voice_selector.item_selected.connect(func(seat: int): AudioManager.set_preview_voice_seat(seat, persist_changes))
	panel.add_child(voice_selector)
	preview_button = _button("试听语音", Vector2(220, 604 if table_mode else 422), Vector2(172, 62), _preview_voice)
	debug_button = _button("关闭debug" if GameConfig.debug_enabled else "开启debug",
		Vector2(36, 500 if table_mode else 320), Vector2(300, 64), _toggle_debug)
	debug_button.name = "DebugToggleButton"
	continue_button = _button("继续游戏" if table_mode else "关闭", Vector2(348, 682) if table_mode else Vector2(404, 422), Vector2(296, 80) if table_mode else Vector2(240, 72), close)
	continue_button.name = "ContinueGameButton"
	if table_mode:
		_label("人机出牌 / 碰杠响应", Vector2(716, 24), Vector2(368, 38), 24)
		for item in [["快", "fast"], ["中", "medium"], ["慢", "slow"]]:
			var speed_key: String = item[1]
			var speed_button := _button(item[0], Vector2(716 + speed_buttons.size() * 126, 70), Vector2(116, 64), func(): _set_speed(speed_key))
			speed_button.tooltip_text = "同时调整 AI 出牌等待和碰杠响应"
			speed_buttons[speed_key] = speed_button
		_label("摸牌动画", Vector2(716, 142), Vector2(368, 38), 24)
		_label("出牌动画", Vector2(716, 254), Vector2(368, 38), 24)
		for item in [["瞬间", "instant"], ["快", "fast"], ["正常", "standard"], ["慢", "slow"]]:
			var key: String = item[1]
			draw_speed_buttons[key] = _button(item[0], Vector2(716 + draw_speed_buttons.size() * 94, 184), Vector2(86, 64), func(): _set_tile_speed("draw", key))
			discard_speed_buttons[key] = _button(item[0], Vector2(716 + discard_speed_buttons.size() * 94, 296), Vector2(86, 64), func(): _set_tile_speed("discard", key))
		_label("结算速度", Vector2(716, 366), Vector2(368, 38), 24)
		for item in [["即时", "instant"], ["正常", "standard"], ["慢速", "slow"], ["细看", "detail"]]:
			var settlement_key: String = item[1]
			var speed_button := _button(item[0], Vector2(716 + settlement_speed_buttons.size() * 94, 408), Vector2(86, 64), func(): _set_settlement_speed(settlement_key))
			settlement_speed_buttons[settlement_key] = speed_button
		_label("AI强度", Vector2(716, 488), Vector2(368, 30), 20)
		for item in [["弱", "weak"], ["中", "medium"], ["强", "strong"]]:
			var strength_key: String = item[1]
			var strength_button := _button(item[0], Vector2(716 + ai_strength_buttons.size() * 126, 524),
				Vector2(116, 60), func(): _set_ai_strength(strength_key))
			strength_button.disabled = strength_key != "weak"
			strength_button.tooltip_text = "中、强 AI 策略后续接入；当前仅弱档可用"
			ai_strength_buttons[strength_key] = strength_button
		_label("四项速度独立调整", Vector2(716, 610), Vector2(368, 30), 20)
		exit_room_button = _button("退出房间", Vector2(716, 682), Vector2(368, 80), func(): exit_requested.emit())
		exit_room_button.name = "ExitRoomButton"
		replay_export_button = _button("保存本局记录", Vector2(36, 682), Vector2(296, 80), func(): replay_export_requested.emit())
		replay_export_button.name = "SaveRoundButton"
		replay_status = _label("选择保存位置，建议放在“下载”文件夹，方便查找和发送。", Vector2(36, 766), Vector2(660, 60), 18)
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
		cancel_exit_button = _button(return_label, Vector2(384, 176), Vector2(288, 126), func(): exit_confirmation.hide())
		cancel_exit_button.reparent(dialog, false)
		exit_confirmation.hide()
	AudioManager.settings_changed.connect(_sync)
	GameConfig.voice_chat_settings_changed.connect(_sync_voice_settings)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_sync()
	_update_speed_buttons()
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
	voice_selector.select(AudioManager.preview_voice_seat)
	for channel in sliders:
		sliders[channel].set_value_no_signal(roundf(float(AudioManager.volumes[channel]) * 100.0))
		percentages[channel].text = "%d%%" % roundi(float(AudioManager.volumes[channel]) * 100.0)
	preview_button.disabled = float(AudioManager.volumes.voice) <= 0.0
	_sync_voice_settings()

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

func _preview_voice() -> void:
	AudioManager.preview_voice(voice_selector.selected)

func _toggle_debug() -> void:
	GameConfig.set_debug_enabled(not GameConfig.debug_enabled, persist_changes)
	if debug_button != null:
		debug_button.text = "关闭debug" if GameConfig.debug_enabled else "开启debug"

func _set_speed(speed_key: String) -> void:
	if not table_mode: GameConfig.set_ai_speed(speed_key, persist_changes)
	ai_speed_selected.emit(speed_key)

func _set_ai_strength(strength_key: String) -> void:
	GameConfig.set_ai_strength(strength_key, persist_changes)
	_update_speed_buttons()
	ai_strength_selected.emit(strength_key)

func _set_tile_speed(action: String, speed_key: String) -> void:
	if action == "draw": GameConfig.set_draw_animation_speed(speed_key, persist_changes)
	else: GameConfig.set_discard_animation_speed(speed_key, persist_changes)
	_update_speed_buttons()

func _set_settlement_speed(speed_key: String) -> void:
	GameConfig.set_settlement_speed(speed_key, persist_changes)
	_update_speed_buttons()

func _update_speed_buttons() -> void:
	var selected: String = GameConfig.ai_speed
	var network := get_node_or_null("/root/Network")
	if table_mode and network != null and network.mode != "":
		selected = str(network.net_node.lobby.get("ai_speed", "fast"))
	for speed_key in speed_buttons:
		speed_buttons[speed_key].modulate = Color("#f4df9f") if speed_key == selected else Color.WHITE
	if GameConfig.ai_strength != "weak":
		GameConfig.set_ai_strength("weak", false)
	for strength_key in ai_strength_buttons:
		ai_strength_buttons[strength_key].modulate = Color("#f4df9f") if strength_key == GameConfig.ai_strength else Color.WHITE
	for speed_key in draw_speed_buttons:
		draw_speed_buttons[speed_key].modulate = Color("#f4df9f") if speed_key == GameConfig.draw_animation_speed else Color.WHITE
	for speed_key in discard_speed_buttons:
		discard_speed_buttons[speed_key].modulate = Color("#f4df9f") if speed_key == GameConfig.discard_animation_speed else Color.WHITE
	for speed_key in settlement_speed_buttons:
		settlement_speed_buttons[speed_key].modulate = Color("#f4df9f") if speed_key == GameConfig.settlement_speed else Color.WHITE

func open() -> void:
	_sync()
	_update_speed_buttons()
	_layout()
	MOTION.appear(overlay)
	MOTION.slide_in(panel)
	preview_button.grab_focus()

func confirm_exit() -> void:
	open()
	if exit_confirmation != null: exit_confirmation.show()

func export_replay(round_state: RoundState, local_seat: int) -> void:
	if replay_exporter != null: replay_exporter.export_round(round_state, local_seat)

func _on_export_status(busy: bool, message: String) -> void:
	replay_export_button.disabled = busy
	replay_export_button.text = "选择保存位置…" if busy else "保存本局记录"
	continue_button.disabled = busy
	exit_room_button.disabled = busy
	replay_status.text = message
	replay_status.tooltip_text = message

func close(persist: bool = true) -> void:
	if replay_exporter != null and replay_exporter.busy: return
	if persist and persist_changes:
		AudioManager.save_settings()
	MOTION.stop(overlay)
	MOTION.stop(panel)
	overlay.hide()
	if exit_confirmation != null: exit_confirmation.hide()

func is_open() -> bool:
	return overlay != null and overlay.visible

func _unhandled_key_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		if exit_confirmation != null and exit_confirmation.visible: exit_confirmation.hide()
		else: close()
		get_viewport().set_input_as_handled()
