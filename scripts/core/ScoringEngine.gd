class_name ScoringEngine
## Called players compare chicken totals; uncalled players pay retained discard chickens.
##
## settle() 产出两套信息：
##   lines    —— 纯文本摘要（日志/兼容用）
##   items[4] —— 每家的结构化得分条目，供结算卡片显示「具体牌 + 分数」
##              每条：{kind, label, tile, tiles, amount, note}
##                kind  —— 条目类别（自摸/冲锋鸡/普通鸡/金鸡/翻鸡/番型/杠/报听）
##                label —— 显示名（如「冲锋鸡」「翻鸡」）
##                tile  —— 单张牌值，供卡片画牌图（"" 表示纯文字条目）
##                tiles —— 该组的全部牌面（如一组杠的 4 张）
##                amount—— 该组总分；unit_amount 为每张分值
##                note  —— 补充说明（付款人、翻倍等）
const CFG := preload("res://scripts/autoload/GameConfig.gd")

## 座位名（相对庄家）
const SEAT_NAMES := ["庄家", "下家", "对家", "上家"]

const CHICKEN := preload("res://scripts/core/ChickenScoring.gd")
const KONG := preload("res://scripts/core/KongScoring.gd")
const WIN := preload("res://scripts/core/WinScoring.gd")
const PAY := preload("res://scripts/core/PaymentLedger.gd")

static func settle(round) -> Dictionary:
	var meta: Dictionary = round.round_meta
	var winner: int = meta.get("winner", -1)
	var dealer: int = meta.get("dealer_seat", 0)
	var deltas := [0.0, 0.0, 0.0, 0.0]
	var points := [0.0, 0.0, 0.0, 0.0]
	var discard_points := [0.0, 0.0, 0.0, 0.0]
	var called_seats: Array = []
	var multiplier := clampi(int(meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	var lines: Array = []
	var transfers: Array = []
	var items: Array = [[], [], [], []]
	var status: Array = ["", "", "", ""]
	var flip: String = meta.get("flip_tile", "") if winner >= 0 else ""
	var self_draw: bool = meta.get("self_draw", false)
	for seat in 4:
		var called := is_called(round, seat)
		called_seats.append(called)
		var profile := chicken_profile(round, seat, flip)
		points[seat] = profile.total if called else 0.0
		discard_points[seat] = profile.discarded if called else 0.0
		if called:
			# 杠内鸡/翻鸡随四张杠牌一起显示，避免同一组牌在两处重复展示。
			for item in profile.raw_items:
				if item.get("source", "") != "kong" and (winner >= 0 or item.get("source", "") == "discard"):
					items[seat].append(item.duplicate(true))
		if profile.burned:
			var burn_label := "杠后抢胡烧鸡" if meta.get("burn_chicken_reason", "") == "after_kong_discard" else "抢杠烧鸡"
			lines.append("%s %s：鸡分 0" % [_nm(seat, dealer), burn_label])
			items[seat].append({"kind": "penalty", "label": burn_label, "tile": "", "tiles": [], "amount": 0.0, "note": "鸡分归零"})
		if winner < 0:
			lines.append("%s%s：保留出牌鸡 %.0f" % [_nm(seat, dealer), " 已叫牌" if called else " 未叫牌", discard_points[seat]])
		else:
			lines.append("%s%s：鸡分 %.0f，打出鸡 %.0f" % [_nm(seat, dealer), " 已叫牌" if called else " 未叫牌", points[seat], discard_points[seat]])
	if multiplier > 1:
		lines.append("本局鸡分 ×%d（不影响额外加分、牌型和报听）" % multiplier)
	if flip != "":
		for tile in Tiles.flip_related(flip):
			if Tiles.is_chicken(tile):
				lines.append("翻中%s：金鸡普通鸡 4，冲锋鸡 8" % ("幺鸡" if tile == "tiao1" else "八筒"))
	if winner < 0:
		var all_called := called_seats.all(func(value): return value)
		# A repeat all-called draw keeps the bonus at 2×; it never compounds.
		var next_multiplier := 2 if all_called else 1
		if all_called:
			lines.append("四家叫牌流局，本局不计分；下局鸡分 ×%d" % next_multiplier)
			items = [[], [], [], []]
		else:
			PAY.pay_uncalled(deltas, transfers, called_seats, discard_points)
			KONG.pay(round, deltas, transfers, called_seats, items, "", true)
			lines.append("牌墙摸完：未叫牌者补打出鸡及应付杠分；叫牌者之间不补差" if called_seats.has(true) else "四家均未叫牌，本局无人收取鸡分或杠分")
		for seat in 4:
			status[seat] = _draw_status(seat, called_seats)
		return _result(deltas, lines, points, discard_points, called_seats, transfers, items, status, all_called, next_multiplier)
	var chicken_points := points.duplicate()
	WIN.bonuses(round, points, items, lines, flip)
	PAY.compare_chickens(deltas, transfers, called_seats, chicken_points)
	PAY.pay_uncalled(deltas, transfers, called_seats, discard_points)
	var bonus: float = points[winner] - chicken_points[winner]
	for seat in 4:
		if seat != winner:
			PAY.transfer(deltas, transfers, seat, winner, bonus, "胡牌额外加分")
	var pattern := WIN.charges(round, deltas, transfers, items, lines)
	KONG.pay(round, deltas, transfers, called_seats, items, flip, false)
	for seat in 4:
		status[seat] = _win_status(seat, winner, self_draw, meta.get("discard_seat", -1), called_seats, pattern, round)
	return _result(deltas, lines, points, discard_points, called_seats, transfers, items, status, false, 1)

## 本局分是本人的通用得分点；明杠基础4分只对放杠者生效，不能混入通用分。

static func _result(deltas: Array, lines: Array, points: Array, discard_points: Array, called: Array, transfers: Array, items: Array, status: Array, all_called_draw: bool, next_multiplier: int) -> Dictionary:
	var round_points := [0.0, 0.0, 0.0, 0.0]
	for seat in 4:
		items[seat] = group_chicken_items(items[seat])
		for item in items[seat]:
			round_points[seat] += maxf(0.0, float(item.get("own_amount", item.get("amount", 0.0))))
	var pairs := pairwise_payments(transfers)
	return {"deltas": deltas, "lines": lines, "points": points, "round_points": round_points,
		"discard_points": discard_points, "called": called, "transfers": transfers, "pairwise": pairs,
		"items": items, "status": status, "all_called_draw": all_called_draw, "next_chicken_multiplier": next_multiplier}

static func _win_status(seat: int, winner: int, self_draw: bool, discard_seat: int, called: Array, pattern: Dictionary, round) -> String:
	var names: Array = []
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
		names.append(str(p.get("dragon_label", "")) if dragon else str(p.get("label", "")))
	if seat == winner:
		# 「胡对家」说的是胡牌者自己的对家，所以按胡牌者的视角取方位。
		var how := "自摸"
		if not self_draw:
			how = "胡" + (["-", "下家", "对家", "上家"][posmod(discard_seat - seat, 4)] if discard_seat >= 0 and discard_seat < 4 else "点炮")
		return "叫牌（%s%s）" % [how, (" " + " ".join(names)) if not names.is_empty() else ""]
	var text := "叫牌" if called[seat] else "未叫牌"
	if round.players[seat].ready:
		text += " · 已报听"
	return text

static func _draw_status(seat: int, called: Array) -> String:
	return "叫牌" if called[seat] else "未叫牌"

static func is_called(round, seat: int) -> bool:
	var player: PlayerState = round.players[seat]
	return round.round_meta.get("winner", -1) == seat or RuleEngine.is_tenpai(player.concealed, player.melds)

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
