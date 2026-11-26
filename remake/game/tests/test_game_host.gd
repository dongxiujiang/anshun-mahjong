extends SceneTree

const Host = preload("res://src/runtime/GameHost.gd")
const Record = preload("res://src/session/RoundRecord.gd")
var raw_ms := 1000
var checks := 0
var failures := 0
var closed := 0
var cues: Array = []
var poses := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func _new(mode: String, external: bool, extra: Dictionary = {}):
	var host := Host.new()
	host.clock_msec = func(): return raw_ms
	var cfg := {"difficulty": "low", "external_presentation": external,
		"ai_delay_ms": 8, "presentation_ms": {"dealt": 30, "turn": 10, "response": 10, "ready_draw": 10}}
	cfg.merge(extra, true)
	check(host.configure("host-suite", mode, 1, cfg), "configure real authority")
	root.add_child(host)
	host.presentation_required.connect(func(cue): cues.append(cue))
	host.dice_updated.connect(func(_state): poses += 1)
	host.room_closed.connect(func(): closed += 1)
	return host

func _run() -> void:
	await _solo()
	await _disconnected()
	await _cutoff()
	await _auto_play_races()
	print("GameHost: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _solo() -> void:
	var host = _new("solo", false)
	var joined: Dictionary = host.join("single", "南", "local")
	var instance: String = joined.ticket.room_instance_id
	var first: Dictionary = joined.view
	check(first.round.phase == "preparing" and first.round.wall_slots.size() == 108 and first.round.players[1].hand.is_empty(), "full wall before rolling or dealing")
	host.set_ready("local", true)
	var forced := false
	var completed := 0
	var checked_center := false
	var saw_ai := false
	var saw_roll := false
	for frame in 100000:
		await process_frame
		var view: Dictionary = host.view_for("local")
		var r: Dictionary = view.round
		saw_roll = saw_roll or r.phase == "dice"
		if r.phase == "dealt":
			check(r.wall_remaining == 56 and r.players[1].hand.size() == 13 and r.players[0].hand.is_empty(), "deal private hands and gate first draw")
			raw_ms += 31
			continue
		if r.phase == "settled":
			var private_record: Dictionary = host.last_completed_record()
			check(private_record.round_number == completed + 1, "settlements come from two different rounds")
			check(view.settlement.scores.reduce(func(total, value): return total + value, 0) == 800, "terminal room ledger stays at 800")
			check(Record.replay(private_record).ok, "full physical-dice and asynchronous AI round replays")
			saw_ai = saw_ai or private_record.inputs.any(func(c): return c.get("type") == "submit" and c.get("seat", 1) != 1)
			if completed == 0:
				check(private_record.inputs.any(func(c): return c.get("type") == "timeout" and c.get("action") == "discard" and c.seat == 1), "one-shot human timeout committed in normal host")
			completed += 1
			if completed >= 2:
				break
			host.set_ready("local", true)
			raw_ms += 1001
			await process_frame
			continue
		var options: Dictionary = r.choices
		if not options.is_empty():
			if not forced and options.actions.has("discard"):
				var prompt: int = r.prompt_id
				var left: int = view.clock.remaining_ms
				check(host.set_solo_paused(true), "single-player background pause")
				raw_ms += 22000
				await process_frame
				check(host.view_for("local").round.prompt_id == prompt and host.view_for("local").clock.remaining_ms == left, "pause suspends action window")
				host.set_solo_paused(false)
				raw_ms += int(view.clock.deadline_ms) - int(host._now()) - 1
				await process_frame
				check(host.view_for("local").round.choices.actions.has("discard"), "ordinary player's final millisecond remains available")
				raw_ms += 2
				for spin in 12000:
					await process_frame
					if host.view_for("local").round.prompt_id != prompt:
						break
				check(host.view_for("local").round.prompt_id != prompt, "real worker completes human timeout")
				forced = true
			else:
				var action := "pass" if options.actions.has("pass") else ("self_win" if options.actions.has("self_win") else "discard")
				var tile_id: int = options.discard_ids[0] if action == "discard" else -1
				check(host.submit("local", instance, view.room.round_number, r.prompt_id, action, tile_id), "normal authenticated human action")
		if r.phase in ["response", "turn"] and not checked_center:
			var ids: Array = r.wall_slots.duplicate()
			for seat in 4:
				if host.center_wall("local", seat):
					var moved: Dictionary = host.view_for("local").round
					check(moved.wall_slots == ids and moved.wall_offsets.size() == 4, "manual one-wall centering preserves all logical slots")
					for other in 4:
						if other != seat:
							check(moved.wall_offsets[other] == 0.0, "other walls stay fixed")
					checked_center = true
					break
		raw_ms += 2
	check(completed == 2 and saw_roll and saw_ai and checked_center and poses > 0, "two complete rounds use real physics, worker decisions and real ledger")
	host.shutdown()
	host.queue_free()

func _wait_phase(host, conn: String, target: String) -> Dictionary:
	for frame in 3500:
		await process_frame
		var view: Dictionary = host.view_for(conn)
		if not view.is_empty() and view.round.phase == target:
			return view
	check(false, "expected host phase " + target)
	return {}

func _auto_play_races() -> void:
	var host = _new("solo", true)
	var entered := Semaphore.new()
	var release := Semaphore.new()
	# Control when the real worker thread returns while keeping the host and rule submission paths intact.
	host._worker = Host.Scheduler.new(func(view: Dictionary, level: String):
		entered.post()
		release.wait()
		return {"prompt_id": view.prompt_id, "action": "discard", "tile_id": view.choices.discard_ids[0]} if level == "low" else {})
	var member: Dictionary = host.join("member", "南", "local").ticket
	var instance: String = member.room_instance_id
	host.set_ready("local", true)
	var view := await _wait_phase(host, "local", "dealt")
	if view.is_empty():
		host.shutdown()
		host.queue_free()
		return
	check(host.set_auto_play("local", instance, 1, true), "owner can opt in during the actual deal")
	raw_ms += 21000
	await process_frame
	check(host._worker._running.is_empty() and host.view_for("local").round.phase == "dealt", "opening gate blocks delegated thinking even after a nominal timeout")
	host.finish_presentation(instance, 1, view.round.prompt_id, 1)
	view = host.view_for("local")
	var prompt: int = view.round.prompt_id
	var opening_cue: Dictionary = view.presentation.duplicate(true)
	check(host.set_auto_play("local", instance, 1, false) and host.view_for("local").presentation == opening_cue, "cancelling during a draw preserves its exact animation cue")
	host.set_auto_play("local", instance, 1, true)
	await process_frame
	check(host._worker._running.is_empty(), "dealer's own turn animation still gates the worker")
	host.finish_presentation(instance, 1, prompt, 1)
	var original: Dictionary = host.view_for("local")
	var tile: int = original.round.choices.discard_ids[0]
	for frame in 3000:
		await process_frame
		if entered.try_wait(): break
	var job: Dictionary = host._session.ai_job(1, raw_ms)
	check(host._worker._running.has(1) and not host.submit("local", instance, 1, prompt, "discard", tile), "one controller owns the active choice")
	check(job.view.players[0].hand.is_empty() and job.view.players[1].hand == original.round.players[1].hand, "worker has only the owner's original private hand")
	host.set_auto_play("local", instance, 1, false)
	host.set_auto_play("local", instance, 1, true)
	check(not host._session.submit_ai(job, "discard", tile, raw_ms), "old permission is invalid even after immediate re-enabling")
	release.post()
	for frame in 3000:
		await process_frame
		if entered.try_wait(): break
	release.post()
	for frame in 3000:
		await process_frame
		if host._decisions.has(1): break
	check(host._decisions.has(1) and host._decisions[1].job.control_revision != job.control_revision, "only the new result reaches the delayed submission queue")
	host.set_solo_paused(true)
	raw_ms += 20000
	await process_frame
	check(host._decisions.has(1) and host.view_for("local").round == original.round, "solo pause freezes even a completed delegated decision")
	host.set_auto_play("local", instance, 1, false)
	host.set_solo_paused(false)
	check(host._decisions.is_empty() and host.view_for("local").clock == original.clock, "cancel drops the queued decision and preserves the original timer")
	raw_ms += 20
	await process_frame
	check(host.view_for("local").round == original.round and host.submit("local", instance, 1, prompt, "discard", tile), "manual control submits once against the original hand after both races")
	var after: Dictionary = host.view_for("local")
	check(after.round.players[1].discards.size() == 1 and not host._session.submit_ai(job, "discard", tile, raw_ms), "late work cannot overwrite the human's accepted discard")
	host.shutdown()
	host.queue_free()

func _disconnected() -> void:
	var host = _new("online", true, {"start_delay_ms": 3000})
	var joined: Dictionary = host.join("member", "北", "old")
	var t: Dictionary = joined.ticket
	host.set_ready("old", true)
	raw_ms += 2999
	await process_frame
	check(host.view_for("old").round.phase == "preparing", "multiplayer readiness countdown")
	host.set_ready("old", false)
	raw_ms += 100
	await process_frame
	check(not host.view_for("old").room.rolling, "cancelling readiness stops opening")
	host.set_ready("old", true)
	raw_ms += 3001
	var view := await _wait_phase(host, "old", "dealt")
	if view.is_empty():
		host.shutdown()
		return
	var instance: String = t.room_instance_id
	check(not host.set_solo_paused(true), "online authority never pauses from UI")
	raw_ms += 9000
	await process_frame
	check(host.view_for("old").round.phase == "dealt", "external authoritative animation waits below the ten-second receipt limit")
	check(not host.finish_presentation(instance, 1, view.round.prompt_id, 0) and host.finish_presentation(instance, 1, view.round.prompt_id, 1), "only exact dealer cue advances")
	view = host.view_for("old")
	check(view.round.choices.is_empty() and view.clock.phase == "waiting_animation", "ordinary timer waits after draw")
	host.finish_presentation(instance, 1, view.round.prompt_id, 1)
	check(host.disconnect_human("old"), "last human can disconnect without closing")
	raw_ms += 15001
	for spin in 18000:
		await process_frame
		if host._state.prompt_id != view.round.prompt_id:
			break
	var restored: Dictionary = host.resume(instance, t.player_id, t.member_token, "returned")
	check(not restored.is_empty() and restored.round.players[1].discards.size() == 1 and restored.round.players[0].hand.is_empty(), "offline room keeps playing then restores private state")
	check(host.view_for("old").is_empty(), "retired transport cannot read snapshots")
	var prior_closed := closed
	host.disconnect_human("returned")
	raw_ms += 299999
	await process_frame
	check(closed == prior_closed, "room still retained before five minutes")
	raw_ms += 1
	await process_frame
	await process_frame
	check(closed == prior_closed + 1 and host.resume(instance, t.player_id, t.member_token, "late").is_empty(), "actual authority expires after five minutes, emits once")
	host.queue_free()

func _cutoff() -> void:
	var host = _new("solo", true)
	var joined: Dictionary = host.join("edge", "东", "edge-c")
	var instance: String = joined.ticket.room_instance_id
	host.set_ready("edge-c", true)
	var view := await _wait_phase(host, "edge-c", "dealt")
	if view.is_empty():
		host.shutdown()
		return
	host.set_solo_paused(true)
	check(host.finish_presentation(instance, 1, view.round.prompt_id, 1) and host.view_for("edge-c").round.phase == "dealt", "animation may finish under settings without starting player clock")
	host.set_solo_paused(false)
	view = host.view_for("edge-c")
	host.finish_presentation(instance, 1, view.round.prompt_id, 1)
	view = host.view_for("edge-c")
	raw_ms = view.clock.deadline_ms
	check(host.submit("edge-c", instance, 1, view.round.prompt_id, "discard", view.round.choices.discard_ids[0]), "legal exact-deadline input is accepted")
	raw_ms += Host.Pace.ACTION_MS
	await process_frame
	await process_frame
	check(host.view_for("edge-c").round.prompt_id!=view.round.prompt_id, "deadline input advances normally without a frozen ruling state")
	host.shutdown()
	host.queue_free()
