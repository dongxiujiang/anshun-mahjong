extends ScrollContainer
## 桌面与触屏共用同一拖动手势，点选与拖动互斥。
const MotionConfig = preload("res://src/presentation/MotionConfig.gd")

const FRICTION := 8.0
const STOP_SPEED := 18.0

var quality := MotionConfig.current_quality
var _pressed := false
var _dragging := false
var _origin := Vector2.ZERO
var _scroll_start := 0
var _finger := -1
var _touch_card: Button
var _last_x := 0.0
var _last_time := 0
var _velocity := 0.0
var _scroll_position := 0.0

func _ready() -> void:
	scroll_deadzone = 12
	set_process(false)
	visibility_changed.connect(_cancel_gesture)

func apply_quality(value: String) -> void:
	quality = MotionConfig.normalize_quality(value)
	if not MotionConfig.is_detail(quality):
		_stop_inertia()

func _stop_inertia() -> void:
	_velocity = 0.0
	set_process(false)

func _release_card() -> void:
	if is_instance_valid(_touch_card):
		_touch_card.button_up.emit()
	_touch_card = null

func _cancel_gesture() -> void:
	_stop_inertia()
	_release_card()
	_pressed = false
	_dragging = false
	_finger = -1

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_stop_inertia()
		var touch := event is InputEventScreenTouch
		if not touch and (event.button_index != MOUSE_BUTTON_LEFT or event.device == InputEvent.DEVICE_ID_EMULATION):
			return
		if event.pressed:
			if _pressed or not get_global_rect().has_point(event.position):
				return
			var bar := get_h_scroll_bar()
			if bar.is_visible_in_tree() and bar.get_global_rect().has_point(event.position):
				return
			_touch_card = _card_at(event.position)
			_pressed = true
			_finger = event.index if touch else -1
			_origin = event.position
			_scroll_start = scroll_horizontal
			_last_x = _origin.x
			_last_time = Time.get_ticks_usec()
			if is_instance_valid(_touch_card):
				_touch_card.button_down.emit()
		elif _pressed and _finger == (event.index if touch else -1):
			var tapped := _touch_card
			_release_card()
			if _dragging and not event.canceled and MotionConfig.is_detail(quality):
				var held := (Time.get_ticks_usec() - _last_time) / 1000000.0
				_velocity *= exp(-FRICTION * held)
				_scroll_position = scroll_horizontal
				set_process(absf(_velocity) >= STOP_SPEED)
			elif is_instance_valid(tapped) and not event.canceled and _card_at(event.position) == tapped:
				tapped.grab_focus()
				tapped.pressed.emit()
			_pressed = false
			_dragging = false
			_finger = -1
		else:
			return
		get_viewport().set_input_as_handled()
	elif _pressed and ((event is InputEventScreenDrag and event.index == _finger) or (event is InputEventMouseMotion and _finger == -1)):
		_move(event.position, event.velocity.x)
		get_viewport().set_input_as_handled()

func _move(point: Vector2, speed: float) -> void:
	var distance := point - _origin
	if not _dragging and absf(distance.x) > scroll_deadzone and absf(distance.x) > absf(distance.y):
		_dragging = true
		_release_card()
	var now := Time.get_ticks_usec()
	if _dragging:
		scroll_horizontal = _scroll_start - roundi(distance.x)
		if MotionConfig.is_detail(quality):
			var elapsed := maxf((now - _last_time) / 1000000.0, get_process_delta_time())
			_velocity = -speed
			if is_zero_approx(speed) and elapsed > 0.0:
				_velocity = (_last_x - point.x) / elapsed
	_last_x = point.x
	_last_time = now

func _process(delta: float) -> void:
	var decay := exp(-FRICTION * delta)
	_scroll_position += _velocity * (1.0 - decay) / FRICTION
	_velocity *= decay
	var target := roundi(_scroll_position)
	scroll_horizontal = target
	if absf(_velocity) < STOP_SPEED or scroll_horizontal != target:
		_stop_inertia()

func _card_at(point: Vector2) -> Button:
	if not get_global_rect().has_point(point):
		return null
	for card in get_child(0)._cards:
		if not card.disabled and card.mouse_filter != MOUSE_FILTER_IGNORE and card.is_visible_in_tree() and card.get_global_rect().has_point(point):
			return card
	return null
