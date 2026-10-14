extends RefCounted
## Short, interruptible motion. Never changes gameplay or networking.
static func enabled() -> bool:
	return DisplayServer.get_name() != "headless"

static func stop(control: Control) -> void:
	if control.has_meta("motion_position"):
		control.position = control.get_meta("motion_position")
		control.remove_meta("motion_position")
	if not control.has_meta("ui_motion"): return
	var previous: Variant = control.get_meta("ui_motion")
	if previous is Tween: previous.kill()
	control.remove_meta("ui_motion")

static func appear(control: Control) -> void:
	stop(control)
	control.show()
	control.modulate.a = 1.0
	if not enabled(): return
	control.modulate.a = 0.0
	var tween := control.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	control.set_meta("ui_motion", tween)
	tween.tween_property(control, "modulate:a", 1.0, 0.22)

static func slide_in(control: Control) -> void:
	stop(control)
	if not enabled(): return
	var destination := control.position
	control.set_meta("motion_position", destination)
	control.position += Vector2(0, 12)
	var tween := control.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	control.set_meta("ui_motion", tween)
	tween.tween_property(control, "position", destination, 0.24)
	tween.tween_callback(func(): control.remove_meta("motion_position"))

static func bind_button(button: Button) -> void:
	if button.has_meta("motion_bound"): return
	button.set_meta("motion_bound", true)
	button.button_down.connect(func(): _press(button, 0.975))
	button.button_up.connect(func(): _press(button, 1.0))
	button.mouse_exited.connect(func(): _press(button, 1.0))

static func _press(button: Button, factor: float) -> void:
	if not enabled() or not button.is_inside_tree(): return
	stop(button)
	button.pivot_offset = button.size / 2.0
	var tween := button.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	button.set_meta("ui_motion", tween)
	tween.tween_property(button, "scale", Vector2.ONE * factor, 0.12 if factor < 1.0 else 0.18)
