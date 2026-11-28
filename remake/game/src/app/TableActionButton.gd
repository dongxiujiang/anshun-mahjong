extends Button
## 新中式玉石鎏金圆形操作按钮；合法动作仍严格来自权威下发。
const MotionConfig = preload("res://src/presentation/MotionConfig.gd")
const MotionFX = preload("res://src/presentation/MotionFX.gd")
const BURST_SIZE := 8
const BURST_COLORS := [Color("#ffe5a3"), Color("#efd085"), Color("#e5ae50")]

var action := ""
var quality := MotionConfig.current_quality
const COLORS := {
	"win": "b93232", "self_win": "b93232",
	"pong": "c98d24", "kong": "c77a1f", "concealed_kong": "227a57", "add_kong": "c77a1f",
	"pass": "2a4f52", "ready": "2c7250", "discard": "2b6088",
}
var _pulse := 0.0
var _pose := Vector2.RIGHT
var _particles: MotionFX.ParticlePool
var _spec := MotionConfig.section("action_button", quality)

func _ready() -> void:
	visibility_changed.connect(_visibility_changed)
	_sync_processing()

func configure(kind: String, title: String, callback: Callable) -> void:
	action = kind; text = title; accessibility_name = title; tooltip_text = title
	custom_minimum_size = Vector2(90, 90)
	button_down.connect(_set_pressed_pose.bind(true))
	button_up.connect(_set_pressed_pose.bind(false))
	pressed.connect(_burst)
	pressed.connect(callback)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_disabled_color", "icon_focus_color"]:
		add_theme_color_override(state, Color.TRANSPARENT)
	for signal_name in ["mouse_entered", "mouse_exited", "button_down", "button_up", "focus_entered", "focus_exited", "resized", "theme_changed"]:
		connect(signal_name, queue_redraw)
	_sync_processing()

func apply_quality(value: String) -> void:
	var next := MotionConfig.normalize_quality(value)
	if quality == next:
		return
	quality = next
	_spec = MotionConfig.section("action_button", quality)
	MotionFX.stop(self)
	_apply_pose(Vector2.RIGHT)
	self_modulate.a = 1.0
	if not _spec.particles_enabled and _particles:
		_particles.clear()
	_sync_processing()

func start_entrance(delay: float = 0.0) -> void:
	if not MotionFX._running(self):
		_apply_pose(Vector2(_spec.enter_from_scale, 0.0))
		self_modulate.a = 0.0
	_animate_pose(Vector2.RIGHT, _spec.enter_duration, _spec.enter_trans, delay)

func _set_pressed_pose(down: bool) -> void:
	if disabled or not is_visible_in_tree():
		return
	var target := Vector2(_spec.press_scale, _spec.press_y_offset) if down else Vector2.RIGHT
	var curve: Tween.TransitionType = MotionConfig.value("button", "ease_trans", null, quality) if down else _spec.release_trans
	_animate_pose(target, _spec.press_duration if down else _spec.release_duration, curve)

func _animate_pose(target: Vector2, duration: float, curve: Tween.TransitionType, delay := 0.0) -> void:
	var tween := MotionFX._begin(self)
	if tween == null:
		_apply_pose(target)
		self_modulate.a = 1.0
		return
	tween.set_trans(curve).set_ease(Tween.EASE_OUT)
	tween.tween_method(_apply_pose, _pose, target, duration).set_delay(delay)
	tween.tween_property(self, "self_modulate:a", 1.0, duration).set_delay(delay)

func _apply_pose(value: Vector2) -> void:
	_pose = value
	queue_redraw()

func _burst() -> void:
	if disabled or not is_visible_in_tree() or not _spec.particles_enabled:
		return
	if not _particles:
		_particles = MotionFX.ParticlePool.new()
	_particles.emit_burst(size * 0.5, BURST_SIZE, BURST_COLORS)
	_sync_processing()
	queue_redraw()

# A local authority can retire the action row synchronously inside pressed.
# Keep the burst at the clicked position when the remaining buttons reflow.
func _exit_tree() -> void:
	MotionFX.stop(self)
	var row := get_parent() as Container
	if row and _particles and _particles.active_count:
		var hud := row.get_parent() as CanvasItem
		if hud:
			var pose := hud.get_global_transform().affine_inverse() * get_global_transform()
			BurstTail.finish_on_hud.call_deferred(weakref(hud), pose, _particles)
			_particles = null

class BurstTail extends Node2D:
	var pool: MotionFX.ParticlePool

	static func finish_on_hud(owner_ref: WeakRef, pose: Transform2D, particles: MotionFX.ParticlePool) -> void:
		var hud := owner_ref.get_ref() as CanvasItem
		if not is_instance_valid(hud) or not hud.is_visible_in_tree() or particles.active_count == 0:
			return
		var tail := BurstTail.new()
		tail.pool = particles
		tail.transform = pose
		hud.add_child(tail, false, Node.INTERNAL_MODE_BACK)

	func _draw() -> void:
		pool.draw(self)

	func _process(delta: float) -> void:
		if not is_visible_in_tree() or not pool.step(delta):
			queue_free()
		queue_redraw()

func _visibility_changed() -> void:
	if not is_visible_in_tree():
		MotionFX.stop(self)
		_apply_pose(Vector2.RIGHT)
		self_modulate.a = 1.0
		if _particles:
			_particles.clear()
	_sync_processing()

func _sync_processing() -> void:
	var pulse: bool = _spec.win_pulse_enabled and action in ["win", "self_win"] and not disabled
	set_process(is_visible_in_tree() and (pulse or (_particles and _particles.active_count > 0)))

func _process(delta: float) -> void:
	if _particles and _particles.active_count:
		_particles.step(delta)
	_pulse += delta * 4.2
	_sync_processing()
	queue_redraw()

func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5

func _draw() -> void:
	_sync_processing()
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	draw_set_transform(center * (1.0 - _pose.x) + Vector2.DOWN * _pose.y, 0.0, Vector2.ONE * _pose.x)
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
		if _spec.win_pulse_enabled and not disabled and action in ["win", "self_win"]:
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
	if _particles and _particles.active_count:
		draw_set_transform(Vector2.ZERO)
		_particles.draw(self)
