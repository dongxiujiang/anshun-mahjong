extends SceneTree
## 对照：焦点座位直接执行 oracle_advise 的 best 动作，其余座位使用启发 AI。
## 只用于验证 Oracle 标签质量，不进入训练。

const ENV := preload("res://rl_env/RlEnv.gd")
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

func _run() -> void:
	var start := int(_arg("start", "0"))
	var count := int(_arg("count", "10"))
	var games := 0
	var score := 0.0
	var wins := 0
	for seed in range(start, start + count):
		var env = ENV.new()
		env.reset(seed)
		var focus: int = int(abs(seed)) % 4
		var actors: Array = []
		for seat in 4:
			var ai = AI.new("OracleEval%d" % seat, "medium")
			ai.use_mcts = false
			ai.rng.seed = seed * 31 + seat + 3
			actors.append(ai)
		var steps := 0
		while steps < 2000 and not env.is_done():
			steps += 1
			var seat := env.current_actor()
			if seat < 0: break
			var actions: Array = env.legal_actions(seat)
			if actions.is_empty(): break
			var code := -1
			if seat == focus:
				code = int(env.oracle_advise(env.observation(seat)).get("best", -1))
			else:
				var kind := env.current_kind()
				var allowed: Dictionary = env.round.allowed_actions(seat)
				var decision: Dictionary
				if kind == "response":
					var prompt: Dictionary = env.round._awaiting_response
					decision = actors[seat].decide_response(env.round, seat,
						int(prompt.get("disc_seat", -1)), str(prompt.get("tile", "")),
						allowed.get("options", {}))
				else:
					decision = actors[seat].decide_turn(env.round, seat)
				code = _decision_code(decision, kind, actions)
			if code < 0: code = int(actions[0].code)
			var result: Dictionary = env.step_state(env.observation(seat), code)
			if not bool(result.get("ok", false)): break
		if env.is_done():
			games += 1
			var scores: Array = env.score_deltas()
			var value := float(scores[focus]) if focus < scores.size() else 0.0
			score += value
			if value > 0.0: wins += 1
	print(JSON.stringify({"games": games, "focus_score": score, "wins": wins}))
	quit(0)
