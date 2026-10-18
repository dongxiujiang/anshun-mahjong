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
	config.set_animation_speed("standard")
	config.set_settlement_speed("detail")
	var settings = load("res://scripts/ui/SoundSettings.gd").new()
	settings.table_mode = true
	settings.persist_changes = false
	root.add_child(settings)
	for draw in config.TILE_ANIMATION_SPEEDS:
		for discard in config.TILE_ANIMATION_SPEEDS:
			settings.draw_speed_buttons[draw].pressed.emit()
			settings.discard_speed_buttons[discard].pressed.emit()
			for ai in config.AI_SPEED_DELAYS:
				config.set_ai_speed(ai)
				t.expect(config.animation_scale_for("draw") == config.TILE_ANIMATION_SPEEDS[draw], "draw speed survives independent discard and AI selections")
				t.expect(config.animation_scale_for("discard") == config.TILE_ANIMATION_SPEEDS[discard], "discard speed survives independent draw and AI selections")
				t.expect(config.animation_scale_for("meld") == 1.0 and config.animation_scale_for("sort_hand") == 1.0, "tile preferences cannot change meld/insert/sort")
				t.expect(config.animation_scale_for("deal") == 1.0 and config.settlement_duration(1.0) == 3.5, "opening and settlement keep their own clocks")
			t.expect(settings.draw_speed_buttons[draw].modulate != Color.WHITE and settings.discard_speed_buttons[discard].modulate != Color.WHITE, "both current selections are marked")
	config.set_draw_animation_speed("invalid")
	config.set_discard_animation_speed("invalid")
	t.expect(config.draw_animation_speed == "slow" and config.discard_animation_speed == "slow", "invalid keys preserve independent preferences")
	settings.free()
	config.set_draw_animation_speed("standard")
	config.set_discard_animation_speed("standard")
	config.set_settlement_speed("slow")
	config.set_ai_speed("fast")

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
	r.ai_delay_seconds = 2.0
	r.players[0].just_drew = ""
	r._ask_turn_actor()
	t.expect(r.turns.size() == 1, "post-pung discard without a draw has no draw wait")
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
	host.free()

func _run() -> void:
	_config_and_controls()
	await _ai_waits()
	quit(t.finish("animation_speed_settings"))
