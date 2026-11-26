extends SceneTree

const Dice = preload("res://src/runtime/DiceRoll.gd")
const Record = preload("res://src/session/RoundRecord.gd")
var sample_size := 24
var failures := 0
var checks := 0
var signals_seen := 0
var client_signals := 0
var observed_pairs := {}
var red_faces := [0, 0, 0, 0, 0, 0]
var white_faces := [0, 0, 0, 0, 0, 0]
var doubles := 0
var collisions := 0
var taps := 0
var server
var client

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="):
			sample_size = clampi(arg.trim_prefix("--samples=").to_int(), 1, 10000)
	server = Dice.new()
	root.add_child(server)
	server.result_ready.connect(func(_red, _white): signals_seen += 1)
	client = Dice.new()
	client.authoritative = false
	root.add_child(client)
	client.result_ready.connect(func(_red, _white): client_signals += 1)
	check(not client.roll(1), "viewer cannot generate an independent throw")
	for index in sample_size:
		check(server.roll(31500 + index), "start fresh physical throw")
		check(not server.roll(31500 + index), "pending throw cannot restart")
		var initial: Dictionary = server.snapshot()
		var checkpoint:Dictionary=server.export_authority()
		check(checkpoint.physics.initial.size()==2 and checkpoint.physics.trajectory[0].frame==0,"authority captures actual initial poses, velocities and first sample")
		check(not initial.has("physics"),"frequent public dice packets omit the private full trace")
		check(initial.result.is_empty() and initial.phase == "rolling", "no pip result exists before rest")
		check(client.apply_snapshot(initial), "viewer displays authority's initial pose")
		var touched := await _wait_for_settle()
		collisions += int(touched)
		if server.phase != "settled":
			break
		var state: Dictionary = server.snapshot()
		var recorded:Dictionary=JSON.parse_string(JSON.stringify(server.record_snapshot()))
		check(Record._valid_dice(recorded),"complete physical trace survives JSON and validation")
		check(recorded.physics.trajectory.back().poses==recorded.poses,"final trace sample is exactly the locked visual result")
		var malformed:Dictionary=recorded.duplicate(true)
		malformed.physics.trajectory[-1].frame+=1
		check(not Record._valid_dice(malformed),"future or inconsistent trace sample rejected")
		var values: Array = state.result
		check(signals_seen == index + 1, "lock and publish once")
		check(values.size() == 2 and values[0] in range(1, 7) and values[1] in range(1, 7), "legal red and white")
		for die_index in 2:
			var die: RigidBody3D = server.dice[die_index]
			var normal: Vector3 = Dice.FACE_NORMALS[values[die_index] - 1]
			check(die.freeze and (die.basis * normal).y > 0.99, "actual final orientation matches physical face")
			check(absf(die.position.y - Dice.SIDE / 2) < 0.03, "valid face lies on table surface")
		var wire_state: Dictionary = JSON.parse_string(JSON.stringify(state))
		check(client.apply_snapshot(wire_state) and client.snapshot().result == values, "viewer adopts one outcome across JSON transport")
		check(not client.apply_snapshot(initial) and not client.apply_snapshot(state), "late or duplicate frames cannot reopen outcome")
		await physics_frame
		check(client_signals == index + 1 and signals_seen == index + 1, "no repeated authority or viewer result")
		var joined = Dice.new()
		joined.authoritative = false
		root.add_child(joined)
		check(joined.apply_snapshot(state) and joined.snapshot().result == values, "reconnect directly to frozen result")
		joined.queue_free()
		red_faces[values[0] - 1] += 1
		white_faces[values[1] - 1] += 1
		var pair := "%d/%d" % values
		observed_pairs[pair] = int(observed_pairs.get(pair, 0)) + 1
		doubles += int(values[0] == values[1])
		taps += server.tap_count
	check(collisions > 0, "sample includes actual die-to-die collision")
	await _stack()
	await _lean()
	print("physical samples=%d red=%s white=%s doubles=%d pairs=%s colliding_throws=%d natural_taps=%d" % [
		sample_size, red_faces, white_faces, doubles, observed_pairs, collisions, taps])
	print("Dice: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _wait_for_settle() -> bool:
	var collision := false
	for _tick in 1800:
		await physics_frame
		var bodies: Array = server.dice[0].get_colliding_bodies()
		collision = collision or bodies.has(server.dice[1])
		if server.phase == "settled":
			return collision
	check(false, "physical throw failed to reach valid rest within 30 simulated seconds")
	return collision

func _place(index: int, at: Vector3, orientation: Basis) -> void:
	var die: RigidBody3D = server.dice[index]
	die.transform = Transform3D(orientation, at)
	die.linear_velocity = Vector3.ZERO
	die.angular_velocity = Vector3.ZERO
	die.sleeping = false

func _stack() -> void:
	check(server.roll(453), "stack fixture starts as ordinary throw")
	_place(0, Vector3(0, Dice.SIDE * 0.5, 0), Basis.IDENTITY)
	_place(1, Vector3(0, Dice.SIDE * 1.5, 0), Basis.IDENTITY)
	await _wait_for_settle()
	check(server.tap_count > 0 and server.phase == "settled", "stack does not count and tap returns both to table")
	var recorded:Dictionary=server.record_snapshot()
	check(recorded.physics.taps.size()==server.tap_count and Record._valid_dice(recorded),"every actual table nudge records its frame and physical impulses")
	check(server.dice[1].position.y < Dice.SIDE, "top die physically left its stack")

func _lean() -> void:
	var wedge := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.53, 0.06, 0.60)
	shape.shape = box
	wedge.add_child(shape)
	wedge.physics_material_override = PhysicsMaterial.new()
	wedge.physics_material_override.friction = 1.0
	wedge.transform = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(18)), Vector3(-0.7, 0.17, 0))
	server.add_child(wedge)
	check(server.roll(455), "lean fixture starts as ordinary throw")
	_place(0, wedge.position + wedge.basis.y * (Dice.SIDE * 0.5 + 0.03), wedge.basis)
	_place(1, Vector3(1.1, Dice.SIDE * 0.5, 0), Basis.IDENTITY)
	await _wait_for_settle()
	check(server.tap_count > 0 and server.phase == "settled", "unlevel die on support is disturbed and obtains valid face by physics")
	wedge.queue_free()
