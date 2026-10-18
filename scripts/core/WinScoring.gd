extends RefCounted
## 计算单个赢家的牌型、自摸、报听和特殊摸牌得分。
const CFG := preload("res://scripts/autoload/GameConfig.gd")
const PAY := preload("res://scripts/core/PaymentLedger.gd")
const CHICKEN := preload("res://scripts/core/ChickenScoring.gd")
const ACTIONS := preload("res://scripts/core/LegalActions.gd")
const SEAT_NAMES := ["庄家", "下家", "对家", "上家"]

static func settle_winner(round, winner: int, chicken_points: Array, winner_seats: Array, deltas: Array, transfers: Array, items: Array, lines: Array) -> Dictionary:
	var meta: Dictionary = round.round_meta
	var player: PlayerState = round.players[winner]
	var self_draw: bool = bool(meta.get("self_draw", false))
	var robbed_kong: bool = bool(meta.get("robbed_kong", false))
	var source := int(meta.get("discard_seat", -1))
	var pattern := RuleEngine.hand_pattern(player.concealed, player.melds, str(meta.get("win_tile", "")))
	if winner == int(meta.get("burn_chicken_seat", -1)):
		return pattern
	var pattern_info := _pattern_info(pattern)
	var pattern_amount: float = float(pattern_info.get("score", 0.0))
	var pattern_label := str(pattern_info.get("label", ""))
	var base_payers: Array = []
	for payer in 4:
		if payer == winner:
			continue
		if self_draw or payer == source:
			base_payers.append(payer)

	if self_draw:
		var primary_amount: float = pattern_amount
		var primary_label := pattern_label
		if primary_amount <= 0.0:
			if not player.ready:
				if CHICKEN.chicken_profile(round, winner, str(meta.get("flip_tile", ""))).total == 0.0:
					# 大干扣按最终参与比较的四家鸡分判断；未叫牌者的结算鸡分为 0。
					var all_chickenless := true
					for other in 4:
						if float(chicken_points[other]) > 0.0:
							all_chickenless = false
							break
					primary_amount = CFG.SCORE_BIG_NO_CHICKEN if all_chickenless else CFG.SCORE_NO_CHICKEN
					primary_label = "大干扣" if all_chickenless else "干扣"
					items[winner].append(_item("bonus", primary_label, primary_amount, "含自摸基础4分"))
				else:
					primary_amount = CFG.SCORE_SELF_DRAW
					primary_label = "自摸基础分"
					items[winner].append(_item("bonus", "自摸", primary_amount, ""))
			# 报听自摸的普通牌只收 24 + 鸡，不再另收自摸 4。
		if pattern_amount > 0.0:
			items[winner].append(_item("pattern", pattern_label, pattern_amount, "牌型分含基础4分"))
		if primary_amount > 0.0:
			for payer in base_payers:
				PAY.transfer(deltas, transfers, payer, winner, primary_amount, primary_label)
			lines.append("%s：每家付 %.0f" % [primary_label, primary_amount])
		if player.ready:
			for payer in base_payers:
				PAY.transfer(deltas, transfers, payer, winner, CFG.SCORE_READY, "报听胡牌")
			items[winner].append(_item("ready", "报听胡牌", CFG.SCORE_READY, "另加报听分，三家各付"))
			lines.append("报听胡牌：每家另付 %.0f" % CFG.SCORE_READY)
	else:
		# 非自摸胡分成三类：抢杠胡、暗/加杠后的单次放炮，以及
		# 报听/大牌胡。普通弃牌不再产生点炮基础分。
		var kong_discard := not robbed_kong and ACTIONS.is_post_kong_discard(round.last_discard)
		var source_called: bool = source >= 0 and source < round.players.size() and RuleEngine.is_tenpai(round.players[source].concealed, round.players[source].melds)
		var base_amount: float = CFG.SCORE_ROB_KONG if robbed_kong else (CFG.SCORE_RON_CALLED if kong_discard and source_called else (CFG.SCORE_RON_UNCALLED if kong_discard else 0.0))
		var base_label := "抢杠胡基础分" if robbed_kong else ("点炮基础分（叫牌）" if base_amount == CFG.SCORE_RON_CALLED else "点炮基础分（未叫牌）")
		if source in range(4):
			PAY.transfer(deltas, transfers, source, winner, base_amount, base_label)
		if base_amount > 0.0:
			items[winner].append(_item("win", base_label, base_amount, "由杠后放炮/被抢杠者单独支付"))
			lines.append("%s：%s付 %.0f" % [base_label, _nm(source, int(meta.get("dealer_seat", 0))), base_amount])

		# 报听胡：点炮时只有点炮者支付；牌型分也只由放炮者支付。
		# 其他两家只按幺鸡八筒、杠分、翻鸡分参与两两比较。
		if player.ready:
			# 报听胡牌：点炮时只有点炮者支付
			if source in range(4) and source != winner:
				PAY.transfer(deltas, transfers, source, winner, CFG.SCORE_READY, "报听胡牌")
				items[winner].append(_item("ready", "报听胡牌", CFG.SCORE_READY, "点炮者支付"))
				lines.append("报听胡牌：%s付 %.0f" % [_nm(source, int(meta.get("dealer_seat", 0))), CFG.SCORE_READY])
		if pattern_amount > 0.0:
			# 放炮牌型分只由放炮者支付；一炮多响时，放炮者向每位赢家
			# 分别支付各自的牌型分。其他两家不付牌型分。
			if source in range(4) and source != winner:
				PAY.transfer(deltas, transfers, source, winner, pattern_amount, pattern_label)
				items[winner].append(_item("pattern", pattern_label, pattern_amount, "放炮者支付"))
				lines.append("%s：%s付 %.0f" % [
					pattern_label,
					_nm(source, int(meta.get("dealer_seat", 0))),
					pattern_amount
				])
	if self_draw and int(meta.get("kong_draw_seat", -1)) == winner:
		_apply_extra(round, winner, CFG.SCORE_KONG_DRAW, "杠开", chicken_points, winner_seats, deltas, transfers, items, lines)
	if self_draw and int(meta.get("last_four_self_draw_seat", -1)) == winner:
		_apply_extra(round, winner, CFG.SCORE_LAST_FOUR, "海底捞", chicken_points, winner_seats, deltas, transfers, items, lines)
	return pattern

static func _apply_extra(round, winner: int, amount: float, label: String, _chicken_points: Array, _winner_seats: Array, deltas: Array, transfers: Array, items: Array, lines: Array) -> void:
	for payer in 4:
		if payer != winner:
			PAY.transfer(deltas, transfers, payer, winner, amount, label)
	items[winner].append(_item("bonus", label, amount, ""))
	lines.append("%s +%.0f" % [label, amount])

static func _pattern_info(pattern: Dictionary) -> Dictionary:
	var key := RuleEngine.special_pattern_key(pattern)
	if key == "":
		if pattern.get("dragon_seven_pairs", false):
			key = "dragon_seven_pairs"
		elif pattern.get("seven_pairs", false):
			key = "seven_pairs"
		elif pattern.get("all_triplets", false):
			key = "all_triplets"
		elif pattern.get("flush", false):
			key = "flush"
	if key == "":
		return {}
	for raw in CFG.PATTERNS:
		var spec: Dictionary = raw
		if spec.get("key", "") == key:
			return {"key": key, "label": str(spec.get("label", "")), "score": float(spec.get("score", 0.0))}
	return {}

static func _item(kind: String, label: String, amount: float, note: String) -> Dictionary:
	return {"kind": kind, "label": label, "tile": "", "tiles": [], "amount": amount, "note": note}

static func _nm(seat: int, dealer: int = 0) -> String:
	return SEAT_NAMES[posmod(seat - dealer, 4)] if seat >= 0 and seat < 4 else "-"
