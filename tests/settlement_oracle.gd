extends RefCounted
## 独立结算核账：手工计算鸡分、逐家收付、杠费和各类胡牌费用。

static func expected(round: RoundState) -> Dictionary:
	var meta: Dictionary = round.round_meta
	var winners: Array = meta.get("winners", []).duplicate()
	if winners.is_empty() and int(meta.get("winner", -1)) >= 0:
		winners.append(int(meta.winner))
	var has_winner := not winners.is_empty()
	var winner := int(meta.get("winner", -1))
	var multiplier := clampi(int(meta.get("chicken_multiplier", 1)), 1, 2)
	var flip := str(meta.get("flip_tile", "")) if has_winner else ""
	var related: Array = []
	if not flip.is_empty():
		var rank := Tiles.rank(flip)
		for offset in [-1, 0, 1]:
			related.append(Tiles.suit(flip) + str(posmod(rank - 1 + offset, 9) + 1))

	var called: Array = []
	var chicken_values: Array = [0.0, 0.0, 0.0, 0.0]
	var discard_values: Array = [0.0, 0.0, 0.0, 0.0]
	var matrix := _empty_matrix()
	for seat in 4:
		var player: PlayerState = round.players[seat]
		var is_called: bool = winners.has(seat) or RuleEngine.is_tenpai(player.concealed, player.melds)
		called.append(is_called)
		var profile := _chicken_values(round, seat, related, multiplier)
		discard_values[seat] = profile.discarded
		chicken_values[seat] = profile.total if is_called else 0.0

	if has_winner:
		for first in 4:
			for second in range(first + 1, 4):
				var difference: float = float(chicken_values[first]) - float(chicken_values[second])
				if difference > 0.0:
					_credit(matrix, second, first, difference)
				elif difference < 0.0:
					_credit(matrix, first, second, -difference)
	else:
		for payer in 4:
			if called[payer]:
				continue
			for receiver in 4:
				if called[receiver]:
					_credit(matrix, payer, receiver, float(discard_values[payer]) + float(discard_values[receiver]))

	# Kong base is a directed fee; chicken inside a kong is included in the
	# ordinary called-chicken comparison for wins and charged separately on draws.
	for receiver in 4:
		if not called[receiver]:
			continue
		for meld in round.players[receiver].melds:
			if meld.kind not in ["kong", "add_kong"] or meld.get("robbed", false):
				continue
			var own_kong: bool = meld.kind == "add_kong" or meld.get("concealed", false)
			var source := int(meld.get("from_seat", -1))
			for payer in 4:
				if payer == receiver or (not has_winner and called[payer]):
					continue
				if own_kong or payer == source:
					_credit(matrix, payer, receiver, 4.0)
			if not has_winner and receiver != int(meta.get("burn_chicken_seat", -1)):
				var tile := str(meld.tile)
				var chicken_fee := 8.0 * multiplier if tile in ["tiao1", "tong8"] else 0.0
				var flip_fee := 4.0 * multiplier if tile in related and tile not in ["tiao1", "tong8"] else 0.0
				for payer in 4:
					if payer != receiver and not called[payer]:
						_credit(matrix, payer, receiver, chicken_fee + flip_fee)

	if has_winner:
		for target in winners:
			var target_seat := int(target)
			var player: PlayerState = round.players[target_seat]
			var pattern := RuleEngine.hand_pattern(player.concealed, player.melds, str(meta.get("win_tile", "")))
			var pattern_fee := _pattern_fee(pattern)
			var self_draw := bool(meta.get("self_draw", false))
			var primary := pattern_fee
			var ready_primary := false
			if primary <= 0.0:
				if player.ready:
					primary = 24.0
					ready_primary = true
				elif self_draw and float(_chicken_values(round, target_seat, related, multiplier).total) <= 0.0:
					var all_chickenless := true
					for other in 4:
						if float(chicken_values[other]) > 0.0:
							all_chickenless = false
							break
					primary = 24.0 if all_chickenless else 14.0
				else:
					primary = 4.0
			for payer in 4:
				if payer == target_seat:
					continue
				var base_payer: bool = self_draw or payer == int(meta.get("discard_seat", -1))
				if base_payer:
					_credit(matrix, payer, target_seat, primary)
				if round.players[payer].ready and not winners.has(payer):
					_credit(matrix, payer, target_seat, 24.0)
				elif player.ready and pattern_fee > 0.0 and base_payer and not ready_primary:
					_credit(matrix, payer, target_seat, 24.0)
			if self_draw and int(meta.get("kong_draw_seat", -1)) == target_seat:
				for payer in 4:
					if payer != target_seat:
						_credit(matrix, payer, target_seat, 5.0)
			if self_draw and int(meta.get("last_four_self_draw_seat", -1)) == target_seat:
				for payer in 4:
					if payer != target_seat:
						_credit(matrix, payer, target_seat, 5.0)

	var deltas := [0.0, 0.0, 0.0, 0.0]
	for seat in 4:
		for other in 4:
			deltas[seat] += float(matrix[seat][other])
	return {"pairwise": matrix, "deltas": deltas, "called": called, "chickens": chicken_values, "discard_chickens": discard_values}

static func _chicken_values(round: RoundState, seat: int, related: Array, multiplier: int) -> Dictionary:
	if seat == int(round.round_meta.get("burn_chicken_seat", -1)):
		return {"total": 0.0, "discarded": 0.0}
	var player: PlayerState = round.players[seat]
	var total := 0.0
	var discarded := 0.0
	for index in player.discards.size():
		var tile := str(player.discards[index])
		if tile not in ["tiao1", "tong8"]:
			continue
		var id: int = player.discard_ids[index] if index < player.discard_ids.size() else index
		var record: Dictionary = round.round_meta.get("charge_chickens", {}).get(tile, {})
		var charge: bool = record.get("owner", -1) == seat and record.get("location", "") == "discard" and record.get("discard_id", -1) == id
		var amount := (4.0 if charge else 2.0) * (2.0 if tile in related else 1.0) * multiplier
		discarded += amount
		total += amount
	for tile_value in player.concealed:
		total += _held_chicken(str(tile_value), related, multiplier)
	for meld in player.melds:
		var count := 3 if meld.kind == "pung" else 4
		for _index in count:
			total += _held_chicken(str(meld.tile), related, multiplier)
	return {"total": total, "discarded": discarded}

static func _held_chicken(tile: String, related: Array, multiplier: int) -> float:
	if tile in ["tiao1", "tong8"]:
		return 2.0 * (2.0 if tile in related else 1.0) * multiplier
	return float(multiplier) if tile in related else 0.0

static func _pattern_fee(pattern: Dictionary) -> float:
	if pattern.get("clean_dragon_seven_pairs", false): return 64.0
	if pattern.get("clean_single_wait", false): return 54.0
	if pattern.get("clean_seven_pairs", false): return 44.0
	if pattern.get("clean_big_single_wait", false): return 44.0
	if pattern.get("clean_big_triplets", false): return 34.0
	if pattern.get("big_triplet_single_wait", false): return 24.0
	if pattern.get("dragon_seven_pairs", false): return 44.0
	if pattern.get("seven_pairs", false): return 24.0
	if pattern.get("all_triplets", false): return 14.0
	if pattern.get("flush", false): return 24.0
	return 0.0

static func _empty_matrix() -> Array:
	return [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]

static func _credit(matrix: Array, payer: int, receiver: int, amount: float) -> void:
	if payer == receiver or amount <= 0.0:
		return
	matrix[receiver][payer] += amount
	matrix[payer][receiver] -= amount

static func check(round: RoundState, result: Dictionary, harness, label: String) -> void:
	var reference := expected(round)
	if result.has("called"):
		harness.expect(result.called == reference.called, "%s 叫牌状态" % label)
	harness.expect(result.pairwise == reference.pairwise, "%s 六对付款：应为%s，实际%s" % [label, reference.pairwise, result.pairwise])
	harness.expect(result.deltas == reference.deltas, "%s 四家净分：应为%s，实际%s" % [label, reference.deltas, result.deltas])
	for seat in 4:
		var sum := 0.0
		for other in 4:
			harness.expect(result.pairwise[seat][other] == -result.pairwise[other][seat], "%s 收付相反" % label)
			sum += float(result.pairwise[seat][other])
		harness.expect(sum == result.deltas[seat], "%s 行合计等于净分" % label)
