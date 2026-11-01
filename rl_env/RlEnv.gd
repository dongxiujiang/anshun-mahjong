extends RefCounted
## 阶段0：RoundState 的同步封装。
## 所有规则判定、动作合法性、响应优先级和结算仍由原有 core 代码完成。
## 本类不包含任何麻将规则实现，也不把对手暗牌或牌墙放进 observation。

const ACTIONS := preload("res://rl_env/ActionCodec.gd")
const ROUND_STATE := preload("res://scripts/core/RoundState.gd")
const SHANTEN := preload("res://scripts/core/Shanten.gd")
const TILES := preload("res://scripts/core/Tiles.gd")
const WALL_RING := preload("res://scripts/core/WallRing.gd")

var round
var seed := 0
var _last_action: Dictionary = {}

func reset(new_seed: int = 0) -> void:
	seed = new_seed
	round = ROUND_STATE.new()
	round.build_players(0)
	round.opening_delay_seconds = 0.0
	round.ai_delay_seconds = 0.0
	round.ai_response_delay_seconds = 0.0
	round.controllers = [null, null, null, null]
	round.set_rng_seed(seed)
	round.start_round(0, seed % 6 + 1)
	_last_action = {}

func is_done() -> bool:
	return round.phase == ROUND_STATE.Phase.SETTLED

func current_actor() -> int:
	if round == null or round.phase != ROUND_STATE.Phase.PLAYING or not round.awaiting:
		return -1
	if not round._awaiting_response.is_empty():
		return int(round._awaiting_response.get("seat", -1))
	return int(round.current_turn)

func current_kind() -> String:
	if round == null or round.phase != ROUND_STATE.Phase.PLAYING or not round.awaiting:
		return "none"
	if not round._awaiting_response.is_empty():
		return "response"
	return "turn"

func _prompt() -> Dictionary:
	return round._awaiting_response.duplicate(true)

## 当前动作由 LegalActions.allowed_actions 生成；这里只编码，不自行判定。
func legal_actions(seat: int = -1) -> Array:
	if seat < 0: seat = current_actor()
	if seat < 0: return []
	var allowed: Dictionary = round.allowed_actions(seat)
	if allowed.is_empty(): return []
	var options: Dictionary = allowed.get("options", {})
	if str(allowed.get("kind", "")) == "response":
		return ACTIONS.response_actions(options)
	return ACTIONS.turn_actions(options)

func action_mask(seat: int = -1) -> PackedByteArray:
	return ACTIONS.mask(legal_actions(seat))

## Python/训练接口：传入可见状态和离散动作，返回下一可见状态、奖励和结束标记。
## state 参数只做一致性校验；对局推进仍由当前权威 round 完成。
func step_state(state_visible: Dictionary, action_code: int) -> Dictionary:
	if not state_visible.is_empty() and int(state_visible.get("actor", current_actor())) != current_actor():
		return {"ok": false, "error": "stale_visible_state"}
	var actor_before := current_actor()
	var before_shanten := 99
	if actor_before >= 0 and actor_before < round.players.size():
		var before_player: PlayerState = round.players[actor_before]
		before_shanten = SHANTEN.shanten(before_player.concealed, before_player.melds)
	var result := step(action_code)
	if not bool(result.get("ok", false)):
		return result
	var done := bool(result.get("done", false))
	var reward := 0.0
	if actor_before >= 0 and actor_before < round.players.size():
		var after_player: PlayerState = round.players[actor_before]
		var after_shanten := SHANTEN.shanten(after_player.concealed, after_player.melds)
		reward += float(before_shanten - after_shanten) * 0.1
	if done:
		var scores := score_deltas()
		if actor_before >= 0 and actor_before < scores.size():
			reward += float(scores[actor_before]) / 100.0
	result["state"] = result.get("observation", {})
	result["reward"] = reward
	return result

## Oracle 只读顾问：可访问当前 round 的隐藏牌，但绝不提交动作。
## 对每个合法动作做一次完整信息快速 rollout，按目标座位的最终得分排序。
func oracle_advise(state_visible: Dictionary, rollout_limit: int = 120) -> Dictionary:
	if round == null or is_done():
		return {"actions": [], "probs": {}, "best": -1}
	var seat := current_actor()
	if seat < 0:
		return {"actions": [], "probs": {}, "best": -1}
	if not state_visible.is_empty() and int(state_visible.get("actor", seat)) != seat:
		return {"actions": [], "probs": {}, "best": -1}
	var actions := legal_actions(seat)
	if actions.is_empty():
		return {"actions": [], "probs": {}, "best": -1}
	var scores: Array = []
	var codes: Array = []
	for action in actions:
		var code := int(action.get("code", -1))
		if code < 0:
			continue
		var clone = _clone_round()
		var decision := ACTIONS.decision_for(action)
		var accepted := false
		if current_kind() == "response":
			var prompt: Dictionary = round._awaiting_response
			accepted = clone.submit_response(seat, str(prompt.get("tile", "")), decision)
		else:
			accepted = clone.submit_turn(seat, decision)
		if not accepted:
			continue
		var delta := _oracle_value(clone, seat)
		codes.append(code)
		scores.append(delta)
	if codes.is_empty():
		return {"actions": [], "probs": {}, "best": -1}
	var best_index := 0
	for i in range(1, scores.size()):
		if float(scores[i]) > float(scores[best_index]):
			best_index = i
	var max_score := float(scores[best_index])
	var total := 0.0
	var weights: Array = []
	for value in scores:
		var weight := exp((float(value) - max_score) / 8.0)
		weights.append(weight)
		total += weight
	var probs: Dictionary = {}
	for i in codes.size():
		probs[int(codes[i])] = float(weights[i]) / maxf(total, 0.000001)
	var best_code := int(codes[best_index])
	var best_action: Dictionary = {}
	for action in actions:
		if int(action.get("code", -1)) == best_code:
			best_action = action
			break
	return {"actions": codes, "probs": probs, "best": best_code,
		"best_action": best_action, "scores": scores}

func _oracle_value(clone, target_seat: int) -> float:
	if clone.phase == ROUND_STATE.Phase.SETTLED:
		var deltas: Array = clone.last_result.get("deltas", [])
		return float(deltas[target_seat]) if target_seat < deltas.size() else 0.0
	var player: PlayerState = clone.players[target_seat]
	var known := {}
	for p in clone.players:
		for tile in p.concealed: known[str(tile)] = int(known.get(str(tile), 0)) + 1
		for meld in p.melds:
			for tile in meld.get("tiles", [meld.get("tile", "")]):
				if str(tile) != "": known[str(tile)] = int(known.get(str(tile), 0)) + 1
		for tile in p.discards: known[str(tile)] = int(known.get(str(tile), 0)) + 1
	var current := SHANTEN.shanten(player.concealed, player.melds)
	var ukeire := 0
	for tile in TILES.all_values():
		var remaining := 4 - int(known.get(str(tile), 0))
		if remaining <= 0: continue
		var candidate: Array = player.concealed.duplicate()
		candidate.append(str(tile))
		if SHANTEN.shanten(candidate, player.melds) < current:
			ukeire += remaining
	# 安全/速度不是唯一目标：完美信息下用向听和真实剩余进张数估值。
	return -float(current) * 100.0 + float(ukeire) * 2.0

func _clone_round():
	var clone = ROUND_STATE.new()
	clone.apply_sync(round.serialize())
	# apply_sync 是给联网客户端用的，默认丢弃隐藏牌墙；Oracle 必须复制完整牌墙。
	if round.wall != null:
		var wall = WALL_RING.new(round.wall._ring.duplicate(), clone.dealer_seat)
		wall._drawn = round.wall._drawn.duplicate()
		wall._head = round.wall._head
		wall._tail = round.wall._tail
		wall.remaining = round.wall.remaining
		wall._segments = round.wall._segments.duplicate(true)
		clone.wall = wall
	clone.opening_delay_seconds = 0.0
	clone.ai_delay_seconds = 0.0
	clone.ai_response_delay_seconds = 0.0
	return clone

func _rollout_value(clone, target_seat: int, limit: int) -> float:
	var actors: Array = []
	for index in 4:
		var ai = preload("res://scripts/ai/AiPlayer.gd").new("OracleRollout%d" % index, "high")
		ai.use_mcts = false
		ai.rng.seed = seed * 131 + index + 17
		actors.append(ai)
	var steps := 0
	while clone.phase != ROUND_STATE.Phase.SETTLED and steps < limit:
		steps += 1
		if not clone.awaiting:
			break
		var seat := int(clone.current_turn)
		var kind := "turn"
		if not clone._awaiting_response.is_empty():
			seat = int(clone._awaiting_response.get("seat", -1))
			kind = "response"
		if seat < 0 or seat > 3:
			break
		var actor = actors[seat]
		var accepted := false
		if kind == "response":
			var prompt: Dictionary = clone._awaiting_response
			var options: Dictionary = clone.legal_response_options(seat, int(prompt.get("disc_seat", -1)),
				str(prompt.get("tile", "")), int(prompt.get("stage", 0)))
			var decision: Dictionary = actor.decide_response(clone, seat, int(prompt.get("disc_seat", -1)),
				str(prompt.get("tile", "")), options)
			accepted = clone.submit_response(seat, str(prompt.get("tile", "")), decision)
		else:
			var decision: Dictionary = actor.decide_turn(clone, seat)
			accepted = clone.submit_turn(seat, decision)
		if not accepted:
			break
	if clone.last_result.is_empty():
		return 0.0
	var deltas: Array = clone.last_result.get("deltas", [])
	return float(deltas[target_seat]) if target_seat < deltas.size() else 0.0

func step(state_or_code, action_code: int = -1) -> Dictionary:
	var code: int
	var state_visible: Dictionary = {}
	if state_or_code is Dictionary:
		state_visible = state_or_code
		code = action_code
	else:
		code = int(state_or_code)
	var seat := current_actor()
	if not state_visible.is_empty() and int(state_visible.get("actor", seat)) != seat:
		return {"ok": false, "error": "stale_visible_state", "actor": seat}
	var kind := current_kind()
	var actions := legal_actions(seat)
	var action := ACTIONS.action_for_code(code, actions)
	if seat < 0 or action.is_empty():
		return {"ok": false, "error": "illegal_action", "actor": seat, "action_mask": ACTIONS.mask(actions)}
	var decision := ACTIONS.decision_for(action)
	var accepted := false
	if kind == "response":
		var prompt := _prompt()
		var tile := str(prompt.get("tile", ""))
		accepted = round.submit_response(seat, tile, decision)
	else:
		accepted = round.submit_turn(seat, decision)
	if not accepted:
		return {"ok": false, "error": "native_rejected", "actor": seat, "decision": decision}
	_last_action = {"code": code, "seat": seat, "kind": kind, "decision": decision}
	var done := is_done()
	return {"ok": true, "done": done, "actor": seat, "code": code,
		"observation": observation(-1 if done else current_actor()),
		"action_mask": action_mask(-1 if done else current_actor()),
		"info": {"actor": seat, "kind": kind, "decision": decision,
			"score": score_deltas() if done else []}}

## 仅返回行动者可见信息。对手暗牌和牌墙永远不在这里。
func observation(seat: int = -1) -> Dictionary:
	if seat < 0: seat = current_actor()
	if seat < 0: seat = 0
	var player: PlayerState = round.players[seat]
	var players: Array = []
	for p in round.players:
		var melds: Array = []
		for index in p.melds.size():
			var meld: Dictionary = p.melds[index]
			var public_meld := {"kind": str(meld.get("kind", "")), "tile": ""}
			if p.seat == seat or round.is_meld_revealed(p.seat, index):
				public_meld.tile = str(meld.get("tile", ""))
			else:
				public_meld.kind = "hidden_meld"
			melds.append(public_meld)
		players.append({"seat": p.seat, "discards": p.discards.duplicate(),
			"discard_history": p.discard_history.duplicate(), "melds": melds,
			"ready": p.ready, "score": p.score})
	var own_melds: Array = player.melds.duplicate(true)
	var legal := legal_actions(seat)
	var obs := {
		"seat": seat,
		"actor": current_actor(),
		"kind": current_kind(),
		"hand": player.concealed.duplicate(),
		"just_drew": player.just_drew,
		"own_melds": own_melds,
		"players": players,
		"wall_count": round._wall_count(),
		"dealer": round.dealer_seat,
		"scores": round.players.map(func(p): return p.score),
		"ready": round.players.map(func(p): return p.ready),
		"flip_tile": str(round.round_meta.get("flip_tile", "")),
		"charge_chickens": round.round_meta.get("charge_chickens", {}).duplicate(true),
		"chicken_multiplier": int(round.round_meta.get("chicken_multiplier", 1)),
		"last_discard": round.last_discard.duplicate(true),
		"legal_actions": legal.duplicate(true),
		"action_mask": ACTIONS.mask(legal),
	}
	if current_kind() == "response" and int(_prompt().get("seat", -1)) == seat:
		obs["response"] = {"tile": str(_prompt().get("tile", "")),
			"source": int(_prompt().get("disc_seat", -1)),
			"stage": int(_prompt().get("stage", round._response_stage))}
	return obs

func score_deltas() -> Array:
	if round == null or round.last_result.is_empty(): return []
	return round.last_result.get("deltas", [0.0, 0.0, 0.0, 0.0]).duplicate()

## 仅训练 Oracle 使用；绝不能被 observation/客户端日志引用。
func oracle_state() -> Dictionary:
	var wall := {"remaining": 0, "ring": [], "head": 0}
	if round.wall != null:
		wall = {"remaining": round.wall.remaining,
			"ring": round.wall._ring.duplicate(), "head": round.wall._head}
	return {"hands": round.players.map(func(p): return p.concealed.duplicate()),
		"wall": wall, "meta": round.round_meta.duplicate(true)}
