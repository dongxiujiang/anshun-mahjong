extends RefCounted
## 测试用独立核账：从实体牌及规则数值计算，不读取计分条目或转账流水。
## 胡牌判型共用 RuleEngine；鸡分、付款范围和六对差额独立计算。

static func expected(round: RoundState) -> Dictionary:
	var meta: Dictionary = round.round_meta
	var winner := int(meta.get("winner", -1))
	var multiplier := clampi(int(meta.get("chicken_multiplier", 1)), 1, 2)
	var related: Array = []
	var flip := str(meta.get("flip_tile", "")) if winner >= 0 else ""
	if not flip.is_empty():
		var rank := Tiles.rank(flip)
		for offset in [-1, 0, 1]:
			related.append(Tiles.suit(flip) + str(posmod(rank - 1 + offset, 9) + 1))
	var called: Array = []
	var chickens: Array = []
	var draw_chickens: Array = []
	var matrix := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
	for seat in 4:
		var player: PlayerState = round.players[seat]
		called.append(seat == winner or RuleEngine.is_tenpai(player.concealed, player.melds))
		var complete := 0.0
		var draw_points := 0.0
		if called[seat] and seat != int(meta.get("burn_chicken_seat", -1)):
			for index in player.discards.size():
				var tile := str(player.discards[index])
				if tile not in ["tiao1", "tong8"]: continue
				var charge: Dictionary = meta.get("charge_chickens", {}).get(tile, {})
				var discard_id: int = player.discard_ids[index] if index < player.discard_ids.size() else index
				var first: bool = charge.get("owner", -1) == seat and charge.get("location", "") == "discard" and charge.get("discard_id", -1) == discard_id
				var base: float = (4.0 if first else 2.0) * multiplier
				draw_points += base
				complete += base * (2.0 if tile in related else 1.0)
			var held: Array = player.concealed.duplicate()
			for meld in player.melds:
				var count := 3 if meld.kind == "pung" else 4
				for _index in count: held.append(meld.tile)
				if meld.kind != "pung" and not meld.get("robbed", false) and meld.tile in ["tiao1", "tong8"]:
					draw_points += 8.0 * multiplier
			for tile in held:
				if tile in ["tiao1", "tong8"]:
					complete += (4.0 if tile in related else 2.0) * multiplier
				elif tile in related:
					complete += multiplier
		chickens.append(complete)
		draw_chickens.append(draw_points)
	# 正数表示本座位向对方收取；每一对只计算一个差额。
	for first in 4:
		for second in range(first + 1, 4):
			if winner >= 0:
				matrix[first][second] = chickens[first] - chickens[second]
			elif called[first] != called[second]:
				matrix[first][second] = draw_chickens[first] if called[first] else -draw_chickens[second]
			matrix[second][first] = -matrix[first][second]
	# 杠基础4独立定向，流局只向未叫牌者收；四家叫牌的流局不收费。
	for receiver in 4:
		if not called[receiver]: continue
		for meld in round.players[receiver].melds:
			if meld.kind == "pung" or meld.get("robbed", false): continue
			var own: bool = meld.kind == "add_kong" or meld.get("concealed", false)
			for payer in 4:
				if payer == receiver or (winner < 0 and called[payer]): continue
				if own or payer == int(meld.get("from_seat", -1)):
					matrix[receiver][payer] += 4.0
					matrix[payer][receiver] -= 4.0
	if winner >= 0:
		var player: PlayerState = round.players[winner]
		var all_tiles: Array = player.concealed.duplicate()
		for meld in player.melds: all_tiles.append(meld.tile)
		var bonus := 4.0 if meta.get("self_draw", false) else 0.0
		if int(meta.get("kong_draw_seat", -1)) == winner: bonus += 9.0
		if int(meta.get("last_four_self_draw_seat", -1)) == winner: bonus += 9.0
		if not all_tiles.any(func(tile): return tile in ["tiao1", "tong8"] or tile in related): bonus += 14.0
		var pattern := RuleEngine.hand_pattern(player.concealed, player.melds, str(meta.get("win_tile", "")))
		var pattern_points := 0.0
		if pattern.get("clean_dragon_seven_pairs", false): pattern_points = 88.0
		elif pattern.get("clean_single_wait", false): pattern_points = 54.0
		elif pattern.get("clean_big_triplets", false): pattern_points = 34.0
		else:
			if pattern.get("seven_pairs", false): pattern_points += 44.0 if pattern.get("dragon_seven_pairs", false) else 24.0
			if pattern.get("all_triplets", false): pattern_points += 14.0
			if pattern.get("flush", false): pattern_points += 24.0
		for payer in 4:
			if payer == winner: continue
			var win_payer: bool = meta.get("self_draw", false) or payer == int(meta.get("discard_seat", -1))
			var fee: float = bonus + (pattern_points if win_payer else 0.0)
			if (player.ready and win_payer) or round.players[payer].ready: fee += 24.0
			matrix[winner][payer] += fee
			matrix[payer][winner] -= fee
	var deltas := [0.0, 0.0, 0.0, 0.0]
	for seat in 4:
		for amount in matrix[seat]: deltas[seat] += float(amount)
	return {"pairwise": matrix, "deltas": deltas, "called": called, "chickens": chickens}

static func check(round: RoundState, result: Dictionary, harness, label: String) -> void:
	var reference := expected(round)
	# 实际对局的 build_result() 沿用网络格式，不含 settle() 内部的 called 字段。
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
