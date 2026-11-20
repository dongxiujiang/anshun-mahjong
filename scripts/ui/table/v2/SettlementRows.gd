extends RefCounted
## 只整理既有账本。牌面分值为单倍单家，不能用本局净增减反推。

const TILES := preload("res://scripts/core/Tiles.gd")

static func totals(plan: Dictionary, meta: Dictionary, seat: int, viewer: int) -> Array:
	var multiplier := maxi(1, int(meta.get("chicken_multiplier", 1)))
	var amounts := {}
	for other in 4:
		if other == seat: continue
		var amount := 0.0
		for stage in plan.get("stages", []): amount += float(stage.scores[seat][other])
		amounts[other] = amount / multiplier
	var common: float = amounts.values()[0]
	for amount in amounts.values():
		if absf(float(amount)) < absf(common): common = float(amount)
	var out := [{"amount": common, "opponent": -1, "suffix": ""}]
	for offset in 4:
		var other := posmod(viewer + offset, 4)
		if other == seat or is_equal_approx(float(amounts[other]), common): continue
		out.append({"amount": float(amounts[other]), "opponent": other, "suffix": "（" + ["我", "上", "对", "下"][offset] + "）"})
	return out

static func caption(label: String) -> String:
	return str({"荒牌牌型分": "牌型", "荒牌基础补付": "基础", "未叫牌出牌鸡": "出牌鸡",
		"未叫牌碰鸡": "碰鸡", "报听胡牌": "报听", "自摸基础分": "自摸", "抢杠胡基础分": "抢杠",
		"点炮基础分（叫牌）": "杠后放炮", "点炮基础分（未叫牌）": "杠后放炮",
		"通行证胡牌": "胡牌", "杠后出牌烧鸡": "烧鸡", "抢杠烧鸡": "烧鸡"}.get(label, label))

static func entries(result: Dictionary, meta: Dictionary, players: Array, plan: Dictionary, seat: int) -> Array:
	var multiplier := maxi(1, int(meta.get("chicken_multiplier", 1)))
	var called := bool(plan.called[seat])
	var is_draw := bool(plan.get("is_draw", int(meta.get("winner", -1)) < 0))
	var out: Array = []
	var all_items: Array = result.get("items", [])
	for original in all_items[seat] if seat < all_items.size() else []:
		var item: Dictionary = original.duplicate(true)
		var kind := str(item.get("kind", ""))
		var label := str(item.get("label", ""))
		if label == "荒牌补付": continue # 合计多家支出，改为下面逐家金额。
		if not called and kind in ["chicken", "charge", "flip"]: continue
		if is_draw and kind in ["chicken", "charge"]: continue
		if kind in ["chicken", "charge"]:
			out.append_array(_chicken_entries([item], multiplier, ""))
			continue
		var cards: Array = item.get("tiles", []).duplicate()
		if cards.is_empty() and str(item.get("tile", "")) != "": cards.append(item.tile)
		var parts: Array = []
		var sideways: Array = []
		if kind == "charge":
			for index in cards.size(): sideways.append(index)
		if kind == "kong":
			for split in [["base_amount", label, "未叫牌杠分"], ["chicken_amount", "杠中鸡", "未叫牌杠中鸡"], ["flip_amount", "翻鸡", ""]]:
				var amount := float(item.get(split[0], 0.0)) / multiplier
				if not called:
					if split[2] == "" or not _paid_kong_debt(result, item, seat, str(split[2])): continue
					amount = -amount
				if not is_zero_approx(amount): parts.append({"label": split[1], "amount": amount})
		else:
			if label in ["未叫牌出牌鸡", "未叫牌碰鸡"]:
				cards = _debt_tiles(players[seat], meta, seat, label == "未叫牌碰鸡", sideways)
			label = caption(label)
			parts.append({"label": label, "amount": float(item.get("amount", 0.0)) / multiplier})
		if not parts.is_empty():
			var entry := {"tiles": cards, "parts": parts, "sideways": sideways}
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
		if not fees[key].opponents.has(other): fees[key].opponents.append(other)
	for fee in fees.values():
		out.append({"tiles": [], "parts": [{"label": caption(fee.label), "amount": fee.amount, "suffix": _opponent_suffix(fee.opponents, seat)}]})
	if is_draw and called:
		var payers: Array = []
		for transfer in result.get("transfers", []):
			if str(transfer.reason) == "荒牌包鸡" and int(transfer.to) == seat and not payers.has(int(transfer.from)):
				payers.append(int(transfer.from))
		if not payers.is_empty():
			# Older cloud records omit the called player's pung chickens from items.
			# Read their unit values from the shared chicken classifier; never settle again.
			var snapshot := RoundState.new()
			snapshot.players.assign(players)
			snapshot.round_meta = meta
			var profile := ScoringEngine.chicken_profile(snapshot, seat, "")
			var chickens: Array = profile.raw_items.filter(func(item): return str(item.get("source", "")) in ["discard", "meld"])
			out.append_array(_chicken_entries(chickens, 1, _opponent_suffix(payers, seat)))
	return out.filter(func(entry): return _has_opponents(entry) == 0) + out.filter(func(entry): return _has_opponents(entry) != 0)

static func _has_opponents(entry: Dictionary) -> int:
	return int(entry.parts.any(func(part): return str(part.get("suffix", "")) != ""))

static func _opponent_suffix(opponents: Array, seat: int) -> String:
	var names: Array[String] = []
	for offset in [1, 2, 3]:
		if opponents.has(posmod(seat + offset, 4)): names.append(["", "上", "对", "下"][offset])
	return "" if names.size() == 3 else "（" + "/".join(names) + "）"

static func _chicken_entries(items: Array, multiplier: int, suffix: String) -> Array:
	var groups := {}
	for item in items:
		var cards: Array = item.get("tiles", []).duplicate()
		if cards.is_empty() and str(item.get("tile", "")) != "": cards.append(item.tile)
		if cards.is_empty(): continue
		var unit := float(item.amount) / multiplier / cards.size()
		var charge := str(item.get("kind", "")) == "charge"
		for card in cards:
			var label := ("冲锋" if charge else "") + ("幺鸡" if card == "tiao1" else "八筒")
			if "金" in str(item.get("label", "")): label = str(item.label) + "·" + ("幺鸡" if card == "tiao1" else "八筒")
			var key := label + str(unit)
			if not groups.has(key): groups[key] = {"tiles": [], "sideways": [], "parts": [{"label": label, "amount": 0.0, "suffix": suffix}]}
			var group: Dictionary = groups[key]
			if charge: group.sideways.append(group.tiles.size())
			group.tiles.append(card)
			group.parts[0].amount += unit
	return groups.values()

static func _paid_kong_debt(result: Dictionary, item: Dictionary, seat: int, reason: String) -> bool:
	var exposed := str(item.get("label", "")) == "明杠" and reason == "未叫牌杠分"
	for row in result.get("transfers", []):
		if int(row.from) == seat and str(row.reason) == reason and (not exposed or int(row.to) == int(item.get("from_seat", -1))):
			return true
	return false

static func _debt_tiles(player, meta: Dictionary, seat: int, pung: bool, sideways: Array) -> Array:
	var cards: Array = []
	if pung:
		for meld in player.melds:
			if meld.kind == "pung" and TILES.is_chicken(meld.tile): cards.append_array([meld.tile, meld.tile, meld.tile])
	else:
		for index in player.discards.size():
			var tile: String = player.discards[index]
			if not TILES.is_chicken(tile): continue
			var charge: Dictionary = meta.get("charge_chickens", {}).get(tile, {})
			var id: int = player.discard_ids[index] if index < player.discard_ids.size() else index
			if charge.get("owner", -1) == seat and charge.get("location", "") == "discard" and charge.get("discard_id", -1) == id:
				sideways.append(cards.size())
			cards.append(tile)
		for resolved in meta.get("resolved_chicken_discards", []):
			if int(resolved.owner) != seat: continue
			if bool(resolved.get("charge", false)): sideways.append(cards.size())
			cards.append(resolved.tile)
	return cards
