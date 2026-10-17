extends "res://scripts/ui/table/TableComponent.gd"
## Consumes authoritative events; owns presentation only, never waits in RoundState.
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const ANIMATION_LAYER := preload("res://scripts/ui/TableAnimationLayer.gd")
var _animation_layer
var _animation_busy := false
var _animation_last_id := 0
var _preview_last_id := 0
var _animation_queue: Array = []
var _skip_visual_once := false
var _session := ""
var _masked: Array[Control] = []
var _event := {}
var _opening := false
var _sorting := false
var _dealt := [0, 0, 0, 0]
## Seats whose persistent draw slot stays hidden until the draw flight lands.
## RoundState emits draw before state_update, so this closes the frame in which
## PlayerTileAreas could otherwise show the authoritative draw tile early.
var _held_draw_seats: Dictionary = {}
## Seats whose authoritative refresh must wait for the hand-discard animation.
## RoundState emits the event before state_update, so without this hold the
## final sorted hand would flash on screen before the old row can animate out.
var _held_refresh_seats: Dictionary = {}

func holds_seat_refresh(seat: int) -> bool:
	return _held_refresh_seats.has(seat)

func holds_draw_slot(seat: int) -> bool:
	return _held_draw_seats.has(seat)

func opening_active() -> bool:
	return _opening

func sorting_active() -> bool:
	return _sorting

func dealt_count(seat: int) -> int:
	return int(_dealt[seat]) if seat in range(4) else 0

func input_locked() -> bool:
	if _opening or _sorting: return true
	# A physical table does not accept the next claim while a tile is still in
	# the air.  The old implementation only locked the local draw, which let a
	# response button appear while a remote discard or meld was still moving.
	return _animation_busy or not _animation_queue.is_empty()

func reset() -> void:
	cancel()
	_animation_last_id = 0
	_preview_last_id = 0
	_session = ""
	_skip_visual_once = false

func cancel(skip_next_event: bool = false) -> void:
	var had_draw_holds := not _held_draw_seats.is_empty()
	var had_hand_holds := not _held_refresh_seats.is_empty()
	_restore()
	_animation_queue.clear()
	_animation_busy = false
	_event = {}
	_held_refresh_seats.clear()
	_held_draw_seats.clear()
	_opening = false
	_sorting = false
	_dealt = [0, 0, 0, 0]
	_skip_visual_once = skip_next_event
	if is_instance_valid(_animation_layer): _animation_layer.cancel()
	if (had_draw_holds or had_hand_holds) and is_instance_valid(table) and table.is_inside_tree():
		# Reconnects and explicit cancellation can interrupt a draw or a hand
		# movement before its completion callback. Rebuild once so hidden nodes and
		# partially moved persistent nodes cannot remain stuck.
		table.call_deferred("_refresh")

func build() -> void:
	_animation_layer = ANIMATION_LAYER.new()
	_animation_layer.name = "AnimationLayer"
	table.add_child(_animation_layer)

func _on_visual_event(event: Dictionary) -> void:
	if _animation_layer == null: return
	var incoming := str(event.get("session", ""))
	if incoming != "" and incoming != _session:
		cancel()
		_animation_last_id = 0
		_session = incoming
	var event_id := int(event.get("id", 0))
	# Capture/review tools can inject local preview events without a round
	# session.  They must never advance the authoritative event cursor, or a
	# later network event with a small id would be mistaken for a duplicate.
	var authoritative_event := incoming != ""
	if authoritative_event:
		if event_id <= _animation_last_id: return
		_animation_last_id = event_id
	elif event_id > 0:
		if event_id <= _preview_last_id: return
		_preview_last_id = event_id
	if _skip_visual_once:
		_skip_visual_once = false
		return
	var copy := event.duplicate(true)
	if event.get("type", "") == "dice" and DisplayServer.get_name() != "headless":
		_opening = true
	var seat := int(event.get("seat", 0))
	if event.get("type", "") == "draw":
		# Set this before state_update.  The refresh that follows will create the
		# persistent node but PlayerTileAreas will keep it invisible until the
		# temporary flying tile reaches the same slot.
		_held_draw_seats[seat] = int(_held_draw_seats.get(seat, 0)) + 1
	if event.get("type", "") == "discard":
		var discard_tile := str(event.get("tile", ""))
		var from_draw := bool(event.get("discard_from_draw", false))
		copy["from"] = _origin(table.draw_box[seat], discard_tile) if from_draw else _discard_origin(seat, discard_tile, int(event.get("discard_index", -1)))
		copy["from_unit"] = table._hand_tile_unit(seat)
		copy["from_rotation"] = UI.ROTATIONS[table._relative_seat(seat)]
		if not from_draw:
			copy["discard_from_hand"] = true
			copy["draw_from"] = _origin(table.draw_box[seat], str(event.get("draw_tile", "")))
			copy["hand_snapshot"] = _hand_snapshot(seat)
			# Hold the rendered old row while RoundState publishes its new
			# concealed array.  The animation must start from these exact nodes.
			_held_refresh_seats[seat] = int(_held_refresh_seats.get(seat, 0)) + 1
	elif event.get("type", "") == "meld" and event.has("source"):
		copy["from"] = _discard_visual_origin(int(event.get("source", -1)), str(event.get("tile", "")), int(event.get("source_discard_id", -1)))
		copy["from_rotation"] = UI.ROTATIONS[table._relative_seat(int(event.get("source", -1)))] if int(event.get("source", -1)) in range(4) else UI.ROTATIONS[table._relative_seat(seat)]
		# The authority removes the two/three matching hand tiles before emitting
		# the meld event.  Capture their old screen positions before state_update
		# rebuilds the hand, so the visual can show the physical take-and-place.
		copy["meld_hand_snapshot"] = _hand_snapshot(seat)
	elif event.get("type", "") == "meld":
		copy["from_rotation"] = UI.ROTATIONS[table._relative_seat(seat)]
		copy["meld_hand_snapshot"] = _hand_snapshot(seat)
	_animation_queue.append(copy)
	table._update_interactivity()
	refresh_masks()
	table.call_deferred("_pump_visual_animation")

func _pump_visual_animation() -> void:
	if _animation_busy or _animation_queue.is_empty() or _animation_layer == null: return
	_event = _animation_queue.pop_front()
	if _event.get("type", "") == "deal_batch":
		var deals: Array = _event.get("deals", [])
		# Reverse insertion keeps the original clockwise deal order.
		for index in range(deals.size() - 1, -1, -1):
			var deal: Dictionary = deals[index]
			_animation_queue.push_front({"type": "deal", "seat": deal.get("seat", 0), "cards": deal.get("cards", [])})
		_pump_visual_animation()
		return
	_animation_busy = true
	if _event.get("type", "") == "dice":
		_opening = DisplayServer.get_name() != "headless"
	var seat := int(_event.get("seat", 0))
	_event["to"] = _animation_target_for_seat(seat)
	if not _event.has("from"):
		_event["from"] = _source_for_event(_event)
	_event["badge_at"] = table._table_center() + [Vector2(0,170), Vector2(250,0), Vector2(0,-170), Vector2(-250,0)][table._relative_seat(seat)]
	_event["destinations"] = _destinations(_event)
	if _event.get("type", "") == "discard" and bool(_event.get("discard_from_hand", false)):
		_prepare_hand_discard_motion(_event)
	if _event.get("type", "") == "draw" and seat != table.human_seat: _event["tile"] = ""
	refresh_masks()
	_animation_layer.play(_event, Callable(table, "_on_visual_animation_finished"))

func _tiles_in(node: Node) -> Array[TileView]:
	var tiles: Array[TileView] = []
	for child in node.get_children():
		if child is TileView: tiles.append(child)
		else: tiles.append_array(_tiles_in(child))
	return tiles

func _tile_with_concealed_index(box: Control, source_index: int) -> TileView:
	if box == null or source_index < 0: return null
	for tile in _tiles_in(box):
		if int(tile.get_meta("concealed_index", -1)) == source_index:
			return tile
	return null

func _position(node: Control) -> Vector2:
	return _animation_layer.get_global_transform().affine_inverse() * node.global_position

func _origin(box: Control, card: String, discard_id: int = -1) -> Vector2:
	var tiles := _tiles_in(box)
	if discard_id >= 0:
		for tile in tiles:
			if int(tile.get_meta("discard_id", -1)) == discard_id:
				return _position(tile)
	for tile in tiles:
		if tile.tile == card and tile.face_up: return _position(tile)
	return _position(tiles.back()) if not tiles.is_empty() else table._table_center()

func _hand_snapshot(seat: int) -> Array:
	var result: Array = []
	if seat < 0 or seat >= table.hand_box.size(): return result
	for tile in _tiles_in(table.hand_box[seat]):
		var source_index := int(tile.get_meta("concealed_index", -1))
		if source_index < 0: continue
		result.append({
			"index": source_index,
			"from": _position(tile),
			"tile": tile.tile if tile.face_up else "",
			"unit": tile.unit,
			"rotation": tile.get_global_transform().get_rotation() - _animation_layer.get_global_transform().get_rotation()
		})
	return result

func _discard_origin(seat: int, card: String, concealed_index: int = -1) -> Vector2:
	if seat < 0 or seat >= 4 or seat >= table.hand_box.size():
		return table._table_center()
	var tiles := _tiles_in(table.hand_box[seat]) + _tiles_in(table.draw_box[seat])
	if concealed_index >= 0:
		for tile in tiles:
			if int(tile.get_meta("concealed_index", -1)) == concealed_index:
				return _position(tile)
	# Prefer the separate draw slot only while the snapshot still identifies this
	# card as the tile just drawn.  A normal discard should fall back to the hand
	# row; using _animation_target_for_seat() here would incorrectly send it from
	# the draw slot after a late network refresh.
	var prefer_draw := false
	if table.round != null and seat < table.round.players.size():
		prefer_draw = str(table.round.players[seat].just_drew) == card
	if prefer_draw:
		for tile in _tiles_in(table.draw_box[seat]):
			if tile.face_up and tile.tile == card:
				return _position(tile)
	for tile in _tiles_in(table.hand_box[seat]):
		if tile.face_up and tile.tile == card:
			return _position(tile)
	if not prefer_draw:
		for tile in _tiles_in(table.draw_box[seat]):
			if tile.face_up and tile.tile == card:
				return _position(tile)
	# A late snapshot can replace the old hand before a visual event is handled.
	# Keep the fallback in the same visual region even when the exact source tile
	# is gone.  This is presentation-only and never changes the authoritative
	# discard index.
	var draw_tiles := _tiles_in(table.draw_box[seat])
	if prefer_draw and not draw_tiles.is_empty(): return _position(draw_tiles[0])
	if not tiles.is_empty():
		return _position(tiles[0])
	return _hand_animation_target_for_seat(seat)

func _discard_visual_origin(seat: int, card: String, discard_id: int = -1) -> Vector2:
	if seat < 0 or seat >= 4:
		return table._table_center()
	var tiles := _tiles_in(table.chicken_box[seat]) + _tiles_in(table.discard_scroll[seat])
	if discard_id >= 0:
		for tile in tiles:
			if int(tile.get_meta("discard_id", -1)) == discard_id:
				return _position(tile)
	for tile in tiles:
		if tile.tile == card and tile.face_up:
			return _position(tile)
	if not tiles.is_empty():
		return _position(tiles.back())
	if seat >= 0 and seat < 4 and is_instance_valid(table.discard_scroll[seat]):
		var river: Control = table.discard_scroll[seat]
		var center_global: Vector2 = river.global_position + river.size / 2.0
		return _animation_layer.get_global_transform().affine_inverse() * center_global
	return table._table_center()

func _targets(event: Dictionary) -> Array[TileView]:
	var seat := int(event.get("seat", 0))
	var type := str(event.get("type", ""))
	if type == "draw": return _tiles_in(table.draw_box[seat])
	if type in ["meld", "meld_reveal"]:
		var group: Array[TileView] = []
		for tile in _tiles_in(table.meld_box[seat]):
			if int(tile.get_meta("meld_index", -1)) == int(event.get("index", -2)): group.append(tile)
		return group
	if type == "discard":
		var candidates := _tiles_in(table.chicken_box[seat]) + _tiles_in(table.discard_scroll[seat])
		for index in range(candidates.size() - 1, -1, -1):
			var candidate: TileView = candidates[index]
			if event.has("discard_id") and int(candidate.get_meta("discard_id", -1)) == int(event.get("discard_id", -2)):
				return [candidate]
			if candidate.tile == str(event.get("tile", "")) and bool(candidate.get_meta("charge_chicken", false)) == bool(event.get("charge", false)): return [candidate]
	return []

func _destinations(event: Dictionary) -> Array:
	var result: Array = []
	var type := str(event.get("type", ""))
	var seat := int(event.get("seat", 0))
	if type == "deal":
		var cards: Array = event.get("cards", [])
		for index in cards.size():
			# Opening hands are rendered in physical deal order.  The target is a
			# deterministic empty-hand slot, so the animation never needs a masked
			# copy of the final sorted hand underneath it.
			var count := int(_dealt[seat]) + index
			var to := _opening_hand_slot_target(seat, count)
			result.append({"to": to, "from": Vector2(event.get("from", _source_for_event(event))) + Vector2(index * 8.0, -index * 5.0), "tile": cards[index] if seat == table.human_seat else "", "unit": table._hand_tile_unit(seat), "rotation": UI.ROTATIONS[table._relative_seat(seat)]})
	else:
		var targets := _targets(event)
		var hand_origins: Array = []
		if type == "meld":
			var meld_card := str(event.get("tile", ""))
			for item in event.get("meld_hand_snapshot", []):
				var item_card := str(item.get("tile", ""))
				if (meld_card != "" and item_card == meld_card) or (meld_card == "" and item_card == ""):
					hand_origins.append(item)
			# A hidden opponent hand has no tile names.  Its rightmost old tiles
			# still give us a stable physical origin without leaking their values.
			if hand_origins.is_empty(): hand_origins = event.get("meld_hand_snapshot", []).duplicate()
		var source_slot := -1
		if type == "meld" and event.has("source") and str(event.get("kind", "")) == "kong":
			for index in targets.size():
				if int(targets[index].get_meta("meld_sideways", -1)) == int(targets[index].get_meta("meld_slot", -2)):
					source_slot = index
					break
			if source_slot < 0 and not targets.is_empty(): source_slot = targets.size() - 1
		for index in targets.size():
			var tile: TileView = targets[index]
			var card := str(event.get("tile", ""))
			if type == "draw" and seat != table.human_seat: card = ""
			var origin := Vector2(event.get("from", table._table_center()))
			var origin_rotation := float(event.get("from_rotation", tile.get_global_transform().get_rotation() - _animation_layer.get_global_transform().get_rotation()))
			if type == "meld" and index == source_slot and event.has("source"):
				origin = Vector2(event.get("from", origin))
			elif type == "meld" and not hand_origins.is_empty():
				var hand_item: Dictionary = hand_origins.pop_back()
				origin = Vector2(hand_item.get("from", origin))
				origin_rotation = float(hand_item.get("rotation", origin_rotation))
			result.append({"to": _position(tile), "from": origin, "tile": card, "unit": tile.unit, "rotation": tile.get_global_transform().get_rotation() - _animation_layer.get_global_transform().get_rotation(), "from_rotation": origin_rotation})
	return result

func _source_for_event(event: Dictionary) -> Vector2:
	var type := str(event.get("type", ""))
	var seat := int(event.get("seat", 0))
	if type in ["deal", "draw"] and seat in range(4):
		# The wall is not rendered in production, but retaining its four physical
		# origins makes the flight read like a tile being drawn from the table edge.
		var relative: int = table._relative_seat(seat)
		if type == "draw" and str(event.get("kind", "head")) == "tail":
			# A kong replacement comes from the dead-wall end, visually opposite the
			# normal head draw for that player.
			relative = posmod(relative + 2, 4)
		return Vector2(UI.ANIMATION_TARGETS[relative])
	return table._table_center()

func _prepare_hand_discard_motion(event: Dictionary) -> void:
	var seat := int(event.get("seat", 0))
	var source_index := int(event.get("discard_index", -1))
	var drawn_hand_index := int(event.get("drawn_hand_index", -1))
	var discard_hand_index := int(event.get("discard_hand_index", -1))
	var row_count := int(event.get("hand_row_count", 0))
	var slot_map: Dictionary = event.get("hand_slot_map", {})
	var snapshot: Array = event.get("hand_snapshot", [])
	var discard_node: TileView = _tile_with_concealed_index(table.hand_box[seat], source_index)
	var drawn_source_index := int(event.get("drawn_source_index", -1))
	var draw_node: TileView = _tile_with_concealed_index(table.draw_box[seat], drawn_source_index)
	event["discard_node"] = discard_node
	event["draw_node"] = draw_node
	if row_count <= 0: row_count = snapshot.size()
	var moves: Array = []
	for item in snapshot:
		var old_index := int(item.get("index", -1))
		if old_index < 0 or old_index == source_index or old_index == drawn_source_index:
			continue
		var final_slot := _slot_map_value(slot_map, old_index)
		if final_slot < 0: continue
		moves.append({
			"node": _tile_with_concealed_index(table.hand_box[seat], old_index),
			"old_index": old_index,
			"slot": final_slot,
			"from": item.get("from", table._table_center()),
			"to": _hand_slot_target(seat, final_slot, row_count),
			"tile": str(item.get("tile", "")),
			"unit": float(item.get("unit", table._hand_tile_unit(seat))),
			"rotation": float(item.get("rotation", UI.ROTATIONS[table._relative_seat(seat)]))
		})
	event["hand_moves"] = moves
	event["hand_move_required"] = drawn_hand_index >= 0 and discard_hand_index >= 0 and drawn_hand_index != discard_hand_index
	# The real drawn tile is now part of the hand snapshot.  Compute its final
	# sorted slot in the same coordinate system used by PlayerTileAreas.
	if drawn_hand_index < 0:
		event["hand_insert"] = {}
		return
	var unit: float = table._hand_tile_unit(seat)
	var target: Vector2 = _hand_slot_target(seat, drawn_hand_index, row_count)
	var reveal: bool = seat == table.human_seat
	event["hand_insert"] = {
		"from": event.get("draw_from", table._table_center()),
		"to": target,
		"tile": str(event.get("draw_tile", "")) if reveal else "",
		"unit": unit,
		"rotation": UI.ROTATIONS[table._relative_seat(seat)],
		"from_unit": table._hand_tile_unit(seat),
		"source_node": draw_node
	}

func _slot_map_value(slot_map: Dictionary, source_index: int) -> int:
	if slot_map.has(source_index): return int(slot_map[source_index])
	var key := str(source_index)
	return int(slot_map[key]) if slot_map.has(key) else -1

func _hand_slot_target(seat: int, slot: int, count: int) -> Vector2:
	if seat < 0 or seat >= table.seat_roots.size() or count <= 0: return table._table_center()
	var local := _hand_slot_local_target(seat, slot, count)
	var global_target: Vector2 = table.seat_roots[seat].get_global_transform() * local
	return _animation_layer.get_global_transform().affine_inverse() * global_target

func _hand_slot_local_target(seat: int, slot: int, count: int) -> Vector2:
	if seat < 0 or seat >= table.seat_roots.size() or count <= 0: return Vector2.ZERO
	var unit: float = table._hand_tile_unit(seat)
	var width := TileView.BASE_W * unit
	var span := maxf(0.0, count * (width + UI.TILE_GAP) - UI.TILE_GAP)
	var right := (span + UI.DRAW_GAP + width) / 2.0
	var hand_x := right - width - UI.DRAW_GAP - span
	return Vector2(hand_x + slot * (width + UI.TILE_GAP), float(table._seat_metrics(seat).hand_y))

func _opening_hand_slot_local(seat: int, slot: int) -> Vector2:
	if seat < 0 or seat >= table.seat_roots.size(): return Vector2.ZERO
	var layout: Dictionary = table._hand_layout(seat)
	var unit: float = table._hand_tile_unit(seat)
	var width := TileView.BASE_W * unit
	return Vector2(float(layout.get("hand_x", 0.0)) + slot * (width + UI.TILE_GAP), float(table._seat_metrics(seat).hand_y))

func _opening_hand_slot_target(seat: int, slot: int) -> Vector2:
	var local := _opening_hand_slot_local(seat, slot)
	if seat < 0 or seat >= table.seat_roots.size(): return table._table_center()
	var global_target: Vector2 = table.seat_roots[seat].get_global_transform() * local
	return _animation_layer.get_global_transform().affine_inverse() * global_target

func _all_opening_tiles_dealt() -> bool:
	if table.round == null or table.round.players.size() != 4: return false
	for seat in 4:
		if int(_dealt[seat]) < table.round.players[seat].concealed.size(): return false
	return true

func _sort_destinations() -> Array:
	var result: Array = []
	for seat in 4:
		if seat >= table.hand_box.size() or seat >= table.round.players.size(): continue
		var player: PlayerState = table.round.players[seat]
		var entries: Array = []
		for tile in _tiles_in(table.hand_box[seat]):
			var source_index := int(tile.get_meta("concealed_index", -1))
			if source_index < 0 or source_index >= player.concealed.size(): continue
			entries.append({"node": tile, "source_index": source_index, "card": str(player.concealed[source_index])})
		entries.sort_custom(func(a, b):
			var av := Tiles.value_index(str(a.get("card", "")))
			var bv := Tiles.value_index(str(b.get("card", "")))
			return int(a.get("source_index", 0)) < int(b.get("source_index", 0)) if av == bv else av < bv)
		for slot in entries.size():
			var item: Dictionary = entries[slot]
			var tile: TileView = item.get("node")
			result.append({
				"node": tile,
				"to": _opening_hand_slot_local(seat, slot),
				"rotation": UI.ROTATIONS[table._relative_seat(seat)],
				"delay": float(slot) * UI.SORT_TILE_STAGGER
			})
	return result

func _start_sorting_animation() -> void:
	if _sorting: return
	_sorting = true
	_event = {"type": "sort_hand", "destinations": _sort_destinations()}
	_animation_busy = true
	table._update_interactivity()
	_animation_layer.play(_event, Callable(table, "_on_visual_animation_finished"))

func refresh_masks() -> void:
	_restore()
	if DisplayServer.get_name() == "headless": return
	if _animation_busy and _event.get("type", "") in ["draw", "discard", "meld", "meld_reveal"]:
		for tile in _targets(_event): _mask(tile)
		if _event.get("type", "") == "discard" and bool(_event.get("discard_from_hand", false)):
			var source_node = _event.get("discard_node")
			if is_instance_valid(source_node) and source_node is TileView:
				# Only the clicked source tile is hidden. The remaining persistent
				# hand nodes stay visible and move into the discarded gap directly.
				_mask(source_node)
			else:
				var seat := int(_event.get("seat", 0))
				var source_index := int(_event.get("discard_index", -1))
				var fallback := _tile_with_concealed_index(table.hand_box[seat], source_index)
				if is_instance_valid(fallback): _mask(fallback)

func _mask(tile: Control) -> void:
	if not _masked.has(tile): _masked.append(tile)
	tile.modulate.a = 0.0
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _restore() -> void:
	for node in _masked:
		if is_instance_valid(node):
			node.modulate.a = 1.0
			if node is TileView: node.mouse_filter = Control.MOUSE_FILTER_STOP if node.interactive else Control.MOUSE_FILTER_IGNORE
	_masked.clear()

func _commit_hand_discard_visual(event: Dictionary) -> bool:
	var seat := int(event.get("seat", -1))
	if seat < 0 or seat >= table.hand_box.size(): return false
	var hand_box: Control = table.hand_box[seat]
	var source_index := int(event.get("discard_index", -1))
	var drawn_source_index_after := int(event.get("drawn_index_after", -1))
	var drawn_slot := int(event.get("drawn_hand_index", -1))
	var row_count := int(event.get("hand_row_count", 0))
	var moves: Array = event.get("hand_moves", [])
	var draw_node = event.get("draw_node")
	if row_count <= 0 or drawn_source_index_after < 0 or drawn_slot < 0 or not (is_instance_valid(draw_node) and draw_node is TileView):
		return false
	for data in moves:
		if not (is_instance_valid(data.get("node")) and data.get("node") is TileView):
			return false
	var discard_node = event.get("discard_node")
	if not (is_instance_valid(discard_node) and discard_node is TileView):
		return false
	# Remove the old discarded entity and move the drawn entity out of draw_box.
	if discard_node.get_parent() != null:
		discard_node.get_parent().remove_child(discard_node)
	discard_node.queue_free()
	if draw_node.get_parent() != hand_box:
		if draw_node.get_parent() != null: draw_node.get_parent().remove_child(draw_node)
		hand_box.add_child(draw_node)
	draw_node.visible = true
	draw_node.modulate.a = 1.0
	draw_node.set_meta("drawn", false)
	draw_node.set_meta("concealed_index", drawn_source_index_after)
	var slot_nodes: Dictionary = {drawn_slot: draw_node}
	for data in moves:
		var node: TileView = data.get("node")
		var old_index := int(data.get("old_index", -1))
		var slot := int(data.get("slot", -1))
		if slot < 0: return false
		# Removing the discarded array element shifts every later concealed index.
		var new_index := old_index - (1 if old_index > source_index else 0)
		node.set_meta("concealed_index", new_index)
		node.set_meta("drawn", false)
		node.visible = true
		node.modulate.a = 1.0
		slot_nodes[slot] = node
	# Place the existing nodes in their final sorted order without rebuilding the
	# hand container. This preserves the physical hand movement on screen.
	for slot in range(row_count):
		if not slot_nodes.has(slot): return false
		var node: TileView = slot_nodes[slot]
		if node.get_parent() != hand_box:
			if node.get_parent() != null: node.get_parent().remove_child(node)
			hand_box.add_child(node)
		hand_box.move_child(node, mini(slot, hand_box.get_child_count() - 1))
		node.set_table_position(_hand_slot_local_target(seat, slot, row_count))
	if seat == table.human_seat:
		table._selected_tile = null
	return true

func _on_visual_animation_finished() -> void:
	var finished_type := str(_event.get("type", ""))
	if finished_type == "sort_hand":
		for data in _event.get("destinations", []):
			var tile = data.get("node")
			if is_instance_valid(tile) and tile is TileView:
				tile.set_table_position(Vector2(data.get("to", tile.position)))
		_sorting = false
		_opening = false
		_animation_busy = false
		table._update_interactivity()
		# The physical nodes have just reached their sorted slots.  Rebuild the
		# authoritative hand once so metadata, selection and hit areas match the
		# sorted logical order without any opening mask.
		table.call_deferred("_refresh")
		table.call_deferred("_pump_visual_animation")
		return
	var refresh_seat := int(_event.get("seat", -1)) if finished_type == "discard" and bool(_event.get("discard_from_hand", false)) else -1
	if _event.get("type", "") == "deal":
		_dealt[int(_event.get("seat", 0))] += _event.get("cards", []).size()
		# Commit this packet to the persistent hand immediately.  The hand area is
		# rendered only up to _dealt[seat], so the just-landed cards remain visible
		# without covering a prebuilt final hand.
		table._refresh()
		if _opening and _all_opening_tiles_dealt():
			_start_sorting_animation()
			return
	if finished_type == "draw" or _animation_queue.is_empty():
		_opening = false
	_restore()
	var committed_hand_discard := false
	if refresh_seat >= 0 and int(_held_refresh_seats.get(refresh_seat, 1)) <= 1:
		committed_hand_discard = _commit_hand_discard_visual(_event)
	_animation_busy = false
	table._update_interactivity()
	refresh_masks()
	if finished_type == "draw":
		var draw_seat := int(_event.get("seat", -1))
		if draw_seat >= 0:
			var remaining_draw_holds := int(_held_draw_seats.get(draw_seat, 1)) - 1
			if remaining_draw_holds <= 0:
				_held_draw_seats.erase(draw_seat)
				for draw_tile in _tiles_in(table.draw_box[draw_seat]):
					draw_tile.visible = true
				# Rebuild after landing so the persistent draw node becomes visible
				# exactly when the flying tile finishes.
				table.call_deferred("_refresh")
			else:
				_held_draw_seats[draw_seat] = remaining_draw_holds
	if refresh_seat >= 0:
		var remaining_holds := int(_held_refresh_seats.get(refresh_seat, 1)) - 1
		if remaining_holds <= 0:
			_held_refresh_seats.erase(refresh_seat)
			# The existing nodes have already been moved and reordered. Rebuild only
			# when a late snapshot made the physical-node commit impossible.
			if not committed_hand_discard:
				table.call_deferred("_refresh")
		else:
			_held_refresh_seats[refresh_seat] = remaining_holds
	table.call_deferred("_pump_visual_animation")
	if _animation_queue.is_empty() and table.round.phase == RoundState.Phase.SETTLED:
		table._refresh.call_deferred()

func _animation_target_for_seat(seat: int) -> Vector2:
	var tiles := _tiles_in(table.draw_box[seat])
	if not tiles.is_empty(): return _position(tiles[0])
	var layout: Dictionary = table._hand_layout(seat) if table.round.players.size() == 4 else {"draw_x": 0}
	var local := Vector2(float(layout.draw_x), float(table._seat_metrics(seat).hand_y))
	return _animation_layer.get_global_transform().affine_inverse() * (table.seat_roots[seat].get_global_transform() * local)

func _hand_animation_target_for_seat(seat: int) -> Vector2:
	if seat < 0 or seat >= 4 or seat >= table.hand_box.size():
		return table._table_center()
	var tiles := _tiles_in(table.hand_box[seat])
	if not tiles.is_empty(): return _position(tiles[0])
	var layout: Dictionary = table._hand_layout(seat) if table.round.players.size() == 4 else {"hand_x": 0}
	var local := Vector2(float(layout.get("hand_x", 0.0)), float(table._seat_metrics(seat).hand_y))
	return _animation_layer.get_global_transform().affine_inverse() * (table.seat_roots[seat].get_global_transform() * local)
