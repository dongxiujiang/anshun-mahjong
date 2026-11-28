extends Node
## Presentation only: the authority and its clocks continue throughout the camera move.
signal finished(entering: bool)
signal crossfade_progress(amount: float)
const MotionConfig = preload("res://src/presentation/MotionConfig.gd")

var active := false
var entering := true
var _elapsed := 0.0
var _duration := 0.0
var _spec: Dictionary
var _detail := false
var _rendered := false
var _warmup_left := 0
var _table: Node3D
var _origin := {}
var _play_rect := Rect2()
var _target_transform := Transform3D.IDENTITY
var _target_fov := 0.0
var _target_far := 0.0
var _high := Transform3D.IDENTITY
var _high_fov := 0.0
var _travel_far := 0.0
var _seated := Transform3D.IDENTITY
var _seated_fov := 0.0

func begin(table: Node3D, _seats: Array, seat: int, descending: bool = true, origin: Dictionary = {}, play_rect: Rect2 = Rect2()) -> void:
	var reversing := active and entering and not descending and _table == table
	var previous_pose: Transform3D = table.camera.transform
	var previous_fov: float = table.camera.fov
	cancel()
	_table = table
	_table.viewer = seat
	_origin = origin
	_play_rect = play_rect
	_spec = MotionConfig.section("transition")
	_detail = MotionConfig.is_detail()
	entering = descending
	_duration = _spec.enter_duration if entering else _spec.exit_duration
	_elapsed = 0.0
	_rendered = DisplayServer.get_name() != "headless"
	_warmup_left = int(_spec.warmup_frames) if _rendered else 0
	active = true
	_table._frame_camera()
	_cache_framing()
	if reversing:
		# The board is already moving. Leave from the pose currently on screen.
		_seated = previous_pose
		_seated_fov = previous_fov
		_apply(0.0)
	_table.get_viewport().size_changed.connect(_cache_framing)
	if _warmup_left > 0:
		RenderingServer.frame_post_draw.connect(_warmup_drawn)
	set_process(true)

func _cache_framing() -> void:
	# TableView's earlier size_changed listener has already framed the new viewport.
	_target_transform = _table.camera.transform
	_target_fov = _table.camera.fov
	_target_far = _table.camera.far
	_seated = _target_transform
	_seated_fov = _target_fov
	_high = _target_transform
	if _origin.is_empty() or _play_rect.size.y <= 0:
		var at := _target_transform.origin
		_high.origin = Vector3(at.x * 0.92, at.y * float(_spec.high_y_mult), at.z * 0.92)
		_high = _high.looking_at(Vector3.ZERO, Vector3.UP)
		_high_fov = _target_fov * float(_spec.fov_mult)
	else:
		var height: float = _origin.height * _play_rect.size.y / _origin.rect.size.y
		var distance: float = maxf(_target_transform.origin.length(), _table.table_edge() * 20)
		var offset: Vector2 = (_origin.center - _play_rect.get_center()) * height / _play_rect.size.y
		_high = Transform3D(_origin.basis, _origin.basis * Vector3(-offset.x, offset.y, distance))
		_high_fov = rad_to_deg(2 * atan(height * 0.5 / distance))
	_travel_far = maxf(_target_far, _high.origin.length() + _table.table_edge() * 4)
	_apply(_elapsed / _duration)

func _warmup_drawn() -> void:
	_warmup_left -= 1
	if _warmup_left == 0:
		RenderingServer.frame_post_draw.disconnect(_warmup_drawn)

func _process(delta: float) -> void:
	if not active or _warmup_left > 0:
		return
	_elapsed = minf(_duration, _elapsed + delta)
	_apply(_elapsed / _duration)
	var fade := clampf(_elapsed / float(_spec.crossfade_duration), 0.0, 1.0)
	if _elapsed >= _duration:
		finish_on_resume()
	else:
		crossfade_progress.emit(smoothstep(0.0, 1.0, fade))

func _apply(t: float) -> void:
	var amount := 1.0 - pow(1.0 - t, 2.0)
	if _detail:
		amount = 1.0 - pow(1.0 - t, 3.0) if entering else t * t * (3.0 - 2.0 * t)
	if not entering:
		amount = 1.0 - amount
	_table.camera.transform = _high.interpolate_with(_seated, amount)
	_table.camera.fov = lerpf(_high_fov, _seated_fov, amount)
	_table.camera.far = _travel_far

func finish_on_resume() -> void:
	if not active:
		return
	crossfade_progress.emit(1.0)
	cancel()
	finished.emit(entering)

func cancel() -> void:
	set_process(false)
	if not active:
		return
	active = false
	if RenderingServer.frame_post_draw.is_connected(_warmup_drawn):
		RenderingServer.frame_post_draw.disconnect(_warmup_drawn)
	_table.get_viewport().size_changed.disconnect(_cache_framing)
	_table.camera.transform = _target_transform
	_table.camera.fov = _target_fov
	_table.camera.far = _target_far
