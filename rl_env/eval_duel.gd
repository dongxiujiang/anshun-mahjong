extends SceneTree
## 固定座位的成对评估：Policy 坐 0 位 vs 基线坐 0 位，使用同一批 seed。

const ENV := preload("res://rl_env/RlEnv.gd")
const SL := preload("res://rl_env/SlPolicyActor.gd")
const BLENDED := preload("res://rl_env/BlendedActor.gd")
const AI := preload("res://scripts/ai/AiPlayer.gd")

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	for raw in OS.get_cmdline_user_args():
		var value := str(raw)
		if value.begins_with("--" + name + "="):
			return value.substr(name.length() + 3)
	return fallback

func _decision_code(decision: Dictionary, kind: String, actions: Array) -> int:
	if kind == "response":
		var wanted: int = int({"win": 111, "pong": 109, "kong": 110, "pass": 112}.get(
			str(decision.get("action", "pass")), 112))
		for action in actions:
			if int(action.code) == wanted: return wanted
		return -1
	if bool(decision.get("self_win", false)):
		for action in actions:
			if int(action.code) == 108: return 108
		return -1
	var dark: Array = decision.get("kong_declares", [])
	if not dark.is_empty():
		for action in actions:
			if str(action.kind) == "kong" and str(action.tile) == str(dark[0]): return int(action.code)
		return -1
	var added: Array = decision.get("add_kong", [])
	if not added.is_empty():
		for action in actions:
			if str(action.kind) == "add_kong" and str(action.tile) == str(added[0]): return int(action.code)
		return -1
	var tile := str(decision.get("discard", ""))
	var wanted_kind := "ready_discard" if bool(decision.get("ready", false)) else "discard"
	for action in actions:
		if str(action.kind) == wanted_kind and str(action.tile) == tile: return int(action.code)
	for action in actions:
		if str(action.kind) == "discard" and str(action.tile) == tile: return int(action.code)
	return -1

func _play(seed: int, actor, baseline_level: String, opponent_level: String, feature_version: int) -> Array:
	var env = ENV.new()
	env.reset(seed)
	var opponents: Array = []
	for seat in 4:
		var ai = AI.new("Opp%d" % seat, baseline_level if seat == 0 else opponent_level)
		ai.use_mcts = false
		ai.rng.seed = seed * 41 + seat + 3
		opponents.append(ai)
	var focus_seat := 0
	var steps := 0
	while steps < 2000 and not env.is_done():
		steps += 1
		var seat := env.current_actor()
		if seat < 0: break
		var actions: Array = env.legal_actions(seat)
		if actions.is_empty(): break
		var code := -1
		if seat == focus_seat and actor != null:
			code = int(actor.choose_policy(env, seat).get("code", -1))
		else:
			var kind := env.current_kind()
			var allowed: Dictionary = env.round.allowed_actions(seat)
			var decision: Dictionary
			if kind == "response":
				var prompt: Dictionary = env.round._awaiting_response
				decision = opponents[seat].decide_response(env.round, seat,
					int(prompt.get("disc_seat", -1)), str(prompt.get("tile", "")),
					allowed.get("options", {}))
			else:
				decision = opponents[seat].decide_turn(env.round, seat)
			code = _decision_code(decision, kind, actions)
		if code < 0: code = int(actions[0].code)
		var result: Dictionary = env.step_state(env.observation(seat), code)
		if not bool(result.get("ok", false)): break
	if not env.is_done():
		return [0.0, 0, steps]
	var scores: Array = env.score_deltas()
	var value := float(scores[0]) if scores.size() > 0 else 0.0
	return [value, 1, steps]

func _run() -> void:
	var start := int(_arg("start", "1000"))
	var count := int(_arg("count", "100"))
	var policy_path := _arg("policy", "")
	var baseline_level := _arg("baseline", "low")
	var opponent_level := _arg("opponent", "low")
	var feature_version := int(_arg("features", "2"))
	var blend := _arg("blend", "0") == "1"
	var confidence := float(_arg("confidence", "0.45"))
	var actor = BLENDED.new(policy_path, confidence, feature_version) if blend and policy_path != "" else (SL.new(policy_path, feature_version) if policy_path != "" else null)
	var pg := 0; var pw := 0; var ps := 0.0
	var bg := 0; var bw := 0; var bs := 0.0
	var diffs: Array = []
	var rows: Array = []
	for seed in range(start, start + count):
		var p: Array = _play(seed, actor, baseline_level, opponent_level, feature_version)
		var b: Array = _play(seed, null, baseline_level, opponent_level, feature_version)
		if int(p[1]) == 1:
			pg += 1
			if float(p[0]) > 0.0: pw += 1
			ps += float(p[0])
		if int(b[1]) == 1:
			bg += 1
			if float(b[0]) > 0.0: bw += 1
			bs += float(b[0])
		if int(p[1]) == 1 and int(b[1]) == 1:
			diffs.append(float(p[0]) - float(b[0]))
		rows.append({"seed": seed, "policy": p, "baseline": b})
	var diff_sum := 0.0
	for value in diffs: diff_sum += float(value)
	print(JSON.stringify({
		"protocol": "seat0 policy/baseline vs same opponents, paired seeds",
		"count": count, "games": pg,
		"policy_wins": pw, "policy_score": ps, "policy_avg": ps / max(1, pg),
		"baseline_wins": bw, "baseline_score": bs, "baseline_avg": bs / max(1, bg),
		"paired_diff_avg": diff_sum / max(1, diffs.size()),
		"rows": rows,
	}))
	quit(0)
