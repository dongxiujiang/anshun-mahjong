extends Button
## 新中式玉石鎏金圆形操作按钮；合法动作仍严格来自权威下发。
var action := ""
const COLORS := {
	"win": "b93232", "self_win": "b93232",
	"pong": "c98d24", "kong": "c77a1f", "concealed_kong": "227a57", "add_kong": "c77a1f",
	"pass": "1e6f74", "ready": "2c7250", "discard": "2b6088",
}
var _pulse := 0.0

func configure(kind: String, title: String, callback: Callable) -> void:
	action = kind; text = title; accessibility_name = title; tooltip_text = title
	custom_minimum_size = Vector2(90, 90)
	pressed.connect(callback)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_disabled_color", "icon_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	for signal_name in ["mouse_entered", "mouse_exited", "button_down", "button_up", "focus_entered", "focus_exited", "resized", "theme_changed"]:
		connect(signal_name, queue_redraw)
	set_process(action in ["win", "self_win"])

func _process(delta: float) -> void:
	if not is_visible_in_tree() or disabled:
		return
	_pulse += delta * 4.2
	queue_redraw()

func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	var base := Color(COLORS.get(action, "2c7250"))
	if disabled:
		base = Color("5a6660")
	elif is_pressed():
		base = base.darkened(0.18)
	elif is_hovered():
		base = base.lightened(0.14)
	# 胡牌/自摸按钮外圈暖金呼吸光晕
	if not disabled and action in ["win", "self_win"]:
		var wave := 0.5 + 0.5 * sin(_pulse)
		draw_circle(center, radius + 3.0 + wave * 2.5, Color(1.0, 0.78, 0.25, 0.18 + 0.16 * wave))
	# 底部柔影
	draw_circle(center + Vector2(0, 4.5), radius, Color(0, 0, 0, 0.36))
	# 外层鎏金金属镶圈
	draw_circle(center, radius, Color("#9e7939") if not disabled else Color("#4a554f"))
	draw_circle(center, radius - 2.2, base.darkened(0.32))
	# 玉石温润渐变光泽层
	for i in range(1, 10):
		var fraction := i / 10.0
		draw_circle(center - Vector2(0, 1.5 * i), (radius - 2.6) * (1.0 - fraction * 0.48), base.lightened(fraction * 0.26))
	# 上半弧温润月牙高光
	draw_arc(center, radius - 5.5, -PI * 0.82, -PI * 0.18, 28, Color(1.0, 0.96, 0.85, 0.28 if not disabled else 0.10), 2.4, true)
	# 双层精细鎏金环线
	draw_arc(center, radius - 0.8, 0, TAU, 64, Color(1.0, 0.90, 0.62, 0.88 if not disabled else 0.35), 1.8, true)
	draw_arc(center, radius - 4.2, 0, TAU, 56, Color(1.0, 0.94, 0.78, 0.36 if not disabled else 0.15), 1.0, true)
	if has_focus():
		draw_arc(center, radius - 3.0, 0, TAU, 64, Color.WHITE, 2.0, true)
	var font := get_theme_default_font()
	var visual_scale := minf(size.x, size.y) / 90.0
	var font_size := maxi(14, roundi((31 if text.length() <= 2 else 23) * visual_scale))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center + Vector2(-width * 0.5, font_size * 0.35 - (9.0 if icon else 0.0))
	draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.18, 0.09, 0.04, 0.72))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#fff6dc") if not disabled else Color("#bcc3be"))
	if icon:
		var image_size := Vector2(20, 26) * visual_scale
		draw_texture_rect(icon, Rect2(center + Vector2(-10, 12) * visual_scale, image_size), false)
