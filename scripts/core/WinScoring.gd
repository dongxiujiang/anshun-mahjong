extends RefCounted
## 计算单个赢家的牌型、自摸、报听和特殊摸牌得分。
const CFG := preload("res://scripts/autoload/GameConfig.gd")
const PAY := preload("res://scripts/core/PaymentLedger.gd")
const ACTIONS := preload("res://scripts/core/LegalActions.gd")
const SEAT_NAMES := ["庄家", "上家", "对家", "下家"]

static func settle_winner(round, winner: int, chicken_points: Array, called_seats: Array, deltas: Array, transfers: Array, items: Array, lines: Array) -> Dictionary:
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
	if not self_draw:
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
		# 赢家自带暗杠/加杠时，普通小牌胡别人弃牌额外收 4 分。
		# 大对子、七对、清一色、报听及以上牌型不再加这笔小牌放炮分。
		if not robbed_kong and source in range(4) and source != winner \
			and ACTIONS.has_self_kong(player) and pattern_amount <= 0.0 and not player.ready \
			and RuleEngine.special_pattern_key(pattern) == "" \
			and not pattern.get("all_triplets", false) and not pattern.get("seven_pairs", false) \
			and not pattern.get("dragon_seven_pairs", false) and not pattern.get("flush", false):
			PAY.transfer(deltas, transfers, source, winner, CFG.SCORE_KONG_SELF_RON, "通行证胡牌")
			items[winner].append(_item("win", "通行证胡牌", CFG.SCORE_KONG_SELF_RON, "放炮者支付"))
			lines.append("通行证胡牌：%s付 %.0f" % [_nm(source, int(meta.get("dealer_seat", 0))), CFG.SCORE_KONG_SELF_RON])

	var dry_label := ""
	var dry_amount := 0.0
	if pattern.get("win", false) and chicken_points[winner] == 0.0 and not _has_any_kong(player):
		var big_dry := true
		for other in 4:
			if other != winner and called_seats[other] and (chicken_points[other] > 0.0 or _has_any_kong(round.players[other])):
				big_dry = false
				break
		dry_label = "大干扣" if big_dry else "干扣"
		dry_amount = CFG.SCORE_BIG_NO_CHICKEN if big_dry else CFG.SCORE_NO_CHICKEN

	# 含基础4的项目逐付款人合并。双方报听点炮时保留原有的24与20两条流水。
	var both_ready: bool = not self_draw and player.ready and source in range(4) and source != winner and round.players[source].ready
	var has_primary := pattern_amount > 0.0 or dry_amount > 0.0
	var pattern_paid := pattern_amount - CFG.SCORE_SELF_DRAW if both_ready and pattern_amount > 0.0 else pattern_amount
	var dry_paid := dry_amount - CFG.SCORE_SELF_DRAW if dry_amount > 0.0 and (pattern_amount > 0.0 or both_ready) else dry_amount
	var ready_paid := CFG.SCORE_READY_PATTERN if has_primary and not both_ready else CFG.SCORE_READY
	var kill_paid := CFG.SCORE_KILL_READY - CFG.SCORE_SELF_DRAW if has_primary else CFG.SCORE_KILL_READY
	var has_payer := false
	var ordinary_draw_paid := false
	var dealer := int(meta.get("dealer_seat", 0))
	for payer in 4:
		if payer == winner or (not self_draw and payer != source):
			continue
		has_payer = true
		PAY.transfer(deltas, transfers, payer, winner, pattern_paid, pattern_label)
		PAY.transfer(deltas, transfers, payer, winner, dry_paid, dry_label)
		if player.ready:
			PAY.transfer(deltas, transfers, payer, winner, ready_paid, "报听胡牌")
			if both_ready:
				PAY.transfer(deltas, transfers, payer, winner, CFG.SCORE_READY_PATTERN, "输家报听")
		elif round.players[payer].ready:
			PAY.transfer(deltas, transfers, payer, winner, kill_paid, "杀报")
			items[winner].append(_item("ready", "杀报", kill_paid, "%s报听，单独支付" % _nm(payer, dealer)))
			lines.append("杀报：%s付 %.0f" % [_nm(payer, dealer), kill_paid])
		elif self_draw and not has_primary:
			PAY.transfer(deltas, transfers, payer, winner, CFG.SCORE_SELF_DRAW, "自摸基础分")
			ordinary_draw_paid = true
	if has_payer:
		var payer_note := "其余每家付" if self_draw else "%s付" % _nm(source, dealer)
		if pattern_paid > 0.0:
			items[winner].append(_item("pattern", pattern_label, pattern_paid, payer_note))
			lines.append("%s：%s %.0f" % [pattern_label, payer_note, pattern_paid])
		if dry_paid > 0.0:
			items[winner].append(_item("bonus", dry_label, dry_paid, payer_note))
			lines.append("%s：%s %.0f" % [dry_label, payer_note, dry_paid])
		if player.ready:
			items[winner].append(_item("ready", "报听胡牌", ready_paid, payer_note))
			lines.append("报听胡牌：%s %.0f" % [payer_note, ready_paid])
			if both_ready:
				items[winner].append(_item("ready", "输家报听", CFG.SCORE_READY_PATTERN, "放炮者也报听，另补"))
				lines.append("输家报听：%s %.0f" % [payer_note, CFG.SCORE_READY_PATTERN])
		if ordinary_draw_paid:
			items[winner].append(_item("bonus", "自摸", CFG.SCORE_SELF_DRAW, "未报听玩家支付"))
			lines.append("自摸基础分：未报听玩家各付 %.0f" % CFG.SCORE_SELF_DRAW)

	if self_draw and int(meta.get("kong_draw_seat", -1)) == winner:
		_apply_extra(winner, CFG.SCORE_KONG_DRAW, "杠开", deltas, transfers, items, lines)
	if self_draw and int(meta.get("last_four_self_draw_seat", -1)) == winner:
		_apply_extra(winner, CFG.SCORE_LAST_FOUR, "海底捞", deltas, transfers, items, lines)
	return pattern

static func _apply_extra(winner: int, amount: float, label: String, deltas: Array, transfers: Array, items: Array, lines: Array) -> void:
	for payer in 4:
		if payer != winner:
			PAY.transfer(deltas, transfers, payer, winner, amount, label)
	items[winner].append(_item("bonus", label, amount, ""))
	lines.append("%s +%.0f" % [label, amount])

## 流局补付：叫牌玩家可能听多张，取所有和牌张里最高的牌型。
static func potential_pattern_info(concealed: Array, melds: Array) -> Dictionary:
	var best: Dictionary = {}
	for tile in RuleEngine.waiting_tiles(concealed, melds):
		var info := _pattern_info(RuleEngine.analyze(concealed + [tile], melds, tile))
		if float(info.get("score", 0.0)) > float(best.get("score", 0.0)):
			best = info.duplicate()
			best["tile"] = tile
	return best

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

static func _has_any_kong(player) -> bool:
	for meld in player.melds:
		if str(meld.get("kind", "")) in ["kong", "add_kong"]:
			return true
	return false
