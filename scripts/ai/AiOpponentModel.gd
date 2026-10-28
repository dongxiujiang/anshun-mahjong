extends RefCounted
## A bounded, deterministic information-set sampler. Samples are legal tenpai
## shapes constrained by our hand, exposed sets and retained discards. They are
## weighted hypotheses, not knowledge of the opponents' actual concealed tiles.
const VALUE := preload("res://scripts/ai/AiValueModel.gd")
const SAMPLE_LIMIT := 16
const ATTEMPT_LIMIT := 64
var _cache_key := ""
var _cached: Dictionary = {}
## 用 122,024 个实际听牌牌张样本拟合的 tile-wait 概率模型。
## 中档才启用；低档保留原采样模型作为基准。
var use_wait_model := false
const WAIT_COEF := [-1.5608709598575967, -0.29432841734207355, -0.09013543417140887,
	0.17222128069077575, 0.06924954497829443, 0.24408553137002884, 0.1622245797505184,
	0.1460945371717493, -0.040633131730585845, -0.28963032277408407, -0.35366729794925533,
	-0.1217766799846469, -0.005317639848025524, -0.0318566258488055, 0.08939840600149647,
	0.061330934718206484, 0.017661279624237056, -0.2160458263462794, -0.24329945325833421,
	-0.16187381061608838, -0.18813387743675278, 0.16958314910708425, 0.06537384161541401,
	0.021894335991348105, 0.015206004034571069, -0.1518219245862006, -0.1439680123402951,
	-0.4627059306784862, -1.251137203243958, -1.6460851752995038, -0.34547680890281035,
	0.05945829181655969, -1.0264914647786088]

func set_wait_model(value: bool) -> void:
	use_wait_model = value
	_cache_key = ""
	_cached = {}

func _model_wait_base(spec: Dictionary, wall: int) -> float:
	return WAIT_COEF[0] + WAIT_COEF[30] * float(spec.history.size()) / 20.0 \
		+ WAIT_COEF[31] * float(spec.melds.size()) / 4.0 \
		+ WAIT_COEF[32] * float(wall) / 55.0

func _model_wait(spec: Dictionary, tile: String, visible: int, base: float, opp_discards: int) -> float:
	var index := Tiles.value_index(tile)
	var logit: float = base + WAIT_COEF[1 + index] \
		+ WAIT_COEF[28] * float(visible) / 4.0 \
		+ WAIT_COEF[29] * float(opp_discards) / 4.0
	return clampf(1.0 / (1.0 + exp(-logit)), 0.002, 0.65)

func observe(round, seat: int, seen: Dictionary) -> Dictionary:
	var specs: Array = []
	for player in round.players:
		if player.seat == seat: continue
		var melds: Array = []
		for index in player.melds.size():
			var meld: Dictionary = player.melds[index].duplicate()
			if not round.is_meld_revealed(player.seat, index): meld.tile = "hidden0"
			melds.append(meld)
		specs.append({"seat": player.seat, "ready": player.ready, "melds": melds,
			"history": player.discard_history.duplicate(), "discards": player.discards.duplicate(),
			"discard_ids": player.discard_ids.duplicate(), "count": player.discard_count})
	var key := str([Tiles.counts_array(seen), specs, round.round_meta.get("chicken_multiplier", 1), round.round_meta.get("charge_chickens", {}), round.round_meta.get("burn_chicken_seat", -1)])
	if key == _cache_key: return _cached
	var random := RandomNumberGenerator.new()
	random.seed = absi(key.hash())
	var flips := VALUE.flip_distribution(seen)
	var pool: Array[int] = []
	for tile in Tiles.all_values(): pool.append(maxi(0, 4 - int(seen.get(tile, 0))))
	var profiles: Array = []
	for spec in specs: profiles.append(_infer(round, spec, pool, flips, random))
	_cache_key = key
	_cached = {"opponents": profiles, "flips": flips, "multiplier": clampi(int(round.round_meta.get("chicken_multiplier", 1)), 1, VALUE.CFG.MAX_CHICKEN_MULTIPLIER), "unknown": pool.reduce(func(a, b): return a + b, 0)}
	return _cached

func _infer(round, spec: Dictionary, pool: Array[int], flips: Dictionary, random: RandomNumberGenerator) -> Dictionary:
	var tenpai := 1.0 if spec.ready or spec.melds.size() == 4 else clampf(0.025 + 0.026 * spec.count + 0.11 * spec.melds.size(), 0.025, 0.85)
	var result := {"seat": spec.seat, "ready": spec.ready, "melds": spec.melds,
		"tenpai_probability": tenpai, "waits": {}, "special_waits": {}, "costs": {}, "special_costs": {}, "uncalled_costs": {}, "special_uncalled_costs": {},
		"chickens": 0.0, "discarded": 0.0, "kong_chickens": 0.0, "draw_discarded": 0.0, "draw_kong_chickens": 0.0, "samples": 0, "sample_hands": []}
	var weights := _tile_weights(spec)
	var sum_weight := 0.0
	var hits := {}
	var special_hits := {}
	var costs := {}
	var special_costs := {}
	var uncalled_costs := {}
	var special_uncalled_costs := {}
	var sample_chickens := 0.0
	var sample_draw_kongs := 0.0
	var sample_kongs := 0.0
	# Early closed hands use broad priors. Sampling begins with public threat evidence.
	if spec.ready or spec.melds.size() >= 2 or spec.count >= 7:
		for _attempt in ATTEMPT_LIMIT:
			if int(result.samples) >= SAMPLE_LIMIT: break
			var sample := _sample(spec, pool, weights, random)
			if sample.is_empty(): continue
			var hand: Array = sample.hand
			var melds: Array = sample.melds
			var weight := _likelihood(hand, spec)
			var profile := VALUE.profile(round, int(spec.seat), hand, melds, flips)
			var draw_profile := VALUE.profile(round, int(spec.seat), hand, melds, {})
			result.samples += 1
			result.sample_hands.append(sample)
			sum_weight += weight
			sample_chickens += weight * float(profile.total)
			sample_draw_kongs += weight * float(draw_profile.kong_chickens)
			sample_kongs += weight * float(profile.kong_chickens)
			for tile in Tiles.all_values():
				var full := hand.duplicate()
				full.append(tile)
				var pattern := RuleEngine.analyze(full, melds, tile)
				if not pattern.win: continue
				var full_profile := VALUE.profile(round, int(spec.seat), full, melds, flips)
				var pattern_fee := VALUE.pattern_points(pattern)
				# 点炮基础费按放炮者叫牌状态区分；牌型分另行叠加。
				var primary_fee := _discard_win_primary_fee(pattern_fee, bool(spec.ready))
				var cost: float = primary_fee + float(full_profile.total)
				cost += VALUE.kong_base(melds, -1) # Source-specific bases are added by risk().
				var uncalled_cost: float = cost - float(full_profile.total) + float(full_profile.discarded) + float(full_profile.kong_chickens)
				hits[tile] = float(hits.get(tile, 0.0)) + weight
				costs[tile] = float(costs.get(tile, 0.0)) + weight * cost
				uncalled_costs[tile] = float(uncalled_costs.get(tile, 0.0)) + weight * uncalled_cost
				if VALUE.allows_ron(pattern, melds, bool(spec.ready)):
					special_hits[tile] = float(special_hits.get(tile, 0.0)) + weight
					special_costs[tile] = float(special_costs.get(tile, 0.0)) + weight * cost
					special_uncalled_costs[tile] = float(special_uncalled_costs.get(tile, 0.0)) + weight * uncalled_cost
	var known_hand: Array = []
	var visible_melds: Array = []
	for meld in spec.melds:
		if meld.tile != "hidden0": visible_melds.append(meld)
	var known := VALUE.profile(round, int(spec.seat), known_hand, visible_melds, flips)
	var known_draw := VALUE.profile(round, int(spec.seat), known_hand, visible_melds, {})
	result.draw_discarded = known_draw.discarded
	result.discarded = known.discarded
	result.kong_chickens = sample_kongs / sum_weight if sum_weight > 0 else known.kong_chickens
	result.draw_kong_chickens = sample_draw_kongs / sum_weight if sum_weight > 0 else known_draw.kong_chickens
	var unknown_total: int = pool.reduce(func(a, b): return a + b, 0)
	var expected_hidden := 0.0
	for tile in Tiles.all_values():
		expected_hidden += (13 - 3 * spec.melds.size()) * pool[Tiles.value_index(tile)] / float(maxi(1, unknown_total)) * VALUE.tile_value(tile, flips, 1)
	result.chickens = sample_chickens / sum_weight if sum_weight > 0 else float(known.total) + expected_hidden
	for tile in Tiles.all_values():
		var index := Tiles.value_index(tile)
		var prior := _prior(spec, tile, pool, weights)
		# Shrink sparse samples toward a nonzero prior. No-furiten rules make
		# previously discarded tiles possible waits, even after a ready declaration.
		var mass := float(hits.get(tile, 0.0))
		var special_mass := float(special_hits.get(tile, 0.0))
		var special_fraction := 1.0 if spec.ready or VALUE.has_self_kong(spec.melds) else (0.65 if spec.melds.size() >= 2 else 0.20)
		var smoothing := 10.0
		result.waits[tile] = clampf((mass + smoothing * prior) / (sum_weight + smoothing), 0.0, 0.65)
		result.special_waits[tile] = minf(float(result.waits[tile]), (special_mass + smoothing * prior * special_fraction) / (sum_weight + smoothing))
		var fallback: float = float(result.chickens) + 10.0 + (VALUE.CFG.SCORE_READY if spec.ready else 0.0)
		result.costs[tile] = (float(costs.get(tile, 0.0)) + smoothing * prior * fallback) / maxf(0.0001, mass + smoothing * prior)
		result.special_costs[tile] = (float(special_costs.get(tile, 0.0)) + smoothing * prior * special_fraction * (fallback + 14.0)) / maxf(0.0001, special_mass + smoothing * prior * special_fraction)
		var uncalled_fallback: float = fallback - float(result.chickens) + float(result.discarded) + float(result.kong_chickens)
		result.uncalled_costs[tile] = (float(uncalled_costs.get(tile, 0.0)) + smoothing * prior * uncalled_fallback) / maxf(0.0001, mass + smoothing * prior)
		result.special_uncalled_costs[tile] = (float(special_uncalled_costs.get(tile, 0.0)) + smoothing * prior * special_fraction * (uncalled_fallback + 14.0)) / maxf(0.0001, special_mass + smoothing * prior * special_fraction)
		# No physical completion exists if all copies of every possible partner
		# have been seen. Owning all four copies alone does NOT make a sequence safe.
		if not _can_wait(index, pool, spec.melds.size(), spec.melds):
			result.waits[tile] = 0.0
			result.special_waits[tile] = 0.0
	# The per-tile likelihoods are not yet a probability mass. Normalize each
	# family so a multi-sided wait cannot sum above 1 and inflate risk.
	var wait_total := 0.0
	var special_total := 0.0
	for tile in Tiles.all_values():
		wait_total += float(result.waits.get(tile, 0.0))
		special_total += float(result.special_waits.get(tile, 0.0))
	if wait_total > 1.0:
		for tile in Tiles.all_values(): result.waits[tile] = float(result.waits[tile]) / wait_total
	if special_total > 1.0:
		for tile in Tiles.all_values(): result.special_waits[tile] = float(result.special_waits[tile]) / special_total
	if use_wait_model:
		var model_total := 0.0
		var wall: int = round._wall_count()
		var base := _model_wait_base(spec, wall)
		var opp_discards := {}
		for discarded in spec.discards:
			opp_discards[discarded] = int(opp_discards.get(discarded, 0)) + 1
		for tile in Tiles.all_values():
			var index := Tiles.value_index(tile)
			result.waits[tile] = _model_wait(spec, tile, 4 - int(pool[index]), base, int(opp_discards.get(tile, 0)))
			result.special_waits[tile] = result.waits[tile]
			model_total += float(result.waits[tile])
		if model_total > 1.0:
			for tile in Tiles.all_values():
				result.waits[tile] = float(result.waits[tile]) / model_total
				result.special_waits[tile] = float(result.waits[tile])
	return result

func risk(context: Dictionary, tile: String, source_ready: bool = false, after_self_kong: bool = false, rob_kong: bool = false, source: int = -1, own_chickens: float = 0.0, own_called: bool = false) -> Dictionary:
	var probability := 0.0
	var expected_loss := 0.0
	var opponents: Array = context.opponents.duplicate()
	if source >= 0:
		opponents.sort_custom(func(a, b): return posmod(int(a.seat) - source, 4) < posmod(int(b.seat) - source, 4))
	for opponent in opponents:
		var unrestricted := source_ready or after_self_kong or rob_kong
		var waits: Dictionary = opponent.waits if unrestricted else opponent.special_waits
		var costs: Dictionary = opponent.costs if unrestricted else opponent.special_costs
		if not own_called: costs = opponent.uncalled_costs if unrestricted else opponent.special_uncalled_costs
		var p := float(opponent.tenpai_probability) * float(waits.get(tile, 0.0))
		var payment := float(costs.get(tile, 0.0)) + VALUE.kong_base(opponent.melds, source) - VALUE.kong_base(opponent.melds, -1)
		if not rob_kong: payment -= own_chickens
		# 一张弃牌可被多家同胡，分别累加每位胡牌者的预期损失。
		expected_loss += p * maxf(0.0, payment)
		probability = 1.0 - (1.0 - probability) * (1.0 - p)
	return {"probability": probability, "loss": expected_loss * int(context.get("multiplier", 1))}

static func _discard_win_primary_fee(pattern_fee: float, declared_ready: bool, source_called: bool = false) -> float:
	# 估算放炮者对该赢家的付款：普通弃牌不收17/21，报听额外24。
	var ready_fee: float = (VALUE.CFG.SCORE_READY_PATTERN if pattern_fee > 0.0 else VALUE.CFG.SCORE_READY) if declared_ready else 0.0
	return pattern_fee + ready_fee

func _tile_weights(spec: Dictionary) -> Array[float]:
	var weights: Array[float] = []
	var suit_sets := {}
	for meld in spec.melds:
		if meld.tile != "hidden0": suit_sets[Tiles.suit(meld.tile)] = int(suit_sets.get(Tiles.suit(meld.tile), 0)) + 1
	for tile in Tiles.all_values():
		var value := 1.0
		if spec.history.has(tile): value *= 0.62
		if Tiles.rank(tile) in [1, 9]: value *= 0.85
		if suit_sets.size() == 1 and int(suit_sets.values()[0]) >= 2:
			value *= 2.8 if Tiles.suit(tile) == str(suit_sets.keys()[0]) else 0.55
		var recent: Array = spec.history.slice(maxi(0, spec.history.size() - 4))
		for discarded in recent:
			if Tiles.suit(discarded) == Tiles.suit(tile) and absi(Tiles.rank(discarded) - Tiles.rank(tile)) in [1, 2]: value *= 1.08
		weights.append(value)
	return weights

func _prior(spec: Dictionary, tile: String, pool: Array[int], weights: Array[float]) -> float:
	var index := Tiles.value_index(tile)
	var partners := 0.0
	for offset in [-2, -1, 1, 2]:
		if index / 9 == (index + offset) / 9 and index + offset >= 0 and index + offset < 27:
			partners += float(pool[index + offset]) / 4.0
	return clampf(0.045 * weights[index] * (0.45 + 0.13 * pool[index] + 0.14 * partners), 0.002, 0.18)

func _can_wait(index: int, pool: Array[int], meld_count: int, own_melds: Array = []) -> bool:
	for meld in own_melds:
		if meld.tile == "hidden0" or Tiles.value_index(meld.tile) != index: continue
		if meld.kind != "pung" or meld_count == 4: return false
	if pool[index] >= 1: return true # Pair / seven-pairs / triplet waits.
	if meld_count >= 4: return false
	for start in range(maxi(index - 2, index / 9 * 9), mini(index, index / 9 * 9 + 6) + 1):
		var possible := true
		for member in range(start, start + 3):
			if member != index and pool[member] < 1: possible = false
		if possible: return true
	return false

func _sample(spec: Dictionary, pool: Array[int], weights: Array[float], random: RandomNumberGenerator) -> Dictionary:
	var remaining := pool.duplicate()
	var melds: Array = spec.melds.duplicate(true)
	var suits := {}
	for meld in melds:
		if meld.tile != "hidden0": suits[Tiles.suit(meld.tile)] = int(suits.get(Tiles.suit(meld.tile), 0)) + 1
	if suits.size() == 1 and int(suits.values()[0]) >= 2 and random.randf() < 0.65:
		weights = weights.duplicate()
		for index in 27:
			if Tiles.suit(Tiles.from_index(index)) != str(suits.keys()[0]): weights[index] = 0.0
	for meld in melds:
		if meld.tile != "hidden0": continue
		var index := _choose(remaining, weights, 4, random)
		if index < 0: return {}
		meld.tile = Tiles.from_index(index)
		remaining[index] -= 4
	var hand: Array = []
	var wait := random.randi_range(0, 26)
	if weights[wait] == 0.0:
		var allowed: Array[int] = []
		for index in 27:
			if weights[index] > 0.0: allowed.append(index)
		if allowed.is_empty():
			# A late information set can exhaust every tile in a preferred suit.
			# Treat that hypothesis as unsampleable instead of indexing an empty
			# fallback list and aborting the AI turn.
			return {}
		wait = allowed[random.randi_range(0, allowed.size() - 1)]
	var pairs_route := melds.is_empty() and random.randf() < 0.20
	var triplet_route := random.randf() < (0.25 + 0.12 * melds.size())
	if pairs_route:
		if not _take(hand, remaining, [wait]): return {}
		for _pair in 6:
			var index := _choose(remaining, weights, 2, random)
			if index < 0 or not _take(hand, remaining, [index, index]): return {}
	else:
		var groups := 4 - melds.size()
		var pair_wait := groups == 0 or random.randf() < 0.23
		if pair_wait:
			if not _take(hand, remaining, [wait]): return {}
		else:
			var pair := _choose(remaining, weights, 2, random)
			if pair < 0 or not _take(hand, remaining, [pair, pair]): return {}
			var partial: Array = [wait, wait]
			if not triplet_route and random.randf() < 0.75:
				var start := wait - random.randi_range(0, 2)
				if start < 0 or start % 9 > 6 or start / 9 != wait / 9: return {}
				partial = []
				for index in range(start, start + 3):
					if index != wait: partial.append(index)
			if not _take(hand, remaining, partial): return {}
			groups -= 1
		for _group in groups:
			var group := _choose_group(remaining, weights, triplet_route, random)
			if group.is_empty() or not _take(hand, remaining, group): return {}
	if not RuleEngine.can_win_on(hand, melds, Tiles.from_index(wait)): return {}
	return {"hand": hand, "melds": melds}

func _choose(pool: Array[int], weights: Array[float], copies: int, random: RandomNumberGenerator) -> int:
	var total := 0.0
	var values: Array[float] = []
	for index in 27:
		var value := weights[index] * pool[index] if pool[index] >= copies else 0.0
		values.append(value)
		total += value
	if total <= 0: return -1
	var pick := random.randf() * total
	for index in 27:
		pick -= values[index]
		if values[index] > 0 and pick <= 0: return index
	return -1

func _choose_group(pool: Array[int], weights: Array[float], triplets: bool, random: RandomNumberGenerator) -> Array:
	var groups: Array = []
	var values: Array[float] = []
	var total := 0.0
	for index in 27:
		if pool[index] >= 3:
			groups.append([index, index, index])
			values.append(weights[index] * pool[index] * 0.7)
			total += values[-1]
		if not triplets and index % 9 <= 6 and pool[index] > 0 and pool[index + 1] > 0 and pool[index + 2] > 0:
			groups.append([index, index + 1, index + 2])
			values.append(pow(weights[index] * weights[index + 1] * weights[index + 2], 1.0 / 3.0) * mini(pool[index], mini(pool[index + 1], pool[index + 2])))
			total += values[-1]
	var pick := random.randf() * total
	for index in groups.size():
		pick -= values[index]
		if pick <= 0: return groups[index]
	return []

func _take(hand: Array, pool: Array[int], indices: Array) -> bool:
	for index in indices:
		if pool[index] <= 0: return false
		pool[index] -= 1
		hand.append(Tiles.from_index(index))
	return true

func _likelihood(hand: Array, spec: Dictionary) -> float:
	var value := 1.0
	var counts := Tiles.to_counts(hand)
	for discarded in spec.history:
		# A discard is soft evidence only; there is deliberately no furiten veto.
		if counts.has(discarded): value *= 0.96 if spec.ready else 0.88
	return maxf(0.15, value)

