extends RefCounted
## Local display state. Sync the selected room's authoritative view of this player's hand.

const Catalog := preload("res://src/domain/TileCatalog.gd")
const NO_TILE := -1

var _suit_order: Array = Catalog.SUITS.duplicate()
var _room_instance_id := ""
var _round_number := 0
var _prompt_id := -1
var _owned := {}
var _ordered: Array[int] = []
var _pending: Array[int] = []
var _draw_id := NO_TILE
var _draw_merged := false
var _selected_id := NO_TILE
var _manual := false
var _dragged_id := NO_TILE
var _gap_slot := -1
var _preview: Array[int] = []
var _draw_merge := {}


func sync_hand(room_instance_id: String, round_number: int, prompt_id: int, own_faces: Array, draw_id: int = NO_TILE) -> bool:
	if room_instance_id.is_empty() or round_number < 1 or prompt_id < 0:
		return false
	if room_instance_id == _room_instance_id and round_number < _round_number:
		return false
	var new_round := room_instance_id != _room_instance_id or round_number != _round_number
	if not new_round and prompt_id < _prompt_id:
		return false
	var next_owned := {}
	for face in own_faces:
		if not face is Dictionary:
			return false
		var raw_id = face.get("id")
		var value = face.get("value")
		if not (raw_id is int or raw_id is float):
			return false
		if raw_id is float and (not is_finite(raw_id) or raw_id != floorf(raw_id)):
			return false
		if raw_id < 0 or raw_id >= Catalog.COUNT:
			return false
		var id := int(raw_id)
		if next_owned.has(id):
			return false
		if not value is String or not Catalog.valid_value(value):
			return false
		if not new_round and _owned.get(id, value) != value:
			return false
		next_owned[id] = value
	if draw_id != NO_TILE and not next_owned.has(draw_id):
		return false
	if new_round or prompt_id != _prompt_id:
		clear_selection()
	_room_instance_id = room_instance_id
	_round_number = round_number
	_prompt_id = prompt_id
	if not new_round and next_owned == _owned and draw_id == _draw_id:
		return true
	_draw_merge = {}
	if not new_round and _draw_id != NO_TILE and next_owned.has(_draw_id) and _draw_id != draw_id:
		var removed := _ordered.filter(func(id): return not next_owned.has(id))
		if removed.size() == 1:
			_draw_merge = {"tile_id": _draw_id, "discard_id": removed[0], "before_slots": _ordered.duplicate()}
	if new_round:
		_manual = false
	_clear_drag()
	_owned = next_owned
	if new_round or draw_id != _draw_id: _draw_merged = false
	_draw_id = draw_id
	if not _owned.has(_selected_id):
		_selected_id = NO_TILE
	if not _manual:
		_sort_owned()
		return true
	_ordered = _ordered.filter(func(id): return (id != _draw_id or _draw_merged) and _owned.has(id))
	_pending = _pending.filter(func(id): return id != _draw_id and _owned.has(id))
	# A manual row keeps new tiles pending until the player places them or restores automatic order.
	for id in _owned:
		if id != _draw_id and not id in _ordered and not id in _pending:
			_pending.append(id)
	return true


func set_suit_order(order: Array) -> bool:
	if order.size() != Catalog.SUITS.size():
		return false
	for suit in Catalog.SUITS:
		if not order.has(suit):
			return false
	_suit_order = order.duplicate()
	if not _manual:
		restore_order()
	return true


func restore_order() -> void:
	_clear_drag()
	_manual = false
	_sort_owned()


## A second tap on the same entity returns its ID for the authority to validate.
func tap(tile_id: int) -> int:
	if _dragged_id != NO_TILE or not _owned.has(tile_id):
		return NO_TILE
	if _selected_id == tile_id:
		return tile_id
	_selected_id = tile_id
	return NO_TILE


func clear_selection() -> void:
	_selected_id = NO_TILE


func begin_drag(tile_id: int) -> bool:
	var row := _drag_row(tile_id)
	var slot := row.find(tile_id)
	if _dragged_id != NO_TILE or slot < 0:
		return false
	clear_selection()
	_dragged_id = tile_id
	_gap_slot = slot
	_preview = row.duplicate()
	_preview[slot] = NO_TILE
	return true


func _drag_row(id: int) -> Array[int]:
	if id == _draw_id and not _draw_merged:
		var row: Array[int] = _ordered + _pending
		row.append(_draw_id)
		return row
	return _ordered + _pending if _pending.has(id) else _ordered


func move_gap(to_slot: int) -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	if _dragged_id == NO_TILE or to_slot < 0 or to_slot >= _preview.size() or to_slot == _gap_slot:
		return moves
	var step := 1 if to_slot > _gap_slot else -1
	for from_slot in range(_gap_slot + step, to_slot + step, step):
		var id := _preview[from_slot]
		var destination := from_slot - step
		_preview[destination] = id
		moves.append({"id": id, "from_slot": from_slot, "to_slot": destination})
	_preview[to_slot] = NO_TILE
	_gap_slot = to_slot
	return moves


func commit_drag(to_slot: int) -> Array[Dictionary]:
	if _dragged_id == NO_TILE:
		return []
	if to_slot < 0 or to_slot >= _preview.size() or to_slot == _drag_row(_dragged_id).find(_dragged_id):
		return cancel_drag()
	var moves := move_gap(to_slot)
	_preview[to_slot] = _dragged_id
	moves.append({"id": _dragged_id, "from_slot": -1, "to_slot": to_slot})
	if _dragged_id == _draw_id and not _draw_merged:
		_ordered = _preview.duplicate()
		_pending.clear()
		_draw_merged = true
	elif _pending.has(_dragged_id):
		if to_slot <= _ordered.size():
			_pending.erase(_dragged_id)
			_ordered.insert(to_slot, _dragged_id)
		else:
			_pending.assign(_preview.slice(_ordered.size()))
	else:
		_ordered = _preview.duplicate()
	_manual = true
	_clear_drag()
	return moves


func cancel_drag() -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	if _dragged_id == NO_TILE:
		return moves
	var origin := _drag_row(_dragged_id)
	for to_slot in origin.size():
		var id := origin[to_slot]
		var from_slot := _preview.find(id)
		if from_slot != to_slot:
			moves.append({"id": id, "from_slot": from_slot, "to_slot": to_slot})
	_clear_drag()
	return moves


func view() -> Dictionary:
	return {
		"slots": _ordered.duplicate() if _dragged_id == NO_TILE else _preview.duplicate(),
		"suit_order": _suit_order.duplicate(),
		"draw_merge": _draw_merge.duplicate(true),
		"draw_id": _draw_id,
		"draw_merged": _draw_merged or (_dragged_id == _draw_id and _draw_id >= 0),
		"pending_insert_ids": [] if _pending.has(_dragged_id) or (_dragged_id == _draw_id and _draw_id >= 0) else _pending.duplicate(),
		"selected_id": _selected_id,
		"dragged_id": _dragged_id,
		"gap_slot": _gap_slot,
		"manual": _manual,
	}


## 显示、点击和拖拽须使用同一序列；建议器只能重排现有自动手牌行。
func apply_auto_slots(slots: Array) -> bool:
	if _manual or _dragged_id != NO_TILE or not _pending.is_empty() or slots.size() != _ordered.size():
		return false
	var seen := {}
	for id in slots:
		if not id is int or not _ordered.has(id) or seen.has(id):
			return false
		seen[id] = true
	_ordered.assign(slots)
	return true

func apply_manual_insertion(slots: Array) -> bool:
	if not _manual or _dragged_id != NO_TILE or _pending.is_empty(): return false
	var current: Array = _ordered + _pending
	var expected := current.duplicate(); expected.sort()
	var provided := slots.duplicate(); provided.sort()
	if expected != provided: return false
	_ordered.assign(slots); _pending.clear()
	return true

func apply_sort_plan(slots: Array, merge_draw: bool) -> bool:
	if _dragged_id != NO_TILE: return false
	var expected: Array = _owned.keys().filter(func(id): return merge_draw or id != _draw_id)
	var received := slots.duplicate(); received.sort(); expected.sort()
	if received != expected: return false
	_draw_merged = merge_draw and _draw_id >= 0
	_ordered.assign(slots); _pending.clear(); _manual = true; clear_selection()
	return true

## Apply once on recovery; live acknowledgements must not replace an active local drag.
func restore_shared(display: Dictionary) -> bool:
	var merged: bool = display.get("draw_merged", false)
	var keys: Dictionary = display.get("own_keys", {})
	var owned_keys := {}
	for id in _owned:
		if (id != _draw_id or merged) and keys.has(str(id)):
			owned_keys[keys[str(id)]] = id
	var slots := []
	var pending := []
	var seen := {}
	for name in ["slots", "pending"]:
		for key in display.get(name, []):
			if not owned_keys.has(key) or seen.has(key): return false
			seen[key] = true
			if name == "slots": slots.append(owned_keys[key])
			else: pending.append(owned_keys[key])
	if seen.size() != _owned.size() - int(_draw_id >= 0 and not merged): return false
	_draw_merged = merged and _draw_id >= 0
	_ordered.assign(slots)
	_pending.assign(pending)
	_manual = display.get("manual", false)
	clear_selection()
	_clear_drag()
	return true


func _sort_owned() -> void:
	_ordered.clear()
	_pending.clear()
	for id in _owned:
		if id != _draw_id or _draw_merged:
			_ordered.append(id)
	_ordered.sort_custom(_less_than)


func _less_than(first: int, second: int) -> bool:
	var first_value: String = _owned[first]
	var second_value: String = _owned[second]
	var first_suit := _suit_order.find(first_value.left(-1))
	var second_suit := _suit_order.find(second_value.left(-1))
	if first_suit != second_suit:
		return first_suit < second_suit
	if first_value != second_value:
		return first_value < second_value
	return first < second


func _clear_drag() -> void:
	_dragged_id = NO_TILE
	_gap_slot = -1
	_preview.clear()
