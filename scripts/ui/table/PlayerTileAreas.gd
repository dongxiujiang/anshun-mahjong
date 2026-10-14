extends "res://scripts/ui/table/TableComponent.gd"
## 管理四家牌区、牌面复用、碰杠鸡牌避让与弃牌滚动。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")

var hand_box := {}
var draw_box := {}
var meld_box := {}
var discard_box := {}
var discard_scroll := {}
var chicken_box := {}
var center_labels := {}
var wall_box := {}
var seat_roots := {}
var wind_labels := {}
var avatars := {}
var dealer_badges := {}
var name_labels := {}
var _status_labels := {}
var _exposed_layouts := {}
var _seat_visual_keys := {}

func build() -> void:
	for seat in 4:
		var station = Control.new()
		station.name = "SeatRoot%d" % seat
		station.position = UI.TABLE_CENTER
		station.mouse_filter = Control.MOUSE_FILTER_IGNORE
		table.surface.add_child(station)
		seat_roots[seat] = station
		hand_box[seat] = table._box(station)
		hand_box[seat].name = "Hand%d" % seat
		draw_box[seat] = table._box(station)
		draw_box[seat].name = "Draw%d" % seat
		meld_box[seat] = table._box(station)
		meld_box[seat].name = "Meld%d" % seat
		chicken_box[seat] = table._box(station)
		chicken_box[seat].name = "Chicken%d" % seat
		wall_box[seat] = table._box(station)
		wall_box[seat].name = "Wall%d" % seat
		discard_box[seat] = []
		var river = ScrollContainer.new()
		river.name = "River%d" % seat
		river.position = UI.RIVER_POSITION
		river.size = UI.RIVER_SIZE
		river.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		# Keep the larger river usable on touch screens without drawing a scrollbar
		# over the tiles.  The wheel/touch scrolling behavior remains available.
		river.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		wall_box[seat].hide()
		station.add_child(river)
		discard_scroll[seat] = river
		var river_content: Control = table._box(river)
		river_content.name = "Tiles"
		for _row in UI.RIVER_ROWS:
			var discard_row: Control = table._box(river_content)
			discard_row.name = "Discard%dRow%d" % [seat, _row]
			discard_box[seat].append(discard_row)
		# Legacy dictionaries stay available to tests and layout code, but the
		# production table no longer renders winds or directional seat labels.
		var avatar: Label = table._label(table.surface, "", Vector2.ZERO, Vector2(1, 1), 1)
		avatar.hide()
		avatars[seat] = avatar
		center_labels[seat] = table._label(table.surface, "", Vector2.ZERO, UI.CENTER_SCORE_SIZE, UI.CENTER_SCORE_FONT_SIZE)
		center_labels[seat].vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var nickname: Label = table._label(table.surface, "", Vector2.ZERO, Vector2(UI.CENTER_SCORE_SIZE.x, 32), UI.CENTER_NAME_FONT_SIZE, UI.MUTED)
		nickname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nickname.clip_text = true
		nickname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		nickname.hide()
		name_labels[seat] = nickname
		var dealer: Label = table._label(table.surface, "庄", Vector2.ZERO, UI.CENTER_DEALER_SIZE, 18, UI.INK)
		dealer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dealer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dealer.add_theme_stylebox_override("normal", table._style(UI.DEALER_BACKGROUND, UI.DEALER_BORDER, 8, 1))
		dealer.hide()
		dealer_badges[seat] = dealer
		_status_labels[seat] = table._label(table.surface, "", Vector2.ZERO, Vector2(300, 74), 17, UI.GOLD)
		_status_labels[seat].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_status_labels[seat].mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_labels[seat].hide()
		var wind: Label = table._label(table.surface, UI.WINDS[seat], Vector2.ZERO, Vector2(32, 32), 19, UI.MUTED)
		wind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		wind_labels[seat] = wind
		wind.hide()

func _refresh_identity(seat: int) -> void:
	if seat >= table.round.players.size(): return
	var relative: int = table._relative_seat(seat)
	var label: Label = center_labels[seat]
	label.size = UI.CENTER_SCORE_SIZE
	label.position = table._table_center() + UI.CENTER_SCORE_OFFSETS[relative] - label.size / 2.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", UI.CENTER_SCORE_FONT_SIZE)
	var player: PlayerState = table.round.players[seat]
	var caption := "%.0f分" % player.score
	label.text = caption
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var font_size := UI.CENTER_SCORE_FONT_SIZE
	while font_size > 12 and TileView._font().get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x: font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UI.GOLD if player.ready else UI.INK)
	var nickname: Label = name_labels[seat]
	nickname.text = "人机" if not player.is_human else str(player.name_label).strip_edges()
	if nickname.text == "": nickname.text = "玩家"
	nickname.size = Vector2(UI.CENTER_SCORE_SIZE.x, maxf(32.0, nickname.get_minimum_size().y))
	nickname.position = label.position - Vector2(0, nickname.size.y + 4.0)
	nickname.tooltip_text = nickname.text
	nickname.visible = table._net_mode() != ""
	var badge: Label = dealer_badges[seat]
	var score_width := TileView._font().get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	badge.position = label.position + Vector2((label.size.x + score_width) / 2.0 + 8.0, (label.size.y - badge.size.y) / 2.0)
	badge.visible = player.is_dealer

func _refresh_seat(seat: int) -> void:
	var relative = table._relative_seat(seat)
	seat_roots[seat].rotation = UI.ROTATIONS[relative]
	var avatar_positions = UI.AVATAR_POSITIONS
	# Reserved positions for the hidden per-seat status labels. Settlement details
	# are shown only in the result card so the active table stays uncluttered.
	var status_positions = UI.HIDDEN_STATUS_POSITIONS
	avatars[seat].position = avatar_positions[relative] + table._table_center() - UI.TABLE_CENTER
	_refresh_identity(seat)
	_status_labels[seat].position = status_positions[relative]
	_status_labels[seat].size = Vector2(320, 84)
	if seat >= table.round.players.size():
		center_labels[seat].text = ""
		name_labels[seat].hide()
		dealer_badges[seat].hide()
		_status_labels[seat].hide()
		return
	var player: PlayerState = table.round.players[seat]
	var plans: Array = _exposed_layouts.get(seat, [])
	var key = var_to_bytes([table.human_seat, table._design_size(), table.round.audio_session, player.concealed, player.just_drew, player.melds,
		player.discards, player.discard_ids, player.discard_count, table.round.phase == RoundState.Phase.SETTLED, table.round.last_discard, plans,
		table.round.round_meta.get("charge_chickens", {}), table._hand_layout(seat)])
	if _seat_visual_keys.get(seat) == key: return
	_seat_visual_keys[seat] = key
	if seat == table.human_seat: table._selected_tile = null
	table._clear_box(meld_box[seat])
	table._clear_box(chicken_box[seat])
	var cards = Tiles.sort_hand(player.concealed)
	var has_draw = player.just_drew != "" and cards.has(player.just_drew)
	if has_draw:
		cards.erase(player.just_drew)
	var player_unit: float = table._player_tile_unit(seat)
	var width = TileView.BASE_W * player_unit
	var height = TileView.BASE_H * player_unit
	# Exposed tiles grow from the left table edge.  The horizontal players' hand
	# and reserved draw slot are centered together without changing tile sizes.
	var metrics: Dictionary = table._seat_metrics(seat)
	var row: Dictionary = table._hand_layout(seat)
	var draw_x: float = row.draw_x
	var hand_x: float = row.hand_x
	for group in _exposed_layouts.get(seat, []):
		var group_origin: Vector2 = group.origin
		if group.has("chicken"):
			var chicken: Dictionary = group.chicken
			var tile: TileView = table._make_tile(chicken.tile, true, player_unit)
			tile.set_meta("charge_chicken", chicken.charge)
			tile.set_highlight(chicken.latest)
			if chicken.charge:
				tile.rotation = -PI / 2.0
				table._put_tile(chicken_box[seat], tile, group_origin + Vector2(0, height))
				tile.tooltip_text = "冲锋鸡 · " + table._cn(chicken.tile)
			else:
				table._put_tile(chicken_box[seat], tile, group_origin)
			continue
		var meld: Dictionary = group.meld
		var count = 3 if meld.kind == "pung" else 4
		var layout: Dictionary = group.layout
		var charge_index := -1
		var up: bool = table.round.is_meld_revealed(seat, group.meld_index)
		for index in count:
			var tile: TileView = table._make_tile(meld.tile if up else "", up, player_unit)
			tile.set_meta("meld_index", int(group.meld_index))
			tile.set_meta("charge_chicken", index == charge_index)
			if index == charge_index:
				tile.tooltip_text = "冲锋鸡 · " + table._cn(meld.tile)
				tile.set_highlight(true)
			if index == int(layout.sideways):
				tile.rotation = -PI / 2.0
			table._put_tile(meld_box[seat], tile, group_origin + Vector2(layout.positions[index]))
	table._clear_box(hand_box[seat])
	table._clear_box(draw_box[seat])
	var own = seat == table.human_seat
	var hand_unit: float = table._hand_tile_unit(seat)
	width = TileView.BASE_W * hand_unit
	var x = hand_x
	var y: float = metrics.hand_y
	var reveal = own or table.round.phase == RoundState.Phase.SETTLED
	for card in cards:
		var tile: TileView = table._make_tile(card if reveal else "", reveal, hand_unit)
		table._put_tile(hand_box[seat], tile, Vector2(x, y))
		if own:
			tile.gui_input.connect(table._on_human_tile_gui.bind(tile))
			tile.set_meta("drawn", false)
		x += width + UI.TILE_GAP
	if has_draw:
		var drawn: TileView = table._make_tile(player.just_drew if reveal else "", reveal, hand_unit)
		table._put_tile(draw_box[seat], drawn, Vector2(draw_x, y))
		drawn.set_meta("drawn", true)
		drawn.set_winning(table.round.phase == RoundState.Phase.SETTLED and int(table.round.round_meta.get("winner", -1)) == seat)
		if own:
			drawn.gui_input.connect(table._on_human_tile_gui.bind(drawn))
	table._refresh_discards(seat)

func _meld_tile_layout(meld: Dictionary, seat: int, unit: float, gap: float) -> Dictionary:
	var width = TileView.BASE_W * unit
	var height = TileView.BASE_H * unit
	var kind = str(meld.get("kind", ""))
	var count = 3 if kind == "pung" else 4
	var source = posmod(int(meld.get("from_seat", -1)) - seat, 4)
	var exposed: bool = kind == "kong" and not meld.get("concealed", false) and int(meld.get("from_seat", -1)) in range(4)
	var sideways = int({1: 3, 2: 3, 3: 0}.get(source, -1)) if exposed else -1
	# 碰牌没有来源标记：即使碰到幺鸡，三张牌也全部竖放。
	var positions: Array = []
	if exposed and source == 2:
		var span = 3 * width + 2 * gap
		for index in 3:
			positions.append(Vector2(index * (width + gap), width + gap))
		positions.append(Vector2((span - height) / 2.0, width))
		return {"positions": positions, "size": Vector2(span, width + gap + height), "sideways": sideways}
	var x = 0.0
	for index in count:
		positions.append(Vector2(x, height if index == sideways else 0.0))
		x += (height if index == sideways else width) + gap
	return {"positions": positions, "size": Vector2(x - gap, height), "sideways": sideways}

func _prepare_exposed_layouts() -> void:
	_exposed_layouts.clear()
	# 联机客户端可能尚未收到四家数据，等待期间不规划牌组。
	if table.round.players.size() != 4:
		return
	var occupied: Array[Rect2] = []
	if table.action_bar.visible:
		occupied.append(Rect2(table.action_bar.position, table.action_bar.size))
	# The score avatars remain in the center after the wall is hidden; exposed
	# groups may now use that free space but must never cover the center panel.
	for control in center_labels.values() + name_labels.values() + dealer_badges.values() + [table.center_info, table._remaining_label]:
		if control.visible: occupied.append(Rect2(control.position, control.size).grow(6.0))
	occupied.append(Rect2(table._settings_button.position + table._settings_button.touch_rect().position, table._settings_button.touch_rect().size).grow(6.0))
	occupied.append(table._table_layout.center_rect().grow(UI.TURN_LIGHT_SPREAD + 6.0))
	for seat in 4:
		var hand_unit: float = table._hand_tile_unit(seat)
		var width = TileView.BASE_W * hand_unit
		var height = TileView.BASE_H * hand_unit
		var transform = Transform2D(UI.ROTATIONS[table._relative_seat(seat)], table._table_center())
		var metrics: Dictionary = table._seat_metrics(seat)
		var player: PlayerState = table.round.players[seat]
		var hand_count = player.concealed.size() - (1 if player.just_drew != "" and player.concealed.has(player.just_drew) else 0)
		var row: Dictionary = table._hand_layout(seat)
		var draw_x: float = row.draw_x
		var hand_x: float = row.hand_x
		for index in hand_count:
			occupied.append(transform * Rect2(Vector2(hand_x + index * (width + UI.TILE_GAP), metrics.hand_y), Vector2(width, height)))
		occupied.append(transform * Rect2(Vector2(draw_x, metrics.hand_y), Vector2(width, height)))
		occupied.append(transform * Rect2(metrics.river_position, metrics.river_size))
	for seat in 4:
		var player_unit: float = table._player_tile_unit(seat)
		var width = TileView.BASE_W * player_unit
		var height = TileView.BASE_H * player_unit
		var transform = Transform2D(UI.ROTATIONS[table._relative_seat(seat)], table._table_center())
		var metrics: Dictionary = table._seat_metrics(seat)
		var player: PlayerState = table.round.players[seat]
		var hand_left: float = table._hand_layout(seat).hand_x
		var next_x: float = metrics.left
		var plans: Array = []
		for group in table._exposed_groups(seat):
			var layout: Dictionary
			if group.has("chicken"):
				var charge: bool = group.chicken.charge
				layout = {"positions": [Vector2(0, height if charge else 0)], "size": Vector2(height if charge else width, height), "sideways": 0 if charge else -1}
			else:
				var meld: Dictionary = group.meld.duplicate()
				meld["charge_marker"] = table.round.is_charge_meld(seat, group.meld_index)
				layout = table._meld_tile_layout(meld, seat, player_unit, UI.TILE_GAP)
			var origin = Vector2.ZERO
			var rects: Array[Rect2] = []
			var placed = false
			var row_index = 0
			while row_index < UI.EXPOSED_MAX_ROWS and not placed:
				# Scan inward for free space, checking every tile's actual bounds;
				# opposite-player kongs include their upper sideways tile.
				var bottom: float = metrics.exposed_y + height if row_index == 0 else metrics.exposed_y - UI.EXPOSED_ROW_GAP - (row_index - 1) * UI.EXPOSED_ROW_STEP
				var right: float = hand_left - UI.EXPOSED_HAND_GAP if row_index == 0 else metrics.overflow_right
				var x: float = next_x if row_index == 0 else metrics.overflow_x
				while x + float(layout.size.x) <= right:
					origin = Vector2(x, bottom - float(layout.size.y))
					rects = table._exposed_rects(layout, origin, transform, width, height)
					if table._exposed_space_clear(rects, occupied):
						placed = true
						break
					x += UI.TILE_GAP
				if not placed:
					row_index += 1
			if not placed:
				push_error("碰杠/鸡牌区域无法容纳当前牌组")
			group["origin"] = origin
			group["layout"] = layout
			plans.append(group)
			occupied.append_array(rects)
			next_x = origin.x + float(layout.size.x) + UI.TILE_GAP + (UI.MELD_GROUP_GAP if group.has("meld") else 0.0)
		_exposed_layouts[seat] = plans

func _exposed_rects(layout: Dictionary, origin: Vector2, transform: Transform2D, width: float, height: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for index in layout.positions.size():
		var pos = origin + Vector2(layout.positions[index])
		var rect = Rect2(pos, Vector2(width, height))
		if index == int(layout.sideways):
			# -90° 绕左上角旋转后，纵向占位是原牌宽，不能减去原牌高。
			rect = Rect2(pos - Vector2(0, width), Vector2(height, width))
		rects.append(transform * rect)
	return rects

func _exposed_space_clear(rects: Array[Rect2], occupied: Array[Rect2]) -> bool:
	var bounds: Rect2 = table._table_bounds()
	for rect in rects:
		if not bounds.encloses(rect):
			return false
		for other in occupied:
			if rect.grow(2.0).intersects(other.grow(-0.5)):
				return false
	return true

func _refresh_status_text(seat: int) -> void:
	var label: Label = _status_labels[seat]
	label.text = ""
	label.hide()

func _chicken_discards(seat: int) -> Array:
	var player: PlayerState = table.round.players[seat]
	var chickens: Array = []
	for index in player.discards.size():
		var card: String = player.discards[index]
		if Tiles.is_chicken(card):
			var latest: bool = table.round.last_discard.get("seat", -1) == seat and table.round.last_discard.get("tile", "") == card and index == player.discards.size() - 1
			var discard_id: int = player.discard_ids[index] if index < player.discard_ids.size() else index
			chickens.append({"tile": card, "charge": table.round.is_charge_discard(seat, index), "latest": latest, "history_index": discard_id})
	return chickens

func _exposed_groups(seat: int) -> Array:
	# Append groups in play order, including chickens between two melds. An added
	# kong keeps the original pung's position. The metadata travels with each meld.
	var groups: Array = []
	for index in table.round.players[seat].melds.size():
		var meld: Dictionary = table.round.players[seat].melds[index]
		groups.append({"meld": meld, "meld_index": index, "order": int(meld.get("after_discard", 0)) * 2, "tie": groups.size()})
	for chicken in table._chicken_discards(seat):
		groups.append({"chicken": chicken, "order": int(chicken.history_index) * 2 + 1, "tie": groups.size()})
	groups.sort_custom(func(a, b): return a.tie < b.tie if a.order == b.order else a.order < b.order)
	return groups

func _refresh_discards(seat: int) -> void:
	var player: PlayerState = table.round.players[seat]
	var metrics: Dictionary = table._seat_metrics(seat)
	var columns: int = metrics.river_columns
	for box in discard_box[seat]:
		table._clear_box(box)
	var width = TileView.BASE_W * UI.TILE_UNIT
	var height = TileView.BASE_H * UI.TILE_UNIT
	var regular_index = 0
	for index in player.discards.size():
		if Tiles.is_chicken(player.discards[index]):
			continue
		var tile: TileView = table._make_tile(player.discards[index], true)
		var latest: bool = table.round.last_discard.get("seat", -1) == seat and table.round.last_discard.get("tile", "") == tile.tile and index == player.discards.size() - 1
		tile.set_highlight(latest)
		var row_index = regular_index / columns
		table._put_tile(discard_box[seat][row_index], tile, Vector2(UI.RIVER_INSET + (regular_index % columns) * (width + UI.TILE_GAP), UI.RIVER_INSET + row_index * (height + UI.TILE_GAP)))
		regular_index += 1
	var river: ScrollContainer = discard_scroll[seat]
	var content: Control = river.get_child(0)
	content.custom_minimum_size = Vector2(metrics.river_size.x - UI.RIVER_CONTENT_MARGIN, maxf(metrics.river_size.y, ceili(regular_index / float(columns)) * (height + UI.TILE_GAP) + 8))
	river.position = metrics.river_position
	river.size = metrics.river_size
	var river_key = ",".join(player.discards)
	if river.get_meta("cards", "") != river_key:
		river.set_meta("cards", river_key)
		table._scroll_to_latest.call_deferred(river)

func _scroll_to_latest(river: ScrollContainer) -> void:
	if not is_instance_valid(table) or not table.is_inside_tree():
		return
	await table.get_tree().process_frame
	if is_instance_valid(table) and table.is_inside_tree() and is_instance_valid(river):
		river.scroll_vertical = int(river.get_v_scroll_bar().max_value)

func _wall_stacks(seat: int) -> Array:
	if table.round.wall != null:
		return table.round.wall.wall_stack_counts(seat)
	if table.round.wall_stacks.has(seat):
		return table.round.wall_stacks[seat]
	var fallback: Array = []
	var remaining = table._wall_remain(seat)
	for index in (14 if posmod(seat - table.round.dealer_seat, 2) == 0 else 13):
		fallback.append(clampi(remaining - index * 2, 0, 2))
	return fallback

func _refresh_walls() -> void:
	for seat in 4:
		table._clear_box(wall_box[seat])
		wall_box[seat].hide()
