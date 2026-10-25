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
var net_labels := {}
var seat_roots := {}
var wind_labels := {}
var avatars := {}
var dealer_badges := {}
var name_labels := {}
var ready_frames := {}
var voice_speaker_buttons := {}
var _status_labels := {}
var _exposed_layouts := {}
var _exposed_layout_key := PackedByteArray()
var _seat_visual_keys := {}
var _pending_ready_round := 0
var _pending_ready_seat := -1
var _ai_teach_tile := ""
var _exposed_keys := {}
var _river_keys := {}

func build() -> void:
	for seat in 4:
		var station = Control.new()
		station.name = "SeatRoot%d" % seat
		station.position = UI.TABLE_CENTER
		station.mouse_filter = Control.MOUSE_FILTER_IGNORE
		table.surface.add_child(station)
		seat_roots[seat] = station
		var ready_frame := Panel.new()
		ready_frame.name = "ReadyFrame%d" % seat
		ready_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ready_frame.z_index = -1
		var ready_style := StyleBoxFlat.new()
		# 只画边框，不填充半透明绿色；整块填充会盖住手牌牌面。
		ready_style.bg_color = Color(0, 0, 0, 0)
		ready_style.border_color = UI.GOLD
		ready_style.set_border_width_all(2)
		ready_style.set_corner_radius_all(18)
		ready_style.shadow_color = Color(UI.GOLD, 0.0)
		ready_style.shadow_size = 0
		ready_frame.add_theme_stylebox_override("panel", ready_style)
		station.add_child(ready_frame)
		ready_frames[seat] = ready_frame
		hand_box[seat] = table._box(station)
		hand_box[seat].name = "Hand%d" % seat
		draw_box[seat] = table._box(station)
		draw_box[seat].name = "Draw%d" % seat
		meld_box[seat] = table._box(station)
		meld_box[seat].name = "Meld%d" % seat
		chicken_box[seat] = table._box(station)
		chicken_box[seat].name = "Chicken%d" % seat
		discard_box[seat] = []
		var river = ScrollContainer.new()
		river.name = "River%d" % seat
		river.position = UI.RIVER_POSITION
		river.size = UI.RIVER_SIZE
		river.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		# Keep the larger river usable on touch screens without drawing a scrollbar
		# over the tiles.  The wheel/touch scrolling behavior remains available.
		river.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
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
		net_labels[seat] = table._label(table.surface, "", Vector2.ZERO, Vector2(150, UI.CENTER_SCORE_SIZE.y), UI.CENTER_SCORE_FONT_SIZE, UI.INK)
		net_labels[seat].vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		net_labels[seat].hide()
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
		var speaker: Button = table._button("喇叭", func(): table._toggle_remote_voice(seat), Vector2(92, 42))
		speaker.name = "VoiceSpeaker%d" % seat
		speaker.add_theme_font_size_override("font_size", 20)
		speaker.tooltip_text = "开关该玩家语音"
		speaker.hide()
		table.surface.add_child(speaker)
		voice_speaker_buttons[seat] = speaker

func _refresh_identity(seat: int) -> void:
	if seat >= table.round.players.size(): return
	var relative: int = table._relative_seat(seat)
	var label: Label = center_labels[seat]
	label.size = UI.CENTER_SCORE_SIZE
	label.position = table._table_center() + UI.CENTER_SCORE_OFFSETS[relative] - label.size / 2.0
	if table.round.phase == RoundState.Phase.SETTLED:
		# 说明留在总分下方，向外让开桌心翻鸡牌与其他座位的昵称。
		label.position += UI.SETTLEMENT_SCORE_SHIFTS[relative]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", UI.CENTER_SCORE_FONT_SIZE)
	var player: PlayerState = table.round.players[seat]
	var settlement_display: bool = table.round.phase == RoundState.Phase.SETTLED and table._settlement_animation_controller.has_started()
	# The settlement controller owns the running total and color until the next
	# round. Identity/snapshot refreshes must not flash the final score early.
	var shown_score := float(player.score)
	if table.round.phase == RoundState.Phase.SETTLED and not settlement_display:
		# A win/meld visual may still be draining before settlement starts.
		var deltas: Array = table.round.last_result.get("deltas", [])
		if seat < deltas.size(): shown_score -= float(deltas[seat])
	var caption: String = label.text if settlement_display else "%.0f分" % shown_score
	if not settlement_display: label.text = caption
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var font_size := UI.CENTER_SCORE_FONT_SIZE
	while font_size > 12 and TileView._font().get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x: font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)
	if not settlement_display:
		label.add_theme_color_override("font_color", UI.GOLD if player.ready else UI.INK)
	var net_label: Label = net_labels[seat]
	net_label.position = label.position + Vector2(label.size.x + 8.0, 0)
	net_label.size = Vector2(150, label.size.y)
	net_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	net_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var nickname: Label = name_labels[seat]
	nickname.text = "人机" if not player.is_human else str(player.name_label).strip_edges()
	if nickname.text == "": nickname.text = "玩家"
	nickname.size = Vector2(UI.CENTER_SCORE_SIZE.x, maxf(32.0, nickname.get_minimum_size().y))
	nickname.position = label.position - Vector2(0, nickname.size.y + 4.0)
	nickname.tooltip_text = nickname.text
	nickname.visible = table._net_mode() != ""
	var speaker: Button = voice_speaker_buttons.get(seat)
	if speaker != null:
		var remote_human: bool = table._net_mode() != "" and seat != table.human_seat and player.is_human and table.round.phase != RoundState.Phase.SETTLED
		speaker.visible = remote_human
		if remote_human:
			# Keep the remote mute control beside the score instead of the
			# nickname, so it does not hang over the discard river.
			speaker.position = label.position + Vector2(
				(label.size.x - speaker.size.x) / 2.0, label.size.y + 4.0)
			var speaker_on: bool = table._remote_voice_enabled(seat)
			speaker.text = "喇叭" if speaker_on else "静音"
			speaker.modulate = Color.WHITE if speaker_on else Color(0.62, 0.62, 0.62)
	var badge: Label = dealer_badges[seat]
	var score_width := TileView._font().get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	badge.position = label.position + Vector2((label.size.x + score_width) / 2.0 + 8.0, (label.size.y - badge.size.y) / 2.0)
	# Reserve the space after the score for the settlement delta.
	badge.visible = player.is_dealer and table.round.phase != RoundState.Phase.SETTLED

func _settlement_reveals_hands() -> bool:
	# The settlement screen is a final, complete snapshot: reveal every hand
	# for winning rounds and exhaustive draws alike.
	return table.round.phase == RoundState.Phase.SETTLED

func _meld_revealed(seat: int, index: int) -> bool:
	if table._table_animation_controller.holds_meld_reveal(seat, index): return false
	# Settlement is a final snapshot: both win and draw reveal every kong/meld
	# group immediately, regardless of the two-discard in-play reveal delay.
	if table.round.phase == RoundState.Phase.SETTLED:
		return true
	# The owner can always read their own concealed kong. Opponents keep the
	# face-down view until the normal delayed public reveal.
	if seat == table.human_seat and index >= 0 and index < table.round.players[seat].melds.size():
		var meld: Dictionary = table.round.players[seat].melds[index]
		if meld.get("kind", "") == "kong" and bool(meld.get("concealed", false)) and not bool(meld.get("robbed", false)):
			return true
	return table.round.is_meld_revealed(seat, index)

func _hand_key(seat: int) -> PackedByteArray:
	var player: PlayerState = table.round.players[seat]
	var controller = table._table_animation_controller
	return var_to_bytes([table.human_seat, table._design_size(), table.round.audio_session,
		player.concealed, player.just_drew, player.ready, _settlement_reveals_hands(), table._hand_layout(seat),
		controller.opening_active(), controller.dealt_count(seat), controller.holds_draw_slot(seat)])

func highlight_ai_teach(tile: String) -> void:
	_ai_teach_tile = tile
	_apply_ai_teach_highlight()

func _apply_ai_teach_highlight() -> void:
	var human: int = int(table.human_seat)
	for box in [hand_box.get(human), draw_box.get(human)]:
		if box == null:
			continue
		for child in box.get_children():
			if child is TileView:
				var mark: bool = _ai_teach_tile != "" and child.face_up and child.tile == _ai_teach_tile
				# 只清掉上一轮 AI 标记，不能把报听/鸡牌等其它金边一起清掉。
				if mark:
					child.set_ai_teach_highlight(true)
					child.set_meta("ai_teach", true)
				elif bool(child.get_meta("ai_teach", false)):
					child.set_ai_teach_highlight(false)
					child.set_meta("ai_teach", false)

func clear_ai_teach_highlight() -> void:
	_ai_teach_tile = ""
	_apply_ai_teach_highlight()

func cache_current_hand(seat: int) -> void:
	_seat_visual_keys[seat] = _hand_key(seat)

func _refresh_seat(seat: int) -> void:
	var relative = table._relative_seat(seat)
	seat_roots[seat].rotation = UI.ROTATIONS[relative]
	var avatar_positions = UI.AVATAR_POSITIONS
	# Reserved positions for the hidden per-seat status labels.
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
	var opening: bool = table._table_animation_controller.opening_active()
	var opening_dealt: int = table._table_animation_controller.dealt_count(seat)
	var draw_hidden: bool = table._table_animation_controller.holds_draw_slot(seat)
	_refresh_exposed(seat)
	_refresh_discards(seat)
	# Hand identity excludes unrelated discards and exposed-layout changes.
	var key := _hand_key(seat)
	if _seat_visual_keys.get(seat) == key: return
	_seat_visual_keys[seat] = key
	if seat == table.human_seat: table._selected_tile = null
	var cards: Array = []
	if opening:
		# During the opening, the authoritative hand is already complete but the
		# table must show only the packets that have physically landed.  Preserve
		# append/deal order here; sorting waits for the separate sort animation.
		for source_index in range(mini(opening_dealt, player.concealed.size())):
			cards.append(player.concealed[source_index])
	else:
		cards = Tiles.sort_hand(player.concealed)
	var has_draw = not opening and player.just_drew != "" and cards.has(player.just_drew)
	if has_draw:
		cards.erase(player.just_drew)
	# Preserve each rendered tile's source index.  A tile name is not unique;
	# the source index identifies the exact duplicate the player clicked.
	var used_indices: Dictionary = {}
	var drawn_index := -1
	if has_draw:
		for source_index in range(player.concealed.size() - 1, -1, -1):
			if player.concealed[source_index] == player.just_drew:
				drawn_index = source_index
				break
	# Exposed tiles grow from the left table edge.  The horizontal players' hand
	# and reserved draw slot are centered together without changing tile sizes.
	var metrics: Dictionary = table._seat_metrics(seat)
	var row: Dictionary = table._hand_layout(seat)
	var draw_x: float = row.draw_x
	var hand_x: float = row.hand_x
	table._clear_box(hand_box[seat])
	table._clear_box(draw_box[seat])
	var own = seat == table.human_seat
	var hand_unit: float = table._hand_tile_unit(seat)
	var width := TileView.BASE_W * hand_unit
	var x = hand_x
	var y: float = metrics.hand_y
	var reveal: bool = own or _settlement_reveals_hands()
	for card in cards:
		var tile: TileView = table._make_tile(card if reveal else "", reveal, hand_unit)
		# Keep the logical source index on every rendered tile, including hidden
		# opponent tiles.  A discard visual event is emitted before the next
		# snapshot refreshes the UI, so this lets remote clients start an animation
		# at the exact tile instead of falling back to the last tile in the row.
		# The index is metadata only and never reveals a hidden tile value.
		for source_index in player.concealed.size():
			if source_index == drawn_index or used_indices.has(source_index):
				continue
			if player.concealed[source_index] == card:
				used_indices[source_index] = true
				tile.set_meta("concealed_index", source_index)
				break
		table._put_tile(hand_box[seat], tile, Vector2(x, y))
		if own:
			tile.gui_input.connect(table._on_human_tile_gui.bind(tile))
			tile.set_meta("drawn", false)
		x += width + UI.TILE_GAP
	if has_draw:
		var drawn: TileView = table._make_tile(player.just_drew if reveal else "", reveal, hand_unit)
		table._put_tile(draw_box[seat], drawn, Vector2(draw_x, y))
		# Keep the authoritative target available for positioning, but invisible
		# until the temporary draw animation has reached this slot.
		drawn.visible = not draw_hidden
		drawn.set_meta("drawn", true)
		drawn.set_winning(_settlement_reveals_hands() and (int(table.round.round_meta.get("winner", -1)) == seat or table.round.last_result.get("winners", table.round.round_meta.get("winners", [])).has(seat)))
		if own:
			drawn.gui_input.connect(table._on_human_tile_gui.bind(drawn))
		if drawn_index >= 0:
			drawn.set_meta("concealed_index", drawn_index)
	if own:
		# 自己的手牌/摸牌位只允许正面牌；任何残留的反面动画牌都不能
		# 盖在手牌上。
		for box in [hand_box[seat], draw_box[seat]]:
			for child in box.get_children():
				if child is TileView and not child.face_up:
					child.hide()
	if own:
		_apply_ai_teach_highlight()
	table._refresh_discards(seat)
	_refresh_ready_discard_hint(seat)
	_refresh_ready_frame(seat)

func _refresh_ready_discard_hint(seat: int) -> void:
	if seat != table.human_seat or table.round == null or table.round.phase != RoundState.Phase.PLAYING:
		return
	var player: PlayerState = table.round.players[seat]
	var hinted: Dictionary = {}
	# 只有点击“报听”进入选牌状态后才标黄可报听的出牌；
	# 报听后自动摸打，不再给自己的摸牌加黄色提示。
	if table.round.current_turn == seat and not table.round.awaiting \
		and not player.ready and table._declaring_ready:
		for tile in table._ready_discards:
			hinted[str(tile)] = true
	for box in [hand_box[seat], draw_box[seat]]:
		for child in box.get_children():
			if child is TileView:
				child.set_score_highlight(hinted.has(str(child.tile)))

func refresh_ready_hint(seat: int) -> void:
	_refresh_ready_discard_hint(seat)

func refresh_ready_frames() -> void:
	for seat in ready_frames:
		_refresh_ready_frame(int(seat))

func show_pending_ready(seat: int) -> void:
	if table.round == null:
		return
	_pending_ready_round = table.round.get_instance_id()
	_pending_ready_seat = seat
	_refresh_ready_frame(seat)

func _refresh_ready_frame(seat: int) -> void:
	var frame: Panel = ready_frames.get(seat)
	if frame == null or seat >= table.round.players.size():
		return
	var player: PlayerState = table.round.players[seat]
	var pending_ready: bool = _pending_ready_seat == seat \
		and table.round != null and _pending_ready_round == table.round.get_instance_id()
	if not player.ready and not pending_ready:
		frame.hide()
		return
	var bounds := Rect2()
	var has_tile := false
	var box: Control = hand_box.get(seat)
	if box == null:
		frame.hide()
		return
	for child in box.get_children():
		if child is TileView and child.visible:
			var rect := Rect2(box.position + child.position, child.size)
			bounds = rect if not has_tile else bounds.merge(rect)
			has_tile = true
	if not has_tile:
		frame.hide()
		return
	frame.position = bounds.position - Vector2(8, 8)
	frame.size = bounds.size + Vector2(16, 16)
	frame.show()
	# 金边只画边框，置于手牌之上，避免被新刷出的牌面盖住。
	frame.move_to_front()

func _refresh_exposed(seat: int) -> void:
	var player: PlayerState = table.round.players[seat]
	var revealed: Array = []
	for index in player.melds.size(): revealed.append(_meld_revealed(seat, index))
	var key = var_to_bytes([table.round.audio_session, _exposed_layouts.get(seat, []), revealed])
	if _exposed_keys.get(seat) == key: return
	_exposed_keys[seat] = key
	table._clear_box(meld_box[seat])
	table._clear_box(chicken_box[seat])
	var player_unit: float = table._player_tile_unit(seat)
	var height := TileView.BASE_H * player_unit
	for group in _exposed_layouts.get(seat, []):
		var group_origin: Vector2 = group.origin
		if group.has("chicken"):
			var chicken: Dictionary = group.chicken
			var tile: TileView = table._make_tile(chicken.tile, true, player_unit)
			tile.set_meta("discard_id", int(chicken.history_index))
			tile.set_meta("charge_chicken", chicken.charge)
			tile.set_highlight(chicken.latest)
			if chicken.charge:
				tile.rotation = -PI / 2.0
				table._put_tile(chicken_box[seat], tile, group_origin + Vector2(0, height))
			else:
				table._put_tile(chicken_box[seat], tile, group_origin)
			continue
		var meld: Dictionary = group.meld
		var count = 3 if meld.kind == "pung" else 4
		var layout: Dictionary = group.layout
		var up: bool = _meld_revealed(seat, group.meld_index)
		for index in count:
			var tile: TileView = table._make_tile(meld.tile if up else "", up, player_unit)
			tile.set_meta("meld_index", int(group.meld_index))
			# Keep the physical slot so a meld animation can place the claimed
			# discard in the sideways kong position while the other tiles come from
			# the caller's old concealed row.
			tile.set_meta("meld_slot", index)
			tile.set_meta("meld_sideways", int(layout.sideways))
			# 碰杠后的鸡牌不再显示冲锋标记；该标记只存在于实际出牌鸡
			# 的 chicken 组中，不能在这里伪造。
			if index == int(layout.sideways):
				tile.rotation = -PI / 2.0
			table._put_tile(meld_box[seat], tile, group_origin + Vector2(layout.positions[index]))

func _meld_tile_layout(meld: Dictionary, seat: int, unit: float, gap: float) -> Dictionary:
	var width = TileView.BASE_W * unit
	var height = TileView.BASE_H * unit
	var kind = str(meld.get("kind", ""))
	var count = 3 if kind == "pung" else 4
	var source = posmod(int(meld.get("from_seat", -1)) - seat, 4)
	var exposed: bool = kind == "kong" and not meld.get("concealed", false) and int(meld.get("from_seat", -1)) in range(4)
	# 明杠的横牌槽位按“来源相对于自己的方向”固定：
	# 上家(3) 横放最左；下家(1) 横放最右；对家(2) 单独走下方
	# 的对家分支，三竖牌加顶部横牌，也以右侧槽位表示。
	var sideways = int({1: 3, 2: 3, 3: 0}.get(source, -1)) if exposed else -1
	# 碰牌没有来源标记：即使碰到幺鸡，三张牌也全部竖放。
	var positions: Array = []
	if exposed and source == 2:
		# 对家明杠：三张竖牌在上方排一行，第四张横放在正中上方；
		# 横牌仍占 sideways=3 槽位，方便动画复用同一组物理槽位。
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

func _exposed_layout_input_key() -> PackedByteArray:
	# 布局输入只包含会影响占位的内容：牌桌尺寸、手牌/摸牌、碰杠与鸡牌、
	# 中心控件以及操作栏可见性。动画帧只要这些输入没变就直接复用结果。
	# 只保留真正影响碰杠/鸡牌占位的内容。操作栏、设置、语音和教学按钮
	# 位于其他区域，不能因为它们的可见性变化导致整组布局重算跳变。
	var parts: Array = [table.size, table._table_bounds(), table._table_layout.center_rect().size,
		table.action_bar.visible, table.action_bar.position, table.action_bar.size]
	for seat in 4:
		var player: PlayerState = table.round.players[seat]
		parts.append([
			table._relative_seat(seat), table._seat_metrics(seat),
			player.concealed.size(), player.just_drew, player.ready, player.melds,
			table._exposed_groups(seat), table._hand_tile_unit(seat), table._player_tile_unit(seat),
		])
	return var_to_bytes(parts)

func exposed_anchor_x(seat: int) -> float:
	return float(table._seat_metrics(seat).left) + UI.EXPOSED_HAND_GAP

func _prepare_exposed_layouts() -> void:
	# 联机客户端可能尚未收到四家数据，等待期间不规划牌组。
	if table.round.players.size() != 4:
		_exposed_layouts.clear()
		_exposed_layout_key = PackedByteArray()
		return
	var layout_key := _exposed_layout_input_key()
	if not _exposed_layouts.is_empty() and layout_key == _exposed_layout_key:
		return
	_exposed_layout_key = layout_key
	_exposed_layouts.clear()
	var occupied: Array[Rect2] = []
	if table.action_bar.visible:
		occupied.append(Rect2(table.action_bar.position, table.action_bar.size))
	# The score avatars remain in the center after the wall is hidden; exposed
	# groups may now use that free space but must never cover the center panel.
	for control in center_labels.values() + name_labels.values() + dealer_badges.values() + [table.center_info, table._remaining_label]:
		if control.visible: occupied.append(Rect2(control.position, control.size).grow(6.0))
	occupied.append(Rect2(table._settings_button.position + table._settings_button.touch_rect().position,
		table._settings_button.touch_rect().size).grow(6.0))
	for control in [table._ai_teach_button, table._voice_button]:
		if control != null and control.visible:
			occupied.append(Rect2(control.position, control.size).grow(6.0))
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
		# 固定锚点使用座位绝对左边界，不再跟 hand_x 随张数漂移。
		# 间距只作用于固定边界，手牌长度变化不得横向拖动整组。
		var anchor_left: float = exposed_anchor_x(seat)
		# 碰杠/鸡牌采用堆叠模式：
		# 最底行放冲锋鸡，上方普通鸡四张一行；碰/杠各占一行，按出牌顺序向上。
		var groups: Array = table._exposed_groups(seat)
		var charge_items: Array = []
		var normal_items: Array = []
		var meld_items: Array = []
		for group in groups:
			var layout: Dictionary
			if group.has("chicken"):
				var charge: bool = group.chicken.charge
				layout = {"positions": [Vector2(0, height if charge else 0)], "size": Vector2(height if charge else width, height), "sideways": 0 if charge else -1}
				var item := {"group": group, "layout": layout}
				if charge: charge_items.append(item)
				else: normal_items.append(item)
			else:
				layout = table._meld_tile_layout(group.meld, seat, player_unit, UI.TILE_GAP)
				meld_items.append({"group": group, "layout": layout})
		var rows: Array = []
		var row_kinds: Array[String] = []
		if not charge_items.is_empty():
			rows.append(charge_items)
			row_kinds.append("charge")
		for index in range(0, normal_items.size(), 4):
			rows.append(normal_items.slice(index, mini(index + 4, normal_items.size())))
			row_kinds.append("normal")
		for item in meld_items:
			rows.append([item])
			row_kinds.append("meld")
		var base_origins: Array = []
		var row_bottom: float = float(metrics.exposed_y) + height
		# 普通鸡、碰、杠之间不再留额外行距；只有冲锋鸡与普通鸡之间
		# 保留一个视觉分隔。牌面内部间距仍由 TILE_GAP 决定。
		var group_gap := UI.EXPOSED_STACK_GAP
		var previous_kind := ""
		for row_index in rows.size():
			var row_items: Array = rows[row_index]
			var row_height := 0.0
			for item in row_items:
				row_height = maxf(row_height, float(item.layout.size.y))
			var x := anchor_left
			for item in row_items:
				base_origins.append({"item": item, "origin": Vector2(x, row_bottom - float(item.layout.size.y))})
				x += float(item.layout.size.x) + group_gap
			var row_gap := UI.EXPOSED_ROW_GAP if previous_kind == "charge" and row_kinds[row_index] != "charge" else UI.EXPOSED_STACK_GAP
			row_bottom -= row_height + row_gap
			previous_kind = row_kinds[row_index]
		var table_bounds: Rect2 = table._table_bounds()
		var chosen_offset := Vector2.INF
		var chosen_rects: Array[Rect2] = []
		var best_score := INF
		var max_dy := int(table_bounds.size.y)
		for dx in range(0, 128, 8):
			for dy in range(0, max_dy, 8):
				var all_rects: Array[Rect2] = []
				for entry in base_origins:
					var origin: Vector2 = entry.origin + Vector2(dx, -dy)
					all_rects.append_array(table._exposed_rects(entry.item.layout, origin, transform, width, height))
				if _exposed_inside(all_rects, table_bounds) and table._exposed_space_clear(all_rects, occupied):
					var score := float(-dx + dy)
					if score < best_score:
						best_score = score
						chosen_offset = Vector2(dx, -dy)
						chosen_rects = all_rects
					break
		var fallback := chosen_offset == Vector2.INF
		var offset := chosen_offset if not fallback else Vector2.ZERO
		if fallback:
			# 兜底也必须压回真实绿面：先求整个块的包围盒，再整体平移。
			var base_rects: Array[Rect2] = []
			for entry in base_origins:
				base_rects.append_array(table._exposed_rects(entry.item.layout, entry.origin, transform, width, height))
			if not base_rects.is_empty():
				var union := base_rects[0]
				for rect in base_rects:
					union = union.merge(rect)
				if union.position.x < table_bounds.position.x:
					offset.x = table_bounds.position.x - union.position.x
				elif union.end.x > table_bounds.end.x:
					offset.x = table_bounds.end.x - union.end.x
				if union.position.y < table_bounds.position.y:
					offset.y = table_bounds.position.y - union.position.y
				elif union.end.y > table_bounds.end.y:
					offset.y = table_bounds.end.y - union.end.y
		var plans: Array = []
		for entry in base_origins:
			var group: Dictionary = entry.item.group
			var layout: Dictionary = entry.item.layout
			group["origin"] = entry.origin + offset
			group["layout"] = layout
			if fallback: group["fallback"] = true
			plans.append(group)
		if fallback: push_warning("碰杠/鸡牌堆叠空间不足，使用紧凑兜底")
		if not fallback: occupied.append_array(chosen_rects)
		else:
			for entry in base_origins:
				occupied.append_array(table._exposed_rects(entry.item.layout, entry.origin + offset, transform, width, height))
		_exposed_layouts[seat] = plans

func _exposed_inside(rects: Array[Rect2], bounds: Rect2) -> bool:
	for rect in rects:
		if not bounds.encloses(rect):
			return false
	return true

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
	# Only replace tiles inside the persistent rows. The settlement controller
	# owns the parent Tiles.modulate alpha until reset at the next round.
	var player: PlayerState = table.round.players[seat]
	var metrics: Dictionary = table._seat_metrics(seat)
	var columns: int = metrics.river_columns
	var latest_discard: Dictionary = table.round.last_discard if int(table.round.last_discard.get("seat", -1)) == seat else {}
	var key = var_to_bytes([table.round.audio_session, player.discards, player.discard_ids, latest_discard, metrics])
	if _river_keys.get(seat) == key: return
	_river_keys[seat] = key
	for box in discard_box[seat]:
		table._clear_box(box)
	var width = TileView.BASE_W * UI.RIVER_TILE_UNIT
	var height = TileView.BASE_H * UI.RIVER_TILE_UNIT
	var regular_index = 0
	for index in player.discards.size():
		if Tiles.is_chicken(player.discards[index]):
			continue
		var tile: TileView = table._make_tile(player.discards[index], true, UI.RIVER_TILE_UNIT)
		tile.set_meta("discard_id", player.discard_ids[index] if index < player.discard_ids.size() else index)
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
	# A queued scroll must outlive neither the component nor its table. Use a
	# static coroutine with an instance ID instead of suspending `self`. Each
	# river gets its own wait (static signal callables ignore bound arguments).
	_scroll_river_after_layout(table.get_tree(), river.get_instance_id())

static func _scroll_river_after_layout(tree: SceneTree, river_id: int) -> void:
	await tree.process_frame
	var river := instance_from_id(river_id) as ScrollContainer
	if is_instance_valid(river) and river.is_inside_tree():
		river.scroll_vertical = int(river.get_v_scroll_bar().max_value)


