extends RefCounted

const MotionConfig = preload("res://src/presentation/MotionConfig.gd")
static var _ui_owners: Array[Node] = []

static func stop(node: Node, slot: String = "motion") -> void:
	if is_instance_valid(node) and node.has_meta(slot):
		var old: Tween = node.get_meta(slot)
		old.kill()
		node.remove_meta(slot)

static func _running(node: Node) -> bool:
	return node.has_meta(&"motion") and node.get_meta(&"motion").is_valid()

static func _begin(node: Node) -> Tween:
	stop(node)
	if not node.is_inside_tree() or node.is_queued_for_deletion():
		return null
	for i in range(_ui_owners.size() - 1, -1, -1):
		if not is_instance_valid(_ui_owners[i]) or not _running(_ui_owners[i]):
			_ui_owners.remove_at(i)
	if _ui_owners.size() >= int(MotionConfig.value("panel", "ui_tween_limit")):
		return null
	# SceneTree drives Tweens even with a headless display.
	var tween := node.create_tween().set_parallel(true)
	_ui_owners.append(node)
	_track(node, tween)
	return tween

static func _track(node: Node, tween: Tween) -> void:
	node.set_meta(&"motion", tween)
	tween.finished.connect(node.remove_meta.bind(&"motion"), CONNECT_ONE_SHOT)

static func _center(node: Control) -> void:
	node.pivot_offset = node.size / 2.0

static func _owns_visual_offset(node: Control) -> bool:
	if not node.offset_transform_enabled:
		node.offset_transform_visual_only = true
		node.offset_transform_enabled = true
		node.set_meta(&"motion_visual_offset", true)
	# HudLayout takes ownership by turning visual_only off, including mid-Tween.
	return node.has_meta(&"motion_visual_offset") and node.offset_transform_visual_only

static func bind_button(button: BaseButton, style: String = "default") -> void:
	if not is_instance_valid(button) or button.has_meta(&"motion_button_style"):
		return
	button.set_meta(&"motion_button_style", style)
	button.set_meta(&"motion_rest_scale", button.scale)
	_center(button)
	button.resized.connect(_center.bind(button))
	button.button_down.connect(_button_event.bind(button, "down"))
	button.button_up.connect(_button_event.bind(button, "up"))
	button.mouse_entered.connect(_button_event.bind(button, "enter"))
	button.mouse_exited.connect(_button_event.bind(button, "exit"))
	button.focus_exited.connect(_button_event.bind(button, "reset"))
	button.visibility_changed.connect(_button_event.bind(button, "reset"))
	# BaseButton redraws on disable, including when a finished hover has no active Tween.
	button.draw.connect(_reset_disabled_button.bind(button))

static func _reset_disabled_button(button: BaseButton) -> void:
	if button.disabled and (button.get_meta(&"motion_down", false) or button.get_meta(&"motion_hover", false)):
		_button_event(button, "reset")

static func _button_event(button: BaseButton, event: String) -> void:
	var down: bool = button.get_meta(&"motion_down", false)
	var hover: bool = button.get_meta(&"motion_hover", false)
	match event:
		"down": down = true
		"up": down = false
		"enter": hover = true
		"exit": hover = false
	var hidden := not button.visible or (button.is_inside_tree() and not button.is_visible_in_tree())
	if event == "reset" or button.disabled or hidden:
		down = false
		hover = false
	button.set_meta(&"motion_down", down)
	button.set_meta(&"motion_hover", hover)
	var spec := MotionConfig.section("button")
	var style: String = button.get_meta(&"motion_button_style")
	var overrides := MotionConfig.section("action_button" if style == "action" else style)
	var target := Vector2(1.0, 0.0)
	if down:
		target = Vector2(overrides.get("press_scale", spec.press_scale), overrides.get("press_y_offset", spec.press_y_offset))
	elif hover:
		target.x = spec.hover_scale
	var pose: Vector2 = button.get_meta(&"motion_button_pose", Vector2.RIGHT)
	if button.disabled or hidden or pose.is_equal_approx(target):
		stop(button)
		_button_pose(target, button)
		return
	var tween := _begin(button)
	if tween == null:
		_button_pose(target, button)
		return
	var duration_key := "press_duration" if down else "release_duration"
	var curve_key := "ease_trans" if down else "release_trans"
	tween.tween_method(_button_pose.bind(button), pose, target, overrides.get(duration_key, spec[duration_key])) \
		.set_trans(overrides.get(curve_key, spec[curve_key])).set_ease(Tween.EASE_OUT)

static func _button_pose(pose: Vector2, button: BaseButton) -> void:
	if button.disabled:
		pose = Vector2.RIGHT
	button.set_meta(&"motion_button_pose", pose)
	if _owns_visual_offset(button):
		button.offset_transform_scale = Vector2.ONE * pose.x
		button.offset_transform_position = Vector2.DOWN * pose.y
	else:
		# Keep both HUD offsets intact. Only scale the button around its own pivot.
		var rest: Vector2 = button.get_meta(&"motion_rest_scale")
		button.scale = rest * pose.x

static func _property(tween: Tween, node: Object, path: NodePath, target: Variant, duration: float, delay: float = 0.0) -> void:
	if tween == null:
		node.set_indexed(path, target)
	else:
		tween.tween_property(node, path, target, duration).set_delay(delay)

static func animate_screen_in(node: Control) -> void:
	var panel := MotionConfig.section("panel")
	_slide(node, true, Vector2.DOWN * panel.screen_in_offset_y, panel.screen_in_duration, panel.ease_trans)

static func animate_popup_show(node: Control, offset_override: Variant = null) -> void:
	var overlay := MotionConfig.section("overlay")
	var offset := Vector2.DOWN * float(overlay.popup_offset_y)
	if offset_override is Vector2:
		offset = offset_override
	elif offset_override is float or offset_override is int:
		offset.y = offset_override
	_slide(node, true, offset, overlay.popup_in, MotionConfig.value("panel", "modal_in_trans"))

static func animate_popup_hide(node: Control) -> void:
	var overlay := MotionConfig.section("overlay")
	_slide(node, false, Vector2.DOWN * overlay.popup_offset_y, overlay.popup_out, MotionConfig.value("panel", "ease_trans"))

static func _slide(node: Control, entering: bool, offset: Vector2, duration: float, curve: Tween.TransitionType, delay: float = 0.0) -> void:
	if not is_instance_valid(node):
		return
	var fresh := not _running(node)
	var tween := _begin(node)
	var slide := _owns_visual_offset(node)
	if entering:
		node.show()
		if fresh and tween:
			node.modulate.a = 0.0
			if slide:
				node.offset_transform_position = offset
	if tween:
		tween.set_trans(curve).set_ease(Tween.EASE_OUT if entering else Tween.EASE_IN)
	_property(tween, node, ^"modulate:a", 1.0 if entering else 0.0, duration, delay)
	if slide:
		var target := Vector2.ZERO if entering else offset
		if tween:
			tween.tween_method(_slide_offset.bind(node), node.offset_transform_position, target, duration).set_delay(delay)
		else:
			_slide_offset(target, node)
	if not entering:
		if tween:
			tween.finished.connect(node.hide)
		else:
			node.hide()

static func _slide_offset(offset: Vector2, node: Control) -> void:
	if _owns_visual_offset(node):
		node.offset_transform_position = offset

static func animate_modal_in(panel: Control, backdrop: CanvasItem = null) -> void:
	_modal(panel, backdrop, true, Callable())

static func animate_modal_out(panel: Control, backdrop: CanvasItem = null, on_done: Callable = Callable()) -> void:
	_modal(panel, backdrop, false, on_done)

static func _modal(panel: Control, backdrop: CanvasItem, entering: bool, on_done: Callable) -> void:
	if not is_instance_valid(panel):
		if is_instance_valid(backdrop) and not entering:
			stop(backdrop)
			backdrop.hide()
		if on_done.is_valid():
			on_done.call()
		return
	var spec := MotionConfig.section("panel")
	var fresh := not _running(panel)
	var tween := _begin(panel)
	var duration: float = spec.modal_in_duration if entering else spec.modal_out_duration
	_center(panel)
	if entering:
		panel.show()
		if fresh and tween:
			panel.scale = Vector2.ONE * spec.modal_from_scale
			panel.modulate.a = 0.0
	if tween:
		tween.set_trans(spec.modal_in_trans if entering else spec.ease_trans)
		tween.set_ease(Tween.EASE_OUT if entering else Tween.EASE_IN)
	_property(tween, panel, ^"scale", Vector2.ONE if entering else Vector2.ONE * spec.modal_to_scale, duration)
	_property(tween, panel, ^"modulate:a", 1.0 if entering else 0.0, duration)
	if is_instance_valid(backdrop) and backdrop != panel:
		var fresh_backdrop := not _running(backdrop) and fresh
		stop(backdrop)
		if entering:
			backdrop.show()
			if fresh_backdrop and tween:
				backdrop.modulate.a = 0.0
		if tween:
			_track(backdrop, tween)
		_property(tween, backdrop, ^"modulate:a", spec.backdrop_alpha if entering else 0.0,
			spec.backdrop_in_duration if entering else duration)
	if not entering:
		if tween:
			tween.finished.connect(panel.hide)
			if is_instance_valid(backdrop) and backdrop != panel:
				tween.finished.connect(backdrop.hide)
			if on_done.is_valid():
				tween.finished.connect(on_done, CONNECT_ONE_SHOT)
		else:
			panel.hide()
			if is_instance_valid(backdrop):
				backdrop.hide()
			if on_done.is_valid():
				on_done.call()

static func animate_stagger_children(nodes: Array, step_override: float = -1.0) -> void:
	var spec := MotionConfig.section("panel")
	var step: float = spec.card_stagger
	if step > 0.0 and step_override >= 0.0:
		step = step_override
	var delay := 0.0
	for node in nodes:
		if not is_instance_valid(node) or not node is Control:
			continue
		if step == 0.0:
			stop(node)
			node.show()
			node.modulate.a = 1.0
			if node.has_meta(&"motion_visual_offset"):
				_slide_offset(Vector2.ZERO, node)
		else:
			_slide(node, true, Vector2.DOWN * spec.screen_in_offset_y, spec.screen_in_duration,
				spec.ease_trans, delay)
			delay += step

static func spring_eval(t: float, response: float = MotionConfig.SPRING_RESPONSE, damping_ratio: float = MotionConfig.SPRING_DAMPING) -> float:
	if t <= 0.0:
		return 0.0
	if t >= 1.0 or response <= 0.0:
		return 1.0
	var phase := t * TAU / response
	var damping := maxf(damping_ratio, 0.0)
	if is_equal_approx(damping, 1.0):
		return 1.0 - exp(-phase) * (1.0 + phase)
	if damping < 1.0:
		var frequency := sqrt(1.0 - damping * damping)
		return 1.0 - exp(-damping * phase) * (cos(frequency * phase) + damping / frequency * sin(frequency * phase))
	var spread := sqrt(damping * damping - 1.0)
	var fast := damping + spread
	var slow := 1.0 / fast
	return 1.0 - (fast * exp(-slow * phase) - slow * exp(-fast * phase)) / (fast - slow)

class ParticlePool:
	const MAX_PARTICLES := MotionConfig.PARTICLE_CAPACITY

	class Particle:
		var position: Vector2
		var velocity: Vector2
		var color: Color
		var life := 0.0
		var lifetime: float
		var gravity: float
		var angle: float
		var spin: float
		var radius: float

	static var _total := 0
	static var _budget_generation := -1
	var _generation := -1
	var _particles: Array[Particle] = []
	var _live := 0
	var active_count: int:
		get:
			return _live if _generation == MotionConfig.particle_generation else 0

	func _init() -> void:
		_particles.resize(MAX_PARTICLES)
		for i in MAX_PARTICLES:
			_particles[i] = Particle.new()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PREDELETE and _generation == _budget_generation:
			_total -= _live

	func _sync_budget() -> void:
		if _budget_generation != MotionConfig.particle_generation:
			_budget_generation = MotionConfig.particle_generation
			_total = 0
		if _generation != _budget_generation:
			_generation = _budget_generation
			_live = 0

	func emit_burst(origin: Vector2, count: int, colors: Array,
			speed_min: float = MotionConfig.PARTICLE_SPEED_MIN, speed_max: float = MotionConfig.PARTICLE_SPEED_MAX,
			life_min: float = MotionConfig.PARTICLE_LIFE_MIN, life_max: float = MotionConfig.PARTICLE_LIFE_MAX,
			gravity: float = MotionConfig.PARTICLE_GRAVITY) -> void:
		_sync_budget()
		if not MotionConfig.is_detail() or count <= 0 or colors.is_empty():
			return
		var available := mini(MAX_PARTICLES - _total, MotionConfig.PARTICLE_BURST_LIMIT)
		for i in mini(count, available):
			var p := _particles[_live]
			p.position = origin
			p.angle = randf() * TAU
			p.velocity = Vector2.from_angle(p.angle) * randf_range(speed_min, speed_max)
			p.lifetime = randf_range(life_min, life_max)
			p.life = p.lifetime
			p.color = colors.pick_random()
			p.gravity = gravity
			p.spin = randf_range(-MotionConfig.PARTICLE_SPIN, MotionConfig.PARTICLE_SPIN)
			p.radius = randf_range(MotionConfig.PARTICLE_RADIUS.x, MotionConfig.PARTICLE_RADIUS.y)
			_live += 1
			_total += 1

	func step(delta: float) -> bool:
		_sync_budget()
		var i := _live
		while i > 0:
			i -= 1
			var p := _particles[i]
			p.life -= delta
			if p.life <= 0.0:
				_live -= 1
				_total -= 1
				_particles[i] = _particles[_live]
				_particles[_live] = p
				continue
			p.velocity.y += p.gravity * delta
			p.position += p.velocity * delta
			p.angle += p.spin * delta
		return _live > 0

	func draw(canvas: CanvasItem) -> void:
		_sync_budget()
		for i in _live:
			var p := _particles[i]
			var color := p.color
			color.a *= p.life / p.lifetime
			if p.spin > 0.0:
				var axis := Vector2.from_angle(p.angle) * p.radius
				canvas.draw_line(p.position - axis, p.position + axis, color, MotionConfig.PARTICLE_FOIL_WIDTH)
			else:
				canvas.draw_circle(p.position, p.radius, color)

	func clear() -> void:
		_sync_budget()
		_total -= _live
		_live = 0
