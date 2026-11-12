extends SceneTree
const H := preload("res://tests/test_harness.gd")
const SUBMIT := preload("res://scripts/ui/ReplayExport.gd")
const REPLAY := preload("res://scripts/core/RoundReplay.gd")
const SMOKE := preload("res://tests/smoke_round.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var url := OS.get_environment("MAHJONG_RECORD_TEST_URL")
	if url.is_empty():
		push_error("Run through tests/run_record_submission.py")
		quit(1)
		return
	root.get_node("UpdateManager").auto_check = false
	var game := RoundState.new()
	game.set_rng_seed(42)
	game.controllers = [null, null, null, null]
	game.start_round(0, 3)
	var submitter := SUBMIT.new()
	submitter.base_url = url + "/missing"
	root.add_child(submitter)
	submitter.submit_round(game)
	t.expect(submitter.state.status == "waiting", "single-player request waits")
	for seat in 4: game.controllers[seat] = SMOKE.SimpleAi.new("AI")
	game._ask_turn_actor()
	t.expect(game.phase == RoundState.Phase.SETTLED, "real single-player game reaches settlement")
	var deadline := Time.get_ticks_msec() + 25000
	while submitter.busy and Time.get_ticks_msec() < deadline: await process_frame
	t.expect(submitter.state.status == "error" and not submitter.busy, "missing endpoint reports failure and allows retry")
	submitter.base_url = url
	submitter.submit_round(game)
	deadline = Time.get_ticks_msec() + 25000
	while submitter.busy and Time.get_ticks_msec() < deadline: await process_frame
	t.expect(submitter.state.status == "done", "real HTTP server confirms stored complete record: " + str(submitter.state))
	t.expect(game.round_meta.winner >= 0 and game.replay_record().events.any(func(event): return event.type == "win"), "winning game includes the final win event")
	submitter.submit_round(game)
	t.expect(submitter.state.status == "done" and not submitter.busy, "successful repeated tap is idempotent")
	var http := HTTPRequest.new()
	root.add_child(http)
	http.timeout = 5.0
	http.request(url + "/round-records?limit=1", PackedStringArray(["Authorization: Bearer " + OS.get_environment("MAHJONG_RECORD_TEST_KEY")]))
	var response: Array = await http.request_completed
	var payload: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	t.expect(int(response[1]) == 200 and payload is Dictionary and payload.count == 1, "protected sample API returns requested count")
	if payload is Dictionary and payload.get("records", []).size() == 1:
		var replayed := REPLAY.replay(payload.records[0].record)
		t.expect(replayed.ok, "downloaded sample replays successfully")
		if replayed.ok: t.expect(REPLAY.fingerprint(replayed.round) == REPLAY.fingerprint(game), "cloud round reproduces exact four-player scores and state")
	submitter.free()
	http.queue_free()
	await H.quit_cleanly(self, t.finish("record_submission_http"))
