extends RefCounted
## 只重排自己的展示行。所有听张与牌型从正式规则计算；可见库存按实际 ID 去重。

const Catalog = preload("res://src/domain/TileCatalog.gd")
const Rules = preload("res://src/anshun/scoring/RuleEngine.gd")
const Win = preload("res://src/anshun/scoring/WinScoring.gd")
const Tiles = preload("res://src/anshun/scoring/Tiles.gd")

var _cache_key := PackedByteArray()
var _cached := {}
var _pattern_key:=PackedByteArray()
var _patterns:={}

func arrange(view: Dictionary, order: Dictionary, priority: String = "multiple", novice: bool = false) -> Dictionary:
	if priority not in ["multiple", "pattern"] or not view.has("viewer_seat") or not order.has("slots"):
		return {}
	var seat := int(view.viewer_seat)
	var players: Array = view.get("players", [])
	if seat not in range(players.size()):
		return {}
	var own: Dictionary = players[seat]
	var visible := _known(view, seat)
	var faces := {}
	for face in own.hand:
		if not face is Dictionary or not _valid_id(face.get("id")) or faces.has(int(face.id)) or not Catalog.valid_value(str(face.get("value", ""))):
			return {}
		faces[int(face.id)] = str(face.value)
	var order_suits: Array = order.get("suit_order", Catalog.SUITS)
	var row: Array = order.slots.duplicate()
	var pending: Array = order.get("pending_insert_ids", [])
	var dragged := int(order.get("dragged_id", -1))
	var is_manual: bool = order.get("manual", false) or dragged != -1
	var draw := int(own.get("draw_id", -1))
	var merge: Dictionary = order.get("draw_merge", {})
	var discard: Dictionary = view.get("last_discard", {})
	var key := var_to_bytes([row, pending, dragged, draw, is_manual, order_suits, faces, own.melds, visible, priority, novice, merge, discard])
	if key == _cache_key:
		return _cached.duplicate(true)
	var result := {"slots": row, "groups": [], "waits": [], "remaining_total": 0, "best_pattern_score": 0,
		"candidates": [], "preferred_indices": [], "pending_insert_ids": pending.duplicate(), "manual": is_manual, "insertion": {}}
	var buckets := {}
	var provided := {}
	for item in row + pending:
		var id: Variant = dragged if item == -1 and dragged >= 0 else item
		if not _valid_id(id) or not faces.has(int(id)) or int(id) == draw or provided.has(int(id)):
			return {}
		provided[int(id)] = true
		var value: String = faces[int(id)]
		if not buckets.has(value):
			buckets[value] = []
		buckets[value].append(int(id))
	if provided.size() != faces.size() - int(draw >= 0):
		return {}
	for ids in buckets.values():
		ids.sort()
	var values := []
	for suit in order_suits:
		for rank in range(1, 10):
			var value: String = suit + str(rank)
			for _id in buckets.get(value, []):
				values.append(value)
	var waits := {}
	if values.size() == 13 - 3 * own.melds.size():
		# 他人公开牌变化只影响剩余张数；本人的牌型相同时复用正式判型。
		var pattern_key:=var_to_bytes([values,own.melds])
		if pattern_key!=_pattern_key:
			_pattern_key=pattern_key;_patterns.clear()
			for tile in Tiles.all_values():
				var pattern:Dictionary=Rules.hand_pattern(values+[tile],own.melds,tile)
				if pattern.win:_patterns[tile]=int(Win.best_wait_pattern({tile:pattern}).get("score",0))
		for tile in _patterns:
			var remaining := maxi(0, 4 - int(visible.get(tile, 0)))
			waits[tile] = {"tile": tile, "remaining": remaining, "pattern_score": _patterns[tile]}
			result.remaining_total += remaining
			result.best_pattern_score = maxi(result.best_pattern_score, waits[tile].pattern_score)
	result.waits = waits.values()
	var groups := _sequential(values)
	var candidates: Array = []
	if not waits.is_empty():
		_candidates(values, [], 0, waits, candidates)
		if own.melds.is_empty():
			_seven_pairs(values, waits, candidates)
		result.candidates = candidates
	var preferred := best_candidates(candidates, priority)
	for candidate in preferred:
		result.preferred_indices.append(candidates.find(candidate))
	if is_manual or not pending.is_empty():
		if dragged == -1 and pending.size() == 1 and not merge.is_empty() and pending[0] == merge.tile_id:
			var inserted := _manual_insert(row, int(pending[0]), faces, preferred, order_suits)
			result.slots = inserted
			result.pending_insert_ids = []
			result.insertion = _insertion_plan(inserted, merge)
		return _cache(key, result)
	if novice:
		if preferred.size() == 1:
			groups = _suit_groups(preferred[0].groups, order_suits)
		else:
			var beginner_groups := _novice(values, order_suits)
			if preferred.is_empty() or preferred.any(func(c): return _shows_groups(beginner_groups, c.groups)):
				groups = beginner_groups
		# 若基本新手分组无法表达任何等优候选，则保留普通序，不另造同分裁决。
	result.slots = []
	for group in groups:
		var ids := []
		for value in group.values:
			ids.append(buckets[value].pop_front())
		result.groups.append({"kind": group.kind, "ids": ids})
		result.slots.append_array(ids)
	if not merge.is_empty() and int(discard.get("seat", -1)) == seat and int(discard.get("tile_id", -1)) == merge.discard_id and result.slots.has(merge.tile_id):
		var shifts := []
		for index in result.slots.size():
			var id: int = result.slots[index]
			var from: int = merge.before_slots.find(id)
			if id != merge.tile_id and from >= 0 and from != index:
				shifts.append({"id": id, "from_slot": from, "to_slot": index})
		result.insertion = {"discard_id": merge.discard_id, "make_room": shifts,
			"tile_id": merge.tile_id, "to_slot": result.slots.find(merge.tile_id)}
	return _cache(key, result)

static func _insertion_plan(slots: Array, merge: Dictionary) -> Dictionary:
	var shifts := []
	var crossings := []
	var old: Array = merge.before_slots.filter(func(id): return id != merge.discard_id)
	# Keep the longest unchanged relative sequence on the rack; lift only the few actual reordering tiles.
	var chains := []; var kept := []
	for index in old.size():
		var chain := []
		for before in index:
			if slots.find(old[before]) < slots.find(old[index]) and chains[before].size() > chain.size(): chain = chains[before]
		chain = chain.duplicate(); chain.append(old[index]); chains.append(chain)
		if chain.size() > kept.size(): kept = chain
	for id in old:
		if slots.has(id) and not kept.has(id): crossings.append(id)
	for index in slots.size():
		var id: int = slots[index]
		var from: int = merge.before_slots.find(id)
		if id != merge.tile_id and from >= 0 and from != index:
			shifts.append({"id": id, "from_slot": from, "to_slot": index})
	return {"discard_id": merge.discard_id, "make_room": shifts, "reorder_ids": crossings, "tile_id": merge.tile_id, "to_slot": slots.find(merge.tile_id)}

## Only the incoming tile and its useful companions may form a new block. Other tiles keep their relative order.
static func _manual_insert(row: Array, incoming: int, faces: Dictionary, preferred: Array, suits: Array) -> Array:
	var value: String = faces[incoming]
	var options := []
	for candidate in preferred:
		for group in candidate.groups:
			if group.values.has(value):
				var needed: Array = group.values.duplicate(); needed.erase(value)
				var companions := []
				for other in row:
					if needed.has(faces[other]):
						companions.append(other); needed.erase(faces[other])
				if needed.is_empty(): options.append({"ids": companions, "rank": 100})
	if options.is_empty():
		for a in row.size():
			var va: String = faces[row[a]]
			if va == value: options.append({"ids": [row[a]], "rank": 20})
			elif va.left(-1) == value.left(-1) and absi(int(va.right(1)) - int(value.right(1))) <= 2:
				options.append({"ids": [row[a]], "rank": 10})
			for b in range(a + 1, row.size()):
				var vb: String = faces[row[b]]
				if va == value and vb == value:
					options.append({"ids": [row[a], row[b]], "rank": 30})
				elif va.left(-1) == value.left(-1) and vb.left(-1) == value.left(-1):
					var ranks := [int(value.right(1)), int(va.right(1)), int(vb.right(1))]; ranks.sort()
					if ranks[1] == ranks[0] + 1 and ranks[2] == ranks[1] + 1:
						options.append({"ids": [row[a], row[b]], "rank": 30})
	if options.is_empty(): options.append({"ids": [], "rank": 0})
	var best := []; var best_score := -INF
	for option in options:
		var rest := row.filter(func(id): return not option.ids.has(id))
		var block: Array = option.ids.duplicate(); block.append(incoming)
		block.sort_custom(func(a, b): return faces[a] < faces[b] if faces[a] != faces[b] else a < b)
		for at in range(rest.size() + 1):
			var trial: Array = rest.slice(0, at) + block + rest.slice(at)
			var displacement := 0.0
			for i in row.size(): displacement += absf(trial.find(row[i]) - i)
			var neighbour_cost := 0.0
			if option.ids.is_empty():
				var rank: int = suits.find(value.left(-1)) * 10 + int(value.right(1))
				if at > 0:
					var left: String = faces[rest[at - 1]]
					neighbour_cost += absi(rank - (suits.find(left.left(-1)) * 10 + int(left.right(1))))
				if at < rest.size():
					var right: String = faces[rest[at]]
					neighbour_cost += absi(rank - (suits.find(right.left(-1)) * 10 + int(right.right(1))))
			var score: float = option.rank * 10000.0 - neighbour_cost * 100.0 - displacement
			if score > best_score: best_score = score; best = trial
	return best

func _cache(key: PackedByteArray, result: Dictionary) -> Dictionary:
	_cache_key = key
	_cached = result
	return result.duplicate(true)

static func _valid_id(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and value >= 0 and value < Catalog.COUNT and value == int(value)

## 单张实体即使出现在最近弃牌、弃牌列或已经认领的组引用中，也只扣一次。
static func _known(view: Dictionary, seat: int) -> Dictionary:
	var by_id := {}
	for row in view.players:
		if int(row.seat) == seat:
			for face in row.hand:
				by_id[int(face.id)] = face.value
		for face in row.discards:
			by_id[int(face.id)] = face.value
		for meld in row.melds:
			var mine: bool = int(row.seat) == seat
			if not mine and meld.get("concealed", false) and int(row.get("discard_count", 0)) < int(meld.get("formed_at", row.get("discard_count", 0))) + 2:
				continue
			if not meld.has("tile") or not Catalog.valid_value(str(meld.tile)):
				continue
			for id in meld.get("tile_ids", []):
				by_id[int(id)] = meld.tile
	for event in [view.get("last_discard", {}), view.get("response", {})]:
		if int(event.get("tile_id", -1)) >= 0 and Catalog.valid_value(str(event.get("tile", ""))):
			by_id[int(event.tile_id)] = event.tile
	return Tiles.to_counts(by_id.values())

static func best_candidates(candidates: Array, priority: String) -> Array:
	if priority not in ["multiple", "pattern"]:
		return []
	var key := "remaining_total" if priority == "multiple" else "best_pattern_score"
	var best := -1
	var result := []
	for item in candidates:
		var score := int(item[key])
		if score > best:
			result.clear()
			best = score
		if score == best:
			result.append(item)
	return result

static func _group(kind: String, values: Array) -> Dictionary:
	return {"kind": kind, "values": values}

## 取出已经成组的三张，余下一张为单吊或四张为一组加将的听形。
## 保留四张作为整体，才能表达复合多面听，不能只枚举孤立两张搭子。
static func _candidates(values: Array, full: Array, first_key: int, waits: Dictionary, out: Array) -> void:
	if values.size() in [1, 4]:
		var subset := []
		for tile in waits:
			if _completes(values, tile):
				subset.append(tile)
		if not subset.is_empty():
			_add_candidate(full + [_group("wait_shape", values)], subset, waits, out)
	if values.size() <= 1:
		return
	var seen := {}
	for value in values:
		if seen.has(value):
			continue
		seen[value] = true
		var index := Tiles.value_index(value)
		var run := [value, Tiles.from_index(index + 1), Tiles.from_index(index + 2)] if Tiles.rank(value) <= 7 else []
		for kind in 2:
			var group_key := index * 2 + kind
			if group_key < first_key:
				continue
			var group := [value, value, value] if kind == 0 else run
			if group.is_empty():
				continue
			var rest := values.duplicate()
			var available := true
			for tile in group:
				if not rest.has(tile):
					available = false
					break
				rest.erase(tile)
			if available:
				_candidates(rest, full + [_group("triplet" if kind == 0 else "sequence", group)], group_key, waits, out)

static func _completes(values: Array, tile: String) -> bool:
	if values.size() == 1:
		return values[0] == tile
	var five: Array = values + [tile]
	for pair in Tiles.to_counts(five):
		if five.count(pair) < 2:
			continue
		var three := five.duplicate()
		three.erase(pair)
		three.erase(pair)
		three.sort()
		if three[0] == three[2] or (_near(three[0], three[1], 1) and _near(three[1], three[2], 1)):
			return true
	return false

static func _seven_pairs(values: Array, waits: Dictionary, out: Array) -> void:
	var groups := []
	var singles := []
	for value in Tiles.to_counts(values):
		var count := values.count(value)
		for _pair in range(count / 2):
			groups.append(_group("pair", [value, value]))
		if count % 2 == 1:
			singles.append(value)
	if groups.size() == 6 and singles.size() == 1 and waits.has(singles[0]):
		_add_candidate(groups + [_group("wait_shape", singles)], singles, waits, out)

static func _add_candidate(groups: Array, tiles: Array, waits: Dictionary, out: Array) -> void:
	var total := 0
	var score := 0
	for tile in tiles:
		total += waits[tile].remaining
		score = maxi(score, waits[tile].pattern_score)
	out.append({"groups": groups, "waits": tiles, "remaining_total": total, "best_pattern_score": score})

static func _near(a: String, b: String, distance: int) -> bool:
	return Tiles.suit(a) == Tiles.suit(b) and Tiles.rank(b) - Tiles.rank(a) == distance

## 普通排法只解释相邻结构，不改变门序、升序、同值相邻。
static func _sequential(values: Array) -> Array:
	var groups := []
	var i := 0
	while i < values.size():
		var amount := 1
		var kind := "single"
		if i + 2 < values.size() and values[i] == values[i + 2]:
			kind = "triplet"
			amount = 3
		elif i + 2 < values.size() and _near(values[i], values[i + 1], 1) and _near(values[i + 1], values[i + 2], 1):
			kind = "sequence"
			amount = 3
		elif i + 1 < values.size() and values[i] == values[i + 1]:
			kind = "pair"
			amount = 2
		elif i + 1 < values.size() and (_near(values[i], values[i + 1], 1) or _near(values[i], values[i + 1], 2)):
			kind = "incomplete"
			amount = 2
		groups.append(_group(kind, values.slice(i, i + amount)))
		i += amount
	return groups

static func _suit_groups(groups: Array, suits: Array) -> Array:
	var ordered := []
	for suit in suits:
		for group in groups:
			if Tiles.suit(group.values[0]) == suit:
				ordered.append(group)
	return ordered

static func _shows_groups(shown: Array, structure: Array) -> bool:
	var groups := shown.duplicate()
	for group in structure:
		if group.kind == "wait_shape":
			continue
		if not groups.has(group):
			return false
		groups.erase(group)
	return true

## 无已叫结构时，新手可按门显示已成顺子，例如把112233展示为123、123。
static func _novice(values: Array, suits: Array) -> Array:
	var out := []
	for suit in suits:
		var rest := values.filter(func(v): return Tiles.suit(v) == suit)
		for rank in range(1, 8):
			var seq := [suit + str(rank), suit + str(rank + 1), suit + str(rank + 2)]
			while rest.has(seq[0]) and rest.has(seq[1]) and rest.has(seq[2]):
				for value in seq:
					rest.erase(value)
				out.append(_group("sequence", seq))
		out.append_array(_sequential(rest))
	return out
