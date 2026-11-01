extends SceneTree

const ENV := preload("res://rl_env/RlEnv.gd")
const ACTIONS := preload("res://rl_env/ActionCodec.gd")
const H := preload("res://tests/test_harness.gd")

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var env = ENV.new()
	env.reset(7)
	var before := JSON.stringify(env.round.serialize())
	var visible: Dictionary = env.observation(env.current_actor())
	var advice: Dictionary = env.oracle_advise(visible)
	var after := JSON.stringify(env.round.serialize())
	t.expect(before == after, "oracle_advise never mutates the live round")
	t.expect(int(advice.get("best", -1)) >= 0, "oracle returns a best legal action")
	var legal := env.legal_actions(env.current_actor())
	t.expect(legal.any(func(action): return int(action.code) == int(advice.best)), "oracle best is legal")
	var total := 0.0
	for value in advice.get("probs", {}).values(): total += float(value)
	t.expect(absf(total - 1.0) < 0.01, "oracle action probabilities sum to one")

	var state: Dictionary = env.observation(env.current_actor())
	var code := int(legal[0].code)
	var step: Dictionary = env.step(state, code)
	t.expect(bool(step.get("ok", false)), "step(state, action) accepts a legal action")
	t.expect(step.has("state") and step.has("reward") and step.has("done"), "step returns state/reward/done")
	await H.quit_cleanly(self, t.finish("oracle_tests"))
