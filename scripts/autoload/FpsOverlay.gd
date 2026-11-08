extends CanvasLayer
## 全局帧率显示。独立 CanvasLayer，切场景时仍然保留。

const FONT := preload("res://res/fonts/NotoSansSC-Regular.otf")

var _label: Label
var _accum := 0.0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	_label = Label.new()
	_label.name = "FpsLabel"
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_left = -110.0
	_label.offset_top = 18.0
	_label.offset_right = 110.0
	_label.offset_bottom = 58.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
	_label.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.02, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

func hide_during_settlement(panel: Control) -> void:
	if _label == null:
		return
	_label.hide()
	panel.tree_exited.connect(_label.show, CONNECT_ONE_SHOT)

func _process(delta: float) -> void:
	if _label == null:
		return
	_accum += delta
	if _accum < 0.25:
		return
	_accum = 0.0
	var fps := Performance.get_monitor(Performance.TIME_FPS)
	_label.text = "FPS %d" % roundi(fps)
	if fps >= 58.0:
		_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
	elif fps >= 45.0:
		_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	else:
		_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.28))
