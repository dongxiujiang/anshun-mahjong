extends RefCounted
## 计算单个赢家的牌型、自摸、报听和特殊摸牌得分。
const CFG := preload("res://scripts/autoload/GameConfig.gd")
const PAY := preload("res://scripts/core/PaymentLedger.gd")
const CHICKEN := preload("res://scripts/core/ChickenScoring.gd")
const SEAT_NAMES := ["庄家", "下家", "对家", "上家"]

static func settle_winner(round, winner: int, chicken_points: Array, winner_seats: Array, deltas: Array, transfers: Array, items: Array, lines: Array) -> Dictionary:
	var meta: Dictionary = round.round_meta
	var player: PlayerState = round.players[winner]
	var self_draw: bool = bool(meta.get("self_draw", false))
	var robbed_kong: bool = bool(meta.get("robbed_kong", false))
	var source := int(meta.get("discard_seat", -1))
	var pattern := RuleEngine.hand_pattern(player.concealed, player.melds, str(meta.get("win_tile", "")))
	var pattern_info := _pattern_info(pattern)
	var pattern_amount: float = float(pattern_info.get("score", 0.0))
	var pattern_label := str(pattern_info.get("label", ""))
	var ready_primary := false
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
			if player.ready:
				primary_amount = CFG.SCORE_READY
				primary_label = "报听胡牌"
				ready_primary = true
				items[winner].append(_item("ready", primary_label, primary_amount, "含自摸基础4分"))
			elif CHICKEN.chicken_profile(round, winner, str(meta.get("flip_tile", ""))).total == 0.0:
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
		if pattern_amount > 0.0:
			items[winner].append(_item("pattern", pattern_label, pattern_amount, "牌型分含基础4分"))
		for payer in base_payers:
			PAY.transfer(deltas, transfers, payer, winner, primary_amount, primary_label)
		lines.append("%s：每家付 %.0f" % [primary_label, primary_amount])
	else:
		# 点炮和抢杠胡均由来源玩家单独支付基础费；牌型分另行计入。
		var source_called: bool = source >= 0 and source < round.players.size() and RuleEngine.is_tenpai(round.players[source].concealed, round.players[source].melds)
		var base_amount: float = CFG.SCORE_ROB_KONG if robbed_kong else (CFG.SCORE_RON_CALLED if source_called else CFG.SCORE_RON_UNCALLED)
		var base_label: String = "抢杠胡基础分" if robbed_kong else ("点炮基础分（叫牌）" if base_amount == CFG.SCORE_RON_CALLED else "点炮基础分（未叫牌）")
		if source in range(4):
			PAY.transfer(deltas, transfers, source, winner, base_amount, base_label)
		items[winner].append(_item("win", base_label, base_amount, "由放炮/被抢杠者单独支付"))
		lines.append("%s：%s付 %.0f" % [base_label, _nm(source, int(meta.get("dealer_seat", 0))), base_amount])
		if pattern_amount <= 0.0 and player.ready:
			pattern_amount = CFG.SCORE_READY
			pattern_label = "报听胡牌"
			ready_primary = true
		if pattern_amount > 0.0:
			PAY.transfer(deltas, transfers, source, winner, pattern_amount, pattern_label)
			items[winner].append(_item("pattern", pattern_label, pattern_amount, "牌型分另计"))
			lines.append("%s：%s另付 %.0f" % [pattern_label, _nm(source, int(meta.get("dealer_seat", 0))), pattern_amount])

	var ready_extra_recorded := false
	for payer in 4:
		if payer == winner:
			continue
		var base_payer: bool = base_payers.has(payer)
		var kills_ready: bool = bool(round.players[payer].ready and not winner_seats.has(payer) and base_payer)
		var winner_ready_fee: bool = bool(player.ready and pattern_info.get("key", "") != "" and base_payer)
		if kills_ready or (winner_ready_fee and not ready_primary):
			PAY.transfer(deltas, transfers, payer, winner, CFG.SCORE_READY, "杀报" if kills_ready else "报听")
			if kills_ready:
				items[payer].append({"kind": "penalty", "label": "杀报", "tile": "", "tiles": [], "amount": -CFG.SCORE_READY, "note": "付给%s" % _nm(winner, int(meta.get("dealer_seat", 0)))})
				lines.append("%s 杀报：付给%s %.0f" % [_nm(payer, int(meta.get("dealer_seat", 0))), _nm(winner, int(meta.get("dealer_seat", 0))), CFG.SCORE_READY])
			else:
				ready_extra_recorded = true
	if ready_extra_recorded:
		items[winner].append(_item("ready", "报听胡牌", CFG.SCORE_READY, "牌型分外加"))
		lines.append("报听胡牌：牌型分外加 %.0f" % CFG.SCORE_READY)
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
