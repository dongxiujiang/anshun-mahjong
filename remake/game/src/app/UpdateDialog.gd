extends Control

signal closed
signal check_requested
signal download_requested
signal cancel_download_requested
signal apply_requested
signal rollback_requested

const UI := preload("res://src/app/AppTheme.gd")
var _snapshot: Dictionary = {}
var _panel: PanelContainer
var _badge: Label
var _version: Label
var _message: Label
var _details: PanelContainer
var _remote: Label
var _notes: Label
var _scroll: ScrollContainer
var _progress: ProgressBar
var _progress_text: Label
var _primary: Button
var _secondary: Button
var _rollback: Button
var _previous_focus: WeakRef

func _ready() -> void:
	theme = UI.menu_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.05, 0.72)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.elevated_card(Color("#102821f6"), 18, 22, UI.GOLD_BORDER, 2, 16))
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := UI.label("软件更新", 27, UI.GOLD_BRIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_badge = UI.label("版本检查", 14, UI.MUTED)
	header.add_child(_badge)
	_version = UI.label("", 16, UI.MUTED)
	content.add_child(_version)
	_message = UI.label("", 18)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_message)
	_details = PanelContainer.new()
	_details.add_theme_stylebox_override("panel", UI.card(Color("#0b201b"), 12, 12, UI.BORDER))
	content.add_child(_details)
	var detail_col := VBoxContainer.new()
	_details.add_child(detail_col)
	_remote = UI.label("", 17, UI.GOLD)
	_remote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_col.add_child(_remote)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_col.add_child(_scroll)
	_notes = UI.label("", 16)
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_notes)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 14
	_progress.show_percentage = false
	content.add_child(_progress)
	_progress_text = UI.label("", 14, UI.MUTED)
	content.add_child(_progress_text)
	var footer := HFlowContainer.new()
	footer.add_theme_constant_override("h_separation", 10)
	content.add_child(footer)
	_rollback = UI.button("回退上一补丁", rollback_requested.emit)
	footer.add_child(_rollback)
	_primary = UI.button("检查更新", _primary_action, true)
	footer.add_child(_primary)
	_secondary = UI.button("关闭", close_dialog)
	footer.add_child(_secondary)
	resized.connect(_fit)
	content.minimum_size_changed.connect(_fit.call_deferred)
	hide()
	apply_snapshot(_snapshot)

func _fit() -> void:
	if not is_instance_valid(_panel): return
	var width := minf(560, maxf(280, size.x - 24))
	_panel.custom_minimum_size.x = width
	_panel.size = Vector2(width, _panel.get_combined_minimum_size().y)
	_panel.position = Vector2(maxf(12.0, (size.x - _panel.size.x) * 0.5), maxf(12.0, (size.y - _panel.size.y) * 0.5))

func apply_snapshot(snap: Dictionary) -> void:
	_snapshot = snap.duplicate(true)
	if not is_instance_valid(_panel): return
	var state := str(snap.get("state", "idle"))
	var latest: Dictionary = snap.get("latest", {})
	var patch: bool = latest.get("kind", "") == "patch"
	_badge.text = "版本检查" if latest.is_empty() else ("热补丁 · 免重装" if patch else "完整新版")
	_badge.add_theme_color_override("font_color", UI.MUTED if latest.is_empty() else (UI.GOLD if patch else Color("#ffcd83")))
	_badge.add_theme_stylebox_override("normal", UI.card(Color("#20342b") if latest.is_empty() or patch else Color("#48351b"), 10, 6, UI.BORDER if latest.is_empty() else UI.GOLD_BORDER))
	_version.text = "当前版本 v%s%s" % [snap.get("current_version", "2.4.3"), " · 热补丁生效中" if snap.get("is_patched", false) else ""]
	_message.text = str(snap.get("message", "检查是否有可用更新"))
	_details.visible = not latest.is_empty()
	_remote.text = "新版 v%s · %.2f MB" % [latest.get("version", ""), float(latest.get("size_bytes", 0)) / 1048576.0]
	var lines := PackedStringArray()
	var notes = latest.get("notes", latest.get("changelog", []))
	if notes is Array:
		for note in notes: lines.append("• " + str(note))
	_notes.text = "\n".join(lines)
	_scroll.custom_minimum_size.y = minf(140, maxf(36, lines.size() * 26))
	_progress.visible = state in ["downloading", "ready"]
	_progress_text.visible = _progress.visible
	var total := int(snap.get("total_bytes", 0))
	var downloaded := int(snap.get("downloaded_bytes", 0))
	_progress.value = 100 if state == "ready" else (100.0 * downloaded / total if total > 0 else 0.0)
	_progress_text.text = "校验完成" if state == "ready" else "%.2f / %.2f MB" % [downloaded / 1048576.0, total / 1048576.0]
	_rollback.visible = bool(snap.get("can_rollback", false)) and state != "downloading"
	_primary.disabled = state == "checking"
	match state:
		"checking": _primary.text = "正在检查…"
		"available": _primary.text = "下载热补丁" if patch else "下载新版安装包"
		"downloading": _primary.text = "取消下载"
		"ready": _primary.text = "重启生效" if patch else "打开安装包"
		_: _primary.text = "检查更新"
	_secondary.text = "稍后再说" if state in ["available", "ready"] else "关闭"
	var focus_buttons: Array[Button] = []
	for button in [_rollback, _primary, _secondary]:
		if button.visible and not button.disabled: focus_buttons.append(button)
	for index in focus_buttons.size():
		var button := focus_buttons[index]
		var next := focus_buttons[(index + 1) % focus_buttons.size()].get_path()
		var previous := focus_buttons[(index + focus_buttons.size() - 1) % focus_buttons.size()].get_path()
		button.focus_next = next
		button.focus_previous = previous
		button.focus_neighbor_left = previous
		button.focus_neighbor_right = next
		button.focus_neighbor_top = previous
		button.focus_neighbor_bottom = next
	_fit.call_deferred()

func _primary_action() -> void:
	match str(_snapshot.get("state", "idle")):
		"available": download_requested.emit()
		"downloading": cancel_download_requested.emit()
		"ready": apply_requested.emit()
		_: check_requested.emit()

func open_dialog(snap: Dictionary) -> void:
	if not visible:
		var focused := get_viewport().gui_get_focus_owner()
		_previous_focus = weakref(focused) if focused != null else null
	apply_snapshot(snap)
	show()
	UI.focus_later(_secondary if _primary.disabled else _primary)

func close_dialog() -> void:
	hide()
	closed.emit()
	if _previous_focus != null:
		var control = _previous_focus.get_ref()
		if is_instance_valid(control): UI.focus_later(control)

func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"): return
	get_viewport().set_input_as_handled()
	close_dialog()
