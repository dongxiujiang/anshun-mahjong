extends Node3D
## 红、白刚体在桌面上的最终朝上面决定规则输入。客户端消费权威姿态。

signal result_ready(red: int, white: int)

const SIDE := 0.38
const FACE_NORMALS := [Vector3.UP, Vector3.BACK, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN]
const STABLE_SECONDS := 0.25
const UPRIGHT_DOT := 0.9925
const TRAY_HALF := 2.2
const TRACE_PARAMETERS_VERSION := 1
const TRACE_EVERY_FRAMES := 3

@export var authoritative := true
var roll_id := 0
var phase := "idle"
var dice: Array[RigidBody3D] = []
var tap_count := 0
var _floor: StaticBody3D
var _rng := RandomNumberGenerator.new()
var _quiet := 0.0
var _frame := 0
var _result: Array[int] = []
var _physics_trace := {}

func _ready() -> void:
	if authoritative:
		_floor = _barrier("Table", Vector3(0, -0.1, 0), Vector3(TRAY_HALF * 2, 0.2, TRAY_HALF * 2))
		for direction in [-1, 1]:
			_barrier("SideX" + str(direction), Vector3(direction * TRAY_HALF, 0.9, 0), Vector3(0.15, 1.8, TRAY_HALF * 2))
			_barrier("SideZ" + str(direction), Vector3(0, 0.9, direction * TRAY_HALF), Vector3(TRAY_HALF * 2, 1.8, 0.15))
	for index in 2:
		var die := RigidBody3D.new()
		die.name = "Red" if index == 0 else "White"
		die.mass = 0.3
		die.freeze = true
		die.continuous_cd = true
		die.contact_monitor = authoritative
		die.max_contacts_reported = 12
		if not authoritative:
			die.collision_layer = 0
			die.collision_mask = 0
		die.physics_material_override = PhysicsMaterial.new()
		die.physics_material_override.friction = 0.65
		die.physics_material_override.bounce = 0.26
		die.position = Vector3(-0.4 if index == 0 else 0.4, SIDE / 2, 0)
		_shape(die, Vector3.ONE * SIDE)
		_faces(die, index == 0)
		add_child(die)
		dice.append(die)
	set_physics_process(authoritative)

func _barrier(label_text: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label_text
	body.position = center
	_shape(body, size)
	add_child(body)
	return body

func _shape(body: CollisionObject3D, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	body.add_child(collider)

func _faces(die: Node3D, red: bool) -> void:
	die.add_child(create_visual(red))

static var _red_mesh: BoxMesh
static var _white_mesh: BoxMesh

static func create_visual(red: bool) -> MeshInstance3D:
	var cached: BoxMesh = _red_mesh if red else _white_mesh
	if cached == null:
		cached = BoxMesh.new()
		cached.size = Vector3.ONE * SIDE
		cached.subdivide_width = 4
		cached.subdivide_height = 4
		cached.subdivide_depth = 4
		var material := ShaderMaterial.new()
		material.shader = preload("res://src/presentation/DiceFaces.gdshader")
		material.set_shader_parameter("red_die", red)
		cached.material = material
		if red:
			_red_mesh = cached
		else:
			_white_mesh = cached
	var cube := MeshInstance3D.new()
	cube.mesh = cached
	return cube

func roll(seed_value: int = -1) -> bool:
	if not authoritative or dice.size() != 2 or phase == "rolling":
		return false
	if seed_value == -1:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	roll_id += 1
	_frame = 0
	tap_count = 0
	_result.clear()
	_quiet = 0.0
	phase = "rolling"
	for index in 2:
		var die := dice[index]
		var side := -1.0 if index == 0 else 1.0
		die.freeze = false
		die.sleeping = false
		die.transform = Transform3D(_random_basis(), Vector3(side * 0.65, 1.1 + 0.06 * index, _rng.randf_range(-0.14, 0.14)))
		die.reset_physics_interpolation()
		die.linear_velocity = Vector3(-side * _rng.randf_range(1.5, 2.1), _rng.randf_range(0.2, 0.6), _rng.randf_range(-0.7, 0.7))
		die.angular_velocity = _random_axis() * _rng.randf_range(11, 21)
	_physics_trace={"parameters_version":TRACE_PARAMETERS_VERSION,
		"backend":str(ProjectSettings.get_setting("physics/3d/physics_engine","GodotPhysics3D")),
		"engine_version":Engine.get_version_info().string,"ticks_per_second":Engine.physics_ticks_per_second,
		"parameters":{"side":SIDE,"tray_half":TRAY_HALF,"gravity":ProjectSettings.get_setting("physics/3d/default_gravity",9.8),
			"mass":dice[0].mass,"friction":dice[0].physics_material_override.friction,"bounce":dice[0].physics_material_override.bounce,
			"stable_seconds":STABLE_SECONDS,"upright_dot":UPRIGHT_DOT},"initial":[],"taps":[],"trajectory":[]}
	var poses:Array=snapshot().poses
	for index in 2:
		_physics_trace.initial.append({"pose":poses[index],"linear_velocity":_vector(dice[index].linear_velocity),"angular_velocity":_vector(dice[index].angular_velocity)})
	_sample_trace()
	return true

static func _vector(value:Vector3)->Array:
	return [value.x,value.y,value.z]

func _sample_trace()->void:
	if _physics_trace.is_empty():return
	var sample:={"frame":_frame,"poses":snapshot().poses}
	var samples:Array=_physics_trace.trajectory
	if not samples.is_empty() and samples.back().frame==_frame:samples[-1]=sample
	else:samples.append(sample)

func record_snapshot()->Dictionary:
	var state:=snapshot()
	if not _physics_trace.is_empty():state.physics=_physics_trace.duplicate(true)
	return state

func _random_basis() -> Basis:
	var u := _rng.randf()
	var a := _rng.randf_range(0, TAU)
	var b := _rng.randf_range(0, TAU)
	return Basis(Quaternion(sqrt(1 - u) * sin(a), sqrt(1 - u) * cos(a), sqrt(u) * sin(b), sqrt(u) * cos(b)))

func _random_axis() -> Vector3:
	var y := _rng.randf_range(-1, 1)
	var a := _rng.randf_range(0, TAU)
	var horizontal := sqrt(maxf(0, 1 - y * y))
	return Vector3(horizontal * cos(a), y, horizontal * sin(a))

func _physics_process(delta: float) -> void:
	if phase != "rolling":
		return
	_frame += 1
	if _frame%TRACE_EVERY_FRAMES==0:_sample_trace()
	for die in dice:
		if die.linear_velocity.length() > 0.045 or die.angular_velocity.length() > 0.12:
			_quiet = 0
			return
	_quiet += delta
	if _quiet < STABLE_SECONDS:
		return
	var values: Array[int] = []
	for die in dice:
		values.append(_resting_face(die))
	if values.has(0):
		# 轻拍产生向上、侧向和旋转冲量；歪靠或叠骰自行重新落下。
		tap_count += 1
		var tap:={"frame":_frame,"dice":[]}
		for index in 2:
			if values[index] != 0:
				continue
			var die := dice[index]
			die.sleeping = false
			var angle := _rng.randf_range(0, TAU)
			var impulse:=die.mass * Vector3(0.95 * cos(angle), 1.6, 0.95 * sin(angle))
			var torque:=_random_axis() * 0.039
			die.apply_central_impulse(impulse)
			die.apply_torque_impulse(torque)
			tap.dice.append({"index":index,"impulse":_vector(impulse),"torque":_vector(torque)})
		if not _physics_trace.is_empty():_physics_trace.taps.append(tap)
		_sample_trace()
		_quiet = 0
		return
	for die in dice:
		die.freeze = true
	_result = values
	phase = "settled"
	_sample_trace()
	result_ready.emit(_result[0], _result[1])

func _resting_face(die: RigidBody3D) -> int:
	if not die.get_colliding_bodies().has(_floor):
		return 0
	for index in FACE_NORMALS.size():
		if (die.basis * FACE_NORMALS[index]).dot(Vector3.UP) >= UPRIGHT_DOT:
			return index + 1
	return 0

func snapshot() -> Dictionary:
	var poses := []
	for die in dice:
		var p := die.position
		var q := die.quaternion
		poses.append([p.x, p.y, p.z, q.x, q.y, q.z, q.w])
	return {"roll_id": roll_id, "frame": _frame, "phase": phase, "poses": poses, "result": _result.duplicate()}

func apply_snapshot(state: Dictionary) -> bool:
	if authoritative or dice.size() != 2:
		return false
	var incoming_id := int(state.get("roll_id", -1))
	var incoming_frame := int(state.get("frame", -1))
	var incoming_phase: String = state.get("phase", "")
	if incoming_id <= 0 or incoming_frame < 0 or incoming_phase not in ["rolling", "settled"]:
		return false
	if incoming_id < roll_id or (incoming_id == roll_id and (phase == "settled" or incoming_frame <= _frame)):
		return false
	var poses: Array = state.get("poses", [])
	var result: Array = state.get("result", [])
	if poses.size() != 2 or (incoming_phase == "rolling" and not result.is_empty()):
		return false
	if incoming_phase == "settled":
		if result.size() != 2:
			return false
		for face in result:
			# JSON numbers arrive as floats; a pip value still has to be an integer.
			if typeof(face) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(face)) or face < 1 or face > 6 or face != int(face):
				return false
	var transforms: Array[Transform3D] = []
	for pose in poses:
		if not pose is Array or pose.size() != 7:
			return false
		for number in pose:
			if typeof(number) not in [TYPE_FLOAT, TYPE_INT]:
				return false
		var rotation := Quaternion(pose[3], pose[4], pose[5], pose[6])
		var position_value := Vector3(pose[0], pose[1], pose[2])
		if not rotation.is_finite() or not rotation.is_normalized() or not position_value.is_finite():
			return false
		transforms.append(Transform3D(Basis(rotation), position_value))
	for index in 2:
		dice[index].transform = transforms[index]
	roll_id = incoming_id
	_frame = incoming_frame
	phase = incoming_phase
	_result.assign(result)
	if phase == "settled":
		result_ready.emit(_result[0], _result[1])
	return true


func export_authority() -> Dictionary:
	var state := record_snapshot()
	if phase == "rolling":
		state.motion = []
		for die in dice:
			state.motion.append([die.transform, die.linear_velocity, die.angular_velocity])
		state.quiet = _quiet
		state.tap_count = tap_count
		state.rng_state = _rng.state
	return state

## 已生效的点数恢复时不重复发 result_ready；尚未停稳的骰子继续物理模拟。
func apply_authority(state: Dictionary) -> bool:
	if not authoritative or dice.size() != 2:
		return false
	if state.get("phase") == "rolling":
		var motion: Variant = state.get("motion")
		if not motion is Array or motion.size() != 2 or not state.get("rng_state") is int:
			return false
		for body in motion:
			if not body is Array or body.size() != 3:
				return false
			if not body[0] is Transform3D or not body[1] is Vector3 or not body[2] is Vector3:
				return false
			if not body[0].is_finite() or not body[1].is_finite() or not body[2].is_finite():
				return false
		roll_id = int(state.roll_id)
		_frame = int(state.frame)
		_quiet = float(state.quiet)
		tap_count = int(state.tap_count)
		_rng.state = state.rng_state
		_physics_trace=state.get("physics",{}).duplicate(true)
		_result.clear()
		for index in 2:
			var die := dice[index]
			die.freeze = false
			die.sleeping = false
			die.transform = motion[index][0]
			die.reset_physics_interpolation()
			die.linear_velocity = motion[index][1]
			die.angular_velocity = motion[index][2]
		phase = "rolling"
		return true
	if state.get("phase") == "idle":
		roll_id = 0
		_frame = 0
		phase = "idle"
		_physics_trace.clear()
		_result = []
		_quiet = STABLE_SECONDS
		return true
	var saved := state.duplicate(true)
	if not saved.get("result") is Array or saved.result.size() != 2:
		return false
	if saved.get("phase") != "settled":
		return false
	for face in saved.result:
		if typeof(face) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(face)) or face < 1 or face > 6 or face != int(face):
			return false
	roll_id = int(saved.get("roll_id", 1))
	_frame = int(saved.get("frame", 0))
	phase = "settled"
	_physics_trace=saved.get("physics",{}).duplicate(true)
	_result.assign([int(saved.result[0]), int(saved.result[1])])
	_quiet = STABLE_SECONDS
	var poses: Array = saved.get("poses", [])
	if poses.size() == 2:
		var transforms: Array[Transform3D] = []
		for pose in poses:
			if not pose is Array or pose.size() != 7:
				transforms = []
				break
			var rotation := Quaternion(pose[3], pose[4], pose[5], pose[6])
			if not rotation.is_finite() or not rotation.is_normalized():
				transforms = []
				break
			transforms.append(Transform3D(Basis(rotation), Vector3(pose[0], pose[1], pose[2])))
		if transforms.size() == 2:
			for index in 2:
				dice[index].transform = transforms[index]
	return true
