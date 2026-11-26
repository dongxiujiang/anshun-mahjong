extends RefCounted

const CFG := preload("res://src/anshun/scoring/RulesConfig.gd")
const RuleEngine := preload("res://src/anshun/scoring/RuleEngine.gd")
const Chicken := preload("res://src/anshun/scoring/ChickenScoring.gd")
const Kong := preload("res://src/anshun/scoring/KongScoring.gd")
const Win := preload("res://src/anshun/scoring/WinScoring.gd")
const Ledger := preload("res://src/anshun/scoring/PaymentLedger.gd")

## round 由权威回合提供，结算只读取玩家和已裁决事实。
static func settle(round: Dictionary) -> Dictionary:
	var meta: Dictionary = round.round_meta
	var winners: Array = meta.get("winners", []).duplicate()
	if winners.is_empty() and int(meta.get("winner", -1)) >= 0:
		winners.append(int(meta.winner))
	var draw := winners.is_empty()
	var flip: String = "" if draw else meta.get("flip_tile", "")
	var called: Array = []
	var waits: Array = []
	var profiles: Array = []
	var chicken_totals: Array = []
	var burned := int(meta.get("burn_chicken_seat", -1))
	for seat in 4:
		var player: Dictionary = round.players[seat]
		var patterns := {} if winners.has(seat) else RuleEngine.settlement_patterns(player.concealed, player.melds)
		waits.append(patterns)
		var is_called := winners.has(seat) or not patterns.is_empty()
		called.append(is_called)
		var profile := Chicken.profile(round, seat, flip, is_called, draw)
		profiles.append(profile)
		chicken_totals.append(Chicken.total(profile))
	var ledger := Ledger.new(burned)
	for seat in 4:
		var opponents: Array = []
		for other in 4:
			if other != seat and _shares_chicken_payment(called, seat, other, draw, burned):
				opponents.append(other)
		for item in profiles[seat]:
			ledger.register(item, opponents)
	if draw:
		_settle_draw(ledger, called, profiles, waits)
	else:
		_settle_chickens(ledger, called, profiles, chicken_totals)
		for winner in winners:
			Win.settle(ledger, round, int(winner), chicken_totals, called)
	Kong.settle(ledger, round.players, called, draw)

	var multiplier := clampi(int(meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	var result := ledger.result(multiplier)
	result.merge({
		"called": called, "winners": winners, "burned_seat": burned,
		"status": called.map(func(value): return "叫牌" if value else "未叫牌"),
		"all_called_draw": draw and not called.has(false),
		"next_chicken_multiplier": CFG.MAX_CHICKEN_MULTIPLIER if draw else 1,
	})
	return result

static func _shares_chicken_payment(called: Array, owner: int, other: int, draw: bool, burned: int) -> bool:
	if called[owner]:
		return not draw or not called[other]
	return called[other] and other != burned

static func _settle_draw(ledger: Ledger, called: Array, profiles: Array, waits: Array) -> void:
	var uncalled: Array = []
	for seat in 4:
		if not called[seat]:
			uncalled.append(seat)
	for receiver in 4:
		if not called[receiver]:
			continue
		var pattern := Win.best_wait_pattern(waits[receiver])
		if pattern.is_empty():
			ledger.award(uncalled, receiver, CFG.SCORE_SELF_DRAW, "荒牌基础补付", "penalty")
		else:
			ledger.award(uncalled, receiver, pattern.score, "荒牌牌型分", "penalty",
				{"pattern": pattern.key, "pattern_label": pattern.label, "wait_tile": pattern.tile})
		var pack := _items_except_kongs(profiles[receiver])
		var kong_chickens := _by_source(profiles[receiver], "kong")
		for payer in uncalled:
			ledger.transfer(payer, receiver, "荒牌包鸡", pack + _items_except_kongs(profiles[payer]))
			ledger.transfer(payer, receiver, "杠中鸡", kong_chickens)
			ledger.transfer(payer, receiver, "未叫牌杠中鸡", _by_source(profiles[payer], "kong"))

static func _settle_chickens(ledger: Ledger, called: Array, profiles: Array, totals: Array) -> void:
	for first in 4:
		for second in range(first + 1, 4):
			if called[first] and called[second]:
				if totals[first] > totals[second]:
					ledger.transfer(second, first, "鸡分差额", profiles[first], profiles[second])
				elif totals[second] > totals[first]:
					ledger.transfer(first, second, "鸡分差额", profiles[second], profiles[first])
				continue
			if called[first] or called[second]:
				var receiver := first if called[first] else second
				var payer := second if called[first] else first
				ledger.transfer(payer, receiver, "鸡分差额", profiles[receiver])
				ledger.transfer(payer, receiver, "未叫牌出牌鸡", _by_source(profiles[payer], "discard"))
				ledger.transfer(payer, receiver, "未叫牌碰鸡", _by_source(profiles[payer], "meld"))
				ledger.transfer(payer, receiver, "未叫牌杠中鸡", _by_source(profiles[payer], "kong"))

static func _by_source(items: Array, source: String) -> Array:
	return items.filter(func(item): return item.source == source)

static func _items_except_kongs(items: Array) -> Array:
	return items.filter(func(item): return item.source != "kong")
