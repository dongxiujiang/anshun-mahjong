extends SceneTree
## 评估 SL/PPO 权重：焦点座位对启发 AI，或四家全部使用策略。

const ENV := preload("res://rl_env/RlEnv.gd")
const SL := preload("res://rl_env/SlPolicyActor.gd")
const BLENDED := preload("res://rl_env/BlendedActor.gd")
const RERANK := preload("res://rl_env/RerankActor.gd")
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
			if int(action.code) == wanted:
				return wanted
		return -1
	if bool(decision.get("self_win", false)):
		for action in actions:
			if int(action.code) == 108:
				return 108
		return -1
	var dark: Array = decision.get("kong_declares", [])
	if not dark.is_empty():
		for action in actions:
			if str(action.kind) == "kong" and str(action.tile) == str(dark[0]):
				return int(action.code)
		return -1
	var added: Array = decision.get("add_kong", [])
	if not added.is_empty():
		for action in actions:
			if str(action.kind) == "add_kong" and str(action.tile) == str(added[0]):
				return int(action.code)
		return -1
	var tile := str(decision.get("discard", ""))
	var wanted_kind := "ready_discard" if bool(decision.get("ready", false)) else "discard"
	for action in actions:
		if str(action.kind) == wanted_kind and str(action.tile) == tile:
			return int(action.code)
	for action in actions:
		if str(action.kind) == "discard" and str(action.tile) == tile:
			return int(action.code)
	return -1

func _run() -> void:
	var start := int(_arg("start", "0"))
	var count := int(_arg("count", "20"))
	var policy_path := _arg("policy", "")
	var all_seats := _arg("all", "0") == "1"
	var sample := _arg("sample", "0") == "1"
	var heuristic_response := _arg("heuristic-response", "0") == "1"
	var oracle_check := _arg("oracle-check", "0") == "1"
	var feature_version := int(_arg("features", "2"))
	var blend := _arg("blend", "0") == "1"
	var rerank := _arg("rerank", "0") == "1"
	var confidence := float(_arg("confidence", "0.45"))
	var level := _arg("level", "low")
	var actor
	if rerank and policy_path != "":
		actor = RERANK.new(policy_path, feature_version)
	elif blend and policy_path != "":
		actor = BLENDED.new(policy_path, confidence, feature_version)
	elif policy_path != "":
		actor = SL.new(policy_path, feature_version)
	else:
		actor = SL.new("", feature_version)
	var results: Array = []
	var policy_score := 0.0
	var policy_wins := 0
	var games := 0
	var oracle_checked := 0
	var oracle_matches := 0
	for seed in range(start, start + count):
		var env = ENV.new()
		env.reset(seed)
		var focus_seat: int = int(abs(seed)) % 4
		var opponents: Array = []
		for seat in 4:
			var ai = AI.new("Eval%d" % seat, level)
			ai.use_mcts = false
			ai.rng.seed = seed * 23 + seat + 7
			opponents.append(ai)
		var steps := 0
		while steps < 2000 and not env.is_done():
			steps += 1
			var seat := env.current_actor()
			if seat < 0:
				break
			var actions: Array = env.legal_actions(seat)
			if actions.is_empty():
				break
			var code := -1
			var use_policy := all_seats or seat == focus_seat
			if use_policy and heuristic_response and env.current_kind() == "response":
				use_policy = false
			if use_policy:
				if sample:
					var rng := RandomNumberGenerator.new()
					rng.seed = seed * 131 + seat + steps
					code = int(actor.sample_action(env, seat, rng, 0.0).get("code", -1))
				else:
					code = int(actor.choose_policy(env, seat).get("code", -1))
				if oracle_check:
					var oracle_code := int(env.oracle_advise(env.observation(seat)).get("best", -1))
					if oracle_code >= 0:
						oracle_checked += 1
						if oracle_code == code: oracle_matches += 1
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
			if code < 0:
				code = int(actions[0].code)
			var result: Dictionary = env.step_state(env.observation(seat), code)
			if not bool(result.get("ok", false)):
				break
		if env.is_done():
			games += 1
			var scores: Array = env.score_deltas()
			if all_seats:
				var average := 0.0
				for value in scores: average += float(value)
				policy_score += average / 4.0
			else:
				var value := float(scores[focus_seat]) if focus_seat < scores.size() else 0.0
				policy_score += value
				if value > 0.0:
					policy_wins += 1
			results.append({"seed": seed, "focus": focus_seat, "steps": steps, "scores": scores})
	print(JSON.stringify({
		"policy": policy_path,
		"all_seats": all_seats,
		"level": level,
		"games": games,
		"policy_score": policy_score,
		"wins": policy_wins,
		"oracle_checked": oracle_checked,
		"oracle_matches": oracle_matches,
		"results": results,
	}))
	quit(0)
