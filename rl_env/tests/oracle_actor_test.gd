extends SceneTree

const ENV := preload("res://rl_env/RlEnv.gd")
const SL := preload("res://rl_env/SlPolicyActor.gd")
const H := preload("res://tests/test_harness.gd")

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var env = ENV.new()
	env.reset(11)
	var actor = SL.new("res://build/ai_high/oracle_sl_smoke2/oracle_sl_weights.json")
	var legal: Array = env.legal_actions(env.current_actor())
	var chosen: Dictionary = actor.choose(env, env.current_actor())
	t.expect(not chosen.is_empty(), "oracle SL actor loads exported weights")
	t.expect(legal.any(func(a): return int(a.code) == int(chosen.get("code", -1))), "oracle SL actor chooses a legal action")
	var step: Dictionary = env.step_state(env.observation(env.current_actor()), int(chosen.code))
	t.expect(bool(step.get("ok", false)), "oracle SL action can step the environment")
	await H.quit_cleanly(self, t.finish("oracle_actor_test"))
