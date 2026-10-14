class_name ScoringEngine
## 四家鸡分、杠分和逐赢家胡牌费统一写入付款流水。
const CFG := preload("res://scripts/autoload/GameConfig.gd")
const SEAT_NAMES := ["庄家", "下家", "对家", "上家"]
const CHICKEN := preload("res://scripts/core/ChickenScoring.gd")
const KONG := preload("res://scripts/core/KongScoring.gd")
const WIN := preload("res://scripts/core/WinScoring.gd")
const PAY := preload("res://scripts/core/PaymentLedger.gd")

static func settle(round) -> Dictionary:
	var meta: Dictionary = round.round_meta
	var winner := int(meta.get("winner", -1))
	var winners: Array = _winner_seats(meta)
	var dealer := int(meta.get("dealer_seat", 0))
	var deltas := [0.0, 0.0, 0.0, 0.0]
	var points := [0.0, 0.0, 0.0, 0.0]
	var discard_points := [0.0, 0.0, 0.0, 0.0]
	var called_seats: Array = []
	var multiplier := clampi(int(meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	var lines: Array = []
	var transfers: Array = []
	var items: Array = [[], [], [], []]
	var status: Array = ["", "", "", ""]
	var flip := str(meta.get("flip_tile", "")) if winner >= 0 else ""
	var self_draw := bool(meta.get("self_draw", false))
	for seat in 4:
		var called := is_called(round, seat)
		called_seats.append(called)
		var profile := chicken_profile(round, seat, flip)
		points[seat] = float(profile.total) if called else 0.0
		# 荒牌结算也要保留未叫者本人的出牌鸡值，按要求由未叫者对叫牌者补付两边之和。
		discard_points[seat] = float(profile.discarded)
		for item in profile.raw_items:
			var source := str(item.get("source", ""))
			if source == "kong":
				continue
			if winner >= 0 and called or winner < 0 and source == "discard":
				items[seat].append(item.duplicate(true))
		if profile.burned:
			var burn_label := "杠后出牌烧鸡" if meta.get("burn_chicken_reason", "") == "after_kong_discard" else "抢杠烧鸡"
			lines.append("%s %s：鸡分 0" % [_nm(seat, dealer), burn_label])
			items[seat].append({"kind": "penalty", "label": burn_label, "tile": "", "tiles": [], "amount": 0.0, "note": "鸡分归零"})
		if winner < 0:
			lines.append("%s%s：出牌鸡 %.0f" % [_nm(seat, dealer), " 已叫牌" if called else " 未叫牌", discard_points[seat]])
		else:
			lines.append("%s%s：鸡分 %.0f，打出鸡 %.0f" % [_nm(seat, dealer), " 已叫牌" if called else " 未叫牌", points[seat], discard_points[seat]])
	if multiplier > 1:
		lines.append("本局鸡分 ×%d（不影响胡牌额外分、牌型和报听）" % multiplier)
	if flip != "":
		for tile in Tiles.flip_related(flip):
			if Tiles.is_chicken(tile):
				lines.append("翻中%s：金鸡普通鸡 4，冲锋鸡 8" % ("幺鸡" if tile == "tiao1" else "八筒"))
	if winner < 0:
		var all_called := called_seats.all(func(value): return value)
		var next_multiplier := 2 if all_called else 1
		if all_called:
			lines.append("四家叫牌流局，本局不计分；下局鸡分 ×2")
			items = [[], [], [], []]
		else:
			PAY.pay_uncalled(deltas, transfers, called_seats, discard_points)
			KONG.pay(round, deltas, transfers, called_seats, items, "", true)
			lines.append("荒牌：未叫者向每位叫牌者补付双方出牌鸡，并按规则补杠分")
		for seat in 4:
			status[seat] = _draw_status(seat, called_seats)
		return _result(deltas, lines, points, discard_points, called_seats, transfers, items, status, all_called, next_multiplier, winners)
	# 鸡分是全场逐对比较；胡牌费用则逐个赢家分别结算。
	PAY.compare_chickens(deltas, transfers, called_seats, points)
	for target in winners:
		WIN.settle_winner(round, int(target), points, winners, deltas, transfers, items, lines)
	KONG.pay(round, deltas, transfers, called_seats, items, flip, false)
	for seat in 4:
		status[seat] = _win_status(seat, winners, self_draw, int(meta.get("discard_seat", -1)), called_seats, round)
	return _result(deltas, lines, points, discard_points, called_seats, transfers, items, status, false, 1, winners)

static func _winner_seats(meta: Dictionary) -> Array:
	var winners: Array = meta.get("winners", []).duplicate()
	if winners.is_empty() and int(meta.get("winner", -1)) >= 0:
		winners.append(int(meta.winner))
	return winners

static func _result(deltas: Array, lines: Array, points: Array, discard_points: Array, called: Array, transfers: Array, items: Array, status: Array, all_called_draw: bool, next_multiplier: int, winners: Array) -> Dictionary:
	var round_points := [0.0, 0.0, 0.0, 0.0]
	for seat in 4:
		items[seat] = group_chicken_items(items[seat])
		for item in items[seat]:
			round_points[seat] += maxf(0.0, float(item.get("own_amount", item.get("amount", 0.0))))
	var pairs := pairwise_payments(transfers)
	return {"deltas": deltas, "lines": lines, "points": points, "round_points": round_points,
		"discard_points": discard_points, "called": called, "transfers": transfers, "pairwise": pairs,
		"items": items, "status": status, "winners": winners.duplicate(), "all_called_draw": all_called_draw, "next_chicken_multiplier": next_multiplier}

static func _win_status(seat: int, winners: Array, self_draw: bool, discard_seat: int, called: Array, round) -> String:
	if winners.has(seat):
		var player: PlayerState = round.players[seat]
		var pattern := RuleEngine.hand_pattern(player.concealed, player.melds, str(round.round_meta.get("win_tile", "")))
		var labels: Array[String] = []
		var special := RuleEngine.special_pattern_key(pattern)
		var key := special
		if key == "":
			if pattern.get("dragon_seven_pairs", false): key = "dragon_seven_pairs"
			elif pattern.get("seven_pairs", false): key = "seven_pairs"
			elif pattern.get("all_triplets", false): key = "all_triplets"
			elif pattern.get("flush", false): key = "flush"
		for raw in CFG.PATTERNS:
			var spec: Dictionary = raw
			if spec.get("key", "") == key:
				labels.append(str(spec.get("label", "")))
				break
		var how: String = "自摸" if self_draw else ("胡" + (["-", "下家", "对家", "上家"][posmod(discard_seat - seat, 4)] if discard_seat >= 0 and discard_seat < 4 else "点炮"))
		if round.round_meta.get("robbed_kong", false): how = "抢杠胡"
		return "叫牌（%s%s）" % [how, (" " + " ".join(labels)) if not labels.is_empty() else ""]
	var text := "叫牌" if called[seat] else "未叫牌"
	if round.players[seat].ready:
		text += " · 已报听"
	return text

static func _draw_status(seat: int, called: Array) -> String:
	return "叫牌" if called[seat] else "未叫牌"

static func is_called(round, seat: int) -> bool:
	var player: PlayerState = round.players[seat]
	if _winner_seats(round.round_meta).has(seat):
		return true
	return RuleEngine.is_tenpai(player.concealed, player.melds)

static func _nm(seat: int, dealer: int = 0) -> String:
	return SEAT_NAMES[posmod(seat - dealer, 4)] if seat >= 0 and seat < 4 else "-"

static func chicken_profile(round, seat: int, flip: String) -> Dictionary:
	return CHICKEN.chicken_profile(round, seat, flip)

static func group_chicken_items(items: Array) -> Array:
	return CHICKEN.group_chicken_items(items)

static func pairwise_payments(transfers: Array) -> Array:
	return PAY.pairwise_payments(transfers)

static func relative_payments(matrix: Array, seat: int) -> Array:
	return PAY.relative_payments(matrix, seat)
