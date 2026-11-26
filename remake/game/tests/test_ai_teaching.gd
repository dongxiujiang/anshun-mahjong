extends SceneTree

const Controller = preload("res://src/ai/TeachingController.gd")
const Teaching = preload("res://src/ai/AiTeaching.gd")
const Ai = preload("res://src/ai/AiPlayer.gd")
const RoundCore = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Wall = preload("res://src/domain/Wall.gd")

var checks := 0
var failures := 0
var results := []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(description)

func envelope(round_state, seat: int, instance := "teaching-room") -> Dictionary:
	return {"room": {"room_instance_id": instance, "round_number": 1}, "seat": seat, "round": round_state.snapshot_for(seat)}

func new_round(deck: Array):
	var state := RoundCore.new()
	check(state.start(1, 5, 2, deck) and state.begin_dealer_turn(), "valid production deal and dealer draw")
	return state

func arranged(hands: Dictionary, draw: String) -> Array:
	var stock := Catalog.values(115)
	var wall := Wall.new(stock)
	wall.open(1, 5)
	var fixed := {}
	var indices := [0, 0, 0, 0]
	for amount in [4, 4, 4, 1]:
		for seat in [1, 0, 3, 2]:
			var cards: Array = hands.get(seat, [])
			for n in amount:
				var id := wall.take_head()
				if indices[seat] < cards.size():
					fixed[id] = cards[indices[seat]]
				indices[seat] += 1
	fixed[wall.take_head()] = draw
	for tile in fixed.values():
		check(stock.has(tile), "fixture respects four copies")
		stock.erase(tile)
	var deck := []
	for i in 108:
		deck.append(fixed[i] if fixed.has(i) else stock.pop_back())
	return deck

func explained(job: Dictionary, action: String, id: int) -> Dictionary:
	return Teaching.explain(job.view, "medium", {"action": action, "tile_id": id, "prompt_id": job.prompt_id})

func wait_for_count(count: int) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while results.size() < count and Time.get_ticks_msec() < deadline:
		await process_frame

func _run() -> void:
	var board = new_round(Catalog.values(3))
	var full := envelope(board, 1)
	var original: Dictionary = board.snapshot_for(1)
	for level in Ai.DIFFICULTIES:
		var job := Teaching.job_for(full, level)
		var advice := Teaching.recommend_one(job.view, level)
		var decision := Ai.decide(original, level)
		check(advice.action == decision.action and advice.tile_id == decision.tile_id, "same full production policy at " + level)
		check(advice.message.begins_with("先打") and advice.tile == board.wall.value(advice.tile_id), "message refers to the actual recommended tile")
	var altered := full.duplicate(true)
	altered.ticket = {"member_token":"never-copy-this"}
	altered.round.wall = board.wall.snapshot()
	altered.round.public_origins = {"7":"irrelevant"}
	altered.round.players[0].hand = [{"id": 42, "value": "never-copy-a-foreign-hand"}]
	altered.round.players[0].display = {"slots":["dragging"]}
	altered.round.players[1].display = {"selected":"highlight"}
	check(Teaching.job_for(full, "low") == Teaching.job_for(altered, "low"), "changing hidden wall, opponent hand, credentials and drag does not change the worker input")
	var hidden := altered.duplicate(true)
	hidden.round.players[0].melds = [{"kind":"kong", "concealed":true, "formed_at":0, "tile":"wan9", "tile_ids":[31, 32, 33, 34]}]
	var hidden_job := Teaching.job_for(hidden, "medium")
	check(hidden_job.view.players[0].melds == [{"kind":"kong", "concealed":true}], "an unrevealed kong has no identifying face, source or IDs in a worker")
	check(not hidden_job.view.has("wall_slots") and not hidden_job.has("ticket"), "worker cannot access stock or connection credentials")
	check(Teaching.job_for(envelope(board, 2), "low").is_empty() and Teaching.job_for(full, "expert").is_empty(), "no advice for another player's turn or unknown difficulty")
	for mutation in ["stale", "wrong-seat", "paused", "no-actions", "fraction"]:
		var bad := full.duplicate(true)
		match mutation:
			"stale": bad.round.choices.prompt_id -= 1
			"wrong-seat": bad.seat = 0
			"paused": bad.paused = true
			"no-actions": bad.round.choices = {}
			"fraction": bad.round.choices.discard_ids[0] = 1.5
		check(Teaching.job_for(bad, "medium").is_empty(), "suppressed advice: " + mutation)
	var tenpai := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tiao1", "tiao2", "tiao3", "tong5"]
	var ready_board = new_round(arranged({1:tenpai}, "tong7"))
	var ready_job := Teaching.job_for(envelope(ready_board, 1), "low")
	var discard: int = ready_board.players[1].draw_id
	check(ready_job.view.choices.ready_ids.has(discard) and explained(ready_job, "ready", discard).message == "打7筒报听。", "report legal declaration with the selected entity")
	check(explained(ready_job, "discard", discard).message == "先打7筒，打完就能叫牌。", "tenpai explanation uses the remaining thirteen and possible visible outs")
	check(explained(ready_job, "ready", -1).is_empty() and explained(ready_job, "self_win", -1).is_empty(), "no fabricated readiness or self-win advice")
	var win_board = new_round(arranged({1:tenpai}, "tong5"))
	var win_job := Teaching.job_for(envelope(win_board, 1), "medium")
	check(Teaching.recommend_one(win_job.view, "medium").message == "可以自摸。", "real self-draw recommendation")
	var response_board = new_round(arranged({0:["wan1","wan1","wan2","wan2","wan3","wan3","wan4","wan4","wan6","wan6","wan7","wan7","tong5"]}, "tong5"))
	var tile: int = response_board.players[1].draw_id
	check(response_board.submit(1, response_board.prompt_id, "discard", tile), "real public discard creates simultaneous choices")
	var response := Teaching.job_for(envelope(response_board, 0), "high")
	check(Teaching.recommend_one(response.view, "high").message == "这张5筒可以胡。" and explained(response, "pass", tile).message == "先过这张5筒。", "response and pass use only the public offered tile")
	var claims_board = new_round(arranged({0:["tong5", "tong5", "tong5"]}, "tong5"))
	tile = claims_board.players[1].draw_id
	check(claims_board.submit(1, claims_board.prompt_id, "discard", tile), "actual fourth copy offered by another seat")
	var claims := Teaching.job_for(envelope(claims_board, 0), "medium")
	check(explained(claims, "pong", tile).message == "5筒可以碰。" and explained(claims, "kong", tile).message == "5筒可以明杠。", "pung and exposed-kong explanations for actual legal options")
	var kong_board = new_round(arranged({1:["wan9", "wan9", "wan9", "wan9"]}, "tong5"))
	var kong := Teaching.job_for(envelope(kong_board, 1), "medium")
	check(explained(kong, "concealed_kong", kong.view.choices.concealed_kong_ids[0]).message == "9万可以暗杠。", "concealed kong only from the owner's own tiles")
	var teacher := Controller.new()
	root.add_child(teacher)
	teacher.recommendation_changed.connect(func(result: Dictionary): results.append(result))
	check(teacher.recommend(full, "medium") and results.is_empty(), "request returns before background calculation")
	check(teacher.recommend(altered, "medium"), "irrelevant display motion does not replace a running calculation")
	await wait_for_count(1)
	check(results.size() == 1 and results[0].room_instance_id == "teaching-room" and results[0].round_number == 1 and results[0].seat == 1 and results[0].prompt_id == board.prompt_id, "receives one scoped recommendation")
	var first_result: Dictionary = results.back()
	check(teacher.recommend(full, "medium") and results.size() == 1, "unchanged prompt does not repeat advice")
	check(original == board.snapshot_for(1) and board.choices(1).discard_ids.has(first_result.tile_id), "showing advice never discards, declares or changes the clock")
	teacher.recommend(full, "high")
	check(results.back().is_empty(), "changing difficulty clears earlier text immediately")
	teacher.recommend(envelope(win_board, 1, "new-room"), "low")
	var expected := results.size() + 1
	await wait_for_count(expected)
	check(results.size() == expected and results.back().action == "self_win" and results.back().room_instance_id == "new-room", "old-room result cannot replace new-room hint, even with matching prompt number")
	teacher.recommend(full, "low")
	teacher.cancel()
	expected = results.size()
	var deadline := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < deadline:
		await process_frame
	check(results.size() == expected and results.back().is_empty(), "leaving or disabling cancels pending advice without applying it")
	teacher.queue_free()
	await process_frame
	print("AI teaching: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
