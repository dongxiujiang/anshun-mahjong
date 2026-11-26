extends RefCounted

const CFG := preload("res://src/anshun/scoring/RulesConfig.gd")
const RuleEngine := preload("res://src/anshun/scoring/RuleEngine.gd")
const Rules := preload("res://src/anshun/scoring/KongRules.gd")
const Ledger := preload("res://src/anshun/scoring/PaymentLedger.gd")

static func settle(ledger: Ledger, round: Dictionary, winner: int, chicken_totals: Array, called: Array) -> void:
	var meta: Dictionary = round.round_meta
	var player: Dictionary = round.players[winner]
	var self_draw: bool = meta.get("self_draw", false)
	var robbed_kong: bool = meta.get("robbed_kong", false)
	var source := int(meta.get("discard_seat", -1))
	var winning_tile := str(meta.get("win_tile", ""))
	var pattern := RuleEngine.hand_pattern(player.concealed, player.melds, winning_tile)
	var pattern_info := _pattern_info(pattern)
	var pattern_amount := float(pattern_info.get("score", 0.0))
	var payers: Array = []
	if self_draw:
		for seat in 4:
			if seat != winner:
				payers.append(seat)
	elif source in range(4) and source != winner:
		payers.append(source)
		if robbed_kong:
			ledger.award(payers, winner, CFG.SCORE_ROB_KONG, "抢杠胡基础分", "win")
		elif Rules.is_post_kong_discard(round.last_discard):
			var amount := CFG.SCORE_RON_CALLED if called[source] else CFG.SCORE_RON_UNCALLED
			var label := "点炮基础分（叫牌）" if called[source] else "点炮基础分（未叫牌）"
			ledger.award(payers, winner, amount, label, "win")
		if not robbed_kong and Rules.has_self_kong(player.melds) and pattern_amount == 0.0 and not player.ready:
			ledger.award(payers, winner, CFG.SCORE_KONG_SELF_RON, "通行证胡牌", "win")

	var both_ready: bool = not self_draw and player.ready and not payers.is_empty() and round.players[source].ready
	if pattern_amount > 0.0:
		var paid_pattern := pattern_amount - CFG.SCORE_SELF_DRAW if both_ready else pattern_amount
		var details := {"pattern": pattern_info.key, "tiles": [winning_tile], "tile_ids": [int(meta.get("win_tile_id", -1))]}
		ledger.award(payers, winner, paid_pattern, pattern_info.label, "pattern", details)
	if player.ready:
		var ready_amount := CFG.SCORE_READY_PATTERN if pattern_amount > 0.0 and not both_ready else CFG.SCORE_READY
		ledger.award(payers, winner, ready_amount, "报听胡牌", "ready")
		if both_ready:
			ledger.award(payers, winner, CFG.SCORE_READY_PATTERN, "输家报听", "ready")
	else:
		var ready_payers := payers.filter(func(seat): return round.players[seat].ready)
		var normal_payers := payers.filter(func(seat): return not round.players[seat].ready)
		var kill_amount := CFG.SCORE_KILL_READY - CFG.SCORE_SELF_DRAW if pattern_amount > 0.0 else CFG.SCORE_KILL_READY
		ledger.award(ready_payers, winner, kill_amount, "杀报", "ready")
		if self_draw and pattern_amount == 0.0:
			var dry: bool = pattern.win and chicken_totals[winner] == 0.0 and not Rules.has_kong(player.melds)
			if dry:
				var big_dry := true
				for other in 4:
					if other != winner and called[other] and (chicken_totals[other] > 0.0 or Rules.has_kong(round.players[other].melds)):
						big_dry = false
						break
				ledger.award(normal_payers, winner, CFG.SCORE_BIG_NO_CHICKEN if big_dry else CFG.SCORE_NO_CHICKEN,
					"大干扣" if big_dry else "干扣", "bonus")
			else:
				ledger.award(normal_payers, winner, CFG.SCORE_SELF_DRAW, "自摸基础分", "bonus")
	if self_draw and int(meta.get("kong_draw_seat", -1)) == winner:
		ledger.award(payers, winner, CFG.SCORE_KONG_DRAW, "杠开", "bonus")
	if self_draw and int(meta.get("last_four_self_draw_seat", -1)) == winner:
		ledger.award(payers, winner, CFG.SCORE_LAST_FOUR, "海底", "bonus")

static func best_wait_pattern(patterns: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for tile in patterns:
		var info := _pattern_info(patterns[tile])
		if float(info.get("score", 0.0)) > float(best.get("score", 0.0)):
			best = info.duplicate()
			best["tile"] = tile
	return best

static func _pattern_info(pattern: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	if not pattern.get("win", false):
		return best
	for spec in CFG.PATTERNS:
		if pattern.get(spec.key, false) and float(spec.score) > float(best.get("score", 0.0)):
			best = spec
	return best
