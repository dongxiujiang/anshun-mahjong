class_name UpdatePanel
extends CanvasLayer
const PANEL_SIZE := Vector2(860, 640)
var overlay: Control
var panel: Panel
var summary: Label
var notes: TextEdit
var progress: ProgressBar
var detail: Label
var action_button: Button
var check_button: Button
var rollback_button: Button
var _manager: Node

func _ready() -> void:
	layer = 25
	_manager = get_node("/root/UpdateManager")
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.04, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	panel = Panel.new()
	panel.size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1e4234")
	style.border_color = Color("#cbb279")
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	panel.add_theme_stylebox_override("panel", style)
	var ui_theme := Theme.new()
	ui_theme.default_font = TileView._font()
	ui_theme.default_font_size = 24
	panel.theme = ui_theme
	overlay.add_child(panel)
	_label("游戏更新", Vector2(32, 20), Vector2(620, 48), 34)
	_label("当前版本 " + _manager.current_version(), Vector2(32, 82), Vector2(796, 36), 23)
	summary = _label("", Vector2(32, 128), Vector2(796, 64), 25)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes = TextEdit.new()
	notes.position = Vector2(32, 206)
	notes.size = Vector2(796, 222)
	notes.editable = false
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	notes.placeholder_text = "有新版本时，这里会显示更新内容"
	notes.add_theme_font_size_override("font_size", 23)
	panel.add_child(notes)
	progress = ProgressBar.new()
	progress.position = Vector2(32, 446)
	progress.size = Vector2(796, 24)
	progress.show_percentage = true
	panel.add_child(progress)
	detail = _label("", Vector2(32, 480), Vector2(796, 60), 21)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	check_button = _button("检查更新", Vector2(32, 554), Vector2(224, 58), func(): _manager.check_updates())
	action_button = _button("下载新版", Vector2(274, 554), Vector2(310, 58), _action)
	_button("关闭", Vector2(602, 554), Vector2(226, 58), close)
	rollback_button = _button("恢复上一小版本", Vector2(610, 20), Vector2(218, 48), func(): _manager.rollback_and_restart())
	rollback_button.add_theme_font_size_override("font_size", 19)
	_manager.state_changed.connect(_sync)
	get_viewport().size_changed.connect(_layout)
	_sync()
	_layout()
	overlay.hide()

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
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#345e48") if state == "normal" else Color("#48795a")
		if state == "disabled": style.bg_color = Color("#304b3c")
		style.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	panel.add_child(button)
	return button

func _layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_scale := get_viewport().get_screen_transform().get_scale().abs()
	var physical_size := viewport_size * screen_scale
	var factor := minf(1.0, minf((physical_size.x - 32.0) / PANEL_SIZE.x, (physical_size.y - 32.0) / PANEL_SIZE.y))
	panel.scale = Vector2.ONE * maxf(0.1, factor / maxf(0.01, screen_scale.x))
	panel.position = (viewport_size - PANEL_SIZE * panel.scale) / 2.0

func _sync() -> void:
	summary.text = _manager.message
	rollback_button.visible = get_node("/root/PatchBoot").can_rollback()
	rollback_button.disabled = _manager.state in ["checking", "downloading"]
	var current_notes := str(_manager.latest.get("notes", ""))
	if notes.text != current_notes: notes.text = current_notes
	check_button.disabled = _manager.state in ["checking", "downloading"]
	progress.visible = _manager.state == "downloading"
	progress.value = clampf(100.0 * _manager.downloaded_bytes / maxf(1, _manager.total_bytes), 0.0, 100.0)
	progress.show_percentage = _manager.total_bytes > 0
	action_button.disabled = false
	match _manager.state:
		"downloading":
			action_button.text = "取消下载"
			detail.text = "已下载 %.1f MB%s；可关闭此面板继续游玩" % [_manager.downloaded_bytes / 1048576.0, " / %.1f MB" % (_manager.total_bytes / 1048576.0) if _manager.total_bytes > 0 else ""]
		"ready":
			if _manager.latest.get("kind", "full") == "patch":
				action_button.text = "重启应用生效"
				detail.text = "小版本补丁已保存，退出房间和对局后重启即可生效，不需要重新安装"
				if not _manager.can_install():
					action_button.disabled = true
					detail.text = "工程预览已验证补丁下载，请在安装版游戏中重启应用"
			else:
				action_button.text = "重启更新" if _manager.can_install() else "打开下载文件夹"
				detail.text = "大版本需要更新完整应用；请先退出房间和对局"
		"available":
			if _manager.latest.get("kind", "full") == "patch":
				action_button.text = "下载小版本补丁"
				detail.text = "游戏内下载补丁，重启后生效，不需要重新安装"
			elif _manager.latest.platform == "android":
				action_button.text = "下载 APK"
				detail.text = "打开下载页面后，由安卓系统确认安装；请使用同一签名的新版"
			elif _manager.can_download():
				action_button.text = "下载新版"
				detail.text = "下载完成后校验文件，再重启更新；旧程序会保留备份"
			else:
				action_button.text = "打开下载页面"
				detail.text = "前往发布页面下载适合你设备的新版"
		_:
			action_button.text = "下载新版"
			action_button.disabled = true
			detail.text = "更新通过 GitHub Releases 发布，无需连接联机房间"

func _action() -> void:
	match _manager.state:
		"downloading": _manager.cancel_download()
		"ready":
			if _manager.can_install(): _manager.install_and_restart()
			else: _manager.open_download_folder()
		"available":
			if _manager.can_download(): _manager.download_update()
			else: _manager.open_download_page()

func open() -> void:
	_sync()
	_layout()
	overlay.show()
	if _manager.state == "idle": _manager.check_updates()

func close() -> void:
	overlay.hide()

func is_open() -> bool:
	return overlay != null and overlay.visible

func _unhandled_key_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
