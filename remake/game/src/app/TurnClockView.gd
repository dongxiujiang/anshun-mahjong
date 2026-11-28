extends Control
## 精巧新中式倒计时钟：仅在轮到本家操作（出牌/碰杠胡响应）且有倒计时显示，位置绝对固定不跳动。
const MotionConfig = preload("res://src/presentation/MotionConfig.gd")
const MotionFX = preload("res://src/presentation/MotionFX.gd")
var quality := MotionConfig.current_quality
var _spec := MotionConfig.section("turn_clock", quality)
var _number := Label.new()
var _caption := Label.new()
var _phase := ""
var _reminder := false
var _remaining := -1
var _fraction := 0.0
var _pulse_time := 0.0

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
	visibility_changed.connect(_visibility_changed)
	hide()
	set_process(false)
	_fit()

func _ready() -> void:
	_sync_pulse()

func apply_quality(value: String) -> void:
	var next := MotionConfig.normalize_quality(value)
	if quality == next:
		return
	quality = next
	_spec = MotionConfig.section("turn_clock", quality)
	_reset_appearance()
	_set_number_color()
	_sync_pulse()
	queue_redraw()

func _reset_appearance() -> void:
	MotionFX.stop(self)
	scale = Vector2.ONE
	_set_appearance_alpha(1.0)

# HudLayout owns modulate.a for user-hidden controls.
func _set_appearance_alpha(alpha: float) -> void:
	self_modulate.a = alpha
	_number.modulate.a = alpha
	_caption.modulate.a = alpha

func _visibility_changed() -> void:
	_sync_pulse()
	_reset_appearance()
	if not is_visible_in_tree():
		return
	var tween := MotionFX._begin(self)
	if tween:
		scale = Vector2.ONE * _spec.show_from_scale
		_set_appearance_alpha(0.0)
		tween.set_trans(MotionConfig.value("panel", "modal_in_trans", null, quality)).set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "scale", Vector2.ONE, _spec.show_duration)
		tween.tween_method(_set_appearance_alpha, 0.0, 1.0, _spec.show_duration)

func _set_number_color() -> void:
	_number.add_theme_color_override("font_color", Color("#ffcf6b") if _reminder else Color("#f7efdc"))

func _sync_pulse() -> void:
	var active := is_visible_in_tree() and _reminder and float(_spec.urgent_pulse_hz) > 0.0
	set_process(active)
	if not active:
		_pulse_time = 0.0

func _process(delta: float) -> void:
	_pulse_time += delta
	var wave := 0.5 + 0.5 * sin(_pulse_time * float(_spec.urgent_pulse_hz))
	_number.add_theme_color_override("font_color", Color("#ffe8ae").lerp(Color("#ffb089"), wave))
	queue_redraw()

func _fit() -> void:
	pivot_offset = size * 0.5
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
	var fraction := clampf(float(maxi(0, int(next[1]))) / maxf(1.0, float(clock.get("duration_ms", 10000))), 0.0, 1.0)
	_caption.text = caption
	_number.accessibility_name = caption + " " + _number.text
	if _reminder != next[2] or _remaining == -1:
		_reminder = next[2]
		_set_number_color()
		_sync_pulse()
		queue_redraw()
	if _phase != next[0] or _remaining != seconds or not is_equal_approx(_fraction, fraction):
		_phase = next[0]
		_remaining = seconds
		_fraction = fraction
		queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := maxf(8.0, minf(size.x, size.y) * 0.5 - 3.0)
	var wave := 0.5 + 0.5 * sin(_pulse_time * float(_spec.urgent_pulse_hz))
	var warning := Color("#ffb94f").lerp(Color("#ff6b4a"), wave)
	var progress := warning if _reminder else Color("#edce83")
	var end_angle := -PI * 0.5 + TAU * _fraction
	if not _spec.tick_marks:
		draw_circle(center, radius, Color("#102e30e6"))
		draw_arc(center, radius - 0.8, 0, TAU, 48, Color("#71908c"), 1.2, true)
		draw_arc(center, radius * 0.80, 0, TAU, 48, Color("#38534f"), 2.8, true)
		if _fraction > 0.0:
			draw_arc(center, radius * 0.80, -PI * 0.5, end_angle, 48, progress, 2.8, true)
		return
	var shadow_center := center + Vector2(0, 3.5)
	draw_circle(shadow_center, radius + 1.0, Color(0, 0, 0, 0.12))
	draw_circle(shadow_center, radius - 1.0, Color(0, 0, 0, 0.25))
	draw_arc(center, radius + 1.0, 0, TAU, 64, Color(1.0, 0.83, 0.47, 0.10), 3.0, true)
	draw_circle(center, radius, Color("#59401f"))
	draw_arc(center, radius - 1.3, -PI * 1.25, -PI * 0.25, 40, Color("#fff0b5"), 2.4, true)
	draw_arc(center, radius - 1.3, -PI * 0.25, PI * 0.75, 40, Color("#6b4b1f"), 2.4, true)
	draw_circle(center, radius - 3.0, Color("#081c19"))
	for i in range(6):
		var fraction := i / 5.0
		draw_circle(center - Vector2(1, 3) * fraction, (radius - 4.0) * (1.0 - fraction * 0.35), Color("#102d27").lerp(Color("#20483a"), fraction))
	# 刻度留在进度轨道内侧，不挤占中心数字。
	for tick in range(12):
		var direction := Vector2.from_angle(-PI * 0.5 + tick * TAU / 12.0)
		var major := tick % 3 == 0
		draw_line(center + direction * (radius - (12.0 if major else 10.5)), center + direction * (radius - 8.0), Color(1.0, 0.90, 0.64, 0.68 if major else 0.30), 1.2 if major else 0.8, true)
	draw_arc(center, radius - 10.0, -PI * 0.84, -PI * 0.20, 28, Color(1.0, 0.97, 0.85, 0.16), 1.6, true)
	var progress_radius := radius * 0.81
	draw_arc(center, progress_radius, 0, TAU, 64, Color(0.71, 0.57, 0.28, 0.24), 3.0, true)
	if _fraction > 0.0:
		draw_arc(center, progress_radius, -PI * 0.5, end_angle, 64, Color(progress.r, progress.g, progress.b, 0.12), 5.4, true)
		draw_arc(center, progress_radius, -PI * 0.5, end_angle, 64, progress, 2.8, true)
		if _spec.progress_bead:
			var bead := center + Vector2.from_angle(end_angle) * progress_radius
			draw_circle(bead, 4.0, Color(progress.r, progress.g, progress.b, 0.18))
			draw_circle(bead, 2.2, progress)
			draw_circle(bead - Vector2(0.4, 0.5), 0.9, Color("#fff8e3"))
	if _reminder:
		draw_arc(center, radius + 1.0, 0, TAU, 64, Color(warning.r, warning.g, warning.b, 0.12 + wave * 0.22), 2.8, true)
