extends RefCounted

const CFG := preload("res://src/anshun/scoring/RulesConfig.gd")
const Tiles := preload("res://src/anshun/scoring/Tiles.gd")

static func profile(round: Dictionary, seat: int, flip: String, called: bool, draw: bool) -> Array:
	var meta: Dictionary = round.round_meta
	if called and seat == int(meta.get("burn_chicken_seat", -1)):
		return []
	var player: Dictionary = round.players[seat]
	var items: Array = []
	var related := Tiles.flip_related(flip)
	var charge_chickens: Dictionary = meta.get("charge_chickens", {})
	var discard_ids: Array = player.get("discard_ids", [])
	for index in player.discards.size():
		var tile: String = player.discards[index]
		var id := _tile_id(discard_ids, index)
		var charge: Dictionary = charge_chickens.get(tile, {})
		var is_charge: bool = charge.get("owner", -1) == seat and charge.get("location", "") == "discard" and charge.get("discard_id", -1) == id
		_append(items, seat, tile, [id], "discard", related, called, is_charge)
	for discard in meta.get("resolved_chicken_discards", []):
		if discard.owner == seat and not discard.get("charge", false):
			_append(items, seat, discard.tile, [int(discard.get("discard_id", -1))], "discard", related, called)
	if called and not draw:
		var concealed_ids: Array = player.get("concealed_ids", [])
		for index in player.concealed.size():
			_append(items, seat, player.concealed[index], [_tile_id(concealed_ids, index)], "hand", related, true)
	for meld in player.melds:
		if meld.get("robbed", false):
			continue
		var is_pung: bool = meld.kind == "pung"
		var ids := meld_ids(meld, 3 if is_pung else 4)
		_append(items, seat, meld.tile, ids, "meld" if is_pung else "kong", related, called)
	return items

static func total(items: Array) -> float:
	var amount := 0.0
	for item in items:
		amount += absf(item.amount)
	return amount

static func meld_ids(meld: Dictionary, count: int) -> Array:
	var ids: Array = []
	for index in count:
		ids.append(_tile_id(meld.get("tile_ids", []), index))
	return ids

static func _tile_id(ids: Array, index: int) -> int:
	return int(ids[index]) if index < ids.size() else -1

static func _append(items: Array, owner: int, tile: String, ids: Array, source: String, related: Array, called: bool, charge: bool = false) -> void:
	var chicken := Tiles.is_chicken(tile)
	if not chicken and (source == "discard" or not called or not related.has(tile)):
		return
	var unit := CFG.SCORE_CHARGE_CHICKEN if charge else CFG.SCORE_CALL_CHICKEN
	var kind := "charge" if charge else "chicken"
	var label := "冲锋鸡" if charge else "普通鸡"
	if chicken and related.has(tile):
		unit *= CFG.SCORE_FLIP_DOUBLE
		label = "冲锋金鸡" if charge else "金鸡"
	elif not chicken:
		unit = CFG.SCORE_FLIP_CHICKEN
		kind = "flip"
		label = "翻鸡"
	var tiles: Array = []
	tiles.resize(ids.size())
	tiles.fill(tile)
	items.append({"owner": owner, "kind": kind, "label": label, "source": source,
		"tiles": tiles, "tile_ids": ids, "amount": unit * ids.size() * (1 if called else -1)})
