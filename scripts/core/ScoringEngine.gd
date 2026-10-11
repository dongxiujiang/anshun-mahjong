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
			lines.append("%s 抢杠烧鸡：鸡分 0" % _nm(seat, dealer))
			items[seat].append({"kind": "penalty", "label": "抢杠烧鸡", "tile": "", "tiles": [], "amount": 0.0, "note": "鸡分归零"})
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
			_pay_uncalled(deltas, transfers, called_seats, discard_points)
			_pay_kongs(round, deltas, transfers, called_seats, items, "", true)
			lines.append("牌墙摸完：未叫牌者补打出鸡及应付杠分；叫牌者之间不补差" if called_seats.has(true) else "四家均未叫牌，本局无人收取鸡分或杠分")
		for seat in 4:
			status[seat] = _draw_status(seat, called_seats)
		return _result(deltas, lines, points, discard_points, called_seats, transfers, items, status, all_called, next_multiplier)
	var chicken_points := points.duplicate()
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
	for first in 4:
		for second in range(first + 1, 4):
			if not called_seats[first] or not called_seats[second]:
				continue
			var difference: float = chicken_points[first] - chicken_points[second]
			if difference > 0:
				_transfer(deltas, transfers, second, first, difference, "鸡分差额")
			elif difference < 0:
				_transfer(deltas, transfers, first, second, -difference, "鸡分差额")
	_pay_uncalled(deltas, transfers, called_seats, discard_points)
	var bonus: float = points[winner] - chicken_points[winner]
	for seat in 4:
		if seat != winner:
			_transfer(deltas, transfers, seat, winner, bonus, "胡牌额外加分")
	var pattern := RuleEngine.hand_pattern(round.players[winner].concealed, round.players[winner].melds)
	for item in [
		["seven_pairs", CFG.SCORE_DRAGON_SEVEN_PAIRS if pattern.get("dragon_seven_pairs", false) else CFG.SCORE_SEVEN_PAIRS, "龙七对" if pattern.get("dragon_seven_pairs", false) else "小七对"],
		["all_triplets", CFG.SCORE_BIG_SET if self_draw else CFG.SCORE_BIG_SET_DISCARD, "大队子"],
		["flush", CFG.SCORE_FLUSH, "清一色"],
	]:
		if pattern.get(item[0], false):
			_pay_win(deltas, transfers, winner, meta, float(item[1]), item[2])
			lines.append("%s：%s付 %.0f" % [item[2], "每家" if self_draw else _nm(meta.get("discard_seat", -1), dealer), item[1]])
			items[winner].append({"kind": "pattern", "label": item[2], "tile": "", "tiles": [], "amount": float(item[1]), "note": "每家付" if self_draw else "%s付" % _nm(meta.get("discard_seat", -1), dealer)})
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
		_transfer(deltas, transfers, payer, winner, CFG.SCORE_READY, "报听")
	_pay_kongs(round, deltas, transfers, called_seats, items, flip, false)
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

## matrix[本人][对方]：正数为收款，负数为付款。各行之和等于实际净变化。
static func pairwise_payments(transfers: Array) -> Array:
	var matrix: Array = [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
	for transfer in transfers:
		var payer := int(transfer.get("from", -1))
		var receiver := int(transfer.get("to", -1))
		if payer not in range(4) or receiver not in range(4) or payer == receiver:
			continue
		var amount := float(transfer.get("amount", 0.0))
		matrix[receiver][payer] += amount
		matrix[payer][receiver] -= amount
	return matrix

static func relative_payments(matrix: Array, seat: int) -> Array:
	var out: Array = []
	for offset in [3, 2, 1]:
		out.append(matrix[seat][posmod(seat + offset, 4)])
	return out

## 第一行文字：叫牌 / 未叫牌；胡牌者写明自摸还是胡谁，以及牌型。
static func _win_status(seat: int, winner: int, self_draw: bool, discard_seat: int, called: Array, pattern: Dictionary, round) -> String:
	var names: Array = []
	if pattern.get("seven_pairs", false):
		names.append("龙七对" if pattern.get("dragon_seven_pairs", false) else "小七对")
	if pattern.get("all_triplets", false):
		names.append("大队子")
	if pattern.get("flush", false):
		names.append("清一色")
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

## 每家的鸡分明细，同时给出「具体牌 + 分」条目。
## 翻牌三张首尾循环：其中若包含一条/八筒，该鸡牌才是金鸡（普通鸡4、冲锋鸡8）；
## 三张中的其他牌均为翻鸡+1。
static func chicken_profile(round, seat: int, flip: String) -> Dictionary:
	var player: PlayerState = round.players[seat]
	var multiplier := clampi(int(round.round_meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	var related: Array = Tiles.flip_related(flip) if flip != "" else []
	var gold_chickens: Array = []
	for related_tile in related:
		if Tiles.is_chicken(str(related_tile)):
			gold_chickens.append(related_tile)
	var discarded := 0.0
	var held := 0.0
	var flipped := 0.0
	var list: Array = []
	var burned: bool = seat == round.round_meta.get("burn_chicken_seat", -1)
	if not burned:
		for index in player.discards.size():
			var tile: String = player.discards[index]
			if not Tiles.is_chicken(tile):
				continue
			var is_charge: bool = round.is_charge_discard(seat, index)
			var base: float = CFG.SCORE_CHARGE_CHICKEN if is_charge else CFG.SCORE_CALL_CHICKEN
			var doubled: bool = tile in gold_chickens
			var amount: float = base * (CFG.SCORE_FLIP_DOUBLE if doubled else 1.0) * multiplier
			discarded += amount
			list.append(_chicken_item(tile, is_charge, doubled, amount, "打出", "discard"))
		for tile in player.concealed:
			_append_hand_chicken(list, tile, related, gold_chickens, multiplier, "手中")
		for meld in player.melds:
			for _index in (3 if meld.get("kind", "") == "pung" else 4):
				_append_hand_chicken(list, str(meld.get("tile", "")), related, gold_chickens, multiplier, "碰中" if meld.get("kind", "") == "pung" else "杠中", "meld" if meld.get("kind", "") == "pung" else "kong")
		for item in list:
			if item.get("source", "") != "discard":
				if item.get("kind", "") == "flip":
					flipped += float(item.get("amount", 0.0))
				else:
					held += float(item.get("amount", 0.0))
	if burned:
		discarded = 0.0
		held = 0.0
		flipped = 0.0
		list = []
	return {"discarded": discarded, "held": held, "flipped": flipped, "total": (discarded + held + flipped), "burned": burned, "items": group_chicken_items(list), "raw_items": list}

static func _append_hand_chicken(list: Array, tile: String, related: Array, gold_chickens: Array, multiplier: int, where: String, source: String = "hand") -> void:
	if Tiles.is_chicken(tile):
		var doubled: bool = tile in gold_chickens
		var amount: float = CFG.SCORE_CALL_CHICKEN * (CFG.SCORE_FLIP_DOUBLE if doubled else 1.0) * multiplier
		list.append(_chicken_item(tile, false, doubled, amount, where, source))
	elif tile in related:
		var amount: float = CFG.SCORE_FLIP_CHICKEN * multiplier
		list.append({"kind": "flip", "label": "翻鸡", "tile": tile, "tiles": [], "amount": amount, "note": "翻牌三张", "source": source})

static func _chicken_item(tile: String, charge: bool, doubled: bool, amount: float, where: String, source: String = "hand") -> Dictionary:
	var label := "冲锋鸡" if charge else "普通鸡"
	if doubled:
		label = "冲锋金鸡" if charge else "金鸡"
	var note := where
	if doubled:
		note += " · 翻牌命中"
	return {"kind": "charge" if charge else "chicken", "label": label, "tile": tile, "tiles": [], "amount": amount, "note": note, "source": source}

## 相同计分类型及相同单张分值合并，牌面放入 tiles；来源只保留为说明文字。
static func group_chicken_items(list: Array) -> Array:
	var grouped: Array = []
	var indexes := {}
	for raw in list:
		var item: Dictionary = raw.duplicate(true)
		if item.get("kind", "") not in ["chicken", "charge", "flip"]:
			grouped.append(item)
			continue
		var tiles: Array = item.get("tiles", []).duplicate()
		if tiles.is_empty():
			tiles.append(str(item.get("tile", "")))
		var count := tiles.size()
		var unit_amount := float(item.get("unit_amount", float(item.get("amount", 0.0)) / count))
		var key := "%s|%s|%s" % [item.get("kind", ""), item.get("label", ""), unit_amount]
		if indexes.has(key):
			var existing: Dictionary = grouped[indexes[key]]
			var existing_tiles: Array = existing.get("tiles", [])
			existing_tiles.append_array(tiles)
			existing["tiles"] = existing_tiles
			existing["amount"] = float(existing.get("amount", 0.0)) + float(item.get("amount", 0.0))
			existing["count"] = int(existing.get("count", 1)) + count
			var old_note := str(existing.get("note", ""))
			var new_note := str(item.get("note", ""))
			if new_note != "" and not old_note.contains(new_note):
				existing["note"] = old_note + (" / " if old_note != "" else "") + new_note
			continue
		item["tiles"] = tiles
		item["count"] = count
		item["unit_amount"] = unit_amount
		indexes[key] = grouped.size()
		grouped.append(item)
	return grouped

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

## 杠基础分独立转账；明杠只收放杠者，暗杠/加杠按本局付款资格逐人收。
## 杠内鸡是通用鸡分：每个未叫牌者也须补；4分基础费才区分明杠的来源。
## 胡牌局叫牌者已在鸡分比较中计入杠内鸡，不再重复转账。
static func _pay_kongs(round, deltas: Array, transfers: Array, called: Array, items: Array, flip: String, is_draw: bool) -> void:
	var related: Array = Tiles.flip_related(flip)
	var multiplier := clampi(int(round.round_meta.get("chicken_multiplier", 1)), 1, CFG.MAX_CHICKEN_MULTIPLIER)
	for receiver in 4:
		if not called[receiver]:
			continue
		for meld in round.players[receiver].melds:
			if meld.get("robbed", false) or meld.kind not in ["kong", "add_kong"]:
				continue
			var tile := str(meld.get("tile", ""))
			var source := int(meld.get("from_seat", -1))
			var own_kong: bool = meld.kind == "add_kong" or meld.get("concealed", false)
			var kind_name: String = "加杠" if meld.kind == "add_kong" else ("暗杠" if meld.get("concealed", false) else "明杠")
			var payers: Array = []
			for payer in 4:
				if payer == receiver or (is_draw and called[payer]):
					continue
				if own_kong or payer == source:
					payers.append(payer)
			var chicken_value := 0.0
			var flip_value := 0.0
			if receiver != round.round_meta.get("burn_chicken_seat", -1):
				if Tiles.is_chicken(tile):
					chicken_value = CFG.SCORE_CALL_CHICKEN * 4.0 * multiplier
					if not is_draw:
						chicken_value *= CFG.SCORE_FLIP_DOUBLE if tile in related else 1.0
				elif not is_draw and tile in related:
					flip_value = CFG.SCORE_FLIP_CHICKEN * 4.0 * multiplier
			for payer in payers:
				_transfer(deltas, transfers, payer, receiver, CFG.SCORE_DRAW_KONG, ("查叫" if is_draw else "") + kind_name)
			var chicken_payers: Array = []
			for payer in 4:
				if payer != receiver and not called[payer] and chicken_value > 0:
					_transfer(deltas, transfers, payer, receiver, chicken_value, "杠中鸡")
					chicken_payers.append(payer)
			if is_draw and payers.is_empty() and chicken_payers.is_empty():
				continue
			var tiles: Array = []
			for _index in 4:
				tiles.append(tile)
			var base: float = CFG.SCORE_DRAW_KONG if not payers.is_empty() else 0.0
			var own_amount := chicken_value + flip_value + (base if own_kong else 0.0)
			items[receiver].append({"kind": "kong", "label": kind_name, "tile": tile, "tiles": tiles,
				"amount": base + chicken_value + flip_value, "base_amount": base,
				"chicken_amount": chicken_value, "flip_amount": flip_value, "own_amount": own_amount,
				"kong_kind": "add_kong" if meld.kind == "add_kong" else ("concealed" if own_kong else "exposed"),
				"from_seat": source, "owner": receiver, "payers": payers, "chicken_payers": chicken_payers, "draw": is_draw, "note": ""})

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

static func _nm(seat: int, dealer: int = 0) -> String:
	return SEAT_NAMES[posmod(seat - dealer, 4)] if seat >= 0 and seat < 4 else "-"
