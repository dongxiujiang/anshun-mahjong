extends Node
## Presentation only: the authority and its clocks continue throughout the camera move.
signal finished(entering: bool)
const SECONDS := 0.72
var active := false
var entering := true
var _elapsed := 0.0
var _table: Node3D
var _origin := {}
var _high := Transform3D.IDENTITY
var _high_fov := 0.0

func begin(table: Node3D, _seats: Array, seat: int, descending: bool = true, origin: Dictionary = {}, play_rect: Rect2 = Rect2()) -> void:
	cancel()
	_table = table
	_table.viewer = seat
	_table._frame_camera()
	_origin = origin.duplicate(true)
	if not _origin.is_empty() and play_rect.size.y > 0:
		var height: float = origin.height * play_rect.size.y / origin.rect.size.y
		var distance: float = maxf(_table.camera.position.length(), _table.table_edge() * 20)
		var delta: Vector2 = origin.center - play_rect.get_center()
		_high = Transform3D(origin.basis, origin.basis * Vector3(-delta.x * height / play_rect.size.y, delta.y * height / play_rect.size.y, distance))
		_high_fov = rad_to_deg(2 * atan(height * 0.5 / distance))
	entering = descending
	_elapsed = 0.0
	active = true
	set_process(true)
	_apply(0.0)

func _process(delta: float) -> void:
	if not active:
		return
	_elapsed = minf(SECONDS, _elapsed + delta)
	_apply(_elapsed / SECONDS)
	if _elapsed >= SECONDS:
		var was_entering := entering
		cancel()
		finished.emit(was_entering)

func _apply(progress: float) -> void:
	_table._frame_camera()
	var target: Transform3D = _table.camera.transform
	var lens: float = _table.camera.fov
	var high := target
	high.origin = Vector3(target.origin.x * 0.50, target.origin.y * 1.65, target.origin.z * 0.50)
	high = high.looking_at(Vector3.ZERO, Vector3.UP)
	if not _origin.is_empty():
		high = _high
	var amount := progress * progress * (3.0 - 2.0 * progress)
	if not entering:
		amount = 1.0 - amount
	_table.camera.transform = high.interpolate_with(target, amount)
	_table.camera.fov = lerpf(lens * 1.65 if _origin.is_empty() else _high_fov, lens, amount)
	_table.camera.far = maxf(_table.camera.far, high.origin.length() + _table.table_edge() * 4)

func finish_on_resume() -> void:
	if not active:
		return
	var was_entering := entering
	cancel()
	finished.emit(was_entering)

func cancel() -> void:
	active = false
	set_process(false)
	if is_instance_valid(_table):
		_table._frame_camera()
