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
	var pong_points := [0.0, 0.0, 0.0, 0.0]
	var pong_debt_points := [0.0, 0.0, 0.0, 0.0]
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
		# 未叫牌不把手中/碰杠中的鸡算作正分；其已打出的鸡记为
		# 负分，和叫牌者逐家比较后由未叫者补付。
		var discard_debt := float(profile.get("discard_debt", profile.discarded))
		var pong_debt := float(profile.get("pung_debt", 0.0))
		points[seat] = float(profile.total) if called else -(discard_debt + pong_debt)
		# 荒牌结算保留未叫者本人的出牌鸡值；另由荒牌补付逻辑加入基础4分。
		discard_points[seat] = float(profile.discarded) if called else discard_debt
		# compare_chickens uses the uncalled-only debt; the draw package
		# (pay_uncalled) needs both sides' pong chickens.
		pong_points[seat] = pong_debt if not called else 0.0
		pong_debt_points[seat] = pong_debt
		for item in profile.raw_items:
			var source := str(item.get("source", ""))
			if source == "kong":
				continue
			if winner >= 0 and called or winner < 0 and source == "discard":
				items[seat].append(item.duplicate(true))
		if not called and discard_debt > 0.0:
			items[seat].append({"kind": "penalty", "label": "未叫牌出牌鸡", "tile": "", "tiles": [],
				"amount": -discard_debt, "own_amount": -discard_debt, "note": "需补付给叫牌玩家"})
		if not called and pong_debt > 0.0:
			items[seat].append({"kind": "penalty", "label": "未叫牌碰鸡", "tile": "", "tiles": [],
				"amount": -pong_debt, "own_amount": -pong_debt, "note": "需补付给叫牌玩家"})
		if profile.burned:
			var burn_label := "杠后出牌烧鸡" if meta.get("burn_chicken_reason", "") == "after_kong_discard" else "抢杠烧鸡"
			lines.append("%s %s：鸡分 0" % [_nm(seat, dealer), burn_label])
			items[seat].append({"kind": "penalty", "label": burn_label, "tile": "", "tiles": [], "amount": 0.0, "note": "鸡分归零"})
		if winner < 0:
			lines.append("%s%s：出牌鸡 %.0f" % [_nm(seat, dealer), " 已叫牌" if called else " 未叫牌", discard_points[seat]])
		else:
			lines.append("%s%s：鸡分 %.0f，打出鸡 %.0f" % [_nm(seat, dealer), " 已叫牌" if called else " 未叫牌", points[seat], discard_points[seat]])
	if multiplier > 1:
		lines.append("以下项目按单倍计算；所有收付求和后统一 ×%d（含杠分、报听费和额外分）" % multiplier)
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
			PAY.pay_uncalled(deltas, transfers, called_seats, discard_points, true, pong_debt_points)
			for payer in 4:
				if called_seats[payer]:
					continue
				var called_count := 0
				for receiver in 4:
					if called_seats[receiver]:
						called_count += 1
				if called_count > 0:
					var huang_amount := CFG.SCORE_SELF_DRAW * called_count
					items[payer].append({"kind": "penalty", "label": "荒牌基础补付", "tile": "", "tiles": [],
						"amount": -huang_amount, "own_amount": -huang_amount, "note": "未叫牌补给叫牌玩家"})
			KONG.pay(round, deltas, transfers, called_seats, items, "", true)
			_pay_uncalled_kong_income(round, called_seats, deltas, transfers)
			lines.append("荒牌：未叫者向每位叫牌者补付双方出牌鸡、基础4分，并按规则补杠分")
		for seat in 4:
			status[seat] = _draw_status(seat, called_seats)
		return _result(deltas, lines, points, discard_points, called_seats, transfers, items, status, all_called, next_multiplier, winners, multiplier)
	# 鸡分是全场逐对比较；胡牌费用则逐个赢家分别结算。
	PAY.compare_chickens(deltas, transfers, called_seats, points, discard_points, pong_points)
	for target in winners:
		WIN.settle_winner(round, int(target), points, winners, deltas, transfers, items, lines)
	KONG.pay(round, deltas, transfers, called_seats, items, flip, false)
	_pay_uncalled_kong_income(round, called_seats, deltas, transfers)
	# §十五：烧鸡取消本局所有收入，也包括未叫者补付的出牌鸡和杠分。
	# 统一在账本边界移除该座位的入账，保留其支出，并同步修正双方净值。
	PAY.cancel_income(deltas, transfers, int(meta.get("burn_chicken_seat", -1)))
	for seat in 4:
		status[seat] = _win_status(seat, winners, self_draw, int(meta.get("discard_seat", -1)), called_seats, round)
	return _result(deltas, lines, points, discard_points, called_seats, transfers, items, status, false, 1, winners, multiplier)

static func _pay_uncalled_kong_income(round, called: Array, deltas: Array, transfers: Array) -> void:
	# 未叫牌杠主不能作为收款的杠主；其基础杠分反向支付给叫牌者，
	# 让叫牌杠主仍能收到自己的基础4分。
	for owner in 4:
		if called[owner] or owner == int(round.round_meta.get("burn_chicken_seat", -1)):
			continue
		for meld in round.players[owner].melds:
			if meld.get("robbed", false) or meld.get("kind", "") not in ["kong", "add_kong"]:
				continue
			for payer in 4:
				if payer == owner or not called[payer] or payer == int(round.round_meta.get("burn_chicken_seat", -1)):
					continue
				PAY.transfer(deltas, transfers, owner, payer, CFG.SCORE_DRAW_KONG, "未叫牌杠分")

static func _winner_seats(meta: Dictionary) -> Array:
	var winners: Array = meta.get("winners", []).duplicate()
	if winners.is_empty() and int(meta.get("winner", -1)) >= 0:
		winners.append(int(meta.winner))
	return winners

static func _result(deltas: Array, lines: Array, points: Array, discard_points: Array, called: Array, transfers: Array, items: Array, status: Array, all_called_draw: bool, next_multiplier: int, winners: Array, multiplier: int = 1) -> Dictionary:
	var round_points := [0.0, 0.0, 0.0, 0.0]
	for seat in 4:
		items[seat] = group_chicken_items(items[seat])
		for item in items[seat]:
			# Signed individual score: called players accumulate positive hand
			# income, uncalled players accumulate their negative debts. The
			# pairwise ledger then settles these signed scores against the table.
			round_points[seat] += float(item.get("own_amount", item.get("amount", 0.0)))
	# multiplier 应用到所有金额（鸡分、牌型分、杠分、报听费、额外胡牌分），
	# 无论胡牌还是流局都应用。
	if multiplier > 1:
		for seat in 4:
			deltas[seat] *= multiplier
			points[seat] *= multiplier
			discard_points[seat] *= multiplier
			round_points[seat] *= multiplier
			for item in items[seat]:
				# 金额字段统一缩放；张数、座位、牌种和付款人保持不变。
				for key in ["amount", "own_amount", "unit_amount", "base_amount", "chicken_amount", "flip_amount"]:
					if item.has(key):
						item[key] *= multiplier
		for t in transfers:
			t["amount"] *= multiplier
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
