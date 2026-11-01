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
	_label.position = Vector2(24, 18)
	_label.size = Vector2(220, 40)
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
	_label.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.02, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

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
