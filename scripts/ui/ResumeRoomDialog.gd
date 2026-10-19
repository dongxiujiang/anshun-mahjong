extends Control
## Game-styled prompt for the saved online room. Kept local to MainMenu so the
## same Panel/Button language is used as the table and settings screens.

signal confirmed
signal leave_requested

const STYLE := preload("res://scripts/ui/UiStyle.gd")
const MOTION := preload("res://scripts/ui/UiMotion.gd")
const PANEL_SIZE := Vector2(760, 360)

var _panel: Panel
var _body: Label
var _resume_button: Button
var _leave_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.04, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_panel = Panel.new()
	_panel.size = PANEL_SIZE
	_panel.add_theme_stylebox_override("panel", STYLE.panel())
	var panel_theme := Theme.new()
	panel_theme.default_font = TileView._font()
	panel_theme.default_font_size = 22
	_panel.theme = panel_theme
	add_child(_panel)
	_label("返回上次房间", Vector2(38, 30), Vector2(684, 44), 32, STYLE.GOLD)
	_body = _label("", Vector2(38, 92), Vector2(684, 100), 22, STYLE.MUTED)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_resume_button = _button("返回房间", Vector2(38, 246), Vector2(330, 76), true, func():
		confirmed.emit()
		hide())
	_leave_button = _button("离开", Vector2(392, 246), Vector2(330, 76), false, func():
		leave_requested.emit()
		hide())
	_leave_button.name = "LeaveRoomButton"
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
	var viewport := get_viewport_rect().size
	var factor := minf(1.0, minf((viewport.x - 32.0) / PANEL_SIZE.x, (viewport.y - 32.0) / PANEL_SIZE.y))
	_panel.scale = Vector2.ONE * maxf(0.1, factor)
	_panel.position = (viewport - PANEL_SIZE * _panel.scale) * 0.5

func open(room_number: String) -> void:
	_body.text = "发现上次联机房间 %s。\n是否恢复原来的座位和对局？\n离开后会清除这个房间记录。" % room_number
	show()
	_layout()
	MOTION.appear(self)
	_resume_button.grab_focus()
