extends SceneTree

const Scheduler = preload("res://src/ai/AiScheduler.gd")
const Match = preload("res://src/session/MatchSession.gd")
const Dice = preload("res://src/runtime/DiceRoll.gd")
const Wall = preload("res://src/domain/Wall.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Shanten = preload("res://src/anshun/scoring/Shanten.gd")
const Value = preload("res://src/ai/AiValueModel.gd")
const NOW := 30

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func _run() -> void:
	var dice := Dice.new()
	root.add_child(dice)
	check(dice.roll(31500), "start an authority roll")
	for _step in 1800:
		if dice.phase == "settled":
			break
		await physics_frame
	check(dice.phase == "settled", "authority dice finished")
	if dice.phase == "settled":
		await _three_responses(dice)
		var job := await _stale_after_resume(dice)
		if not job.is_empty():
			await _replacements_and_shutdown(job)
	check(Shanten._thread_caches.keys() == [OS.get_thread_caller_id()] and Value._unit_caches.is_empty(),
		"joined jobs released both worker caches and kept the authority rule cache")
	print("AI scheduler: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _begin(dice: Dice, dealer: int, deck: Array) -> Match:
	var game := Match.new("123")
	var joined := game.join("host", "东", "host-link", NOW)
	check(not joined.is_empty() and game.set_ready("host-link", true, NOW), "host joins ready")
	check(game.start_round(dice, deck, NOW, dealer), "match starts with real deal and settled dice")
	var first := game.view_for("host-link", NOW)
	check(game.begin_dealer_turn(first.room.room_instance_id, 1, first.round.prompt_id, NOW), "match begins dealer draw")
	return game

func _response_deck(red: int) -> Array:
	var probe := Wall.new(Catalog.values(99))
	probe.open(1, red)
	var hands := {0: ["wan", "112233446677"], 3: ["tiao", "112233445566"], 2: ["tong", "112233445566"]}
	var fixed := {(probe.break_index + 52) % 108: "wan5"}
	for seat in hands:
		var offset := posmod(1 - seat, 4)
		for index in 12:
			fixed[(probe.break_index + (index / 4) * 16 + offset * 4 + index % 4) % 108] = hands[seat][0] + hands[seat][1][index]
		fixed[(probe.break_index + 48 + offset) % 108] = "wan5"
	var pool := Catalog.values(285)
	for value in fixed.values():
		pool.erase(value)
	var deck := []
	for id in 108:
		deck.append(fixed[id] if fixed.has(id) else pool.pop_back())
	return deck

func _collect(scheduler: Scheduler, count: int) -> Array:
	var results := []
	var deadline := Time.get_ticks_msec() + 5000
	while results.size() < count and Time.get_ticks_msec() < deadline:
		results.append_array(scheduler.poll())
		if results.size() < count:
			await process_frame
	return results

func _three_responses(dice: Dice) -> void:
	var game := _begin(dice, 1, _response_deck(dice.snapshot().result[0]))
	var opening := game.view_for("host-link", NOW)
	var instance: String = opening.room.room_instance_id
	var tile_id: int = opening.round.players[1].draw_id
	check(game.submit("host-link", instance, 1, opening.round.prompt_id, "discard", tile_id, NOW), "host creates one simultaneous response window")
	var scheduler := Scheduler.new()
	var original := {}
	for seat in [0, 2, 3]:
		var job := game.ai_job(seat, NOW)
		check(job.get("view", {}).get("choices", {}).get("actions", []).has("win"), "seat %s can win in the same window" % seat)
		original[seat] = [job, job.duplicate(true)]
		check(scheduler.enqueue(job, "medium") and scheduler.enqueue(job, "medium"), "accept and deduplicate seat %s" % seat)
	check(scheduler._running.size() == 3 and scheduler._queued.is_empty(), "three independent running seats and no duplicates queued")
	var replies := await _collect(scheduler, 3)
	var responded := []
	for item in replies:
		var seat: int = item.job.seat
		check(original.has(seat) and item.job == original[seat][1], "result preserves seat %s's exact original authority job" % seat)
		check(item.decision == {"prompt_id": item.job.prompt_id, "action": "win", "tile_id": tile_id}, "seat %s returns a legal win on the shared physical tile" % seat)
		check(game.submit_ai(item.job, item.decision.action, item.decision.tile_id, NOW), "authority applies the identified AI response")
		responded.append(seat)
	responded.sort()
	check(responded == [0, 2, 3], "one response per AI seat")
	var final := game.view_for("host-link", NOW)
	check(final.get("settlement", {}).get("round_meta", {}).get("winners", []) == [0, 3, 2], "all three wins settle in seat priority, independent of worker order")
	for pair in original.values():
		check(pair[0] == pair[1], "worker leaves the source job and view unmodified")
	scheduler.shutdown()

func _stale_after_resume(dice: Dice) -> Dictionary:
	var game := _begin(dice, 0, Catalog.values(165))
	var job := game.ai_job(0, NOW)
	var scheduler := Scheduler.new()
	check(job.get("view", {}).get("choices", {}).get("actions", []).has("discard"), "AI turn fixture offers a discard")
	check(scheduler.enqueue(job, "low"), "submit work before seat control changes")
	var member: Dictionary = game.join("member", "北", "early-link", NOW).ticket
	check(member.seat == 0 and game.set_auto_play("early-link", member.room_instance_id, 1, true, NOW) == 1, "new owner explicitly delegates the seat taken from AI")
	var delegated := game.ai_job(0, NOW)
	var tile: int = delegated.view.choices.discard_ids[0]
	check(not game.submit_ai(job, "discard", tile, NOW), "former pure AI cannot act under the new human's separate authorization")
	check(game.disconnect_human("early-link", NOW), "human disconnects while delegated work is outstanding")
	var resumed := game.resume(member.room_instance_id, "member", member.member_token, "recovered-link", NOW)
	check(game.set_auto_play("early-link", member.room_instance_id, 1, true, NOW) == -1, "retired connection cannot delegate the recovered seat")
	check(game.set_auto_play("recovered-link", member.room_instance_id, 1, true, NOW) == 1 and not game.submit_ai(delegated, "discard", tile, NOW), "fresh permission never revives a stale delegated decision")
	game.set_auto_play("recovered-link", member.room_instance_id, 1, false, NOW)
	check(resumed.round.prompt_id == job.prompt_id and resumed.round.players[0].hand == job.view.players[0].hand,
		"resumed member recovers the same live prompt and hand")
	var result := await _collect(scheduler, 1)
	check(result.size() == 1, "original worker finishes after the control change")
	if result.size() == 1:
		var item: Dictionary = result[0]
		check(not game.submit_ai(item.job, item.decision.action, item.decision.tile_id, NOW), "authority rejects late work after member reconnect")
		check(game.view_for("recovered-link", NOW).round == resumed.round, "late work leaves resumed prompt unchanged")
		var tile_id: int = resumed.round.choices.discard_ids[0]
		check(game.submit("recovered-link", member.room_instance_id, 1, job.prompt_id, "discard", tile_id, NOW), "resumed member can act")
	scheduler.shutdown()
	return job

func _replacements_and_shutdown(job: Dictionary) -> void:
	var scheduler := Scheduler.new()
	var seat: int = job.seat
	check(not scheduler.enqueue(job, "unknown"), "reject unknown production difficulty")
	check(scheduler.enqueue(job, "low"), "start a worker for replacement test")
	var running: RefCounted = scheduler._running[seat]
	var candidate := job.duplicate(true)
	for index in range(1, 51):
		candidate.control_revision = job.control_revision + index
		check(scheduler.enqueue(candidate, "high"), "queue latest version %s" % index)
		check(scheduler._running.size() == 1 and scheduler._queued.size() == 1, "one running and one replacement per seat")
	var expected := candidate.duplicate(true)
	candidate.view.choices.actions.clear()
	candidate.control_revision = -1
	var result := await _collect(scheduler, 1)
	check(result.size() == 1 and result[0].job == expected and running.cancelled, "only the latest queued deep copy is delivered")
	check(scheduler.poll().is_empty(), "completed work is delivered once")
	check(scheduler.enqueue(job, "high") and scheduler.enqueue(job, "low"), "queue work to cancel")
	scheduler.cancel_seat(seat)
	check(scheduler._queued.is_empty() and scheduler._running[seat].cancelled, "cancel discards the replacement and invalidates the running result")
	var cancelled: RefCounted = scheduler._running[seat]
	var deadline := Time.get_ticks_msec() + 5000
	var dropped := []
	while scheduler._running.has(seat) and Time.get_ticks_msec() < deadline:
		dropped.append_array(scheduler.poll())
		await process_frame
	check(scheduler._running.is_empty() and not cancelled.decision.is_empty() and dropped.is_empty(),
		"poll retires cancelled computation without delivering it")
	check(scheduler.enqueue(job, "high") and scheduler.enqueue(job, "low"), "queue work before closing room")
	var current: RefCounted = scheduler._running[seat]
	var never_started: RefCounted = scheduler._queued[seat]
	scheduler.shutdown()
	check(scheduler._running.is_empty() and scheduler._queued.is_empty() and not current.decision.is_empty() and never_started.task_id == -1,
		"shutdown joins the running worker and discards the queued replacement")
	check(scheduler.poll().is_empty() and not scheduler.enqueue(job, "low"), "closed scheduler cannot deliver cancelled work or start more")
	var abandoned := Scheduler.new()
	check(abandoned.enqueue(job, "medium"), "start a worker before releasing the scheduler")
	var finishing: RefCounted = abandoned._running[seat]
	abandoned = null
	check(not finishing.decision.is_empty(), "releasing the scheduler joins any remaining pool task")
