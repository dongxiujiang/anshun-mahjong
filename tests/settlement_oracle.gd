extends RefCounted
## 独立结算核账：手工计算鸡分、逐家收付、杠费和各类胡牌费用。

static func expected(round: RoundState) -> Dictionary:
	var meta: Dictionary = round.round_meta
	var burned := int(meta.get("burn_chicken_seat", -1))
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
	var pong_values: Array = [0.0, 0.0, 0.0, 0.0]
	var matrix := _empty_matrix()
	for seat in 4:
		var player: PlayerState = round.players[seat]
		var is_called: bool = winners.has(seat) or RuleEngine.is_tenpai(player.concealed, player.melds)
		called.append(is_called)
		var profile := _chicken_values(round, seat, related)
		if seat == burned:
			# The burned seat's own chicken score is zero, including its own
			# discard/pong debt; it still pays the winner's chicken by comparison.
			profile.debt = 0.0
			profile.pung_debt = 0.0
			profile.discarded = 0.0
			profile.total = 0.0
		discard_values[seat] = profile.discarded if is_called else profile.debt
		pong_values[seat] = 0.0 if is_called else float(profile.pung_debt)
		# 胡牌局中，叫牌者用完整鸡分比较；未叫牌者以已打出鸡和
		# 碰中鸡的负分参与比较。这样核账器与 ScoringEngine 完全一致。
		chicken_values[seat] = profile.total if is_called else -(float(profile.debt) + float(profile.pung_debt))

	if has_winner:
		for first in 4:
			for second in range(first + 1, 4):
				if not called[first] and not called[second]:
					continue
				var difference: float = float(chicken_values[first]) - float(chicken_values[second])
				if difference > 0.0:
					_credit(matrix, second, first, difference, burned)
				elif difference < 0.0:
					_credit(matrix, first, second, -difference, burned)
	else:
		for payer in 4:
			if called[payer]:
				continue
			for receiver in 4:
				if called[receiver]:
					_credit(matrix, payer, receiver, float(discard_values[payer]) + float(discard_values[receiver]) + float(pong_values[payer]) + 4.0, burned)

	# 杠基础分是定向费用；杠中鸡在胡牌局已经进入鸡分比较，流局时
	# 才向未叫牌者单独收取。未叫牌杠牌者的杠收入则反向记为其付款。
	for receiver in 4:
		if called[receiver] and receiver != burned:
			for meld in round.players[receiver].melds:
				if meld.kind not in ["kong", "add_kong"] or meld.get("robbed", false):
					continue
				var own_kong: bool = meld.kind == "add_kong" or meld.get("concealed", false)
				var source := int(meld.get("from_seat", -1))
				for payer in 4:
					if payer == receiver or (not has_winner and called[payer]):
						continue
					if own_kong or payer == source:
						_credit(matrix, payer, receiver, 4.0, burned)
				if not has_winner and receiver != int(meta.get("burn_chicken_seat", -1)):
					var tile := str(meld.tile)
					var chicken_fee := 8.0 if tile in ["tiao1", "tong8"] else 0.0
					var flip_fee := 4.0 if tile in related and tile not in ["tiao1", "tong8"] else 0.0
					for payer in 4:
						if payer != receiver and not called[payer]:
							_credit(matrix, payer, receiver, chicken_fee + flip_fee, burned)
		else:
			continue
	# 未叫牌杠主不能作为收款杠主：明杠只反向付给放杠者，
	# 暗杠/加杠才反向付给每位叫牌者。
	for owner in 4:
		if called[owner]:
			continue
		for meld in round.players[owner].melds:
			if meld.kind not in ["kong", "add_kong"] or meld.get("robbed", false):
				continue
			if meld.kind == "kong" and not meld.get("concealed", false):
				var source := int(meld.get("from_seat", -1))
				if source in range(4) and source != owner:
					_credit(matrix, owner, source, 4.0, burned)
			else:
				for payer in 4:
					if called[payer]:
						_credit(matrix, owner, payer, 4.0, burned)

	# 未叫牌杠家的杠中鸡不计正分，但要向每位叫牌玩家单独补付。
	# 胡牌局只有翻牌关联幺鸡/八筒时才翻倍；流局不翻鸡。
	for owner in 4:
		if called[owner]:
			continue
		for meld in round.players[owner].melds:
			if meld.kind not in ["kong", "add_kong"] or meld.get("robbed", false):
				continue
			var tile := str(meld.tile)
			if tile not in ["tiao1", "tong8"]:
				continue
			var chicken_fee: float = 8.0
			if has_winner and tile in related:
				chicken_fee *= 2.0
			for receiver in 4:
				if called[receiver]:
					_credit(matrix, owner, receiver, chicken_fee, burned)

	if has_winner:
		for target in winners:
			var target_seat := int(target)
			var player: PlayerState = round.players[target_seat]
			var pattern := RuleEngine.hand_pattern(player.concealed, player.melds, str(meta.get("win_tile", "")))
			# 所有费用先单倍计算，最后对矩阵统一应用倍率。
			var pattern_fee := _pattern_fee(pattern)
			var self_draw := bool(meta.get("self_draw", false))
			var robbed_kong := bool(meta.get("robbed_kong", false))
			var source := int(meta.get("discard_seat", -1))
			var base_payers: Array = []
			for payer in 4:
				if payer != target_seat and (self_draw or payer == source):
					base_payers.append(payer)
			if self_draw:
				var primary := pattern_fee
				if primary <= 0.0:
					if player.ready:
						primary = 0.0
					elif float(_chicken_values(round, target_seat, related).total) <= 0.0:
						var all_chickenless := true
						for other in 4:
							if float(chicken_values[other]) > 0.0:
								all_chickenless = false
								break
						primary = 24.0 if all_chickenless else 14.0
					else:
						primary = 4.0
				for payer in base_payers:
					var add := primary
					if player.ready:
						add += 20.0 if pattern_fee > 0.0 else 24.0
					elif round.players[payer].ready:
						add += 24.0
					_credit(matrix, payer, target_seat, add, burned)
			else:
				var kong_discard := not robbed_kong and _is_post_kong_discard(round.last_discard)
				var source_called := source >= 0 and source < 4 and RuleEngine.is_tenpai(round.players[source].concealed, round.players[source].melds)
				var base := 12.0 if robbed_kong else (17.0 if kong_discard and source_called else (21.0 if kong_discard else 0.0))
				if source in range(4) and base > 0.0:
					_credit(matrix, source, target_seat, base, burned)
				if player.ready:
					# 报听胡牌：点炮时只有点炮者支付
					if source in range(4) and source != target_seat:
						_credit(matrix, source, target_seat, 24.0, burned)
				elif source in range(4) and source != target_seat and round.players[source].ready:
					# 杀报：赢家未报听，报听者放炮单独支付24。
					_credit(matrix, source, target_seat, 24.0, burned)
				# 放炮牌型分只由放炮者支付；一炮多响时每位赢家
				# 分别向放炮者收取自己的牌型分，赢家之间不互付差额。
				if pattern_fee > 0.0 and source in range(4) and source != target_seat:
					_credit(matrix, source, target_seat, pattern_fee, burned)
				var own_kong: bool = player.melds.any(func(meld): return meld.kind == "add_kong" or (meld.kind == "kong" and meld.get("concealed", false)))
				if not robbed_kong and own_kong and pattern_fee <= 0.0 and not player.ready \
					and not pattern.get("all_triplets", false) and not pattern.get("seven_pairs", false) \
					and not pattern.get("dragon_seven_pairs", false) and not pattern.get("flush", false) \
					and source in range(4) and source != target_seat:
					_credit(matrix, source, target_seat, 4.0, burned)
			if self_draw and int(meta.get("kong_draw_seat", -1)) == target_seat:
				for payer in 4:
					if payer != target_seat:
						_credit(matrix, payer, target_seat, 5.0, burned)
			if self_draw and int(meta.get("last_four_self_draw_seat", -1)) == target_seat:
				for payer in 4:
					if payer != target_seat:
						_credit(matrix, payer, target_seat, 5.0, burned)

	var deltas := [0.0, 0.0, 0.0, 0.0]
	for seat in 4:
		for other in 4:
			deltas[seat] += float(matrix[seat][other])
	_apply_multiplier(matrix, deltas, multiplier)
	return {"pairwise": matrix, "deltas": deltas, "called": called, "chickens": chicken_values, "discard_chickens": discard_values}

static func _chicken_values(round: RoundState, seat: int, related: Array) -> Dictionary:
	var player: PlayerState = round.players[seat]
	var total := 0.0
	var discarded := 0.0
	var pung_debt := 0.0
	for index in player.discards.size():
		var tile := str(player.discards[index])
		if tile not in ["tiao1", "tong8"]:
			continue
		var id: int = player.discard_ids[index] if index < player.discard_ids.size() else index
		var record: Dictionary = round.round_meta.get("charge_chickens", {}).get(tile, {})
		var charge: bool = record.get("owner", -1) == seat and record.get("location", "") == "discard" and record.get("discard_id", -1) == id
		var amount := (4.0 if charge else 2.0) * (2.0 if tile in related else 1.0)
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
		var amount := (4.0 if charge else 2.0) * (2.0 if tile in related else 1.0)
		discarded += amount
		total += amount
	for tile_value in player.concealed:
		total += _held_chicken(str(tile_value), related)
	for meld in player.melds:
		var count := 3 if meld.kind == "pung" else 4
		if meld.kind == "pung" and str(meld.tile) in ["tiao1", "tong8"]:
			pung_debt += 2.0 * (2.0 if str(meld.tile) in related else 1.0) * 3.0
		for _index in count:
			total += _held_chicken(str(meld.tile), related)
	return {"total": 0.0 if seat == int(round.round_meta.get("burn_chicken_seat", -1)) else total, "discarded": 0.0 if seat == int(round.round_meta.get("burn_chicken_seat", -1)) else discarded, "debt": discarded, "pung_debt": pung_debt}

static func _held_chicken(tile: String, related: Array) -> float:
	if tile in ["tiao1", "tong8"]:
		return 2.0 * (2.0 if tile in related else 1.0)
	return 1.0 if tile in related else 0.0

static func _is_post_kong_discard(last_discard: Dictionary) -> bool:
	if not bool(last_discard.get("after_kong", false)):
		return false
	return int(last_discard.get("kong_kind", RoundState.KongKind.NONE)) in [RoundState.KongKind.CONCEALED, RoundState.KongKind.ADD_KONG]

static func _pattern_fee(pattern: Dictionary) -> float:
	if pattern.get("clean_dragon_seven_pairs", false): return 64.0
	if pattern.get("clean_single_wait", false): return 54.0
	if pattern.get("clean_seven_pairs", false): return 44.0
	if pattern.get("clean_big_triplets", false): return 34.0
	if pattern.get("big_triplet_single_wait", false): return 24.0
	if pattern.get("dragon_seven_pairs", false): return 44.0
	if pattern.get("seven_pairs", false): return 24.0
	if pattern.get("all_triplets", false): return 14.0
	if pattern.get("flush", false): return 24.0
	return 0.0


static func _apply_multiplier(matrix: Array, deltas: Array, multiplier: int) -> void:
	if multiplier <= 1:
		return
	for seat in 4:
		deltas[seat] *= multiplier
		for other in 4:
			matrix[seat][other] *= multiplier

static func _empty_matrix() -> Array:
	return [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]

static func _credit(matrix: Array, payer: int, receiver: int, amount: float, blocked_receiver: int = -1) -> void:
	if receiver == blocked_receiver or payer == receiver or amount <= 0.0:
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
