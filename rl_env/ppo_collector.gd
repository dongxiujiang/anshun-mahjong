extends SceneTree
## PPO/自博弈 rollout：一个策略座位使用当前 SL/PPO 权重，其余座位使用启发池。
## 记录策略座位的转移，Oracle 不在本阶段出现。

const ENV := preload("res://rl_env/RlEnv.gd")
const OBS := preload("res://rl_env/ObservationCodec.gd")
const SL := preload("res://rl_env/SlPolicyActor.gd")
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
	var epsilon := float(_arg("epsilon", "0.02"))
	var snapshots := _arg("snapshots", "")
	var snapshot_paths: Array = []
	for path in snapshots.split(",", false):
		if str(path).strip_edges() != "":
			snapshot_paths.append(str(path).strip_edges())
	var out := _arg("out", "user://ppo_rollout.jsonl")
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		push_error("cannot write " + out)
		quit(2)
		return
	var actor = SL.new(policy_path, 2) if policy_path != "" else SL.new("", 2)
	var games := 0
	var rows := 0
	for seed in range(start, start + count):
		var env = ENV.new()
		env.reset(seed)
		var policy_seat: int = int(abs(seed)) % 4
		var rng := RandomNumberGenerator.new()
		rng.seed = seed * 37 + 3
		var opponents: Array = []
		var snapshots_by_seat: Array = [null, null, null, null]
		for seat in 4:
			var ai = AI.new("PPOHeuristic%d" % seat, "medium")
			ai.use_mcts = false
			ai.rng.seed = seed * 19 + seat + 5
			if seat % 3 == 0:
				ai.set_defense_weight(1.0)
				ai.set_risk_aversion(1.3)
			elif seat % 3 == 1:
				ai.set_defense_weight(0.12)
				ai.set_risk_aversion(0.7)
			opponents.append(ai)
			if seat != policy_seat and not snapshot_paths.is_empty() and rng.randf() < 0.35:
				var snapshot_path: String = str(snapshot_paths[rng.randi_range(0, snapshot_paths.size() - 1)])
				snapshots_by_seat[seat] = SL.new(snapshot_path, 2)
		var done := false
		var steps := 0
		var game_rows: Array = []
		var policy_done_rewarded := false
		while steps < 2000 and not env.is_done():
			steps += 1
			var seat := env.current_actor()
			if seat < 0:
				break
			var actions: Array = env.legal_actions(seat)
			if actions.is_empty():
				break
			var visible: Dictionary = env.observation(seat)
			var mask_before: Array = Array(env.action_mask(seat))
			var code := -1
			var logprob := 0.0
			var value := 0.0
			if seat == policy_seat:
				var sampled: Dictionary = actor.sample_action(env, seat, rng, epsilon)
				code = int(sampled.get("code", -1))
				logprob = float(sampled.get("logprob", 0.0))
				value = float(sampled.get("value", 0.0))
			else:
				var snapshot = snapshots_by_seat[seat]
				if snapshot != null:
					var chosen: Dictionary = snapshot.choose(env, seat)
					code = int(chosen.get("code", -1))
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
			var result: Dictionary = env.step_state(visible, code)
			done = bool(result.get("done", false))
			if seat == policy_seat:
				game_rows.append({
					"x": OBS.encode_v2(visible),
					"feature_version": 2,
					"mask": mask_before,
					"action": code,
					"logprob": logprob,
					"value": value,
					"reward": float(result.get("reward", 0.0)),
					"done": done,
					"game": seed,
					"seat": seat,
					"step": steps,
				})
				if done:
					policy_done_rewarded = true
			if not bool(result.get("ok", false)):
				break
		if done and not game_rows.is_empty() and not policy_done_rewarded:
			# 对手结束对局时，策略座位没有机会再走一步；把终局分差加到
			# 它最后一次转移，保证稀疏奖励不会丢失。
			var scores: Array = env.score_deltas()
			var terminal := float(scores[policy_seat]) / 100.0 if policy_seat < scores.size() else 0.0
			game_rows[-1]["reward"] = float(game_rows[-1]["reward"]) + terminal
			game_rows[-1]["done"] = true
		for row in game_rows:
			file.store_line(JSON.stringify(row))
		rows += game_rows.size()
		if done:
			games += 1
	file.close()
	print("[ppo] games=", games, " rows=", rows, " out=", out)
	quit(0)
