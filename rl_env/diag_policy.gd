extends SceneTree
## 诊断：同一焦点局面下，策略 argmax 与 Oracle 标签的差异。

const ENV := preload("res://rl_env/RlEnv.gd")
const SL := preload("res://rl_env/SlPolicyActor.gd")

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for raw in OS.get_cmdline_user_args():
		var value := str(raw)
		if value.begins_with("--" + name + "="):
			return value.substr(name.length() + 3)
	return fallback

func _run() -> void:
	var seed := int(_arg("seed", "700"))
	var policy_path := _arg("policy", "")
	var feature_version := int(_arg("features", "2"))
	var env = ENV.new()
	env.reset(seed)
	var actor = SL.new(policy_path, feature_version)
	var focus: int = int(abs(seed)) % 4
	var steps := 0
	var shown := 0
	while steps < 2000 and not env.is_done() and shown < 20:
		steps += 1
		var seat := env.current_actor()
		if seat < 0: break
		var actions: Array = env.legal_actions(seat)
		if actions.is_empty(): break
		if seat == focus:
			var chosen: Dictionary = actor.choose_policy(env, seat)
			var advice: Dictionary = env.oracle_advise(env.observation(seat))
			var code := int(chosen.get("code", -1))
			var best := int(advice.get("best", -1))
			print("[diag] step=%d kind=%s legal=%s chosen=%d oracle=%d match=%s" % [
				steps, env.current_kind(), str(actions.map(func(a): return int(a.code))), code, best, str(code == best)])
			shown += 1
			env.step(code)
		else:
			env.step(int(actions[0].code))
	print("[diag] done score=", env.score_deltas())
	quit(0)
