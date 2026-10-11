class_name ScoringEngine
## Called players compare chicken totals; uncalled players pay retained discard chickens.
const CFG := preload("res://scripts/autoload/GameConfig.gd")

static func settle(round) -> Dictionary:
	var meta: Dictionary = round.round_meta
	var winner: int = meta.get("winner", -1)
	var deltas := [0.0, 0.0, 0.0, 0.0]
	var points := [0.0, 0.0, 0.0, 0.0]
	var discard_points := [0.0, 0.0, 0.0, 0.0]
	var called_seats: Array = []
	var multiplier := clampi(int(meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	var lines: Array = []
	var transfers: Array = []
	var flip: String = meta.get("flip_tile", "") if winner >= 0 else ""
	var self_draw: bool = meta.get("self_draw", false)
	for seat in 4:
		var called := is_called(round, seat)
		called_seats.append(called)
		var profile := chicken_profile(round, seat, flip)
		if profile.burned:
			lines.append("%s 抢杠烧鸡：鸡分 0" % _nm(seat))
		points[seat] = profile.total if called else 0.0
		discard_points[seat] = profile.discarded if called else 0.0
		if winner < 0:
			lines.append("%s%s：保留出牌鸡 %.0f" % [_nm(seat), " 已叫牌" if called else " 未叫牌", discard_points[seat]])
		else:
			lines.append("%s%s：鸡分 %.0f，打出鸡 %.0f" % [_nm(seat), " 已叫牌" if called else " 未叫牌", points[seat], discard_points[seat]])
	if multiplier > 1:
		lines.append("本局鸡分 ×%d（不影响额外加分、牌型和报听）" % multiplier)
	if flip != "":
		for tile in Tiles.flip_related(flip):
			if Tiles.is_chicken(tile):
				lines.append("翻中%s：普通鸡 4，冲锋鸡 8" % ("幺鸡" if tile == "tiao1" else "八筒"))
	if winner < 0:
		var all_called := called_seats.all(func(value): return value)
		# A repeat all-called draw keeps the bonus at 2×; it never compounds.
		var next_multiplier := 2 if all_called else 1
		if all_called:
			lines.append("四家叫牌流局，本局不计分；下局鸡分 ×%d" % next_multiplier)
		else:
			_pay_uncalled(deltas, transfers, called_seats, discard_points)
			_pay_draw_kongs(round, deltas, transfers, called_seats)
			lines.append("牌墙摸完：未叫牌者补打出鸡及应付杠分；叫牌者之间不补差" if called_seats.has(true) else "四家均未叫牌，本局无人收取鸡分或杠分")
		return {"deltas": deltas, "lines": lines, "points": points, "discard_points": discard_points, "called": called_seats, "transfers": transfers, "all_called_draw": all_called, "next_chicken_multiplier": next_multiplier}
	var chicken_points := points.duplicate()
	if self_draw:
		points[winner] += CFG.SCORE_SELF_DRAW
		lines.append("自摸 +4")
	if meta.get("kong_draw_seat", -1) == winner:
		points[winner] += CFG.SCORE_KONG_DRAW
		lines.append("杠开 +9")
	if meta.get("last_four_self_draw_seat", -1) == winner:
		points[winner] += CFG.SCORE_LAST_FOUR
		lines.append("最后四张自摸 +9")
	if _no_chicken_hand(round.players[winner], flip):
		points[winner] += CFG.SCORE_NO_CHICKEN
		lines.append("无鸡 +14")
	for first in 4:
		for second in range(first + 1, 4):
			if not called_seats[first] or not called_seats[second]:
				continue
			var difference: float = chicken_points[first] - chicken_points[second]
			if difference > 0:
				_transfer(deltas, transfers, second, first, difference, "多退少补")
			elif difference < 0:
				_transfer(deltas, transfers, first, second, -difference, "多退少补")
	_pay_uncalled(deltas, transfers, called_seats, discard_points)
	var bonus: float = points[winner] - chicken_points[winner]
	for seat in 4:
		if seat != winner:
			_transfer(deltas, transfers, seat, winner, bonus, "胡牌额外加分")
	var pattern := RuleEngine.hand_pattern(round.players[winner].concealed, round.players[winner].melds)
	for item in [
		["seven_pairs", CFG.SCORE_SEVEN_PAIRS, "小七对"],
		["all_triplets", CFG.SCORE_BIG_SET if self_draw else CFG.SCORE_BIG_SET_DISCARD, "大队子"],
		["flush", CFG.SCORE_FLUSH, "清一色"],
	]:
		if pattern.get(item[0], false):
			_pay_win(deltas, transfers, winner, meta, float(item[1]), item[2])
			lines.append("%s：%s付 %.0f" % [item[2], "每家" if self_draw else _nm(meta.get("discard_seat", -1)), item[1]])
	var ready_payments := {}
	if round.players[winner].ready:
		for seat in 4:
			if seat != winner and (self_draw or seat == meta.get("discard_seat", -1)):
				ready_payments[seat] = true
		lines.append("报听胡牌：每名应付者付 24")
	# 被杀 means a declared-ready player loses to another player's win.
	for seat in 4:
		if seat != winner and round.players[seat].ready:
			ready_payments[seat] = true
			lines.append("%s 报听被杀：付 24" % _nm(seat))
	for payer in ready_payments:
		_transfer(deltas, transfers, payer, winner, CFG.SCORE_READY, "报听")
	return {"deltas": deltas, "lines": lines, "points": points, "discard_points": discard_points, "called": called_seats, "transfers": transfers, "all_called_draw": false, "next_chicken_multiplier": 1}

static func chicken_profile(round, seat: int, flip: String) -> Dictionary:
	var player: PlayerState = round.players[seat]
	var multiplier := clampi(int(round.round_meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	var related: Array = Tiles.flip_related(flip) if flip != "" else []
	var discarded := 0.0
	var held := 0.0
	var flipped := 0.0
	for index in player.discards.size():
		var tile: String = player.discards[index]
		if Tiles.is_chicken(tile):
			var base: float = CFG.SCORE_CHARGE_CHICKEN if round.is_charge_discard(seat, index) else CFG.SCORE_CALL_CHICKEN
			discarded += base * (CFG.SCORE_FLIP_DOUBLE if tile in related else 1.0)
	for tile in player.all_hand_tiles():
		if Tiles.is_chicken(tile):
			held += CFG.SCORE_CALL_CHICKEN * (CFG.SCORE_FLIP_DOUBLE if tile in related else 1.0)
		elif tile in related:
			flipped += CFG.SCORE_FLIP_CHICKEN
	# A claimed charge keeps its visual marker but scores as an ordinary chicken.
	# Every claimed chicken above therefore contributes two points per tile.
	var burned: bool = seat == round.round_meta.get("burn_chicken_seat", -1)
	if burned:
		discarded = 0.0
		held = 0.0
		flipped = 0.0
	return {"discarded": discarded * multiplier, "held": held * multiplier, "flipped": flipped * multiplier, "total": (discarded + held + flipped) * multiplier, "burned": burned}

static func _pay_uncalled(deltas: Array, transfers: Array, called: Array, discard_points: Array) -> void:
	for payer in 4:
		if called[payer]:
			continue
		for receiver in 4:
			if called[receiver]:
				_transfer(deltas, transfers, payer, receiver, discard_points[receiver], "未叫牌补打出鸡")

static func is_called(round, seat: int) -> bool:
	var player: PlayerState = round.players[seat]
	return round.round_meta.get("winner", -1) == seat or RuleEngine.is_tenpai(player.concealed, player.melds)

static func _pay_draw_kongs(round, deltas: Array, transfers: Array, called: Array) -> void:
	for receiver in 4:
		if not called[receiver]:
			continue
		for meld in round.players[receiver].melds:
			if meld.get("robbed", false) or meld.kind not in ["kong", "add_kong"]:
				continue
			# Each kong pays its four-point base plus two per chicken tile in the kong.
			var chicken_count := 4 if Tiles.is_chicken(str(meld.get("tile", ""))) else 0
			var amount: float = CFG.SCORE_DRAW_KONG + CFG.SCORE_CALL_CHICKEN * chicken_count
			if meld.kind == "add_kong" or meld.get("concealed", false):
				for payer in 4:
					if not called[payer]:
						_transfer(deltas, transfers, payer, receiver, amount, "查叫加杠" if meld.kind == "add_kong" else "查叫暗杠")
			else:
				var source := int(meld.get("from_seat", -1))
				if source >= 0 and source < 4 and not called[source]:
					_transfer(deltas, transfers, source, receiver, amount, "查叫明杠")

static func _no_chicken_hand(player: PlayerState, flip: String) -> bool:
	var related: Array = Tiles.flip_related(flip) if flip != "" else []
	for tile in player.all_hand_tiles():
		if Tiles.is_chicken(tile) or tile in related:
			return false
	return true

static func _pay_win(deltas: Array, transfers: Array, winner: int, meta: Dictionary, amount: float, reason: String) -> void:
	if meta.get("self_draw", false):
		for seat in 4:
			if seat != winner:
				_transfer(deltas, transfers, seat, winner, amount, reason)
	else:
		_transfer(deltas, transfers, int(meta.get("discard_seat", -1)), winner, amount, reason)

static func _transfer(deltas: Array, transfers: Array, payer: int, receiver: int, amount: float, reason: String) -> void:
	if payer < 0 or receiver < 0 or payer == receiver or amount <= 0:
		return
	deltas[payer] -= amount
	deltas[receiver] += amount
	transfers.append({"from": payer, "to": receiver, "amount": amount, "reason": reason})

static func _nm(seat: int) -> String:
	return ["庄家", "下家", "对家", "上家"][seat] if seat >= 0 and seat < 4 else "-"
