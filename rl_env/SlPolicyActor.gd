extends RefCounted
## 阶段1 SL 策略的离线推理器。只消费 RlEnv 的公开 observation。

const OBS := preload("res://rl_env/ObservationCodec.gd")
const WEIGHTS_PATH := "res://rl_env/sl_balanced_weights.json"
static var _cache: Dictionary = {}
var _weights: Dictionary = {}
var _loaded_path := ""
var weights_path := WEIGHTS_PATH
var last_value := 0.0

func _init(path: String = "") -> void:
	if path != "":
		weights_path = path
	if _weights.is_empty() or _loaded_path != weights_path:
		if _cache.has(weights_path):
			_weights = _cache[weights_path]
		else:
			_weights = _load()
			_cache[weights_path] = _weights
		_loaded_path = weights_path

func _load() -> Dictionary:
	var f := FileAccess.open(weights_path, FileAccess.READ)
	if f == null: return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary: return {}
	var out := {}
	for key in parsed:
		if key.ends_with("weight"):
			var mat: Array = []
			for row in parsed[key]: mat.append(PackedFloat32Array(row))
			out[key] = mat
		else:
			out[key] = PackedFloat32Array(parsed[key])
	return out

func _forward(x: PackedFloat32Array) -> Array:
	if _weights.is_empty() or not _weights.has("policy.weight") or not _weights.has("value.weight"):
		return []
	var w1: Array = _weights["trunk.0.weight"]
	var b1: PackedFloat32Array = _weights["trunk.0.bias"]
	var h1 := PackedFloat32Array(); h1.resize(w1.size())
	for row in w1.size():
		var s := b1[row]
		var w: PackedFloat32Array = w1[row]
		for c in x.size(): s += w[c] * x[c]
		h1[row] = maxf(0.0, s)
	var w2: Array = _weights["trunk.2.weight"]
	var b2: PackedFloat32Array = _weights["trunk.2.bias"]
	var h2 := PackedFloat32Array(); h2.resize(w2.size())
	for row in w2.size():
		var s := b2[row]
		var w: PackedFloat32Array = w2[row]
		for c in h1.size(): s += w[c] * h1[c]
		h2[row] = maxf(0.0, s)
	var w3: Array = _weights["policy.weight"]
	var b3: PackedFloat32Array = _weights["policy.bias"]
	var policy := PackedFloat32Array(); policy.resize(w3.size())
	for row in w3.size():
		var s := b3[row]
		var w: PackedFloat32Array = w3[row]
		for c in h2.size(): s += w[c] * h2[c]
		policy[row] = s
	var vw: Array = _weights["value.weight"]
	var vb: PackedFloat32Array = _weights["value.bias"]
	var value := vb[0]
	for c in h2.size(): value += vw[0][c] * h2[c]
	return [policy, value]

func policy_for(env, seat: int) -> Dictionary:
	var legal: Array = env.legal_actions(seat)
	if legal.is_empty():
		return {}
	var result := _forward(PackedFloat32Array(OBS.encode(env.observation(seat))))
	if result.is_empty():
		return {"actions": legal, "probs": [], "value": 0.0}
	var logits: PackedFloat32Array = result[0]
	last_value = float(result[1])
	var best := -INF
	for action in legal:
		best = maxf(best, logits[int(action.code)])
	var probs: Array = []
	var total := 0.0
	for action in legal:
		var value := exp(float(logits[int(action.code)]) - best)
		probs.append(value)
		total += value
	for i in probs.size():
		probs[i] = float(probs[i]) / maxf(total, 0.000001)
	return {"actions": legal, "probs": probs, "value": float(result[1])}

func sample_action(env, seat: int, rng: RandomNumberGenerator, epsilon: float = 0.0) -> Dictionary:
	var policy: Dictionary = policy_for(env, seat)
	var legal: Array = policy.get("actions", [])
	if legal.is_empty():
		return {}
	var chosen_index := 0
	var probs: Array = policy.get("probs", [])
	if probs.is_empty() or probs.size() != legal.size():
		probs = []
		for _i in legal.size():
			probs.append(1.0 / float(legal.size()))
	if rng.randf() < epsilon:
		chosen_index = rng.randi_range(0, legal.size() - 1)
	else:
		var roll := rng.randf()
		var cumulative := 0.0
		for i in legal.size():
			cumulative += float(probs[i])
			if roll <= cumulative:
				chosen_index = i
				break
	var action: Dictionary = legal[chosen_index]
	return {
		"action": action,
		"code": int(action.code),
		"logprob": log(float(probs[chosen_index]) if float(probs[chosen_index]) > 0.0 else 0.000001),
		"value": float(policy.get("value", 0.0)),
		"probs": probs,
	}

func choose(env, seat: int) -> Dictionary:
	var legal: Array = env.legal_actions(seat)
	if legal.is_empty(): return {}
	# 初始 SL 对响应动作保守处理：能胡就胡，否则过。
	# 碰/杠的细粒度时机留给后续 PPO 学习，避免低频动作过拟合。
	if env.current_kind() == "response":
		for action in legal:
			if int(action.code) == 111: return action
		for action in legal:
			if int(action.code) == 112: return action
		return legal[0]
	var x := PackedFloat32Array(OBS.encode(env.observation(seat)))
	var result := _forward(x)
	if result.is_empty(): return legal[0]
	var policy: PackedFloat32Array = result[0]
	last_value = float(result[1])
	var best: Dictionary = legal[0]
	var best_score := -INF
	for action in legal:
		var score := policy[int(action.code)]
		if score > best_score:
			best_score = score
			best = action
	return best


