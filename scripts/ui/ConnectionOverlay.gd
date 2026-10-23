extends Control
## Shared connection/reconnect card. Uses the same panel, typography, buttons
## and motion as the lobby, settings and saved-room prompt.

signal retry_requested
signal leave_requested

const STYLE := preload("res://scripts/ui/UiStyle.gd")
const MOTION := preload("res://scripts/ui/UiMotion.gd")
const PANEL_SIZE := Vector2(760, 360)

var _panel: Panel
var _title: Label
var _body: Label
var _progress: Label
var _retry_button: Button
var _leave_button: Button

func _ready() -> void:
	name = "ConnectionOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 320
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.02, 0.06, 0.04, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_panel = Panel.new()
	_panel.name = "ConnectionCard"
	_panel.size = PANEL_SIZE
	_panel.add_theme_stylebox_override("panel", STYLE.panel())
	var panel_theme := Theme.new()
	panel_theme.default_font = TileView._font()
	panel_theme.default_font_size = 22
	_panel.theme = panel_theme
	add_child(_panel)
	_title = _label("", Vector2(38, 28), Vector2(684, 44), 32, STYLE.GOLD)
	_body = _label("", Vector2(38, 88), Vector2(684, 96), 22, STYLE.MUTED)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress = _label("", Vector2(38, 188), Vector2(684, 36), 20, STYLE.GOLD)
	_retry_button = _button("重试", Vector2(38, 246), Vector2(330, 76), true, func():
		retry_requested.emit())
	_retry_button.name = "RetryConnectionButton"
	_leave_button = _button("返回大厅", Vector2(392, 246), Vector2(330, 76), false, func():
		leave_requested.emit()
		close())
	_leave_button.name = "LeaveConnectionButton"
	resized.connect(_layout)
	_layout()
	hide()

func _label(text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.add_theme_font_override("font", TileView._font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_panel.add_child(label)
	return label

func _button(text: String, pos: Vector2, dimensions: Vector2, primary: bool, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = pos
	button.size = dimensions
	button.add_theme_font_override("font", TileView._font())
	button.add_theme_font_size_override("font_size", 28)
	STYLE.button(button, primary)
	button.pressed.connect(callback)
	_panel.add_child(button)
	return button

func _layout() -> void:
	if _panel == null:
		return
	var bounds := STYLE.usable_rect(self)
	if not bounds.has_area():
		bounds = Rect2(Vector2.ZERO, get_viewport_rect().size)
	var factor := minf(1.0, minf((bounds.size.x - 32.0) / PANEL_SIZE.x, (bounds.size.y - 32.0) / PANEL_SIZE.y))
	_panel.scale = Vector2.ONE * maxf(0.1, factor)
	_panel.position = bounds.position + (bounds.size - PANEL_SIZE * _panel.scale) * 0.5

func show_reconnecting(attempt: int = 0, maximum: int = 5) -> void:
	var was_visible := visible
	show()
	_title.text = "正在恢复连接"
	_body.text = "联机连接中断，正在恢复原座位和最新牌局。\n请不要退出游戏，恢复后会继续当前对局。"
	_progress.text = "正在连接…" if attempt <= 0 else "第 %d / %d 次尝试" % [attempt, maximum]
	_retry_button.hide()
	_leave_button.text = "取消并返回大厅"
	_layout()
	if not was_visible:
		MOTION.appear(self)
		if MOTION.enabled():
			MOTION.slide_in(_panel)

func show_error(message: String) -> void:
	var was_visible := visible
	show()
	_title.text = "连接未恢复"
	_body.text = message.strip_edges() if message.strip_edges() != "" else "无法恢复原房间，请重试或返回大厅。"
	_progress.text = "原座位会为你保留一段时间。"
	_retry_button.show()
	_leave_button.text = "返回大厅"
	_layout()
	if not was_visible:
		MOTION.appear(self)
		if MOTION.enabled():
			MOTION.slide_in(_panel)

func show_connecting(message: String = "正在连接房间…") -> void:
	var was_visible := visible
	show()
	_title.text = "正在连接"
	_body.text = message
	_progress.text = ""
	_retry_button.hide()
	_leave_button.text = "取消"
	_layout()
	if not was_visible:
		MOTION.appear(self)

func close() -> void:
	MOTION.stop(self)
	hide()

func is_open() -> bool:
	return visible
