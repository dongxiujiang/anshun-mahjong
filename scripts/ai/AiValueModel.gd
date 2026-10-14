extends RefCounted
## Expected payments, in score points. Unknown flips use the unseen tile pool,
## never the actual wall order. Probability estimates are heuristic, not learned.
const CFG := preload("res://scripts/autoload/GameConfig.gd")
static var _unit_cache := {}

static func flip_distribution(seen: Dictionary, fixed_flip: String = "") -> Dictionary:
	if fixed_flip != "": return {fixed_flip: 1.0}
	var result := {}
	var total := 0.0
	for tile in Tiles.all_values():
		var copies := maxi(0, 4 - int(seen.get(tile, 0)))
		result[tile] = float(copies)
		total += copies
	for tile in result:
		result[tile] = result[tile] / total if total > 0 else 1.0 / 27.0
	return result

static func tile_value(tile: String, flips: Dictionary, multiplier: int, charge: bool = false) -> float:
	var hit := 0.0
	for flip in flips:
		if tile in Tiles.flip_related(flip): hit += float(flips[flip])
	if Tiles.is_chicken(tile):
		return (CFG.SCORE_CHARGE_CHICKEN if charge else CFG.SCORE_CALL_CHICKEN) * (1.0 + hit) * multiplier
	return CFG.SCORE_FLIP_CHICKEN * hit * multiplier

static func _unit_values(flips: Dictionary, multiplier: int) -> Dictionary:
	var key := str([flips, multiplier])
	if _unit_cache.has(key): return _unit_cache[key]
	var values := {}
	for tile in Tiles.all_values(): values[tile] = tile_value(tile, flips, multiplier)
	if _unit_cache.size() >= 128: _unit_cache.clear()
	_unit_cache[key] = values
	return values

static func profile(round, seat: int, hand: Array, melds: Array, flips: Dictionary, discard: String = "") -> Dictionary:
	var multiplier := clampi(int(round.round_meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	var values := _unit_values(flips, multiplier)
	var result := {"discarded": 0.0, "total": 0.0, "kong_chickens": 0.0, "no_chicken": 0.0}
	var tiles := hand.duplicate()
	for meld in melds:
		for _index in (3 if meld.kind == "pung" else 4): tiles.append(meld.tile)
	if not tiles.any(func(tile): return Tiles.is_chicken(tile)):
		for flip in flips:
			var related := Tiles.flip_related(flip)
			if not tiles.any(func(tile): return tile in related):
				result.no_chicken += float(flips[flip]) * CFG.SCORE_NO_CHICKEN
	if seat == int(round.round_meta.get("burn_chicken_seat", -1)): return result
	for index in round.players[seat].discards.size():
		var tile: String = round.players[seat].discards[index]
		if Tiles.is_chicken(tile):
			result.discarded += float(values[tile]) * (CFG.SCORE_CHARGE_CHICKEN / CFG.SCORE_CALL_CHICKEN if round.is_charge_discard(seat, index) else 1.0)
	if Tiles.is_chicken(discard):
		result.discarded += float(values[discard]) * (CFG.SCORE_CHARGE_CHICKEN / CFG.SCORE_CALL_CHICKEN if not round.has_charge(discard) else 1.0)
	result.total = result.discarded
	for tile in tiles: result.total += float(values.get(tile, 0.0))
	for meld in melds:
		if meld.kind != "pung" and not meld.get("robbed", false) and Tiles.is_chicken(meld.tile):
			result.kong_chickens += 4.0 * float(values[meld.tile])
	return result

static func pattern_points(pattern: Dictionary) -> float:
	var special := RuleEngine.special_pattern_key(pattern)
	var key := special
	if key == "":
		if pattern.get("dragon_seven_pairs", false): key = "dragon_seven_pairs"
		elif pattern.get("seven_pairs", false): key = "seven_pairs"
		elif pattern.get("all_triplets", false): key = "all_triplets"
		elif pattern.get("flush", false): key = "flush"
	for raw in CFG.PATTERNS:
		var spec: Dictionary = raw
		if spec.get("key", "") == key:
			return float(spec.get("score", 0.0))
	return 0.0

static func kong_base(melds: Array, payer: int) -> float:
	var result := 0.0
	for meld in melds:
		if meld.kind == "pung" or meld.get("robbed", false): continue
		if meld.kind == "add_kong" or meld.get("concealed", false) or (payer >= 0 and int(meld.get("from_seat", -1)) == payer):
			result += CFG.SCORE_DRAW_KONG
	return result

static func has_self_kong(melds: Array) -> bool:
	return melds.any(func(meld): return meld.kind == "add_kong" or (meld.kind == "kong" and meld.get("concealed", false)))

static func allows_ron(pattern: Dictionary, melds: Array, declared_ready: bool) -> bool:
	return declared_ready or has_self_kong(melds) or pattern.get("all_triplets", false) \
		or pattern.get("flush", false) or pattern.get("seven_pairs", false) \
		or RuleEngine.special_pattern_key(pattern) != ""

## Estimate pattern routes before completion; exact patterns replace this at tenpai.
static func potential_pattern(hand: Array, melds: Array) -> float:
	var counts := Tiles.to_counts(hand)
	var pairs := 0
	var triplets := melds.size()
	var suits := {}
	for tile in counts:
		pairs += int(counts[tile]) / 2
		if int(counts[tile]) >= 3: triplets += 1
	for tile in hand: suits[Tiles.suit(tile)] = int(suits.get(Tiles.suit(tile), 0)) + 1
	for meld in melds: suits[Tiles.suit(meld.tile)] = int(suits.get(Tiles.suit(meld.tile), 0)) + 3
	var result := 0.0
	if melds.is_empty():
		result += pow(minf(1.0, pairs / 7.0), 4.0) * (CFG.SCORE_DRAGON_SEVEN_PAIRS if counts.values().has(4) else CFG.SCORE_SEVEN_PAIRS)
	result = maxf(result, pow(minf(1.0, (triplets + 0.35 * pairs) / 4.0), 4.0) * CFG.SCORE_BIG_SET)
	if not suits.is_empty():
		var largest: int = suits.values().max()
		var compatible := melds.all(func(meld): return int(suits.get(Tiles.suit(meld.tile), 0)) == largest)
		if compatible: result += pow(largest / float(maxi(1, hand.size() + 3 * melds.size())), 8.0) * CFG.SCORE_FLUSH
	return result

## Net receipts if we win, conditional on public estimates of who is called.
## A meld's base 4 is charged only to its source unless it is an own kong.
static func win_value(round, seat: int, hand: Array, melds: Array, flips: Dictionary, opponents: Array, declared_ready: bool, self_draw: bool = true, source: int = -1, discard: String = "", kong_draw: bool = false) -> float:
	var own := profile(round, seat, hand, melds, flips, discard)
	var pattern := RuleEngine.analyze(hand, melds)
	var points := pattern_points(pattern) if pattern.win else potential_pattern(hand, melds)
	var primary := points
	if primary <= 0.0:
		primary = CFG.SCORE_READY if declared_ready else CFG.SCORE_SELF_DRAW
		if self_draw and float(own.total) <= 0.0:
			var all_dry := true
			for opponent in opponents:
				if float(opponent.tenpai_probability) > 0.0 and float(opponent.chickens) > 0.0:
					all_dry = false
					break
			primary = CFG.SCORE_BIG_NO_CHICKEN if all_dry else CFG.SCORE_NO_CHICKEN
	var bonus := (CFG.SCORE_KONG_DRAW if kong_draw else 0.0) + (CFG.SCORE_LAST_FOUR if self_draw and round._wall_count() <= 4 else 0.0)
	var total := 0.0
	for opponent in opponents:
		var payer := int(opponent.seat)
		var called := float(opponent.tenpai_probability)
		# 鸡分采用四家两两比较：赢家向叫牌对手收差额，向未叫牌对手收自己的全部鸡分。
		total += called * (float(own.total) - float(opponent.chickens)) + (1.0 - called) * float(own.total)
		total += kong_base(melds, payer) - called * kong_base(opponent.melds, seat)
		total += bonus
		var base_payer := self_draw or payer == source
		if base_payer: total += primary
		# 清牌型上报听另加24；普通报听已用24替换基础4。报听者被杀也只付一份。
		if opponent.ready or (declared_ready and points > 0.0 and base_payer):
			total += CFG.SCORE_READY
	return total

static func draw_value(round, seat: int, hand: Array, melds: Array, opponents: Array, discard: String = "") -> Dictionary:
	# No flip in an exhaustive draw. Only retained discards and kong chickens count.
	var own := profile(round, seat, hand, melds, {}, discard)
	var called_value := 0.0
	var uncalled_value := 0.0
	for opponent in opponents:
		var probability := float(opponent.tenpai_probability)
		called_value += (1.0 - probability) * (float(own.discarded) + float(opponent.draw_discarded) + float(own.kong_chickens) + kong_base(melds, int(opponent.seat)))
		uncalled_value -= probability * (float(opponent.draw_discarded) + float(own.discarded) + float(opponent.draw_kong_chickens) + kong_base(opponent.melds, seat))
	return {"called": called_value, "uncalled": uncalled_value}

static func settlement_value(round, seat: int, hand: Array, melds: Array, flips: Dictionary, opponents: Array, discard: String = "") -> Dictionary:
	var own := profile(round, seat, hand, melds, flips, discard)
	var called_value := 0.0
	var uncalled_value := 0.0
	for opponent in opponents:
		var probability := float(opponent.tenpai_probability)
		called_value += probability * (float(own.total) - float(opponent.chickens)) + (1.0 - probability) * float(own.total)
		called_value += kong_base(melds, int(opponent.seat)) - probability * kong_base(opponent.melds, seat)
		uncalled_value -= probability * (float(opponent.chickens) + kong_base(opponent.melds, seat))
	return {"called": called_value, "uncalled": uncalled_value}
