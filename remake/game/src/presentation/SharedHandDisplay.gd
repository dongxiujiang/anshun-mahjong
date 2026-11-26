extends RefCounted
## Authority-side presentation of already-owned tiles. The round never reads this state.
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Layout = preload("res://src/presentation/TableLayout.gd")
const PublicPlacement = preload("res://src/presentation/PublicTablePlacement.gd")
const Arrangement = preload("res://src/presentation/HandArrangement.gd")

var _keys: Array[String] = []
var _rows := []
var _public_origins := {}
var _placement
var _event_cursor := 0
var _prompt := -1
var _motion_serial := 0

func _init(use_saved_layout: bool=true) -> void:
	_placement=PublicPlacement.new(use_saved_layout)
	var salt := Crypto.new().generate_random_bytes(32).hex_encode()
	for id in Catalog.COUNT:
		_keys.append(("%s/%d" % [salt, id]).sha256_text().left(32))
	for seat in 4:
		_rows.append({"cards": [], "draw": -1, "slots": [], "deal_keys": [], "pending": [], "manual": false,
			"suits": Catalog.SUITS.duplicate(), "preview": [], "selected": -1, "dragged": -1, "position": []})

func clear_gesture(seat: int) -> void:
	var row: Dictionary = _rows[seat]
	row.preview = []
	row.dragged = -1
	row.selected = -1
	row.position = []

func sync(round_state, preferences: Array = []) -> void:
	_placement.sync_status(round_state)
	for player in round_state.players:
		var row: Dictionary = _rows[player.seat]
		var profile: Dictionary = preferences[player.seat] if preferences.size() == 4 else {}
		if profile.has("suit_order"):
			row.suits = profile.suit_order.duplicate()
		if _prompt != round_state.prompt_id:
			row.selected = -1
			row.motion = {}
		if row.cards == player.hand and row.draw == player.draw_id:
			continue
		clear_gesture(player.seat)
		var before: Array = row.slots + row.pending
		var removed: Array = row.cards.filter(func(id): return not player.hand.has(id))
		row.merge = {"tile_id": row.draw, "discard_id": removed[0], "before_slots": before} if row.draw >= 0 and player.hand.has(row.draw) and row.draw != player.draw_id and removed.size() == 1 else {}
		if row.draw != player.draw_id: row.draw_merged = false
		row.cards = player.hand.duplicate()
		row.draw = player.draw_id
		var regular: Array = row.cards.filter(func(id): return id != row.draw)
		if row.manual:
			row.slots = row.slots.filter(func(id): return regular.has(id))
			row.pending = row.pending.filter(func(id): return regular.has(id))
			for id in regular:
				if not row.slots.has(id) and not row.pending.has(id):
					row.pending.append(id)
		else:
			regular.sort_custom(func(a, b):
				var va: String = round_state.wall.value(a)
				var vb: String = round_state.wall.value(b)
				var sa: int = row.suits.find(va.left(-1))
				var sb: int = row.suits.find(vb.left(-1))
				return sa < sb if sa != sb else (va < vb if va != vb else a < b))
			row.slots = regular
			row.pending = []
			if profile.get("novice", false):
				# Same owned/public inputs as the live client; only opaque slot order leaves the authority.
				var arranged := Arrangement.new().arrange(round_state.snapshot_for(player.seat),
					{"slots": regular, "suit_order": row.suits}, profile.get("hand_priority", "multiple"), true)
				if arranged.has("slots"):
					row.slots = arranged.slots
	_prompt = round_state.prompt_id
	while _event_cursor < round_state.events.size():
		var event: Dictionary = round_state.events[_event_cursor]
		_event_cursor += 1
		_placement.consume(round_state, event)
		match event.type:
			"deal":
				_rows[event.seat].deal_keys.append_array(event.ids.map(_key))
			"discard", "offer_add_kong", "add_kong":
				_reveal([event.id])
			"meld":
				if not event.meld.concealed:
					_reveal(event.meld.tile_ids)
			"reveal":
				_reveal(event.ids)
			"finish":
				for player in round_state.players:
					_reveal(player.hand)
					for meld in player.melds:
						_reveal(meld.tile_ids)

func _reveal(ids: Array) -> void:
	for id in ids:
		_public_origins[str(id)] = _keys[id]

static func _id(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floorf(value) and value >= -1 and value < Catalog.COUNT

## -1 rejects stale/malformed data, 0 is an idempotent repeat, 1 changes the view.
func accept(seat: int, display: Dictionary) -> int:
	var row: Dictionary = _rows[seat]
	var slots = display.get("slots")
	var pending = display.get("pending_insert_ids", [])
	var drag = display.get("dragged_id", -1)
	var selected = display.get("selected_id", -1)
	var pos = display.get("drag_position", [])
	var manual = display.get("manual", row.manual)
	var suits = display.get("suit_order", row.suits)
	var merged = display.get("draw_merged", row.get("draw_merged", false))
	if not merged is bool or (merged and row.draw < 0): return -1
	if not slots is Array or not pending is Array or not pos is Array or not suits is Array or not manual is bool:
		return -1
	var expected: int = row.cards.size() - int(row.draw >= 0 and not merged)
	if slots.size() + pending.size() != expected or not _id(drag) or not _id(selected):
		return -1
	if display.has("draw_id") and (not _id(display.draw_id) or display.draw_id != row.draw):
		return -1
	if suits.size() != 3 or not Catalog.SUITS.all(func(suit): return suits.has(suit)):
		return -1
	if selected >= 0 and (not row.cards.has(int(selected)) or drag >= 0):
		return -1
	if pos.size() != 0:
		if drag < 0 or pos.size() != 2:
			return -1
		for coordinate in pos:
			if not (coordinate is int or coordinate is float) or not is_finite(coordinate) or absf(coordinate) > _placement.table_edge():
				return -1
	var normalized_slots := []
	var normalized_pending := []
	var seen := {}
	var gap := -1
	for part in 2:
		var is_slot := part == 0
		var values: Array = slots if is_slot else pending
		for raw in values:
			if not _id(raw):
				return -1
			var id := int(raw)
			if id == -1:
				if not is_slot or gap >= 0 or drag < 0:
					return -1
				gap = normalized_slots.size()
				id = int(drag)
			if (id == row.draw and not merged) or not row.cards.has(id) or seen.has(id):
				return -1
			seen[id] = true
			if is_slot:
				normalized_slots.append(int(raw))
			else:
				normalized_pending.append(id)
	if (drag >= 0) != (gap >= 0) or (not manual and not normalized_pending.is_empty()):
		return -1
	if display.has("gap_slot") and (not _id(display.gap_slot) or int(display.gap_slot) != gap):
		return -1
	if drag >= 0:
		if manual != row.manual:
			return -1
		if row.pending.has(int(drag)) or (int(drag) == row.draw and merged and not row.slots.has(int(drag))):
			# The pending tile can cross the full displayed row; every other identity retains its order.
			var origin: Array = row.slots + row.pending
			origin.erase(int(drag))
			var crossed := normalized_slots.duplicate()
			crossed.erase(-1)
			if not normalized_pending.is_empty() or crossed != origin:
				return -1
		elif not row.slots.has(int(drag)) or normalized_pending != row.pending:
			return -1
	var current: Array = row.preview if row.dragged >= 0 else row.slots
	var shown_pending: Array = [] if row.pending.has(row.dragged) else row.pending
	if current == normalized_slots and shown_pending == normalized_pending and row.dragged == drag and row.selected == selected and row.position == pos and row.manual == manual and row.suits == suits and row.get("draw_merged",false) == merged:
		return 0
	if drag >= 0:
		row.preview = normalized_slots
	else:
		var merge: Dictionary = row.get("merge",{})
		if merged and not row.get("draw_merged",false): merge = {"tile_id":row.draw,"discard_id":-1,"before_slots":row.slots}
		if row.dragged < 0 and not merge.is_empty() and normalized_slots.has(merge.tile_id) and not row.slots.has(merge.tile_id):
			var plan := Arrangement._insertion_plan(normalized_slots, merge)
			_motion_serial += 1
			row.motion = {"token": _motion_serial, "tile": int(plan.tile_id), "reorder": plan.reorder_ids}
		row.slots = normalized_slots
		row.preview = []
		row.pending = normalized_pending
		row.manual = manual
	row.suits = suits.duplicate()
	row.draw_merged = merged
	row.dragged = int(drag)
	row.selected = int(selected)
	row.position = pos.duplicate()
	return 1

func _key(id: int) -> String:
	return "" if id < 0 else _keys[id]


func export_authority() -> Dictionary:
	return {"keys": _keys.duplicate(), "rows": _rows.duplicate(true),
		"motion_serial": _motion_serial,
		"public_origins": _public_origins.duplicate(true),
		"placement": _placement.export_authority(), "event_cursor": _event_cursor, "prompt": _prompt}


func restore_authority(state: Dictionary) -> bool:
	if not state.get("keys") is Array or state.keys.size() != Catalog.COUNT:
		return false
	if not state.get("rows") is Array or state.rows.size() != 4:
		return false
	if not state.get("placement") is Dictionary or not _placement.restore_authority(state.placement):
		return false
	_keys.assign(state.keys)
	_rows = state.rows.duplicate(true)
	_motion_serial = int(state.get("motion_serial",0))
	_public_origins = state.get("public_origins", {}).duplicate(true)
	_event_cursor = int(state.get("event_cursor", 0))
	_prompt = int(state.get("prompt", -1))
	return true

## Decorate the round's detached, already-masked snapshot. Only the owner receives a hand ID lookup.
func project(round_state, view: Dictionary) -> void:
	view.public_origins = _public_origins.duplicate()
	for player in view.players:
		var seat: int = player.seat
		var row: Dictionary = _rows[seat]
		player.public_centers = _placement.centers_for(seat)
		if not _placement.layout_hash.is_empty():
			player.public_regions = _placement.regions_for(seat)
			player.public_layout_hash = _placement.layout_hash
		var slots: Array = row.preview if row.dragged >= 0 else row.slots
		var pending: Array = [] if row.pending.has(row.dragged) else row.pending
		player.display = {"slots": slots.map(_key), "pending": pending.map(_key), "draw": "" if row.get("draw_merged",false) else _key(row.draw), "draw_merged": row.get("draw_merged",false),
			"dragged": _key(row.dragged), "selected": _key(row.selected), "manual": row.manual,
			"drag_position": row.position.duplicate(), "deal_keys": row.deal_keys.duplicate()}
		var motion: Dictionary = row.get("motion",{})
		if not motion.is_empty(): player.display.motion = {"token":motion.token, "tile":_key(motion.tile), "reorder":motion.reorder.map(_key)}
		if seat == view.viewer_seat:
			var own_keys := {}
			for id in row.cards:
				own_keys[str(id)] = _keys[id]
			player.display.own_keys = own_keys
		for i in player.melds.size():
			player.melds[i].display_keys = round_state.players[seat].melds[i].tile_ids.map(_key)
