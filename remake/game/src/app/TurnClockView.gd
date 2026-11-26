extends Control
## 精巧新中式倒计时钟：仅在轮到本家操作（出牌/碰杠胡响应）且有倒计时显示，位置绝对固定不跳动。
const UI = preload("res://src/app/AppTheme.gd")
var _number := Label.new()
var _caption := Label.new()
var _phase := ""
var _reminder := false
var _remaining := -1
var _fraction := 0.0

func _init() -> void:
	custom_minimum_size = Vector2(68, 68)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_number); add_child(_caption)
	_caption.hide()
	_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_number.add_theme_font_size_override("font_size", 26)
	_number.add_theme_color_override("font_outline_color", Color("#0b1d17"))
	_number.add_theme_constant_override("outline_size", 3)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 13)
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	_number.position = Vector2.ZERO; _number.size = size
	_caption.position = Vector2(0, size.y + 2); _caption.size = Vector2(size.x, 20)
	queue_redraw()

func show_clock(clock: Dictionary, round_view: Dictionary, viewer: int, suppressed: bool = false) -> void:
	var next := [clock.get("phase", ""), int(clock.get("remaining_ms", -1)), bool(clock.get("reminder", false))]
	var seconds := ceili(float(next[1]) / 1000.0)
	var round_phase: String = str(round_view.get("phase", ""))
	var caption := "等待操作"
	if next[0] == "waiting_animation": caption = "等待动画"
	elif next[0] == "grace": caption = "额外等待"
	elif clock.get("kind") == "response" and round_phase == "turn":
		caption = "自摸选择" if int(round_view.get("turn", -1)) == viewer else "等待自摸选择"
	elif round_phase == "response": caption = "请选择" if not clock.is_empty() else "等待响应"
	elif round_phase == "turn": caption = "请出牌" if int(round_view.get("turn", -1)) == viewer else "对方出牌"
	elif round_phase == "dice": caption = "掷骰子"
	elif round_phase == "dealt": caption = "正在发牌"

	var own_actionable := false
	if not suppressed and not round_view.is_empty() and round_phase in ["turn", "response"] and next[1] >= 0 and next[0] != "waiting_animation":
		if round_view.has("choices"):
			own_actionable = not round_view.get("choices", {}).get("actions", []).is_empty()
		elif round_phase == "turn":
			own_actionable = int(round_view.get("turn", -1)) == viewer
		else:
			own_actionable = not clock.is_empty()

	visible = own_actionable
	_number.text = str(maxi(0, seconds)) if next[1] >= 0 else "·"
	_fraction = clampf(float(maxi(0, int(next[1]))) / maxf(1.0, float(clock.get("duration_ms", 10000))), 0.0, 1.0)
	_caption.text = caption
	_number.accessibility_name = caption + " " + _number.text
	_number.add_theme_color_override("font_color", Color("#ffcf6b") if next[2] else Color("#f7efdc"))
	if _phase != next[0] or _reminder != next[2] or _remaining != seconds:
		_phase = next[0]; _reminder = next[2]; _remaining = seconds; queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := maxf(8.0, minf(size.x, size.y) * 0.5 - 3.0)
	var rim := Color("#f2b84b") if _reminder else Color("#a2beae")
	var glow := Color(0.96, 0.56, 0.16, 0.28) if _reminder else Color(0.24, 0.62, 0.48, 0.14)
	draw_circle(center + Vector2(0, 2), radius, Color(0, 0, 0, 0.34))
	draw_circle(center, radius + 2.0, glow)
	draw_circle(center, radius, Color("#0d2620f2"))
	draw_arc(center, radius - 1.0, 0.0, TAU, 56, rim, 2.0, true)
	draw_arc(center, radius * 0.84, 0.0, TAU, 48, Color(rim.r, rim.g, rim.b, 0.22), 2.5, true)
	draw_arc(center, radius * 0.84, -PI * 0.5, -PI * 0.5 + TAU * _fraction, 48, Color("#ffb94f") if _reminder else Color("#e2c170"), 3.2, true)
