extends RefCounted
## Initial slot is the physical tile identity. No view or dealer rotates this array.
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Seats = preload("res://src/domain/Seats.gd")
const COUNT := 108
const SEGMENTS := [
	{"seat": 3, "start": 0, "columns": 14},
	{"seat": 0, "start": 28, "columns": 13},
	{"seat": 1, "start": 54, "columns": 14},
	{"seat": 2, "start": 82, "columns": 13},
]

var _tiles: Array[String] = []
var _taken: Array[bool] = []
var _opened := false
var remaining := 0
var head_index := -1
var tail_index := -1
var break_index := -1

func _init(shuffled_values: Array = []) -> void:
	if not Catalog.valid_deck(shuffled_values):
		return
	_tiles.assign(shuffled_values)
	_taken.resize(COUNT)
	_taken.fill(false)
	remaining = COUNT

func open(dealer: int, red: int) -> bool:
	if _opened or remaining != COUNT or dealer not in range(4) or red not in range(1, 7):
		return false
	var target := Seats.opposite(dealer) if red in [1, 3, 5] else (Seats.previous(dealer) if red == 4 else Seats.next(dealer))
	for segment in SEGMENTS:
		if segment.seat == target:
			break_index = int(segment.start) + red * 2
			head_index = break_index
			tail_index = posmod(break_index - 2, COUNT)
			_opened = true
			return true
	return false

func value(tile_id: int) -> String:
	return _tiles[tile_id] if tile_id >= 0 and tile_id < _tiles.size() else ""

func is_taken(tile_id: int) -> bool:
	return tile_id >= 0 and tile_id < _taken.size() and _taken[tile_id]

func peek_head() -> int:
	return _next_available(head_index, false)

func take_head() -> int:
	return _take(false)

func take_tail() -> int:
	return _take(true)

func _take(tail: bool) -> int:
	var tile_id := _next_available(tail_index if tail else head_index, tail)
	if tile_id < 0:
		return -1
	_taken[tile_id] = true
	remaining -= 1
	if tail:
		tail_index = _successor(tile_id, true)
	else:
		head_index = _successor(tile_id, false)
	return tile_id

func _next_available(start: int, tail: bool) -> int:
	if not _opened or remaining == 0:
		return -1
	var slot := start
	for step in COUNT:
		if not _taken[slot]:
			return slot
		slot = _successor(slot, tail)
	return -1

static func _successor(slot: int, tail: bool) -> int:
	if not tail:
		return (slot + 1) % COUNT
	return (slot + 1) % COUNT if slot % 2 == 0 else posmod(slot - 3, COUNT)

func slot_info(tile_id: int) -> Dictionary:
	if tile_id < 0 or tile_id >= _tiles.size():
		return {}
	for segment in SEGMENTS:
		if tile_id >= segment.start and tile_id < segment.start + segment.columns * 2:
			return {"id": tile_id, "seat": segment.seat, "column": (tile_id - int(segment.start)) / 2, "layer": tile_id % 2, "taken": _taken[tile_id]}
	return {}

func occupied_slots() -> Array[int]:
	var result: Array[int] = []
	for tile_id in _taken.size():
		if not _taken[tile_id]:
			result.append(tile_id)
	return result

func flip_landing(tile_id: int) -> Dictionary:
	if tile_id < 0 or tile_id >= _taken.size() or _taken[tile_id]:
		return {}
	if tile_id % 2 == 0 and not _taken[tile_id + 1]:
		return {"source_id": tile_id, "column": tile_id / 2, "stack_count": 2}
	# Bottom tile moves visually to the next nonempty column; the wall stays untouched.
	if tile_id % 2 == 1:
		for distance in range(1, COUNT / 2):
			var upper: int = posmod(tile_id - 1 + distance * 2, COUNT)
			var count := int(not _taken[upper]) + int(not _taken[upper + 1])
			if count > 0:
				return {"source_id": tile_id, "column": upper / 2, "stack_count": count + 1}
	return {"source_id": tile_id, "column": tile_id / 2, "stack_count": 1}

func snapshot() -> Dictionary:
	# Authority-only; clients receive occupancy, never the shuffled values.
	return {"tiles": _tiles.duplicate(), "taken": _taken.duplicate(), "head_index": head_index, "tail_index": tail_index, "break_index": break_index, "remaining": remaining}


func restore(state: Dictionary) -> bool:
	if state.get("tiles", []) is Array and not Catalog.valid_deck(state.tiles):
		return false
	var taken: Variant = state.get("taken", [])
	var head: Variant = state.get("head_index", -1)
	var tail: Variant = state.get("tail_index", -1)
	var broken: Variant = state.get("break_index", -1)
	if not taken is Array or taken.size() != COUNT:
		return false
	for index in COUNT:
		if not taken[index] is bool:
			return false
	if head is int and (head < 0 or head >= COUNT): return false
	if tail is int and (tail < 0 or tail >= COUNT): return false
	if broken is int and (broken < -1 or broken >= COUNT): return false
	_tiles.assign(state.tiles)
	_taken.assign(taken)
	head_index = head
	tail_index = tail
	break_index = broken
	_opened = broken >= 0
	remaining = int(COUNT - _taken.count(true))
	if remaining < 0 or remaining > COUNT:
		return false
	return true
