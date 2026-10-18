extends RefCounted
## 鸡牌、金鸡、翻鸡和烧鸡的识别及展示条目，不负责玩家间付款。
const CFG := preload("res://scripts/autoload/GameConfig.gd")

static func chicken_profile(round, seat: int, flip: String) -> Dictionary:
	var player: PlayerState = round.players[seat]
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
	for index in player.discards.size():
		var tile: String = player.discards[index]
		if not Tiles.is_chicken(tile):
			continue
		var is_charge: bool = round.is_charge_discard(seat, index)
		var base: float = CFG.SCORE_CHARGE_CHICKEN if is_charge else CFG.SCORE_CALL_CHICKEN
		var doubled: bool = tile in gold_chickens
		var amount: float = base * (CFG.SCORE_FLIP_DOUBLE if doubled else 1.0)
		discarded += amount
		list.append(_chicken_item(tile, is_charge, doubled, amount, "打出", "discard"))
	# 胡牌时被胡的弃牌会从 player.discards 移入赢家的逻辑手牌。
	# 这张牌仍属于原出牌者的"打出鸡"，否则未叫牌者会漏付该鸡分。
	for raw_record in round.round_meta.get("resolved_chicken_discards", []):
		var record: Dictionary = raw_record
		if int(record.get("owner", -1)) != seat:
			continue
		var tile := str(record.get("tile", ""))
		if not Tiles.is_chicken(tile):
			continue
		var is_charge: bool = bool(record.get("charge", false))
		var base: float = CFG.SCORE_CHARGE_CHICKEN if is_charge else CFG.SCORE_CALL_CHICKEN
		var doubled: bool = tile in gold_chickens
		var amount: float = base * (CFG.SCORE_FLIP_DOUBLE if doubled else 1.0)
		discarded += amount
		list.append(_chicken_item(tile, is_charge, doubled, amount, "打出（胡牌）", "discard"))
	for tile in player.concealed:
		_append_hand_chicken(list, tile, related, gold_chickens, "手中")
	for meld_index in player.melds.size():
		var meld: Dictionary = player.melds[meld_index]
		for _index in (3 if meld.get("kind", "") == "pung" else 4):
			_append_hand_chicken(list, str(meld.get("tile", "")), related, gold_chickens, "碰中" if meld.get("kind", "") == "pung" else "杠中", "meld" if meld.get("kind", "") == "pung" else "kong", false)
	for item in list:
		if item.get("source", "") != "discard":
			if item.get("kind", "") == "flip":
				flipped += float(item.get("amount", 0.0))
			else:
				held += float(item.get("amount", 0.0))
	# 烧鸡只取消收入；未叫者的出牌鸡债务仍需支付。
	var discard_debt := discarded
	if burned:
		discarded = 0.0
		held = 0.0
		flipped = 0.0
		list = []
	return {"discard_debt": discard_debt, "discarded": discarded, "held": held, "flipped": flipped, "total": (discarded + held + flipped), "burned": burned, "items": group_chicken_items(list), "raw_items": list}

static func _append_hand_chicken(list: Array, tile: String, related: Array, gold_chickens: Array, where: String, source: String = "hand", charge: bool = false) -> void:
	if Tiles.is_chicken(tile):
		var doubled: bool = tile in gold_chickens
		# 碰杠后不再显示冲锋标记，按普通鸡每张2分，并按碰杠竖向摆放。
		var amount: float = CFG.SCORE_CALL_CHICKEN * (CFG.SCORE_FLIP_DOUBLE if doubled else 1.0)
		list.append(_chicken_item(tile, charge, doubled, amount, where, source))
	elif tile in related:
		var amount: float = CFG.SCORE_FLIP_CHICKEN
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
