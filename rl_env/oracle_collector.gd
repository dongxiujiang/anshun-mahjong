extends SceneTree
## Oracle 行为克隆数据生成：
## - 对局演化完全由中档启发 AI 驱动；
## - Oracle 仅对标签采样座位的可见状态给出推荐，不执行动作；
## - 输出 JSONL，后续由 Python 转 parquet。

const ENV := preload("res://rl_env/RlEnv.gd")
const OBS := preload("res://rl_env/ObservationCodec.gd")
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
			if int(action.get("code", -1)) == wanted:
				return wanted
		return -1
	if bool(decision.get("self_win", false)):
		for action in actions:
			if int(action.get("code", -1)) == 108:
				return 108
		return -1
	var dark: Array = decision.get("kong_declares", [])
	if not dark.is_empty():
		for action in actions:
			if str(action.get("kind", "")) == "kong" and str(action.get("tile", "")) == str(dark[0]):
				return int(action.code)
		return -1
	var added: Array = decision.get("add_kong", [])
	if not added.is_empty():
		for action in actions:
			if str(action.get("kind", "")) == "add_kong" and str(action.get("tile", "")) == str(added[0]):
				return int(action.code)
		return -1
	var tile := str(decision.get("discard", ""))
	var wanted_kind := "ready_discard" if bool(decision.get("ready", false)) else "discard"
	for action in actions:
		if str(action.get("kind", "")) == wanted_kind and str(action.get("tile", "")) == tile:
			return int(action.code)
	for action in actions:
		if str(action.get("kind", "")) == "discard" and str(action.get("tile", "")) == tile:
			return int(action.code)
	return -1

func _run() -> void:
	var start := int(_arg("start", "0"))
	var count := int(_arg("count", "1"))
	var level := _arg("level", "medium")
	var rollout_limit := int(_arg("rollout-limit", "80"))
	var min_steps := int(_arg("min-steps", "20"))
	var output := _arg("out", "user://oracle.jsonl")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + output)
		quit(2)
		return
	var games := 0
	var rows := 0
	var failed := 0
	for seed in range(start, start + count):
		print("[oracle] game seed=", seed)
		var env = ENV.new()
		env.reset(seed)
		var oracle_seat: int = int(abs(seed)) % 4
		var actors: Array = []
		var styles := ["balanced", "conservative", "aggressive"]
		for seat in 4:
			var actor = AI.new("OracleHeuristic%d" % seat, level)
			actor.rng.seed = seed * 17 + seat + 1
			match styles[(seed + seat) % styles.size()]:
				"conservative":
					actor.set_defense_weight(1.0)
					actor.set_risk_aversion(1.4)
					actor.candidate_slack = 1
				"aggressive":
					actor.set_defense_weight(0.1)
					actor.set_risk_aversion(0.65)
					actor.candidate_slack = 0
				_:
					actor.set_defense_weight(0.55)
					actor.set_risk_aversion(1.0)
			actors.append(actor)
		var game_rows: Array = []
		var steps := 0
		var oracle_samples := 0
		while steps < 2000 and not env.is_done():
			steps += 1
			var actor_seat := env.current_actor()
			if actor_seat < 0:
				failed += 1
				break
			var kind := env.current_kind()
			var actions: Array = env.legal_actions(actor_seat)
			if actions.is_empty():
				failed += 1
				break
			var visible: Dictionary = env.observation(actor_seat)
			if actor_seat == oracle_seat:
				var advice: Dictionary = env.oracle_advise(visible, rollout_limit)
				if int(advice.get("best", -1)) >= 0:
					var row := {
						"x": OBS.encode(visible),
						"mask": Array(env.action_mask(actor_seat)),
						"action": int(advice.best),
						"probs": advice.probs,
						"seat": actor_seat,
						"kind": kind,
						"step": steps,
						"game": seed,
						"oracle_seat": oracle_seat,
					}
					game_rows.append(row)
					oracle_samples += 1
			var decision: Dictionary
			if kind == "response":
				var prompt: Dictionary = env.round._awaiting_response
				decision = actors[actor_seat].decide_response(env.round, actor_seat,
					int(prompt.get("disc_seat", -1)), str(prompt.get("tile", "")),
					env.round.legal_response_options(actor_seat, int(prompt.get("disc_seat", -1)),
						str(prompt.get("tile", "")), int(prompt.get("stage", 0))))
			else:
				decision = actors[actor_seat].decide_turn(env.round, actor_seat)
			var code := _decision_code(decision, kind, actions)
			if code < 0:
				code = int(actions[0].code)
			var result: Dictionary = env.step(code)
			if not bool(result.get("ok", false)):
				failed += 1
				break
		if not env.is_done():
			failed += 1
			continue
		if steps < min_steps or oracle_samples == 0:
			continue
		var scores: Array = env.score_deltas()
		var value := float(scores[oracle_seat]) / 100.0
		var has_kong := false
		for p in env.round.players:
			for meld in p.melds:
				if str(meld.get("kind", "")) in ["kong", "add_kong"]:
					has_kong = true
		var has_charge := not (env.round.round_meta.get("charge_chickens", {}) as Dictionary).is_empty()
		for row in game_rows:
			row["value"] = value
			row["steps"] = steps
			row["has_chicken"] = has_charge
			row["has_kong"] = has_kong
			row["has_charge_chicken"] = has_charge
			file.store_line(JSON.stringify(row))
			rows += 1
		games += 1
	file.close()
	print("[oracle] games=", games, " rows=", rows, " failed=", failed, " out=", output)
	quit(0)
