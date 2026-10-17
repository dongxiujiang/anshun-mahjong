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
		# 胡牌局中，叫牌者用完整鸡分比较；未叫牌者以已打出鸡的负分
		# 参与比较。这样核账器与 ScoringEngine 的付款范围完全一致。
		chicken_values[seat] = profile.total if is_called else -profile.discarded

	if has_winner:
		for first in 4:
			for second in range(first + 1, 4):
				if not called[first] and not called[second]:
					continue
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
					_credit(matrix, payer, receiver, float(discard_values[payer]) + float(discard_values[receiver]) + 4.0)

	# 杠基础分是定向费用；杠中鸡在胡牌局已经进入鸡分比较，流局时
	# 才向未叫牌者单独收取。未叫牌杠牌者的杠收入则反向记为其付款。
	for receiver in 4:
		if called[receiver]:
			for meld in round.players[receiver].melds:
				if meld.kind not in ["kong", "add_kong"] or meld.get("robbed", false):
					continue
				if _cancelled_kong(round, receiver, meld):
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
		elif not has_winner:
			# 流局时未叫牌杠牌者不收杠分，反而向每位叫牌者支付4分；
			# 明杠仍只涉及原放杠者，暗杠/加杠涉及所有叫牌者。
			for meld in round.players[receiver].melds:
				if meld.kind not in ["kong", "add_kong"] or meld.get("robbed", false):
					continue
				if _cancelled_kong(round, receiver, meld):
					continue
				var own_kong: bool = meld.kind == "add_kong" or meld.get("concealed", false)
				var source := int(meld.get("from_seat", -1))
				for payer in 4:
					if payer == receiver or not called[payer] or (not own_kong and payer != source):
						continue
					_credit(matrix, receiver, payer, 4.0)
		else:
			continue
	# 未叫牌杠家的杠中鸡不计正分，但要向每位叫牌玩家单独补付。
	# 胡牌局只有翻牌关联幺鸡/八筒时才翻倍；流局不翻鸡。
	for owner in 4:
		if called[owner]:
			continue
		for meld in round.players[owner].melds:
			if meld.kind not in ["kong", "add_kong"] or meld.get("robbed", false):
				continue
			if _cancelled_kong(round, owner, meld):
				continue
			var tile := str(meld.tile)
			if tile not in ["tiao1", "tong8"]:
				continue
			var chicken_fee: float = 8.0 * multiplier
			if has_winner and tile in related:
				chicken_fee *= 2.0
			for receiver in 4:
				if called[receiver]:
					_credit(matrix, owner, receiver, chicken_fee)

	# For a winning round, an uncalled kong owner pays its directed kong fee to
	# called players. This is separate from chicken comparison.
	if has_winner:
		for owner in 4:
			if called[owner]:
				continue
			for meld in round.players[owner].melds:
				if meld.kind not in ["kong", "add_kong"] or meld.get("robbed", false):
					continue
				if _cancelled_kong(round, owner, meld):
					continue
				var own_kong: bool = meld.kind == "add_kong" or meld.get("concealed", false)
				var source := int(meld.get("from_seat", -1))
				for payer in 4:
					if payer == owner or not called[payer] or (not own_kong and payer != source):
						continue
					_credit(matrix, owner, payer, 4.0)

	if has_winner:
		for target in winners:
			var target_seat := int(target)
			var player: PlayerState = round.players[target_seat]
			var pattern := RuleEngine.hand_pattern(player.concealed, player.melds, str(meta.get("win_tile", "")))
			var pattern_fee := _pattern_fee(pattern)
			var self_draw := bool(meta.get("self_draw", false))
			var robbed_kong := bool(meta.get("robbed_kong", false))
			var source := int(meta.get("discard_seat", -1))
			var ready_primary := false
			var base_payers: Array = []
			for payer in 4:
				if payer != target_seat and (self_draw or payer == source):
					base_payers.append(payer)
			if self_draw:
				var primary := pattern_fee
				if primary <= 0.0:
					if player.ready:
						primary = 24.0
						ready_primary = true
					elif float(_chicken_values(round, target_seat, related, multiplier).total) <= 0.0:
						var all_chickenless := true
						for other in 4:
							if float(chicken_values[other]) > 0.0:
								all_chickenless = false
								break
						primary = 24.0 if all_chickenless else 14.0
					else:
						primary = 4.0
				for payer in base_payers:
					_credit(matrix, payer, target_seat, primary)
			else:
				var kong_discard := not robbed_kong and _is_post_kong_discard(round.last_discard)
				var source_called := source >= 0 and source < 4 and RuleEngine.is_tenpai(round.players[source].concealed, round.players[source].melds)
				var base := 12.0 if robbed_kong else (17.0 if kong_discard and source_called else (21.0 if kong_discard else 0.0))
				if source in range(4) and base > 0.0:
					_credit(matrix, source, target_seat, base)
				if player.ready:
					# 报听胡牌：点炮时只有点炮者支付
					if source in range(4) and source != target_seat:
						_credit(matrix, source, target_seat, 24.0)
				if pattern_fee > 0.0:
					for payer in 4:
						if payer != target_seat and not winners.has(payer):
							_credit(matrix, payer, target_seat, pattern_fee)
				if source in range(4) and source != target_seat and round.players[source].ready:
					_credit(matrix, source, target_seat, 24.0)
			for payer in 4:
				# 付款已按当前 WinScoring 规则在上方逐家展开。
				pass
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

static func _cancelled_kong(round: RoundState, receiver: int, meld: Dictionary) -> bool:
	if int(round.round_meta.get("burn_chicken_seat", -1)) != receiver or str(round.round_meta.get("burn_chicken_reason", "")) != "after_kong_discard":
		return false
	var last: Dictionary = round.last_discard
	if not bool(last.get("after_kong", false)) or int(last.get("seat", -1)) != receiver:
		return false
	if meld.has("after_discard") and int(meld.get("after_discard", -1)) + 1 != int(round.players[receiver].discard_count):
		return false
	var kind := int(last.get("kong_kind", RoundState.KongKind.NONE))
	if kind == RoundState.KongKind.CONCEALED:
		return meld.kind == "kong" and bool(meld.get("concealed", false))
	if kind == RoundState.KongKind.ADD_KONG:
		return meld.kind == "add_kong"
	return false

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
	for raw_record in round.round_meta.get("resolved_chicken_discards", []):
		var record: Dictionary = raw_record
		if int(record.get("owner", -1)) != seat:
			continue
		var tile := str(record.get("tile", ""))
		if tile not in ["tiao1", "tong8"]:
			continue
		var charge: bool = bool(record.get("charge", false))
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

static func _is_post_kong_discard(last_discard: Dictionary) -> bool:
	if not bool(last_discard.get("after_kong", false)):
		return false
	return int(last_discard.get("kong_kind", RoundState.KongKind.NONE)) in [RoundState.KongKind.CONCEALED, RoundState.KongKind.ADD_KONG]

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
