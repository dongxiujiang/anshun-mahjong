extends SceneTree

const Host = preload("res://src/runtime/GameHost.gd")
const Room = preload("res://src/session/RoomSession.gd")
var old_now := 1000
var new_now := 10000
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(description)

func restore(source):
	var target := Host.new()
	target.clock_msec = func(): return new_now
	root.add_child(target)
	var state: Dictionary = bytes_to_var(var_to_bytes(source.export_authority()))
	if target.restore_authority(state):
		return target
	target.queue_free()
	return null

func resume(host, ticket: Dictionary, connection: String) -> Dictionary:
	return host.resume(ticket.room_instance_id, ticket.player_id, ticket.member_token, connection)

func _run() -> void:
	var source := Host.new()
	source.clock_msec = func(): return old_now
	root.add_child(source)
	source.configure("123456", "lan", 1, {"external_presentation": true})
	# This deck gives the dealer a discard that offers pong for every red die face.
	source._rng.seed = 172
	var ticket: Dictionary = source.join("member", "南", "old").ticket
	source.set_ready("old", true)
	var waiting = restore(source)
	check(waiting != null, "restore opening countdown")
	if waiting != null:
		check(waiting._prepare_at - new_now == source._prepare_at - old_now, "opening countdown remains")
		check(not resume(waiting, ticket, "new").is_empty(), "valid member ticket resumes")
		waiting.queue_free()
	old_now = source._prepare_at
	for frame in 3:
		if source._dice.phase == "rolling":
			break
		await process_frame
	check(source._dice.phase == "rolling", "source starts a physical roll")
	var rolling = restore(source)
	check(rolling != null, "restore a live roll")
	if rolling != null:
		check(rolling._roll_valid, "roll remains eligible to start the deal")
		check(rolling._dice.snapshot() == source._dice.snapshot(), "poses and frame match the snapshot")
		for index in 2:
			check(rolling._dice.dice[index].linear_velocity == source._dice.dice[index].linear_velocity, "linear motion continues")
			check(rolling._dice.dice[index].angular_velocity == source._dice.dice[index].angular_velocity, "angular motion continues")
		var frame_before_bind: int = rolling._dice.snapshot().frame
		await physics_frame
		await physics_frame
		check(rolling._dice.snapshot().frame == frame_before_bind, "roll waits for a member to rebind")
		check(resume(rolling, ticket, "promoted").round.phase == "dice", "resumed member observes the roll")
		for frame in 600:
			if rolling._state.phase == "dealt":
				break
			await physics_frame
		check(rolling._state.phase == "dealt", "physical roll settles and starts a single deal")
		if rolling._state.phase == "dealt":
			var result: Array = rolling._dice.snapshot().result
			for index in 2:
				var face: Vector3 = rolling._dice.FACE_NORMALS[result[index] - 1]
				check((rolling._dice.dice[index].basis * face).dot(Vector3.UP) >= rolling._dice.UPRIGHT_DOT, "result comes from the resumed die's upper face")
			_check_dealt(rolling, ticket)
		rolling.queue_free()
	_check_close()
	source.queue_free()
	await process_frame
	print("Authority restore: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_dealt(source, ticket: Dictionary) -> void:
	var original: Dictionary = source.view_for("promoted")
	source._wall_offsets[1] = 1.5
	var dealt = restore(source)
	check(dealt != null, "restore external deal animation")
	if dealt == null:
		return
	var view := resume(dealt, ticket, "dealt")
	check(view.round.players[1].hand == original.round.players[1].hand, "private hand persists")
	check(view.round.players[0].hand.is_empty(), "opponent hand stays private")
	check(view.round.wall_offsets[1] == 1.5, "wall offset persists")
	check(view.round.phase == "dealt" and dealt._cues.has(1), "deal remains gated on its cue")
	check(dealt.finish_presentation(ticket.room_instance_id, 1, view.round.prompt_id, 1), "deal cue advances the same round")
	_check_turn(dealt, ticket)
	dealt.queue_free()

func _check_turn(source, ticket: Dictionary) -> void:
	var prompt: int = source._state.prompt_id
	var target = restore(source)
	check(target != null, "restore turn before presentation ends")
	if target == null:
		return
	var view := resume(target, ticket, "turn")
	check(view.clock.phase == "waiting_animation" and view.round.choices.is_empty(), "turn remains gated after restore")
	check(target.finish_presentation(ticket.room_instance_id, 1, prompt, 1), "finish restored turn cue")
	var original_now := new_now
	new_now += 3210
	var remaining: int = target.view_for("turn").clock.remaining_ms
	var checkpoint: Dictionary = target.export_authority()
	new_now = 25
	var timed := Host.new()
	timed.clock_msec = func(): return new_now
	root.add_child(timed)
	check(timed.restore_authority(checkpoint), "restore a released turn on a younger process clock")
	view = resume(timed, ticket, "timed")
	check(view.clock.remaining_ms == remaining and not view.round.choices.is_empty(), "released turn keeps its remaining time and choices")
	var deadline: int = timed._clock.timing_for(1, prompt, 1, new_now).deadline_ms
	var tile: int = view.round.choices.discard_ids[0]
	check(timed.acknowledge_foreground_view("timed", ticket.room_instance_id, 0), "new transport grants foreground control")
	_check_response(timed, ticket, view)
	new_now = deadline
	check(timed.submit("timed", ticket.room_instance_id, 1, prompt, "discard", tile), "restored authority accepts legal input exactly at its rebased cutoff")
	timed._pump_actions(new_now)
	var continued = restore(timed)
	check(continued != null and continued._state.prompt_id==timed._state.prompt_id and continued._state.prompt_id!=prompt, "restore preserves the accepted result instead of an undecided cutoff")
	if continued != null:
		check(not continued._expired.has(1), "accepted operation cannot revive an old timeout intent")
		continued.queue_free()
	timed.queue_free()
	target.queue_free()
	new_now = original_now

func _check_response(source, ticket: Dictionary, view: Dictionary) -> void:
	var target = restore(source)
	check(target != null, "restore turn to produce a real response")
	if target == null:
		return
	resume(target, ticket, "response-source")
	target.acknowledge_foreground_view("response-source", ticket.room_instance_id, 0)
	var round_state = target._session._round
	var chosen := -1
	for id in view.round.choices.discard_ids:
		var value: String = round_state.wall.value(id)
		for seat in [0, 2, 3]:
			if round_state.players[seat].hand.filter(func(other): return round_state.wall.value(other) == value).size() >= 2:
				chosen = id
				break
		if chosen >= 0:
			break
	check(chosen >= 0, "fixture has an offered pong")
	if chosen < 0:
		target.queue_free()
		return
	check(target.submit("response-source", ticket.room_instance_id, 1, view.round.prompt_id, "discard", chosen), "real discard opens response")
	check(target._state.phase == "response" and not target._cues.is_empty(), "response waits for eligible seats' cues")
	var restored = restore(target)
	check(restored != null, "restore response checkpoint")
	if restored != null:
		var resumed := resume(restored, ticket, "response-resumed")
		check(resumed.round.phase == "response" and resumed.round.choices.is_empty(), "discarder cannot see other seats' response choices")
		check(restored._session._round._response == round_state._response and restored._cues == target._cues, "response options and cues survive")
		restored.queue_free()
	target.queue_free()

func _check_close() -> void:
	var room := Room.new("123456")
	room.join("member", "南", "initial", 1000)
	room.disconnect_human("initial", 1200)
	var restored := Room.new("123456")
	check(restored.restore_authority(room.export_authority()), "restore disconnected room")
	restored.rebase_close_at(9000)
	check(restored.is_open(310199), "room stays open until the final millisecond of grace")
	check(not restored.is_open(310200), "room closes after five minutes")
