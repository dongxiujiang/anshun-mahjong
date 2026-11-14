extends RefCounted
## 只整理既有账本。牌面分值为单倍单家，不能用本局净增减反推。

const TILES := preload("res://scripts/core/Tiles.gd")

static func caption(label: String) -> String:
	return str({"荒牌牌型分": "牌型", "荒牌基础补付": "基础", "未叫牌出牌鸡": "出牌鸡",
		"未叫牌碰鸡": "碰鸡", "报听胡牌": "报听", "自摸基础分": "自摸", "抢杠胡基础分": "抢杠",
		"点炮基础分（叫牌）": "杠后放炮", "点炮基础分（未叫牌）": "杠后放炮",
		"通行证胡牌": "胡牌", "杠后出牌烧鸡": "烧鸡", "抢杠烧鸡": "烧鸡"}.get(label, label))

static func entries(result: Dictionary, meta: Dictionary, players: Array, plan: Dictionary, seat: int) -> Array:
	var multiplier := maxi(1, int(meta.get("chicken_multiplier", 1)))
	var called := bool(plan.called[seat])
	var out: Array = []
	var all_items: Array = result.get("items", [])
	for original in all_items[seat] if seat < all_items.size() else []:
		var item: Dictionary = original.duplicate(true)
		var kind := str(item.get("kind", ""))
		var label := str(item.get("label", ""))
		if label == "荒牌补付": continue # 合计多家支出，改为下面逐家金额。
		if not called and kind in ["chicken", "charge", "flip"]: continue
		var cards: Array = item.get("tiles", []).duplicate()
		if cards.is_empty() and str(item.get("tile", "")) != "": cards.append(item.tile)
		var parts: Array = []
		if kind == "kong":
			for split in [["base_amount", label, "未叫牌杠分"], ["chicken_amount", "杠中鸡", "未叫牌杠中鸡"], ["flip_amount", "翻鸡", ""]]:
				var amount := float(item.get(split[0], 0.0)) / multiplier
				if not called:
					if split[2] == "" or not _paid_kong_debt(result, item, seat, str(split[2])): continue
					amount = -amount
				if not is_zero_approx(amount): parts.append({"label": split[1], "amount": amount})
		else:
			if label in ["未叫牌出牌鸡", "未叫牌碰鸡"]:
				cards = _debt_tiles(players[seat], meta, seat, label == "未叫牌碰鸡")
			label = caption(label)
			parts.append({"label": label, "amount": float(item.get("amount", 0.0)) / multiplier})
		if not parts.is_empty():
			var entry := {"tiles": cards, "parts": parts}
			if kind == "kong": entry["kong"] = {"label": label, "from_seat": int(item.get("from_seat", -1)), "seat": seat}
			out.append(entry)
	var fees := {}
	for transfer in result.get("transfers", []):
		if str(transfer.reason) not in ["荒牌基础补付", "荒牌牌型分"]: continue
		if int(transfer.from) != seat and int(transfer.to) != seat: continue
		var amount := float(transfer.amount) / multiplier * (1.0 if int(transfer.to) == seat else -1.0)
		var other := int(transfer.from) if amount > 0 else int(transfer.to)
		var key := str(transfer.reason) + ":" + str(amount)
		if not fees.has(key): fees[key] = {"label": str(transfer.reason), "amount": amount, "opponents": []}
		fees[key].opponents.append(["", "上", "对", "下"][posmod(other - seat, 4)])
	for fee in fees.values():
		out.append({"tiles": [], "parts": [{"label": caption(fee.label), "amount": fee.amount, "suffix": "（" + "/".join(fee.opponents) + "）"}]})
	return out

static func _paid_kong_debt(result: Dictionary, item: Dictionary, seat: int, reason: String) -> bool:
	var exposed := str(item.get("label", "")) == "明杠" and reason == "未叫牌杠分"
	for row in result.get("transfers", []):
		if int(row.from) == seat and str(row.reason) == reason and (not exposed or int(row.to) == int(item.get("from_seat", -1))):
			return true
	return false

static func _debt_tiles(player, meta: Dictionary, seat: int, pung: bool) -> Array:
	var cards: Array = []
	if pung:
		for meld in player.melds:
			if meld.kind == "pung" and TILES.is_chicken(meld.tile): cards.append_array([meld.tile, meld.tile, meld.tile])
	else:
		for tile in player.discards:
			if TILES.is_chicken(tile): cards.append(tile)
		for resolved in meta.get("resolved_chicken_discards", []):
			if int(resolved.owner) == seat: cards.append(resolved.tile)
	return cards
