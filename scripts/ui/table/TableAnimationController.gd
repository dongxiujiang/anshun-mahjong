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
var _opening_speed_scale := 1.0
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
# Discard flight + insert own a separate lane; claims and the next draw never
# wait for that lane. Only a subsequent action by the same seat reconciles it.
var _discard_tasks: Dictionary = {}
var _parallel_effects: Dictionary = {}
var _task_id := 0
var _tile_pool = preload("res://scripts/ui/TileViewPool.gd").new()

func has_pending() -> bool:
	return _animation_busy or not _animation_queue.is_empty() or not _discard_tasks.is_empty() or not _parallel_effects.is_empty()

func defers_discard_sound() -> bool:
	return DisplayServer.get_name() != "headless" and GameConfig.animation_scale_for("discard") > 0.0 and not _animation_layer._skip

func dispose_pool() -> void:
	_tile_pool.clear()

func holds_meld_reveal(seat: int, index: int) -> bool:
	if DisplayServer.get_name() == "headless": return false
	var events: Array = _animation_queue.duplicate()
	if _animation_busy: events.append(_event)
	for effect in _parallel_effects.values(): events.append(effect.event)
	for event in events:
		if event.get("type", "") == "meld_reveal" and int(event.get("seat", -1)) == seat and int(event.get("index", -1)) == index:
			return true
	return false


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
	var seat: int = table.human_seat
	# A response reads a discard, not the opponent's still-sorting hand.
	# For our turn, the draw/own meld must have finished before any button shows.
	if holds_draw_slot(seat): return true
	if table._selecting and holds_seat_refresh(seat): return true
	var events: Array = _animation_queue.duplicate()
	if _animation_busy: events.append(_event)
	for event in events:
		if int(event.get("seat", -1)) == seat and event.get("type", "") in ["draw", "meld"]:
			return true
	return false

func reset() -> void:
	cancel()
	_animation_last_id = 0
	_preview_last_id = 0
	_session = ""
	_skip_visual_once = false

func cancel(skip_next_event: bool = false) -> void:
	var had_draw_holds := not _held_draw_seats.is_empty()
	var had_hand_holds := not _held_refresh_seats.is_empty() or _sorting
	if _sorting and is_instance_valid(table): table._seat_visual_keys.clear()
	if is_instance_valid(table):
		for seat in _held_refresh_seats: table._seat_visual_keys.erase(seat)
	_restore()
	for task in _discard_tasks.values():
		task.layer.cancel()
		task.layer.queue_free()
	_discard_tasks.clear()
	for effect in _parallel_effects.values():
		effect.layer.cancel()
		effect.layer.queue_free()
	_parallel_effects.clear()
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
	_animation_layer.tile_pool = _tile_pool
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
	if event.get("fast_forward", false):
		cancel()
		return
	var copy := event.duplicate(true)
	if event.get("type", "") == "dice" and DisplayServer.get_name() != "headless":
		_opening = true
		# 联机房间由权威端按 0.5 倍节奏开始首次摸牌，所有客户端动画同步
		# 使用 0.5 倍，确保 13 张牌动画结束就接摸牌，而不是再空等。
		_opening_speed_scale = 0.5 if table._net_mode() != "" else GameConfig.opening_animation_scale()
	var seat := int(event.get("seat", 0))
	if event.get("type", "") in ["draw", "meld", "discard"]:
		_finish_seat_discard(seat)
	if event.get("type", "") == "draw":
		# Set this before state_update.  The refresh that follows will create the
		# persistent node but PlayerTileAreas will keep it invisible until the
		# temporary flying tile reaches the same slot.
		_held_draw_seats[seat] = int(_held_draw_seats.get(seat, 0)) + 1
	if event.get("type", "") == "discard":
		# The authority may run faster than an observer's UI. Retire superseded
		# own draws/melds without delaying the real discard or rebuilding its source.
		if _animation_busy and int(_event.get("seat", -1)) == seat and _event.get("type", "") in ["draw", "meld"]:
			_animation_layer.finish_now()
		_animation_queue = _animation_queue.filter(func(pending): return not (int(pending.get("seat", -1)) == seat and pending.get("type", "") in ["draw", "meld"]))
		_held_draw_seats.erase(seat)
		var discard_tile := str(event.get("tile", ""))
		var from_draw := bool(event.get("discard_from_draw", false))
		copy["from"] = _animation_target_for_seat(seat) if from_draw else _discard_origin(seat, discard_tile, int(event.get("discard_index", -1)))
		copy["from_unit"] = table._hand_tile_unit(seat)
		copy["from_rotation"] = UI.ROTATIONS[table._relative_seat(seat)]
		if not from_draw and int(event.get("discard_index", -1)) >= 0:
			copy["discard_from_hand"] = true
			copy["draw_from"] = _origin(table.draw_box[seat], str(event.get("draw_tile", "")))
			copy["hand_snapshot"] = _hand_snapshot(seat)
			# Hold the rendered old row while RoundState publishes its new
			# concealed array.  The animation must start from these exact nodes.
			_held_refresh_seats[seat] = int(_held_refresh_seats.get(seat, 0)) + 1
		# Materialize only public zones now: a following claim can remove this
		# discard before the deferred pump. Preserve its real landing coordinates.
		table._prepare_exposed_layouts()
		table._player_tile_areas._refresh_exposed(seat)
		table._player_tile_areas._refresh_discards(seat)
		copy["landing_destinations"] = _destinations(copy)
	elif event.get("type", "") == "meld" and event.has("source"):
		copy["from"] = _discard_visual_origin(int(event.get("source", -1)), str(event.get("tile", "")), int(event.get("source_discard_id", -1)))
		copy["from_rotation"] = UI.ROTATIONS[table._relative_seat(int(event.get("source", -1)))] if int(event.get("source", -1)) in range(4) else UI.ROTATIONS[table._relative_seat(seat)]
		# The authority removes the two/three matching hand tiles before emitting
		# the meld event.  Capture their old screen positions before state_update
		# rebuilds the hand, so the visual can show the physical take-and-place.
		copy["meld_hand_snapshot"] = _hand_snapshot(seat, true)
	elif event.get("type", "") == "meld":
		copy["from_rotation"] = UI.ROTATIONS[table._relative_seat(seat)]
		copy["meld_hand_snapshot"] = _hand_snapshot(seat, true)
	if copy.get("type", "") == "meld" and copy.has("source"):
		_claim_discard(copy)
	if copy.get("type", "") == "discard":
		copy["destinations"] = copy.get("landing_destinations", [])
		if copy.get("discard_from_hand", false): _prepare_hand_discard_motion(copy)
		_start_discard(copy)
		return
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
	_event["destinations"] = _event.get("landing_destinations", _destinations(_event))
	if _event.get("type", "") == "discard" and bool(_event.get("discard_from_hand", false)):
		_prepare_hand_discard_motion(_event)
	if _event.get("type", "") == "draw" and seat != table.human_seat: _event["tile"] = ""
	if _event.get("type", "") == "discard":
		var discard := _event
		_event = {}
		_animation_busy = false
		_start_discard(discard)
		table.call_deferred("_pump_visual_animation")
		return
	if _event.get("type", "") in ["ready", "meld_reveal"]:
		var effect := _event
		_event = {}
		_animation_busy = false
		_start_parallel_effect(effect)
		table.call_deferred("_pump_visual_animation")
		return
	if _opening: _event["speed_scale"] = _opening_speed_scale
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

func _hand_snapshot(seat: int, include_draw: bool = false) -> Array:
	var result: Array = []
	if seat < 0 or seat >= table.hand_box.size(): return result
	var tiles := _tiles_in(table.hand_box[seat])
	if include_draw: tiles.append_array(_tiles_in(table.draw_box[seat]))
	for tile in tiles:
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
			if int(tile.get_meta("meld_index", -1)) == int(event.get("index", -2)):
				if type == "meld" and event.get("kind", "") == "add_kong" and int(tile.get_meta("meld_slot", -1)) != 3: continue
				group.append(tile)
		return group
	if type == "discard":
		var candidates := _tiles_in(table.chicken_box[seat]) + _tiles_in(table.discard_scroll[seat])
		for index in range(candidates.size() - 1, -1, -1):
			var candidate: TileView = candidates[index]
			if event.has("discard_id") and int(candidate.get_meta("discard_id", -1)) == int(event.get("discard_id", -2)):
				return [candidate]
			if not event.has("discard_id") and candidate.tile == str(event.get("tile", "")) and bool(candidate.get_meta("charge_chicken", false)) == bool(event.get("charge", false)): return [candidate]
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
				var indices: Array = event.get("hand_indices", [])
				if (indices.has(int(item.get("index", -1))) if not indices.is_empty() else ((meld_card != "" and item_card == meld_card) or (meld_card == "" and item_card == ""))):
					hand_origins.append(item)
			# A hidden opponent hand has no tile names.  Its rightmost old tiles
			# still give us a stable physical origin without leaking their values.
			if hand_origins.is_empty(): hand_origins = event.get("meld_hand_snapshot", []).duplicate()
		var source_slot := -1
		if type == "meld" and event.has("source") and str(event.get("kind", "")) in ["kong", "pung"]:
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
	var row_count := int(event.get("hand_row_count", 0))
	var slot_map: Dictionary = event.get("hand_slot_map", {})
	var snapshot: Array = event.get("hand_snapshot", [])
	var discard_node: TileView = _tile_with_concealed_index(table.hand_box[seat], source_index)
	var drawn_source_index := int(event.get("drawn_source_index", -1))
	var draw_node: TileView = _tile_with_concealed_index(table.draw_box[seat], drawn_source_index)
	event["discard_node"] = discard_node
	event["draw_node"] = draw_node
	if row_count <= 0: row_count = snapshot.size()
	if drawn_source_index < 0:
		# A post-pung discard has no draw to insert, but still closes its hole.
		row_count = maxi(0, snapshot.size() - 1)
		event["hand_row_count"] = row_count
		slot_map = {}
		for item in snapshot:
			var old_index := int(item.get("index", -1))
			if old_index != source_index: slot_map[old_index] = slot_map.size()
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
	event["hand_move_required"] = moves.any(func(data): return not Vector2(data.from).is_equal_approx(Vector2(data.to)))
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
		if int(_dealt[seat]) < 13: return false
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
				"rotation": 0.0,
				"delay": float(slot) * UI.SORT_TILE_STAGGER
			})
	return result

func _start_sorting_animation() -> void:
	if _sorting: return
	_sorting = true
	_event = {"type": "sort_hand", "destinations": _sort_destinations()}
	if _opening: _event["speed_scale"] = _opening_speed_scale
	_animation_busy = true
	table._update_interactivity()
	_animation_layer.play(_event, Callable(table, "_on_visual_animation_finished"))

func refresh_masks() -> void:
	_restore()
	if DisplayServer.get_name() == "headless": return
	var events: Array = _animation_queue.duplicate()
	if _animation_busy: events.append(_event)
	for effect in _parallel_effects.values():
		if effect.event.get("type", "") == "meld_reveal":
			for tile in _targets(effect.event): _mask(tile)
	for task in _discard_tasks.values():
		var event: Dictionary = task.event
		if not task.landed and not event.get("claimed", false):
			for tile in _targets(event): _mask(tile)
		var source_node = event.get("discard_node")
		if is_instance_valid(source_node): _mask(source_node)
	for event in events:
		if event.get("type", "") in ["draw", "discard", "meld"]:
			for tile in _targets(event): _mask(tile)
		if event.get("type", "") == "meld_reveal" and _animation_busy and event == _event:
			for tile in _targets(event): _mask(tile)

func _start_parallel_effect(event: Dictionary) -> void:
	_task_id += 1
	var id := _task_id
	var layer = ANIMATION_LAYER.new()
	layer.name = "TableEffect%d" % id
	layer.tile_pool = _tile_pool
	layer.set_skip(_animation_layer._skip)
	_animation_layer.add_child(layer)
	_parallel_effects[id] = {"event": event, "layer": layer}
	refresh_masks()
	layer.play(event, _finish_parallel_effect.bind(id))

func _finish_parallel_effect(id: int) -> void:
	if not _parallel_effects.has(id): return
	var effect: Dictionary = _parallel_effects[id]
	_parallel_effects.erase(id)
	effect.layer.queue_free()
	refresh_masks()
	table.call_deferred("_refresh")

func _start_discard(event: Dictionary) -> void:
	_task_id += 1
	var id := _task_id
	var layer = ANIMATION_LAYER.new()
	layer.name = "DiscardLane%d" % id
	layer.tile_pool = _tile_pool
	layer.set_skip(_animation_layer._skip)
	# Child of the design-space layer: resize/letterboxing applies to all lanes.
	_animation_layer.add_child(layer)
	_discard_tasks[id] = {"event": event, "layer": layer, "landed": false, "sound": defers_discard_sound()}
	layer.discard_landed.connect(_discard_landed.bind(id))
	refresh_masks()
	layer.play(event, _finish_discard.bind(id))
	table._update_interactivity()

func _discard_landed(id: int) -> void:
	if not _discard_tasks.has(id): return
	var task: Dictionary = _discard_tasks[id]
	if task.landed: return
	task.landed = true
	if not task.event.get("claimed", false) and task.sound:
		AudioManager.play_discard_impact(table)
	refresh_masks()

func _finish_discard(id: int, refresh: bool = true) -> void:
	if not _discard_tasks.has(id): return
	var task: Dictionary = _discard_tasks[id]
	_discard_tasks.erase(id)
	var event: Dictionary = task.event
	var seat := int(event.get("seat", -1))
	task.layer.cancel()
	task.layer.queue_free()
	_restore()
	if event.get("discard_from_hand", false):
		var committed := _commit_hand_discard_visual(event)
		_held_refresh_seats.erase(seat)
		if committed and refresh and table.round.phase == RoundState.Phase.PLAYING: table._player_tile_areas.cache_current_hand(seat)
		if not committed: table._seat_visual_keys.erase(seat)
		# Refresh only on failure or future state changes. Successful commits keep
		# the physical entities; update the key on the next normal refresh.
	refresh_masks()
	table._update_interactivity()
	if refresh: table.call_deferred("_refresh")

func _finish_seat_discard(seat: int) -> void:
	for id in _discard_tasks.keys():
		if int(_discard_tasks[id].event.get("seat", -1)) == seat:
			_finish_discard(id, false)

func _claim_discard(claim: Dictionary) -> void:
	var source := int(claim.get("source", -1))
	var discard_id := int(claim.get("source_discard_id", -1))
	for event in _animation_queue:
		if event.get("type", "") == "discard" and int(event.get("seat", -2)) == source and int(event.get("discard_id", -2)) == discard_id:
			event["claimed"] = true
	for task in _discard_tasks.values():
		var event: Dictionary = task.event
		if int(event.get("seat", -2)) != source or int(event.get("discard_id", -2)) != discard_id: continue
		if not task.landed:
			claim["from"] = task.layer.discard_position(Vector2(claim.get("from", Vector2.ZERO)))
			event["claimed"] = true
			task.layer.hide_discard_flight()

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
	var slot_nodes: Dictionary = {}
	var source_indices: Dictionary = {}
	var draw_node = event.get("draw_node")
	if drawn_slot >= 0:
		if drawn_source_index_after < 0 or not is_instance_valid(draw_node): return false
		slot_nodes[drawn_slot] = draw_node
		source_indices[drawn_slot] = drawn_source_index_after
	for data in event.get("hand_moves", []):
		var node = data.get("node")
		var slot := int(data.get("slot", -1))
		var old_index := int(data.get("old_index", -1))
		if slot < 0 or not is_instance_valid(node): return false
		slot_nodes[slot] = node
		source_indices[slot] = old_index - (1 if old_index > source_index else 0)
	var discard_node = event.get("discard_node")
	if not is_instance_valid(discard_node) or slot_nodes.size() != row_count: return false
	for slot in row_count:
		if not slot_nodes.has(slot): return false
	# Validate the entire row before mutating any UI entity. Rules are untouched.
	if discard_node.get_parent() != null: discard_node.get_parent().remove_child(discard_node)
	discard_node.queue_free()
	for slot in row_count:
		var node: TileView = slot_nodes[slot]
		if node.get_parent() != hand_box:
			if node.get_parent() != null: node.get_parent().remove_child(node)
			hand_box.add_child(node)
		node.visible = true
		node.modulate.a = 1.0
		node.set_meta("concealed_index", source_indices[slot])
		node.set_meta("drawn", false)
		hand_box.move_child(node, mini(slot, hand_box.get_child_count() - 1))
		node.set_table_position(_hand_slot_local_target(seat, slot, row_count))
	if seat == table.human_seat: table._selected_tile = null
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
	table._update_interactivity()
	if finished_type == "meld_reveal": table.call_deferred("_refresh")
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
