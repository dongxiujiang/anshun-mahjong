extends Button
## 新中式玉石鎏金圆形操作按钮；合法动作仍严格来自权威下发。
var action := ""
var quality := "detail"
const COLORS := {
	"win": "b93232", "self_win": "b93232",
	"pong": "c98d24", "kong": "c77a1f", "concealed_kong": "227a57", "add_kong": "c77a1f",
	"pass": "2a4f52", "ready": "2c7250", "discard": "2b6088",
}
var _pulse := 0.0
var _appear := 0.0

func _ready() -> void:
	_appear = 0.0
	visibility_changed.connect(_sync_processing)
	_sync_processing()

func configure(kind: String, title: String, callback: Callable) -> void:
	action = kind; text = title; accessibility_name = title; tooltip_text = title
	custom_minimum_size = Vector2(90, 90)
	pressed.connect(callback)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_disabled_color", "icon_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	for signal_name in ["mouse_entered", "mouse_exited", "button_down", "button_up", "focus_entered", "focus_exited", "resized", "theme_changed"]:
		connect(signal_name, queue_redraw)
	_sync_processing()

func apply_quality(value: String) -> void:
	var next := "detail" if value == "detail" else "smooth"
	if quality == next:
		return
	quality = next
	_sync_processing()
	queue_redraw()

func _sync_processing() -> void:
	set_process(_appear < 1.0 or (quality == "detail" and action in ["win", "self_win"] and not disabled and is_visible_in_tree()))

func _process(delta: float) -> void:
	_appear = minf(1.0, _appear + delta / 0.13)
	if quality == "detail" and action in ["win", "self_win"] and not disabled and is_visible_in_tree():
		_pulse += delta * 4.2
	_sync_processing()
	queue_redraw()

func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5

func _draw() -> void:
	_sync_processing()
	var center := size * 0.5
	var eased := 1.0 + 2.70158 * pow(_appear - 1.0, 3.0) + 1.70158 * pow(_appear - 1.0, 2.0)
	var radius := (minf(size.x, size.y) * 0.5 - 4.0) * lerpf(0.78, 1.0, eased)
	if is_pressed() and not disabled:
		radius *= 0.93
		center.y += 1.8
	var base := Color(COLORS.get(action, "2c7250"))
	if disabled:
		base = Color("5a6660")
	elif is_pressed():
		base = base.darkened(0.18)
	elif is_hovered():
		base = base.lightened(0.14)
	if quality == "smooth":
		draw_circle(center + Vector2(0, 2.0), radius, Color(0, 0, 0, 0.14))
		draw_circle(center, radius, base)
		draw_arc(center, radius - 0.6, 0, TAU, 48, base.lightened(0.32), 1.2, true)
	else:
		# 胡牌印章的暖金光晕留在柔影后方。
		if not disabled and action in ["win", "self_win"]:
			var wave := 0.5 + 0.5 * sin(_pulse)
			draw_circle(center, radius + 3.0 + wave * 1.5, Color(1.0, 0.78, 0.25, 0.10 + 0.08 * wave))
		var shadow_center := center + Vector2(0, 5.0)
		draw_circle(shadow_center, radius + 1.5, Color(0, 0, 0, 0.12))
		draw_circle(shadow_center, radius - 1.0, Color(0, 0, 0, 0.24))
		var metal_alpha := 0.35 if disabled else 0.9
		draw_circle(center, radius, Color("#51402a") if not disabled else Color("#4a554f"))
		draw_arc(center, radius - 1.6, -PI * 1.25, -PI * 0.25, 40, Color(1.0, 0.949, 0.745, metal_alpha), 2.6, true)
		draw_arc(center, radius - 1.6, -PI * 0.25, PI * 0.75, 40, Color(0.424, 0.290, 0.114, metal_alpha), 2.6, true)
		draw_circle(center, radius - 3.2, base.darkened(0.55))
		# 偏向左上光源的温润凸面，外围保留深色内凹槽。
		for i in range(10):
			var fraction := i / 9.0
			draw_circle(center - Vector2(3, 8) * fraction, (radius - 4.4) * (1.0 - fraction * 0.52), base.lightened(fraction * 0.28))
		draw_arc(center, radius - 6.8, -PI * 0.85, -PI * 0.20, 32, Color(1.0, 0.97, 0.88, 0.30 if not disabled else 0.10), 2.2, true)
		draw_arc(center, radius - 5.2, PI * 0.15, PI * 0.78, 28, Color(1.0, 0.86, 0.52, 0.24 if not disabled else 0.08), 1.2, true)
		draw_arc(center, radius - 8.8, 0, TAU, 56, Color(0.45, 0.31, 0.12, 0.45 if not disabled else 0.18), 0.8, true)
	if has_focus():
		draw_arc(center, radius - 3.0, 0, TAU, 64, Color.WHITE, 2.0, true)
	var font := get_theme_default_font()
	var visual_scale := minf(size.x, size.y) / 90.0
	var font_size := maxi(14, roundi((31 if text.length() <= 2 else 23) * visual_scale))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var baseline := center + Vector2(-width * 0.5, font_size * 0.35 - (9.0 if icon else 0.0))
	if quality == "detail":
		draw_string(font, baseline + Vector2(0.8, 1.8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.10, 0.05, 0.02, 0.75))
		draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.18, 0.09, 0.04, 0.72))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#fff8e3") if not disabled else Color("#bcc3be"))
	if icon:
		var image_size := Vector2(20, 26) * visual_scale
		draw_texture_rect(icon, Rect2(center + Vector2(-10, 12) * visual_scale, image_size), false)
