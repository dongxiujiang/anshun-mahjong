extends RefCounted
## 策略 + 启发兜底：模型只有在合法动作上的最高置信度足够高时才接管，
## 否则退回中档启发 AI，避免弱策略把整局拖垮。

const SL := preload("res://rl_env/SlPolicyActor.gd")
const AI := preload("res://scripts/ai/AiPlayer.gd")
const OBS := preload("res://rl_env/ObservationCodec.gd")

var policy
var fallback
var confidence := 0.45
var feature_version := 2
var last_value := 0.0
var last_policy_code := -1
var last_fallback_code := -1

func _init(policy_path: String, threshold: float = 0.45, version: int = 2) -> void:
	policy = SL.new(policy_path, version)
	confidence = threshold
	feature_version = version
	fallback = AI.new("BlendFallback", "low")
	fallback.use_mcts = false
	fallback.rng.seed = 20261101

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
	var add: Array = decision.get("add_kong", [])
	if not add.is_empty():
		for action in actions:
			if str(action.kind) == "add_kong" and str(action.tile) == str(add[0]): return int(action.code)
		return -1
	var tile := str(decision.get("discard", ""))
	var kind_wanted := "ready_discard" if bool(decision.get("ready", false)) else "discard"
	for action in actions:
		if str(action.kind) == kind_wanted and str(action.tile) == tile: return int(action.code)
	for action in actions:
		if str(action.kind) == "discard" and str(action.tile) == tile: return int(action.code)
	return -1

func _heuristic_code(env, seat: int) -> int:
	var kind: String = env.current_kind()
	var actions: Array = env.legal_actions(seat)
	var allowed: Dictionary = env.round.allowed_actions(seat)
	var decision: Dictionary
	if kind == "response":
		var prompt: Dictionary = env.round._awaiting_response
		decision = fallback.decide_response(env.round, seat, int(prompt.get("disc_seat", -1)),
			str(prompt.get("tile", "")), allowed.get("options", {}))
	else:
		decision = fallback.decide_turn(env.round, seat)
	return _decision_code(decision, kind, actions)

func choose_policy(env, seat: int) -> Dictionary:
	var legal: Array = env.legal_actions(seat)
	if legal.is_empty():
		return {}
	# 响应窗口优先使用规则的胡/碰/杠/过，策略只接管出牌。
	if env.current_kind() == "response":
		var response_code := _heuristic_code(env, seat)
		for action in legal:
			if int(action.code) == response_code:
				return action
		return legal[0]
	var info: Dictionary = policy.policy_for(env, seat)
	var probs: Array = info.get("probs", [])
	var policy_code := -1
	var best_prob := 0.0
	if probs.size() == legal.size():
		for i in legal.size():
			if float(probs[i]) > best_prob:
				best_prob = float(probs[i])
				policy_code = int(legal[i].code)
	last_policy_code = policy_code
	var fallback_code := _heuristic_code(env, seat)
	last_fallback_code = fallback_code
	var chosen := fallback_code
	if policy_code >= 0 and fallback_code >= 0 and best_prob >= confidence:
		chosen = policy_code
	if chosen < 0:
		chosen = policy_code if policy_code >= 0 else int(legal[0].code)
	for action in legal:
		if int(action.code) == chosen:
			return action
	return legal[0]
