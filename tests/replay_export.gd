extends SceneTree
const H := preload("res://tests/test_harness.gd")
const SUBMIT := preload("res://scripts/ui/ReplayExport.gd")
const REPLAY := preload("res://scripts/core/RoundReplay.gd")
const SMOKE := preload("res://tests/smoke_round.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _game() -> RoundState:
	var game := RoundState.new()
	game.set_rng_seed(20261112)
	game.controllers = [null, null, null, null]
	game.start_round(0, 3)
	return game

func _run() -> void:
	root.get_node("UpdateManager").auto_check = false
	var game := _game()
	var submitter := SUBMIT.new()
	root.add_child(submitter)
	submitter.base_url = "not-configured"
	submitter.submit_round(null)
	t.expect(not submitter.busy and submitter.state.status == "error", "no game cannot be submitted")
	var before := REPLAY.fingerprint(game)
	submitter.submit_round(game)
	t.expect(submitter.busy and submitter.state.status == "waiting", "mid-round request waits for settlement")
	t.expect(submitter._pending.is_empty() and submitter._http == null, "waiting does not upload hidden hands or a partial snapshot")
	submitter.submit_round(game)
	t.expect(game.round_finished.get_connections().size() == 1, "repeated request does not register duplicate finish listeners")
	t.expect(REPLAY.fingerprint(game) == before, "request does not change game state")
	for seat in 4: game.controllers[seat] = SMOKE.SimpleAi.new("AI")
	game._ask_turn_actor()
	t.expect(game.phase == RoundState.Phase.SETTLED, "finish an actual seeded game")
	t.expect(not submitter.busy and submitter.state.status == "error", "missing server reports failure, never a false success")
	t.expect(game.round_finished.get_connections().is_empty(), "completed request releases round listeners")
	var record := game.replay_record()
	var replayed := REPLAY.replay(record)
	t.expect(replayed.ok, "submitted record format remains replayable")
	if replayed.ok: t.expect(REPLAY.fingerprint(replayed.round) == REPLAY.fingerprint(game), "replay reaches the identical settlement")
	var kinds: Array = record.events.map(func(event): return event.type)
	for kind in ["dice", "deal_batch", "draw", "discard", "settlement"]:
		t.expect(kinds.has(kind), "full event history includes " + kind)
	t.expect(record.events.back().type == "settlement" and record.final.state.phase == "settled", "record ends with settlement and all final hands")
	t.expect(record.events.size() > game.visual_events.size(), "complete history outlives the short animation buffer")
	var client := RoundState.new()
	client.apply_sync(game.serialize_for_seat(2))
	submitter.submit_round(client)
	t.expect(submitter.state.status == "error" and submitter._http == null, "ordinary client snapshot cannot pretend to be a full replay")
	var abandoned := _game()
	submitter.submit_round(abandoned)
	abandoned.start_round(0, 4)
	t.expect(not submitter.busy and submitter.state.status == "error", "replaced unfinished game cannot upload a different round")
	submitter.free()
	await _test_ui()
	await H.quit_cleanly(self, t.finish("replay_export"))

func _test_ui() -> void:
	var settings = load("res://scripts/ui/SoundSettings.gd").new()
	settings.table_mode = true
	settings.persist_changes = false
	root.add_child(settings)
	var table = load("res://scripts/ui/GameTable.gd").new()
	table.round = _game()
	table._sound_settings = settings
	settings.replay_export_requested.connect(table._export_current_replay)
	settings.open()
	t.expect(settings.replay_export_button.text == "提交本局记录", "button uses cloud submission wording")
	settings.replay_export_button.pressed.emit()
	t.expect(settings.replay_exporter.state.status == "waiting" and settings.replay_status.text.contains("结束后"), "button registers the current real round")
	t.expect(settings.replay_export_button.disabled and not settings.continue_button.disabled and not settings.exit_room_button.disabled, "registration blocks duplicate taps but never blocks play or exit")
	settings.close(false)
	await create_timer(0.3).timeout
	t.expect(not settings.is_open(), "player can close settings while waiting")
	settings.open()
	await create_timer(0.4).timeout
	root.content_scale_size = Vector2i(2280, 1280)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for dimensions in [Vector2i(1280,720), Vector2i(960,540), Vector2i(2400,1080)]:
		root.size = dimensions
		await process_frame
		settings._layout()
		t.expect(root.get_visible_rect().encloses(settings.panel.get_global_rect()), "submission settings fit " + str(dimensions))
		if DisplayServer.get_name() != "headless" and dimensions == Vector2i(1280,720):
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://build/record-submission")
			root.get_texture().get_image().save_png("res://build/record-submission/settings-waiting.png")
	var unfinished: RoundState = table.round
	settings.free()
	t.expect(unfinished.round_finished.get_connections().is_empty(), "leaving single-player cancels the unfinished registration")
	table.free()
