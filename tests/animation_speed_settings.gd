extends SceneTree
## Timing contracts: independent preferences, real controls and guarded AI waits.
const H := preload("res://tests/test_harness.gd")
var t := H.new()

class Actor extends RefCounted:
	var turn := {"discard": "tong9"}
	var response := {"action": "pong"}
	func decide_turn(_round, _seat) -> Dictionary: return turn
	func decide_response(_round, _seat, _source, _tile, _options) -> Dictionary: return response

class Probe extends RoundState:
	var turns: Array = []
	var responses: Array = []
	func _apply_turn_action(seat: int, decision: Dictionary) -> void:
		turns.append({"seat": seat, "decision": decision})
	func _process_response(seat: int, source: int, tile: String, decision: Dictionary) -> void:
		responses.append({"seat": seat, "source": source, "tile": tile, "decision": decision})

func _initialize() -> void: call_deferred("_run")

func _probe() -> Probe:
	var r := Probe.new()
	r.set_rng_seed(20261018)
	r.build_players(0)
	r.phase = RoundState.Phase.PLAYING
	r.current_turn = 0
	r.controllers = [Actor.new(), Actor.new(), null, null]
	r.players[0].concealed = ["tong9"]
	r.players[0].just_drew = "tong9"
	return r

func _config_and_controls() -> void:
	var config = root.get_node("GameConfig")
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	var settings = table._sound_settings
	settings.persist_changes = false
	settings.open()
	var timing: Array = [settings.tile_speed_slider, settings.ai_speed_slider, settings.settlement_speed_slider]
	for slider in timing:
		t.expect(slider.min_value == 0.0 and slider.max_value == 2.0 and slider.step == 0.01, "each speed control supports 0–2 seconds")
		t.expect(settings._timing_labels[slider].position.x > slider.get_rect().end.x, "numeric readout sits to the right")
	for seconds in [0.0, 1.37, 2.0]:
		for slider in timing:
			slider.value = seconds
			t.expect(settings._timing_labels[slider].text == "%.2f s" % seconds, "readout shows the exact selected duration")
		t.expect(is_equal_approx(config.tile_motion_seconds(), seconds), "draw and discard use the shared duration")
		t.expect(is_equal_approx(config.opening_deal_scale(config.opening_speed_key()) * config.DEAL_FLIGHT_SECONDS, seconds), "each opening packet shares the configured duration")
		t.expect(is_equal_approx(config.ai_speed_seconds(config.ai_speed), seconds), "AI control stores seconds")
		t.expect(is_equal_approx(config.settlement_duration(config.SETTLEMENT_STEP_SECONDS), seconds), "each scoring stage uses the configured duration")
	settings.tile_speed_slider.drag_started.emit()
	settings.tile_speed_slider.value = 0.64
	t.expect(is_equal_approx(config.tile_animation_seconds, 2.0), "dragging updates the readout without saving every increment")
	settings.tile_speed_slider.drag_ended.emit(true)
	t.expect(is_equal_approx(config.tile_animation_seconds, 0.64), "releasing the slider commits the selected duration")
	config.set_tile_animation_seconds(-0.1, false)
	t.expect(is_equal_approx(config.tile_animation_seconds, 0.64), "invalid tile duration is ignored")
	config.set_settlement_speed("fast", false)
	config.set_ai_speed("fast", false)
	config.set_tile_animation_seconds(0.30, false)
	table.free()

func _ai_waits() -> void:
	var r := _probe()
	r.ai_delay_seconds = 0.02
	r._ask_turn_actor()
	t.expect(r.turns.is_empty(), "AI discard waits after draw")
	await create_timer(0.06).timeout
	t.expect(r.turns.size() == 1 and r.turns[0].decision == {"discard": "tong9"}, "draw wait applies exactly one recorded decision")
	for action in [{"self_win": true}, {"kong_declares": ["tong9"]}, {"add_kong": ["tong9"]}]:
		r = _probe()
		r.ai_delay_seconds = 2.0
		r.controllers[0].turn = action
		r._ask_turn_actor()
		t.expect(r.turns.size() == 1, "draw-to-discard speed does not delay win/kong decisions")
	r = _probe()
	r.ai_delay_seconds = 0.02
	r.players[0].just_drew = ""
	r._ask_turn_actor()
	t.expect(r.turns.is_empty(), "post-pung discard also waits")
	await create_timer(0.06).timeout
	t.expect(r.turns.size() == 1 and r.turns[0].decision == {"discard": "tong9"}, "post-pung delay applies exactly one recorded decision")
	for ai in [0.0, 0.8, 1.3, 2.0]:
		for action in ["pong", "kong", "win", "pass"]:
			r = _probe()
			r.ai_delay_seconds = ai
			r.ai_response_delay_seconds = 0.02
			r._response_stage = RoundState.ResponseStage.MELD
			r._pending_responders = [1]
			r.controllers[1].response = {"action": action}
			r._queue_ai_response(1, 0, "tiao3", {}, r.controllers[1])
			t.expect(r.responses.size() == (1 if action == "pass" else 0), "pass is immediate; claims use only the fixed response beat")
			await create_timer(0.06).timeout
			t.expect(r.responses.size() == 1 and r.responses[0].decision.action == action, "response finishes independently of the AI discard delay")
	# A dedicated host uses the selected lobby value, not this client's setting.
	var host := NetGameNode.new()
	host.dedicated = true
	for speed in ["fast", "medium", "slow"]:
		host.ai_speed = speed
		t.expect(host._ai_turn_delay() == root.get_node("GameConfig").AI_SPEED_DELAYS[speed], "network and offline use the same draw wait rates")
		t.expect(host._ai_response_delay() == root.get_node("GameConfig").AI_SPEED_DELAYS[speed], "claim beat matches the same speed selection")
	for seconds in [0.0, 0.37, 2.0]:
		host.ai_speed = "%.2f" % seconds
		t.expect(is_equal_approx(host._ai_turn_delay(), seconds) and is_equal_approx(host._ai_response_delay(), seconds), "dedicated room uses numeric wait for AI turns and claims")
	host.free()

func _opening_ready_gate() -> void:
	var net := NetGameNode.new()
	root.add_child(net)
	net.host_mode = true
	net.round_number = 7
	net._members = {2: {}, 3: {}}
	net._opening_waiters = {2: true, 3: true}
	net.game = RoundState.new()
	net.game.controllers = [null, null, null, null]
	net.game.pause_after_opening = true
	net.game.start_round(1, 2, 3)
	var session: String = net.game.audio_session
	t.expect(net.game.wall.remaining == 56 and net.game.phase == RoundState.Phase.PLAYING,
		"authority waits with thirteen tiles per player even after its opening timer")
	net.game.restore_human_control(net.game.current_turn)
	t.expect(not net.game.awaiting, "rejoining during the opening cannot prompt an undrawn hand")
	net._accept_opening_ready(2, 6, session)
	net._accept_opening_ready(2, 7, "stale")
	net._accept_opening_ready(99, 7, session)
	t.expect(net._opening_waiters.size() == 2, "stale and nonmember confirmations cannot release the gate")
	net._accept_opening_ready(2, 7, session)
	t.expect(net.game.pause_after_opening and net.game.wall.remaining == 56, "one fast client cannot start play before the slow client")
	net._accept_opening_ready(3, 7, session)
	t.expect(not net.game.pause_after_opening and net.game.wall.remaining == 55, "last confirmation releases exactly the first draw")
	net._accept_opening_ready(3, 7, session)
	t.expect(net.game.wall.remaining == 55, "duplicate confirmations never draw again")
	net.free()

func _run() -> void:
	_opening_ready_gate()
	_config_and_controls()
	await _ai_waits()
	quit(t.finish("animation_speed_settings"))

