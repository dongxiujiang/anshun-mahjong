extends RefCounted
## 只在启发 AI 的候选出牌集合内使用策略重排，避免弱策略选中低质量牌。

const SL := preload("res://rl_env/SlPolicyActor.gd")
const AI := preload("res://scripts/ai/AiPlayer.gd")

var policy
var fallback
var feature_version := 2
var fallback_decision: Dictionary = {}
var last_policy_code := -1
var last_fallback_code := -1

func _init(policy_path: String, version: int = 2) -> void:
	policy = SL.new(policy_path, version)
	feature_version = version
	fallback = AI.new("RerankFallback", "low")
	fallback.use_mcts = false
	fallback.rng.seed = 20261101

func _code_for_tile(actions: Array, tile: String, ready: bool) -> int:
	var wanted := "ready_discard" if ready else "discard"
	for action in actions:
		if str(action.kind) == wanted and str(action.tile) == tile:
			return int(action.code)
	for action in actions:
		if str(action.kind) == "discard" and str(action.tile) == tile:
			return int(action.code)
	return -1

func choose_policy(env, seat: int) -> Dictionary:
	var legal: Array = env.legal_actions(seat)
	if legal.is_empty():
		return {}
	if env.current_kind() == "response":
		var allowed: Dictionary = env.round.allowed_actions(seat)
		var prompt: Dictionary = env.round._awaiting_response
		var decision: Dictionary = fallback.decide_response(env.round, seat,
			int(prompt.get("disc_seat", -1)), str(prompt.get("tile", "")),
			allowed.get("options", {}))
		var wanted: int = int({"win": 111, "pong": 109, "kong": 110, "pass": 112}.get(
			str(decision.get("action", "pass")), 112))
		for action in legal:
			if int(action.code) == wanted:
				return action
		return legal[0]
	var info: Dictionary = policy.policy_for(env, seat)
	var probs: Array = info.get("probs", [])
	if probs.size() != legal.size():
		return fallback_action(env, seat, legal)
	fallback_decision = fallback.decide_turn(env.round, seat)
	last_fallback_code = -1
	var candidates: Array = []
	if not fallback_decision.get("discard", "").is_empty():
		var tile := str(fallback_decision.get("discard", ""))
		var ready := bool(fallback_decision.get("ready", false))
		var fallback_code := _code_for_tile(legal, tile, ready)
		last_fallback_code = fallback_code
		for action in legal:
			if int(action.code) == fallback_code:
				candidates.append(action)
				break
	for candidate in fallback.last_analysis:
		var tile := str(candidate.get("tile", ""))
		if tile == "": continue
		var code := _code_for_tile(legal, tile, bool(candidate.get("declare_ready", false)))
		if code < 0: continue
		if candidates.any(func(a): return int(a.code) == code): continue
		for action in legal:
			if int(action.code) == code:
				candidates.append(action)
				break
	if candidates.is_empty():
		return fallback_action(env, seat, legal)
	var chosen: Dictionary = candidates[0]
	var best_prob := -INF
	for action in candidates:
		var index := -1
		for i in legal.size():
			if int(legal[i].code) == int(action.code):
				index = i
				break
		if index >= 0 and float(probs[index]) > best_prob:
			best_prob = float(probs[index])
			chosen = action
	last_policy_code = int(chosen.code)
	return chosen

func fallback_action(env, seat: int, legal: Array) -> Dictionary:
	var decision: Dictionary = fallback.decide_turn(env.round, seat)
	var tile := str(decision.get("discard", ""))
	var code := _code_for_tile(legal, tile, bool(decision.get("ready", false)))
	for action in legal:
		if int(action.code) == code:
			return action
	return legal[0]
