extends RefCounted
## 自摸/杠开/末四张/无鸡额外分，以及牌型和报听费用。
const CFG := preload("res://scripts/autoload/GameConfig.gd")
const PAY := preload("res://scripts/core/PaymentLedger.gd")
const SEAT_NAMES := ["庄家", "下家", "对家", "上家"]

static func bonuses(round, points: Array, items: Array, lines: Array, flip: String) -> void:
	var meta: Dictionary = round.round_meta
	var winner: int = meta.winner
	var self_draw: bool = meta.get("self_draw", false)
	if self_draw:
		points[winner] += CFG.SCORE_SELF_DRAW
		lines.append("自摸 +4")
		items[winner].append({"kind": "bonus", "label": "自摸", "tile": "", "tiles": [], "amount": CFG.SCORE_SELF_DRAW, "note": ""})
	if meta.get("kong_draw_seat", -1) == winner:
		points[winner] += CFG.SCORE_KONG_DRAW
		lines.append("杠开 +9")
		items[winner].append({"kind": "bonus", "label": "杠开", "tile": "", "tiles": [], "amount": CFG.SCORE_KONG_DRAW, "note": ""})
	if meta.get("last_four_self_draw_seat", -1) == winner:
		points[winner] += CFG.SCORE_LAST_FOUR
		lines.append("最后四张自摸 +9")
		items[winner].append({"kind": "bonus", "label": "最后四张自摸", "tile": "", "tiles": [], "amount": CFG.SCORE_LAST_FOUR, "note": ""})
	if _no_chicken_hand(round.players[winner], flip):
		points[winner] += CFG.SCORE_NO_CHICKEN
		lines.append("无鸡 +14")
		items[winner].append({"kind": "bonus", "label": "无鸡", "tile": "", "tiles": [], "amount": CFG.SCORE_NO_CHICKEN, "note": ""})

static func charges(round, deltas: Array, transfers: Array, items: Array, lines: Array) -> Dictionary:
	var meta: Dictionary = round.round_meta
	var winner: int = meta.winner
	var self_draw: bool = meta.get("self_draw", false)
	var dealer: int = meta.get("dealer_seat", 0)
	var pattern := RuleEngine.hand_pattern(round.players[winner].concealed, round.players[winner].melds, str(meta.get("win_tile", "")))
	var special := RuleEngine.special_pattern_key(pattern)
	for spec in CFG.PATTERNS:
		var p: Dictionary = spec
		var key: String = p.get("key", "")
		if special != "":
			if key != special:
				continue
		elif not pattern.get(key, false):
			continue
		var dragon: bool = p.has("dragon_flag") and pattern.get(str(p.get("dragon_flag", "")), false)
		var label: String = str(p.get("dragon_label", "")) if dragon else str(p.get("label", ""))
		var amount: float = float(p.get("dragon_self" if dragon else "self", 0.0)) if self_draw else float(p.get("dragon_discard" if dragon else "discard", 0.0))
		PAY.pay_win(deltas, transfers, winner, meta, amount, label)
		lines.append("%s：%s付 %.0f" % [label, "每家" if self_draw else _nm(meta.get("discard_seat", -1), dealer), amount])
		items[winner].append({"kind": "pattern", "label": label, "tile": "", "tiles": [], "amount": amount, "note": "每家付" if self_draw else "%s付" % _nm(meta.get("discard_seat", -1), dealer)})
	var ready_payments := {}
	if round.players[winner].ready:
		for seat in 4:
			if seat != winner and (self_draw or seat == meta.get("discard_seat", -1)):
				ready_payments[seat] = true
		lines.append("报听胡牌：每名应付者付 24")
		items[winner].append({"kind": "ready", "label": "报听胡牌", "tile": "", "tiles": [], "amount": CFG.SCORE_READY, "note": "每名应付者付"})
	# 被杀 means a declared-ready player loses to another player's win.
	for seat in 4:
		if seat != winner and round.players[seat].ready:
			ready_payments[seat] = true
			lines.append("%s 报听被杀：付 24" % _nm(seat, dealer))
			items[seat].append({"kind": "penalty", "label": "报听被杀", "tile": "", "tiles": [], "amount": -CFG.SCORE_READY, "note": "付给%s" % _nm(winner, dealer)})
	for payer in ready_payments:
		PAY.transfer(deltas, transfers, payer, winner, CFG.SCORE_READY, "报听")
	return pattern

static func _no_chicken_hand(player: PlayerState, flip: String) -> bool:
	var related: Array = Tiles.flip_related(flip) if flip != "" else []
	for tile in player.all_hand_tiles():
		if Tiles.is_chicken(tile) or tile in related:
			return false
	return true

static func _nm(seat: int, dealer: int = 0) -> String:
	return SEAT_NAMES[posmod(seat - dealer, 4)] if seat >= 0 and seat < 4 else "-"
