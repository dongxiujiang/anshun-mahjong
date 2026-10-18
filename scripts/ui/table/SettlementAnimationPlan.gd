extends RefCounted
## Read-only presentation of an already settled result. Never calls settle or
## derives money from tile counts, scoring constants, or the round multiplier.
## Matrices use absolute seats: matrix[receiver][payer] is positive income.
## Winners remain absolute seats, sorted by their offset from human_seat.

const SCORING := preload("res://scripts/core/ScoringEngine.gd")
const TILE := preload("res://scripts/core/Tiles.gd")
const CONFIG := preload("res://scripts/autoload/GameConfig.gd")
const WIN_REASONS := ["自摸基础分", "干扣", "大干扣", "报听胡牌", "抢杠胡基础分",
	"点炮基础分（叫牌）", "点炮基础分（未叫牌）", "牌型差额", "杠开", "海底捞"]
const DRAW_KONG_REASONS := ["暗杠", "加杠", "明杠", "查叫暗杠", "查叫加杠",
	"查叫明杠", "杠中鸡", "未叫牌杠分", "未叫牌杠中鸡"]

## Each stage has key/matrix; win also has winner. flip/chicken additionally
## expose gross: each called seat's item total BEFORE pairwise comparison.
## Uncalled debts are actual payments in matrices, not positive gross income.
## Inputs and all their nested arrays/dictionaries are left untouched.
static func build(result: Dictionary, meta: Dictionary, players: Array, human_seat: int = 0) -> Dictionary:
	var transfers: Array = result.get("transfers", [])
	var items: Array = result.get("items", [])
	var winners := _winners(result, meta, human_seat)
	var is_draw := winners.is_empty()
	var called := _called(result, winners)
	var all_called_draw := is_draw and (bool(result.get("all_called_draw", meta.get("all_called_draw", false))) or called.all(func(value): return value))
	var burned := int(meta.get("burn_chicken_seat", -1))
	if burned not in range(4):
		burned = -1
	var flip_tiles: Array = [] if is_draw else TILE.flip_related(str(meta.get("flip_tile", "")))
	var gold_tiles: Array = []
	for tile in flip_tiles:
		if TILE.is_chicken(str(tile)):
			gold_tiles.append(tile)
	var final: Array = SCORING.pairwise_payments(transfers)
	var deltas := _deltas(result, final)
	_reconcile(final, deltas)
	var stages: Array = []
	var plan := {"stages": stages, "final": final, "deltas": deltas, "winners": winners,
		"flip_tiles": flip_tiles, "gold_tiles": gold_tiles, "burned": burned,
		"all_called_draw": all_called_draw, "is_draw": is_draw, "called": called,
		"identities": _identities(result, meta, players, winners, called)}
	if all_called_draw:
		return plan

	var flip_gross := [0.0, 0.0, 0.0, 0.0]
	var chicken_gross := [0.0, 0.0, 0.0, 0.0]
	if not is_draw:
		_collect_gross(items, called, burned, gold_tiles, flip_gross, chicken_gross)
	var flip_matrix := _compare(flip_gross, called, burned)
	var chicken_matrix := _compare(chicken_gross, called, burned)
	var kong_matrix := _zero()
	var win_matrices: Dictionary = {}
	var win_reasons := _win_reasons(items)
	for winner in winners:
		win_matrices[winner] = _zero()

	# These reason-only rows lose their original meld identity. Only classify
	# them when retained metadata and the actual rows identify their source.
	var reversed_kongs: Dictionary = {}
	var kong_chickens: Dictionary = {}
	if not is_draw:
		reversed_kongs = _uncalled_categories(transfers, players, called, "未叫牌杠分", gold_tiles)
		kong_chickens = _uncalled_categories(transfers, players, called, "未叫牌杠中鸡", gold_tiles)
	for index in transfers.size():
		var entry: Dictionary = transfers[index]
		var payer := int(entry.get("from", -1))
		var receiver := int(entry.get("to", -1))
		var amount := float(entry.get("amount", 0.0))
		var reason := str(entry.get("reason", ""))
		if payer not in range(4) or receiver not in range(4) or payer == receiver or receiver == burned or amount <= 0.0:
			continue
		if is_draw:
			if reason in DRAW_KONG_REASONS:
				_pay(kong_matrix, payer, receiver, amount)
			continue
		if reason in ["暗杠", "加杠"] or reversed_kongs.get(index, "") == "kong":
			# The ledger base payment is used, never the kong item's amount:
			# chicken_amount/flip_amount already belong to the chicken comparison.
			_pay(kong_matrix, payer, receiver, amount)
		elif reason in ["未叫牌杠中鸡", "未叫牌出牌鸡"] and not called[payer] and called[receiver]:
			var category := str(kong_chickens.get(index, ""))
			if reason == "未叫牌出牌鸡":
				category = _discard_category(players, meta, payer, gold_tiles)
			if category == "flip":
				_pay(flip_matrix, payer, receiver, amount)
			elif category == "chicken":
				_pay(chicken_matrix, payer, receiver, amount)
		elif win_matrices.has(receiver) and reason in win_reasons:
			_pay(win_matrices[receiver], payer, receiver, amount)

	if not is_draw:
		stages.append({"key": "flip", "matrix": flip_matrix, "gross": flip_gross})
		stages.append({"key": "chicken", "matrix": chicken_matrix, "gross": chicken_gross})
	stages.append({"key": "kong", "matrix": kong_matrix})
	for winner in winners:
		stages.append({"key": "win", "matrix": win_matrices[winner], "winner": winner})
	# Missing item/source data, ambiguous debts, exposed win-round kongs and
	# penalties remain here. This is only an aggregate display difference;
	# it must never invent scoring rules or a missing base payment.
	var shown := _zero()
	for stage in stages:
		for first in 4:
			for second in 4:
				shown[first][second] += stage.matrix[first][second]
	var residual := _zero()
	var has_residual := false
	for first in 4:
		for second in range(first + 1, 4):
			var difference: float = final[first][second] - shown[first][second]
			residual[first][second] = difference
			residual[second][first] = -difference
			if difference != 0.0:
				has_residual = true
	if has_residual:
		stages.append({"key": "other", "matrix": residual})
	return plan

## 只读已结算的独立项目金额，不重定价、不合计三家收入或借用玩家净分。
## 来源方位以该玩家自己为基准，与观看者/庄家位置无关。
static func _identities(result: Dictionary, meta: Dictionary, players: Array, winners: Array, called: Array) -> Array:
	var identities: Array = []
	var items: Array = result.get("items", [])
	var source := int(meta.get("discard_seat", -1))
	var self_draw := bool(meta.get("self_draw", false))
	var robbed := bool(meta.get("robbed_kong", false))
	for seat in 4:
		var won := seat in winners
		var title := "叫牌" if called[seat] else "未叫牌"
		var detail: Array[String] = []
		if won:
			var seat_items: Array = items[seat] if seat < items.size() else []
			var ready := seat < players.size() and players[seat] != null and bool(players[seat].ready)
			var has_ready_item := false
			for item in seat_items:
				if str(item.get("kind", "")) == "ready":
					ready = true
					has_ready_item = true
			var direction: String = ["", "下家", "对家", "上家"][posmod(source - seat, 4)] if source in range(4) else ""
			var origin := "胡牌"
			if self_draw:
				origin = "报听自摸" if ready else "自摸"
			elif robbed:
				# 抢杠金额属于抢杠基础项，报听项另列，避免把 12+24 混成来源总分。
				origin = ("报听" if ready and not has_ready_item else "") + ("抢杠" + direction if direction != "" else "抢杠胡")
			elif ready:
				origin = "报听胡" + direction
			elif direction != "":
				origin = direction + "放炮"
			var patterns: Array[String] = []
			var extras: Array[String] = []
			var used_origin := false
			for item in seat_items:
				var kind := str(item.get("kind", ""))
				var caption := str(item.get("label", ""))
				if not used_origin and _identity_source_item(item, self_draw, robbed, ready):
					origin = _identity_with_amount(origin, item)
					used_origin = true
					continue
				if kind == "ready": caption = "报听"
				elif caption == "清龙对": caption = "清龙七对"
				elif caption == "自摸": caption = "自摸基础分"
				if caption == "": continue
				var entry := _identity_with_amount(caption, item)
				if kind == "pattern" or (kind == "bonus" and caption in ["干扣", "大干扣"]):
					patterns.append(entry)
				elif kind in ["ready", "win"] or (kind == "bonus" and caption == "自摸基础分"):
					# 报听自摸的普通自摸项仍单列；大牌型/干扣没有该项时不补造 4 分。
					detail.append(entry)
				elif kind == "bonus":
					extras.append(entry)
			detail.append_array(patterns)
			detail.append_array(extras)
			title = "胡牌 · " + origin
		identities.append({"title": title, "detail": " · ".join(detail), "winner": won, "called": called[seat]})
	return identities

static func _identity_source_item(item: Dictionary, self_draw: bool, robbed: bool, ready: bool) -> bool:
	var kind := str(item.get("kind", ""))
	var caption := str(item.get("label", ""))
	if robbed and not self_draw:
		return kind == "win" and caption == "抢杠胡基础分"
	if ready:
		return kind == "ready"
	if self_draw:
		return kind in ["bonus", "win"] and caption in ["自摸", "自摸基础分"]
	return kind == "win" and caption in ["点炮基础分（叫牌）", "点炮基础分（未叫牌）"]

static func _identity_with_amount(caption: String, item: Dictionary) -> String:
	var value = item.get("amount")
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]: return caption
	var amount := float(value)
	if not is_finite(amount): return caption
	var signed := "%+.0f" % amount if amount == floor(amount) else ("+" if amount > 0.0 else "") + str(amount)
	return caption + " " + signed

static func _winners(result: Dictionary, meta: Dictionary, human_seat: int) -> Array:
	var source: Array = result.get("winners", [])
	if source.is_empty():
		source = meta.get("winners", [])
	if source.is_empty() and int(meta.get("winner", -1)) in range(4):
		source = [int(meta.winner)]
	var winners: Array = []
	for value in source:
		var seat := int(value)
		if seat in range(4) and seat not in winners:
			winners.append(seat)
	winners.sort_custom(func(a, b): return posmod(int(a) - human_seat, 4) < posmod(int(b) - human_seat, 4))
	return winners

static func _called(result: Dictionary, winners: Array) -> Array:
	var source: Array = result.get("called", [])
	var status: Array = result.get("status", [])
	var called: Array = []
	for seat in 4:
		if seat < source.size():
			called.append(bool(source[seat]))
		else:
			# RoundState.build_result retains the settled status but omits
			# ScoringEngine's called array. Do not rerun hand analysis here.
			called.append(seat in winners or (seat < status.size() and str(status[seat]).begins_with("叫牌")))
	return called

static func _collect_gross(items: Array, called: Array, burned: int, gold: Array, flip: Array, chicken: Array) -> void:
	for seat in mini(4, items.size()):
		if not called[seat] or seat == burned:
			continue
		for item in items[seat]:
			var kind := str(item.get("kind", ""))
			if kind == "flip":
				flip[seat] += maxf(0.0, float(item.get("amount", 0.0)))
			elif kind in ["chicken", "charge"]:
				# group_chicken_items retains only the FIRST source, even when
				# tiles combine hand/meld/discard. Split by tiles/unit_amount,
				# never by that source or the first tile of a grouped item.
				_split_chickens(item, float(item.get("amount", 0.0)), gold, flip, chicken, seat, true)
			elif kind == "kong":
				flip[seat] += maxf(0.0, float(item.get("flip_amount", 0.0)))
				_split_chickens(item, float(item.get("chicken_amount", 0.0)), gold, flip, chicken, seat, false)

static func _split_chickens(item: Dictionary, amount: float, gold: Array, flip: Array, chicken: Array, seat: int, use_unit: bool) -> void:
	var tiles: Array = item.get("tiles", [])
	if tiles.is_empty() and str(item.get("tile", "")) != "":
		tiles = [str(item.tile)]
	if tiles.is_empty() or amount <= 0.0:
		# An amount with no identifiable tile stays in the ledger residual.
		return
	var unit := amount / tiles.size()
	if use_unit:
		unit = maxf(0.0, float(item.get("unit_amount", unit)))
	for raw_tile in tiles:
		var tile := str(raw_tile)
		if not TILE.is_chicken(tile):
			continue
		if tile in gold:
			flip[seat] += unit
		else:
			chicken[seat] += unit

static func _compare(gross: Array, called: Array, burned: int) -> Array:
	var matrix := _zero()
	for first in 4:
		for second in range(first + 1, 4):
			if not called[first] and not called[second]:
				continue
			var difference: float = gross[first] - gross[second]
			if difference > 0.0 and first != burned:
				_pay(matrix, second, first, difference)
			elif difference < 0.0 and second != burned:
				_pay(matrix, first, second, -difference)
	return matrix

static func _player_array(players: Array, seat: int, property: String) -> Array:
	if seat >= players.size() or players[seat] == null:
		return []
	var player = players[seat]
	var value = player.get(property, []) if player is Dictionary else player.get(property)
	return value if value is Array else []

static func _uncalled_categories(transfers: Array, players: Array, called: Array, reason: String, gold: Array) -> Dictionary:
	var categories: Dictionary = {}
	var chicken_debt := reason == "未叫牌杠中鸡"
	for owner in 4:
		if called[owner]:
			continue
		var meld_categories: Array = []
		var unknown_tile := false
		for meld in _player_array(players, owner, "melds"):
			if bool(meld.get("robbed", false)) or str(meld.get("kind", "")) not in ["kong", "add_kong"]:
				continue
			if chicken_debt:
				var tile := str(meld.get("tile", ""))
				if tile == "":
					unknown_tile = true
				elif TILE.is_chicken(tile):
					meld_categories.append("flip" if tile in gold else "chicken")
			else:
				var own_kong := str(meld.get("kind", "")) == "add_kong" or bool(meld.get("concealed", false))
				meld_categories.append("kong" if own_kong else "other")
		if meld_categories.is_empty() or unknown_tile:
			continue
		for receiver in 4:
			if not called[receiver]:
				continue
			var rows: Array = []
			for index in transfers.size():
				var entry: Dictionary = transfers[index]
				if str(entry.get("reason", "")) == reason and int(entry.get("from", -1)) == owner and int(entry.get("to", -1)) == receiver:
					rows.append(index)
			if meld_categories.all(func(category): return category == meld_categories[0]):
				for index in rows:
					categories[index] = meld_categories[0]
			elif rows.size() == meld_categories.size():
				if chicken_debt:
					# Mixed gold/non-gold debts: recognize recorded amount groups
					# using meld counts, without recalculating either group's rate.
					var amounts: Array = []
					for index in rows:
						var amount := float(transfers[index].get("amount", 0.0))
						if amount not in amounts:
							amounts.append(amount)
					amounts.sort()
					if amounts.size() != 2:
						continue
					var gold_rows: Array = rows.filter(func(index): return float(transfers[index].get("amount", 0.0)) == float(amounts[1]))
					if gold_rows.size() != meld_categories.count("flip") or float(amounts[0]) <= 0.0:
						continue
					for index in rows:
						categories[index] = "flip" if index in gold_rows else "chicken"
				else:
					# ScoringEngine emits one reversed-base row per meld, in meld
					# order for each recipient. An incomplete/aggregated mixed set
					# cannot identify exposed versus own kongs and stays residual.
					for offset in rows.size():
						categories[rows[offset]] = meld_categories[offset]
	return categories

static func _discard_category(players: Array, meta: Dictionary, owner: int, gold: Array) -> String:
	var tiles := _player_array(players, owner, "discards").duplicate()
	for record in meta.get("resolved_chicken_discards", []):
		if int(record.get("owner", -1)) == owner:
			tiles.append(str(record.get("tile", "")))
	var category := ""
	for value in tiles:
		var tile := str(value)
		if not TILE.is_chicken(tile):
			continue
		var next := "flip" if tile in gold else "chicken"
		if category != "" and category != next:
			# The combined debt no longer tells us which tiles were charge
			# chickens. A mixed-class amount cannot be split from tile counts.
			return ""
		category = next
	return category

static func _win_reasons(items: Array) -> Array:
	var reasons := WIN_REASONS.duplicate()
	# Labels identify actual transfers; pattern score values are never read.
	for spec in CONFIG.PATTERNS:
		reasons.append(str(spec.get("label", "")))
	for seat_items in items:
		for item in seat_items:
			if str(item.get("kind", "")) in ["win", "pattern", "ready", "bonus"]:
				var label := str(item.get("label", ""))
				if label != "" and label not in reasons:
					reasons.append(label)
	return reasons

static func _deltas(result: Dictionary, matrix: Array) -> Array:
	var source: Array = result.get("deltas", [])
	var deltas: Array = []
	for seat in 4:
		var total := 0.0
		for value in matrix[seat]:
			total += float(value)
		deltas.append(float(source[seat]) if seat < source.size() else total)
	return deltas

static func _reconcile(matrix: Array, deltas: Array) -> void:
	var gaps: Array = []
	for seat in 4:
		var total := 0.0
		for value in matrix[seat]:
			total += float(value)
		gaps.append(float(deltas[seat]) - total)
	# Settled deltas are zero-sum. Pair only their aggregate missing amounts,
	# deterministically, preserving antisymmetry and all recorded pair flows.
	# These balancing entries have no invented scoring reason and go to other.
	for receiver in 4:
		if float(gaps[receiver]) <= 0.0:
			continue
		for payer in 4:
			if float(gaps[payer]) >= 0.0:
				continue
			var amount := minf(float(gaps[receiver]), -float(gaps[payer]))
			_pay(matrix, payer, receiver, amount)
			gaps[receiver] -= amount
			gaps[payer] += amount

static func _zero() -> Array:
	return [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]

static func _pay(matrix: Array, payer: int, receiver: int, amount: float) -> void:
	matrix[receiver][payer] += amount
	matrix[payer][receiver] -= amount
