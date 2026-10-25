extends RefCounted
## Bounded Monte Carlo tree search for discard selection.
## The search only receives the public unseen-count map and the current hand;
## it never reads opponent concealed tiles or the wall order.

const VALUE := preload("res://scripts/ai/AiValueModel.gd")
const OPPONENT := preload("res://scripts/ai/AiOpponentModel.gd")
## Keep the search bounded so a phone can finish a turn promptly.
## AiPlayer sends only its strongest few candidates here; the value model
## remains the primary decision layer.
var iterations := 16
var defense_weight := 0.0
var _opponent_model := OPPONENT.new()
const DEPTH := 2
const EXPLORATION := 1.15

func rank(round, seat: int, hand: Array, melds: Array, seen: Dictionary, candidates: Array, context: Dictionary, weight: float = -1.0) -> Dictionary:
	if weight >= 0.0:
		defense_weight = weight
	var roots: Array = []
	var indexes := {}
	for candidate in candidates:
		var tile := str(candidate.get("tile", ""))
		if tile == "" or indexes.has(tile): continue
		indexes[tile] = roots.size()
		roots.append({"tile": tile, "visits": 0, "value": 0.0})
	if roots.is_empty(): return {}
	var random := RandomNumberGenerator.new()
	random.seed = absi(str([Tiles.counts_array(seen), hand, melds]).hash())
	var pool := _pool(seen)
	for iteration in iterations:
		var root_index := _select_root(roots)
		var root: Dictionary = roots[root_index]
		var state: Array = hand.duplicate()
		state.erase(root.tile)
		# 每个 rollout 都必须从相同的未知牌池开始；模拟内的摸牌只影响
		# 当前分支，不能污染其他候选牌或后续 rollout。
		var reward := -defense_weight * _discard_loss(context, str(root.tile))
		reward += _simulate(round, seat, state, melds, pool, random, context)
		root.visits = int(root.visits) + 1
		root.value = float(root.value) + reward
		roots[root_index] = root
	var result: Dictionary = {}
	for root in roots:
		result[root.tile] = {"visits": root.visits, "value": root.value / float(maxi(1, int(root.visits)))}
	return result

func _select_root(roots: Array) -> int:
	for index in roots.size():
		if int(roots[index].visits) == 0: return index
	var total := 0.0
	for root in roots: total += int(root.visits)
	var best := 0
	var best_score := -INF
	for index in roots.size():
		var root: Dictionary = roots[index]
		var mean := float(root.value) / float(root.visits)
		var bonus := EXPLORATION * sqrt(log(maxf(1.0, total)) / float(root.visits))
		if mean + bonus > best_score:
			best_score = mean + bonus
			best = index
	return best

func _pool(seen: Dictionary) -> Array[int]:
	var pool: Array[int] = []
	for tile in Tiles.all_values():
		pool.append(maxi(0, 4 - int(seen.get(tile, 0))))
	return pool

func _simulate(round, seat: int, state: Array, melds: Array, pool: Array[int], random: RandomNumberGenerator, context: Dictionary) -> float:
	var current := state.duplicate()
	var remaining_pool: Array[int] = _copy_pool(pool)
	var reward := 0.0
	for depth in DEPTH:
		var drawn := _draw_and_consume(remaining_pool, random)
		if drawn < 0: break
		var tile := Tiles.from_index(drawn)
		current.append(tile)
		if RuleEngine.analyze(current, melds).win:
			var flips: Dictionary = context.get("flips", {})
			reward += 12.0 + 0.05 * VALUE.win_value(round, seat, current, melds, flips, context.get("opponents", []), false, true)
			break
		var discard := _quick_discard(current, melds, remaining_pool)
		if discard == "": break
		current.erase(discard)
		var distance := Shanten.shanten(current, melds)
		var outs := _outs(current, melds, remaining_pool)
		reward += (4.0 - float(distance)) * 2.2 + float(outs) * 0.06
		if defense_weight > 0.0:
			reward -= defense_weight * _discard_loss(context, discard)
	# A small pattern term helps retain seven-pairs/flush routes when progress ties.
	reward += 0.10 * VALUE.potential_pattern(current, melds)
	return reward

func _discard_loss(context: Dictionary, tile: String) -> float:
	if tile == "" or defense_weight <= 0.0:
		return 0.0
	# risk() 已包含对手听牌概率与牌型危险度；巡目不要在这里重复乘。
	return float(_opponent_model.risk(context, tile, false, false, false, -1).loss)

func _draw(pool: Array[int], random: RandomNumberGenerator) -> int:
	var total := 0
	for count in pool: total += int(count)
	if total <= 0: return -1
	var pick := random.randi_range(1, total)
	for index in pool.size():
		pick -= int(pool[index])
		if pick <= 0: return index
	return -1

func _draw_and_consume(pool: Array[int], random: RandomNumberGenerator) -> int:
	var drawn := _draw(pool, random)
	if drawn >= 0 and drawn < pool.size():
		pool[drawn] = maxi(0, int(pool[drawn]) - 1)
	return drawn

func _copy_pool(pool: Array[int]) -> Array[int]:
	var copy: Array[int] = []
	copy.resize(pool.size())
	for index in pool.size():
		copy[index] = int(pool[index])
	return copy

func _quick_discard(hand: Array, melds: Array, pool: Array[int]) -> String:
	var best := ""
	var best_score := INF
	var counts := Tiles.to_counts(hand)
	for tile in Tiles.to_counts(hand):
		var score := 0.0
		var copies := int(counts[tile])
		# Preserve pairs, triplets and connected suited tiles. This is only the
		# rollout policy; the real hand evaluator remains authoritative.
		score += 3.0 if copies == 1 else (8.0 if copies == 2 else 12.0)
		var suit := Tiles.suit(tile)
		var rank := Tiles.rank(tile)
		if rank > 1 and counts.has(Tiles.val(suit, rank - 1)): score += 2.0
		if rank < 9 and counts.has(Tiles.val(suit, rank + 1)): score += 2.0
		if rank > 2 and counts.has(Tiles.val(suit, rank - 2)): score += 1.0
		if rank < 8 and counts.has(Tiles.val(suit, rank + 2)): score += 1.0
		if score < best_score:
			best = tile
			best_score = score
	return best

func _outs(hand: Array, melds: Array, pool: Array[int]) -> int:
	var counts := Tiles.to_counts(hand)
	var result := 0
	for index in pool.size():
		if pool[index] <= 0: continue
		var tile := Tiles.from_index(index)
		var copies := int(counts.get(tile, 0))
		var suit := Tiles.suit(tile)
		var rank := Tiles.rank(tile)
		var connected := copies > 0
		connected = connected or (rank > 1 and counts.has(Tiles.val(suit, rank - 1)))
		connected = connected or (rank < 9 and counts.has(Tiles.val(suit, rank + 1)))
		if connected: result += int(pool[index])
	return result
