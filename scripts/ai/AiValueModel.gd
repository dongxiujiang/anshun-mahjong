extends RefCounted
## Expected payments, in score points. Unknown flips use the unseen tile pool,
## never the actual wall order. Probability estimates are heuristic, not learned.
const CFG := preload("res://scripts/autoload/GameConfig.gd")
const ACTIONS := preload("res://scripts/core/LegalActions.gd")
static var _unit_caches := {}
static var _unit_cache_mutex := Mutex.new()

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
	var thread_id := OS.get_thread_caller_id()
	_unit_cache_mutex.lock()
	if not _unit_caches.has(thread_id): _unit_caches[thread_id] = {}
	var cache: Dictionary = _unit_caches[thread_id]
	_unit_cache_mutex.unlock()
	var key := str([flips, multiplier])
	if cache.has(key): return cache[key]
	var values := {}
	for tile in Tiles.all_values(): values[tile] = tile_value(tile, flips, multiplier)
	if cache.size() >= 128: cache.clear()
	cache[key] = values
	return values

static func profile(round, seat: int, hand: Array, melds: Array, flips: Dictionary, discard: String = "") -> Dictionary:
	# 与结算一致：鸡分、牌型和定向费用先按单倍计算，最后统一翻倍。
	var values := _unit_values(flips, 1)
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

static func uncalled_kong_base(melds: Array) -> float:
	return CFG.SCORE_DRAW_KONG * melds.filter(func(meld): return meld.kind in ["kong", "add_kong"] and not meld.get("robbed", false)).size()

static func uncalled_kong_base_for(melds: Array, receiver: int) -> float:
	# 未叫牌明杠只反向付给放杠者；暗杠/加杠才付给每位叫牌者。
	var total := 0.0
	for meld in melds:
		if meld.kind not in ["kong", "add_kong"] or meld.get("robbed", false):
			continue
		if meld.kind == "kong" and not meld.get("concealed", false):
			if int(meld.get("from_seat", -1)) == receiver:
				total += CFG.SCORE_DRAW_KONG
		else:
			total += CFG.SCORE_DRAW_KONG
	return total

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
static func win_value(round, seat: int, hand: Array, melds: Array, flips: Dictionary, opponents: Array, declared_ready: bool, self_draw: bool = true, source: int = -1, discard: String = "", kong_draw: bool = false, win_tile: String = "") -> float:
	var own := profile(round, seat, hand, melds, flips, discard)
	var pattern := RuleEngine.analyze(hand, melds, win_tile if win_tile != "" else str(round.round_meta.get("win_tile", "")))
	var multiplier := clampi(int(round.round_meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	var points := pattern_points(pattern) if pattern.win else 0.0
	var primary := points
	if self_draw and primary <= 0.0:
		if declared_ready:
			# 报听自摸的普通牌只收 24 + 鸡，不再另收自摸 4。
			primary = 0.0
		else:
			primary = CFG.SCORE_SELF_DRAW
			if float(own.total) <= 0.0:
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
		# 未叫牌者以出牌鸡负分参与比较，因此赢家还收取对方保留的
		# 出牌鸡；叫牌者则按完整鸡分逐家比较。
		total += called * (float(own.total) - float(opponent.chickens)) + (1.0 - called) * (float(own.total) + float(opponent.discarded))
		total += kong_base(melds, payer) - called * kong_base(opponent.melds, seat)
		# §十八（一）6：未叫杠主的全部杠基础和杠中鸡向每个叫牌者反付。
		total += (1.0 - called) * (uncalled_kong_base(opponent.melds) + float(opponent.get("kong_chickens", 0.0)))
		if self_draw:
			total += bonus
			if declared_ready:
				total += CFG.SCORE_READY
		var base_payer := self_draw or payer == source
		if base_payer:
			if self_draw:
				total += primary
			else:
				# 普通弃牌不收17/21；只有抢杠胡或暗/加杠后的
				# 第一张弃牌才产生基础费。
				var meta: Dictionary = round.round_meta
				if bool(meta.get("robbed_kong", false)):
					total += CFG.SCORE_ROB_KONG
				elif ACTIONS.is_post_kong_discard(round.last_discard):
					total += CFG.SCORE_RON_CALLED if called > 0.5 else CFG.SCORE_RON_UNCALLED
		# §十二：报听费只由点炮者支付，点炮者是否报听不产生额外费用。
		if not self_draw:
			# 牌型费：只由放炮者支付；其他两家不付牌型分。
			if payer == source and points > 0.0:
				total += points
			# 自带暗杠/加杠的小牌放炮：普通小牌才加4。
			if payer == source and has_self_kong(melds) and points <= 0.0 and not declared_ready \
				and RuleEngine.special_pattern_key(pattern) == "" \
				and not pattern.get("all_triplets", false) and not pattern.get("seven_pairs", false) \
				and not pattern.get("dragon_seven_pairs", false) and not pattern.get("flush", false):
				total += CFG.SCORE_KONG_SELF_RON
			# 报听费：只有点炮者支付
			if payer == source:
				if declared_ready:
					total += CFG.SCORE_READY
	return total * multiplier

static func draw_value(round, seat: int, hand: Array, melds: Array, opponents: Array, discard: String = "") -> Dictionary:
	# No flip in an exhaustive draw. Only retained discards and kong chickens count.
	var own := profile(round, seat, hand, melds, {}, discard)
	var called_value := 0.0
	var uncalled_value := 0.0
	for opponent in opponents:
		var probability := float(opponent.tenpai_probability)
		called_value += (1.0 - probability) * (float(own.discarded) + float(opponent.draw_discarded) + CFG.SCORE_SELF_DRAW + float(own.kong_chickens) + kong_base(melds, int(opponent.seat)) + uncalled_kong_base_for(opponent.melds, seat) + float(opponent.get("draw_kong_chickens", 0.0)))
		# 未叫牌方也要为自己的杠中鸡向每位已叫牌对手逐家补付；
		# 因此估值中同时扣除对手的杠中鸡和本人的杠中鸡。
		uncalled_value -= probability * (float(opponent.draw_discarded) + float(own.discarded) + CFG.SCORE_SELF_DRAW + float(opponent.draw_kong_chickens) + float(own.kong_chickens) + kong_base(opponent.melds, seat) + uncalled_kong_base_for(melds, int(opponent.seat)))
	var multiplier := clampi(int(round.round_meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	return {"called": called_value * multiplier, "uncalled": uncalled_value * multiplier}

static func settlement_value(round, seat: int, hand: Array, melds: Array, flips: Dictionary, opponents: Array, discard: String = "") -> Dictionary:
	var own := profile(round, seat, hand, melds, flips, discard)
	var called_value := 0.0
	var uncalled_value := 0.0
	for opponent in opponents:
		var probability := float(opponent.tenpai_probability)
		called_value += probability * (float(own.total) - float(opponent.chickens)) + (1.0 - probability) * (float(own.total) + float(opponent.discarded))
		called_value += kong_base(melds, int(opponent.seat)) - probability * kong_base(opponent.melds, seat)
		uncalled_value -= probability * (float(opponent.discarded) + kong_base(opponent.melds, seat))
	var multiplier := clampi(int(round.round_meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	return {"called": called_value * multiplier, "uncalled": uncalled_value * multiplier}
