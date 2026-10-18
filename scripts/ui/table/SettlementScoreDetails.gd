extends RefCounted
## Read-only presentation. Chicken amounts are recorded item contributions;
## kong base amounts and uncalled debts are actual, attributable ledger totals.
## Missing/ambiguous attribution has NO stage entry, never an invented zero.
## IDs are seat:hand_flip, seat:hand_chicken, seat:draw, seat:chicken_TILE,
## seat:meld_INDEX. tiles contains only currently visible logical occurrences.

const TILE := preload("res://scripts/core/Tiles.gd")

static func build(result: Dictionary, meta: Dictionary, players: Array, plan: Dictionary) -> Array:
	var context: Dictionary = result.get("round_meta", meta)
	var winners: Array = result.get("winners", context.get("winners", plan.get("winners", []))).duplicate()
	if winners.is_empty() and int(context.get("winner", -1)) in range(4):
		winners.append(int(context.winner))
	var is_draw := bool(plan.get("is_draw", winners.is_empty()))
	var called := _called(result, plan, winners)
	if is_draw and (bool(plan.get("all_called_draw", result.get("all_called_draw", context.get("all_called_draw", false)))) or called.all(func(value): return value)):
		return []
	var gold: Array = []
	if not is_draw:
		for value in TILE.flip_related(str(context.get("flip_tile", result.get("flip_tile", "")))):
			if TILE.is_chicken(value): gold.append(value)
	var related: Array = [] if is_draw else TILE.flip_related(str(context.get("flip_tile", result.get("flip_tile", ""))))
	var burned := int(context.get("burn_chicken_seat", plan.get("burned", -1)))
	var snapshots: Array = result.get("players", players)
	var all_items: Array = result.get("items", [])
	var transfers: Array = result.get("transfers", [])
	var output: Array = []
	for seat in mini(4, snapshots.size()):
		var snapshot = snapshots[seat]
		var visual = players[seat] if seat < players.size() else snapshot
		var groups: Dictionary = {}
		var occurrences := _sources(snapshot, visual, seat, context, winners, is_draw, related, gold, groups)
		var items: Array = all_items[seat] if seat < all_items.size() else []
		if called[seat] and seat != burned:
			# Charge rows first: a unique unknown discard can be identified by its
			# recorded charge item; multiple indistinguishable discards stay unknown.
			for kind in ["charge", "chicken", "flip"]:
				for item in items:
					if str(item.get("kind", "")) == kind and not (is_draw and kind == "flip"):
						_assign_item(item, occurrences, groups, gold)
			_kongs(items, transfers, snapshot, groups, seat, is_draw, called, gold)
		for group in groups.values():
			if seat == burned: _note(group, "烧鸡：本局收入0，补付照算。")
			elif not called[seat]: _note(group, "未叫牌：手中、碰杠中的鸡不记正分。")
		if not called[seat]:
			_debt(groups, occurrences, transfers, seat, "未叫牌出牌鸡", "discard", gold)
			_debt(groups, occurrences, transfers, seat, "未叫牌杠分", "kong", gold)
			_debt(groups, occurrences, transfers, seat, "未叫牌杠中鸡", "kong_chicken", gold)
		if is_draw:
			for group in groups.values():
				if group.area != "chicken": continue
				_combined(group, _rows(transfers, seat, "荒牌包鸡", false), "（含双方出牌鸡及荒牌补付）")
		for group in groups.values():
			if is_draw and group._parts.has("chicken"):
				var target := "kong" if group.area == "meld" else "other"
				if not group._parts.has(target): group._parts[target] = []
				group._parts[target].append_array(group._parts.chicken)
				group._parts.erase("chicken")
			_finish_group(group)
			output.append(group)
	return output

static func _player_value(player, key: String, fallback):
	if player is Dictionary: return player.get(key, fallback)
	if player == null: return fallback
	var value = player.get(key)
	return fallback if value == null else value

static func _called(result: Dictionary, plan: Dictionary, winners: Array) -> Array:
	var values: Array = result.get("called", plan.get("called", []))
	var status: Array = result.get("status", [])
	var out: Array = []
	for seat in 4:
		out.append(bool(values[seat]) if seat < values.size() else (seat in winners or (seat < status.size() and str(status[seat]).begins_with("叫牌"))))
	return out

static func _group(groups: Dictionary, seat: int, key: String, area: String, meld_index: int = -1) -> Dictionary:
	if not groups.has(key):
		var tiles: Array[String] = []
		groups[key] = {"id": "%d:%s" % [seat, key], "seat": seat, "area": area,
			"meld_index": meld_index, "tiles": tiles, "stages": {}, "detail": "", "_notes": [], "_parts": {}, "_robbed": false, "_kong": false, "_base_stage": "kong", "_title": ""}
	return groups[key]

static func _source(pool: Array, groups: Dictionary, seat: int, key: String, area: String, tile: String, charge: int = 0, meld_index: int = -1) -> void:
	if key != "": _group(groups, seat, key, area, meld_index).tiles.append(tile)
	pool.append({"key": key, "tile": tile, "charge": charge, "area": area, "used": false})

static func _stage(tile: String, gold: Array) -> String:
	return "chicken" if TILE.is_chicken(tile) and tile not in gold else "flip"

static func _sources(snapshot, visual, seat: int, meta: Dictionary, winners: Array, is_draw: bool, related: Array, gold: Array, groups: Dictionary) -> Array:
	var pool: Array = []
	var hand: Array = _player_value(snapshot, "concealed", [])
	if not is_draw:
		var drawn := str(_player_value(snapshot, "just_drew", ""))
		if drawn == "" and _player_value(visual, "concealed", []) == hand:
			drawn = str(_player_value(visual, "just_drew", ""))
		if drawn == "" and seat in winners: drawn = str(meta.get("win_tile", ""))
		var drawn_index := hand.rfind(drawn) if drawn != "" else -1
		for index in hand.size():
			var tile := str(hand[index])
			if not TILE.is_chicken(tile) and tile not in related: continue
			var area := "draw" if index == drawn_index else "hand"
			var key := "draw" if area == "draw" else "hand_" + _stage(tile, gold)
			_source(pool, groups, seat, key, area, tile)
	var melds: Array = _player_value(snapshot, "melds", [])
	for index in melds.size():
		var meld: Dictionary = melds[index]
		var kind := str(meld.get("kind", ""))
		if kind not in ["pung", "kong", "add_kong"]: continue
		var key := "meld_%d" % index
		var group := _group(groups, seat, key, "meld", index)
		group._kong = kind != "pung"
		group._robbed = bool(meld.get("robbed", false))
		group._base_stage = "other" if not is_draw and kind == "kong" and not bool(meld.get("concealed", false)) else "kong"
		group._title = "碰牌" if kind == "pung" else _kong_label(meld)
		if group._robbed: _note(group, "被抢杠，本组不收杠分。")
		if kind == "pung" and (is_draw or (not TILE.is_chicken(str(meld.get("tile", ""))) and str(meld.get("tile", "")) not in related)):
			_note(group, "本组碰牌不计分。")
		for slot in (3 if kind == "pung" else 4):
			var tile := str(meld.get("tile", ""))
			if kind == "pung" and not is_draw:
				_source(pool, groups, seat, key, "meld", tile, 0, index)
			else:
				group.tiles.append(tile)
	var discards: Array = _player_value(snapshot, "discards", [])
	var ids: Array = _player_value(snapshot, "discard_ids", [])
	if ids.is_empty() and _player_value(visual, "discards", []) == discards: ids = _player_value(visual, "discard_ids", [])
	for index in discards.size():
		var tile := str(discards[index])
		if not TILE.is_chicken(tile): continue
		var charge := 0
		var marker: Dictionary = meta.get("charge_chickens", {}).get(tile, {})
		if int(marker.get("owner", -1)) == seat and str(marker.get("location", "")) == "discard":
			charge = int(int(ids[index]) == int(marker.get("discard_id", -1))) if index < ids.size() else -1
		_source(pool, groups, seat, "chicken_" + tile, "chicken", tile, charge)
	# These occurrences consume their recorded item units but never create a
	# visible source tile or get reassigned to the winner's draw slot.
	for record in meta.get("resolved_chicken_discards", []):
		if int(record.get("owner", -1)) == seat and TILE.is_chicken(str(record.get("tile", ""))):
			_source(pool, groups, seat, "", "chicken", str(record.tile), int(bool(record.get("charge", false))))
	return pool

static func _assign_item(item: Dictionary, pool: Array, groups: Dictionary, gold: Array) -> void:
	var tiles: Array = item.get("tiles", []).duplicate()
	if tiles.is_empty() and str(item.get("tile", "")) != "": tiles.append(str(item.tile))
	var amount := float(item.get("amount", 0.0))
	if tiles.is_empty() or not is_finite(amount) or amount <= 0.0: return
	var unit := float(item.get("unit_amount", amount / tiles.size()))
	var valid := is_finite(unit) and unit > 0.0 and is_equal_approx(unit * tiles.size(), amount)
	var counts: Dictionary = {}
	for tile in tiles: counts[str(tile)] = int(counts.get(str(tile), 0)) + 1
	var kind := str(item.get("kind", ""))
	var label := str(item.get("label", {"flip": "翻鸡", "chicken": "普通鸡", "charge": "冲锋鸡"}.get(kind, "鸡分")))
	for tile in counts:
		var matches: Array = []
		for source in pool:
			if source.used or source.tile != tile: continue
			if kind == "flip" and (TILE.is_chicken(tile) or source.area == "chicken"): continue
			if kind != "flip" and not TILE.is_chicken(tile): continue
			if kind == "charge" and (source.area != "chicken" or int(source.charge) == 0): continue
			if kind == "chicken" and int(source.charge) == 1: continue
			matches.append(source)
		if not valid or matches.size() != int(counts[tile]):
			for group in groups.values():
				if tile in group.tiles:
					_note(group, "本组暂无独立明细；该家%s合计%s分。" % [label, _number(amount)])
			continue
		for source in matches:
			source.used = true
			if source.key == "": continue
			_part(groups[source.key], _stage(tile, gold), label, unit, 1, unit)

static func _kong_label(meld: Dictionary) -> String:
	if str(meld.get("kind", "")) == "add_kong": return "加杠"
	return "暗杠" if bool(meld.get("concealed", false)) else "明杠"

static func _matches_kong(item: Dictionary, meld: Dictionary, seat: int) -> bool:
	if str(meld.get("kind", "")) not in ["kong", "add_kong"]: return false
	if str(item.get("kind", "")) != "kong" or int(item.get("owner", seat)) != seat: return false
	if str(item.get("tile", "")) != str(meld.get("tile", "")): return false
	if str(item.get("label", "")) != _kong_label(meld): return false
	return int(item.get("from_seat", -1)) == int(meld.get("from_seat", -1))

static func _kong_rows(item: Dictionary, items: Array, transfers: Array, seat: int, reason: String, amount_key: String, payers_key: String, is_draw: bool, called: Array) -> Array:
	var out: Array = []
	var item_index := items.find(item)
	var seen: Array = []
	for raw_payer in item.get(payers_key, []):
		var payer := int(raw_payer)
		if payer not in range(4) or payer in seen or (is_draw and bool(called[payer])): continue
		seen.append(payer)
		var rows: Array = _rows(transfers, seat, reason, true).filter(func(row): return int(row.from) == payer and is_equal_approx(float(row.amount), float(item.get(amount_key, 0.0))))
		var candidates: Array = []
		for index in items.size():
			var other: Dictionary = items[index]
			if str(other.get("kind", "")) != "kong": continue
			if amount_key == "base_amount" and other.get("label", "") != item.get("label", ""): continue
			if payer in other.get(payers_key, []) and is_equal_approx(float(other.get(amount_key, 0.0)), float(item.get(amount_key, 0.0))):
				candidates.append(index)
		# Scoring emits meld items and each payer's rows in the same meld order.
		# Only a complete, equally sized set establishes this correspondence.
		if candidates.size() == rows.size() and item_index in candidates:
			out.append(rows[candidates.find(item_index)])
	return out

static func _kongs(items: Array, transfers: Array, snapshot, groups: Dictionary, seat: int, is_draw: bool, called: Array, gold: Array) -> void:
	var melds: Array = _player_value(snapshot, "melds", [])
	for group in groups.values():
		if not group._kong or group._robbed: continue
		var meld: Dictionary = melds[int(group.meld_index)]
		var matches: Array = items.filter(func(item): return _matches_kong(item, meld, seat))
		if matches.size() != 1:
			_note(group, "本组暂无独立杠分明细。")
			continue
		var item: Dictionary = matches[0]
		# A legacy/partial snapshot may contain duplicate meld identities.
		if melds.filter(func(candidate): return not bool(candidate.get("robbed", false)) and _matches_kong(item, candidate, seat)).size() != 1:
			_note(group, "本组暂无独立杠分明细。")
			continue
		var label := _kong_label(meld)
		var base_rows := _kong_rows(item, items, transfers, seat, ("查叫" if is_draw else "") + label, "base_amount", "payers", is_draw, called)
		for row in base_rows:
			_part(group, str(group._base_stage), label, float(row.amount), 1, float(row.amount))
			_note(group, _flow(row, seat) + ("（杠分）" if float(item.get("chicken_amount", 0.0)) > 0.0 or float(item.get("flip_amount", 0.0)) > 0.0 else ""))
		if base_rows.size() != item.get("payers", []).size():
			_combined(group, _rows(transfers, seat, ("查叫" if is_draw else "") + label, true))
			if base_rows.is_empty(): _note(group, "本组暂无独立杠分明细。")
		var chicken := float(item.get("chicken_amount", 0.0))
		var flip := float(item.get("flip_amount", 0.0))
		var tile := str(meld.get("tile", ""))
		if is_draw:
			for row in _kong_rows(item, items, transfers, seat, "杠中鸡", "chicken_amount", "chicken_payers", true, called):
				_part(group, "chicken", "杠中鸡补付", float(row.amount), 1, float(row.amount))
				_note(group, _flow(row, seat) + "（杠中鸡）")
		else:
			if chicken > 0.0 and is_finite(chicken):
				_part(group, _stage(tile, gold), "金鸡" if tile in gold else "普通鸡", chicken, group.tiles.size(), chicken / group.tiles.size())
			if flip > 0.0 and is_finite(flip):
				_part(group, "flip", "翻鸡", flip, group.tiles.size(), flip / group.tiles.size())

static func _rows(transfers: Array, seat: int, reason: String, incoming: bool) -> Array:
	var out: Array = []
	for row in transfers:
		var payer := int(row.get("from", -1))
		var receiver := int(row.get("to", -1))
		var amount := float(row.get("amount", 0.0))
		if payer not in range(4) or receiver not in range(4) or payer == receiver or not is_finite(amount) or amount <= 0.0: continue
		if str(row.get("reason", "")) != reason: continue
		if (incoming and receiver == seat) or (not incoming and (payer == seat or receiver == seat)): out.append(row)
	return out

static func _debt(groups: Dictionary, pool: Array, transfers: Array, seat: int, reason: String, category: String, gold: Array) -> void:
	var candidates: Array = []
	for group in groups.values():
		if category == "discard" and group.area == "chicken": candidates.append(group)
		elif category != "discard" and group._kong and not group._robbed:
			if category == "kong" or (not group.tiles.is_empty() and TILE.is_chicken(group.tiles[0])): candidates.append(group)
	var rows := _rows(transfers, seat, reason, false).filter(func(row): return int(row.from) == seat)
	var hidden := category == "discard" and pool.any(func(source): return source.key == "")
	for group in candidates:
		var exact := candidates.size() == 1 and not hidden
		for row in rows:
			if exact:
				var stage := str(group._base_stage) if category == "kong" else _stage(str(group.tiles[0]), gold)
				_part(group, stage, reason, -float(row.amount), 1, -float(row.amount))
				_note(group, _flow(row, seat) + "（%s）" % reason)
		if not exact:
			_combined(group, rows, "（%s%s）" % [reason, "，含已被胡走的出牌鸡" if hidden else ""])

static func _combined(group: Dictionary, rows: Array, suffix: String = "") -> void:
	var combined: Dictionary = {}
	for row in rows:
		var key := "%d:%d" % [int(row.from), int(row.to)]
		if not combined.has(key): combined[key] = {"from": int(row.from), "to": int(row.to), "amount": 0.0}
		combined[key].amount += float(row.amount)
	var descriptions: Array[String] = []
	for row in combined.values(): descriptions.append(_flow(row, int(group.seat)))
	if not descriptions.is_empty(): _note(group, "本组暂无独立收付明细；该家合计" + "、".join(descriptions) + suffix + "。")

static func _part(group: Dictionary, stage: String, label: String, amount: float, count: int, unit: float) -> void:
	if not is_finite(amount) or is_zero_approx(amount): return
	if not group._parts.has(stage): group._parts[stage] = []
	for part in group._parts[stage]:
		if part.label == label and is_equal_approx(float(part.unit), unit):
			part.amount += amount
			part.count += count
			return
	group._parts[stage].append({"label": label, "amount": amount, "count": count, "unit": unit})

static func _note(group: Dictionary, message: String) -> void:
	if message not in group._notes: group._notes.append(message)

static func _finish_group(group: Dictionary) -> void:
	var lines: Array[String] = []
	var heading := str(group._title)
	if heading == "": heading = str({"hand": "手牌", "draw": "摸牌／胡牌张", "chicken": "出牌鸡", "meld": "碰杠"}[group.area])
	var counts: Dictionary = {}
	for tile in group.tiles: counts[tile] = int(counts.get(tile, 0)) + 1
	var tile_text: Array[String] = []
	for tile in counts: tile_text.append("%s%d张" % [_tile_name(str(tile)), int(counts[tile])])
	lines.append(heading + " · " + "、".join(tile_text))
	for stage in ["flip", "chicken", "kong", "other"]:
		var parts: Array = group._parts.get(stage, [])
		if parts.is_empty(): continue
		var total := 0.0
		var terms: Array[String] = []
		for part in parts:
			total += float(part.amount)
			terms.append(_number(float(part.amount)))
		var title := str(parts[0].label)
		if parts.size() > 1:
			title = "金鸡" if parts.all(func(part): return str(part.label).contains("金鸡")) else ("翻鸡" if stage == "flip" else ("杠分" if stage == "kong" else "鸡分"))
		var expression := ("+" if total > 0.0 else "") + _number(total)
		if parts.size() > 1: expression = "＋".join(terms) + "＝" + _number(total)
		elif stage in ["kong", "other"] and int(parts[0].count) > 1:
			expression = ("+" if total > 0.0 else "") + _number(float(parts[0].unit)) + "×%d＝%s" % [int(parts[0].count), _number(total)]
		group.stages[stage] = {"amount": total, "text": title + " " + expression}
		# Actual base payers are already listed below. A plain kong needs only
		# its compact tile heading and those payment lines, not a second 4x1.
		var only_base := parts.all(func(part): return str(part.label) in ["明杠", "暗杠", "加杠", "未叫牌杠分"])
		if not only_base:
			lines.append(str(group.stages[stage].text) + "分")
			for part in parts:
				if parts.size() > 1 or int(part.count) > 1:
					lines.append("%s：%s×%d＝%s分" % [part.label, _number(float(part.unit)), int(part.count), _number(float(part.amount))])
		if stage in ["flip", "chicken"] and total > 0.0: lines.append("牌面分 · 按差额收付")
	for note in group._notes: lines.append(str(note))
	if group.stages.is_empty() and not lines.any(func(line): return str(line).contains("不计分") or str(line).contains("暂无") or str(line).contains("收入0")):
		lines.append("本组不计分。")
	group.detail = "\n".join(lines)
	for key in ["_notes", "_parts", "_robbed", "_kong", "_base_stage", "_title"]: group.erase(key)

static func _flow(row: Dictionary, seat: int) -> String:
	var incoming := int(row.to) == seat
	var other := int(row.from) if incoming else int(row.to)
	var direction: String = ["本家", "下家", "对家", "上家"][posmod(other - seat, 4)]
	return "向%s%s%s分" % [direction, "收" if incoming else "付", _number(float(row.amount))]

static func _number(value: float) -> String:
	return "%.0f" % value if is_equal_approx(value, roundf(value)) else str(value)

static func _tile_name(tile: String) -> String:
	if tile == "tiao1": return "幺鸡"
	if tile == "tong8": return "八筒"
	if tile.length() < 2: return tile
	return str(TILE.rank(tile)) + str({"wan": "万", "tiao": "条", "tong": "筒"}.get(TILE.suit(tile), ""))
