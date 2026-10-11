extends Control

signal quit_to_menu

const DESIGN_SIZE := Vector2(1440, 1520)
const TABLE_CENTER := Vector2(720, 760)
const TILE_UNIT := 1.1
const PLAYER_TILE_UNIT := 1.35
const TILE_GAP := 4.0
const EXPOSED_LEFT_X := -674.0
const PLAYER_RIGHT_X := 550.0
const HAND_ROW_Y := 594.0
const EXPOSED_OVERFLOW_X := -564.0
const EXPOSED_OVERFLOW_Y := 492.0
const EXPOSED_OVERFLOW_RIGHT_X := 472.0
const EXPOSED_HAND_GAP := 36.0
const DRAW_GAP := 24.0
const RIVER_COLUMNS := 6
const RIVER_POSITION := Vector2(-180, 180)
const RIVER_SIZE := Vector2(360, 228)
const ROTATIONS := [0.0, -PI / 2.0, PI, PI / 2.0]
const WINDS := ["东", "南", "西", "北"]
const INK := Color("#edf3ee")
const MUTED := Color("#aac5b9")
const GOLD := Color("#edcc80")

var round: RoundState
var human_seat := 0
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
var status_label: Label
var action_bar: HBoxContainer
var center_info: Label
var round_label: Label
var surface: Control
var result_layer: Control
var net_submit_turn: Callable
var net_submit_response: Callable
var _selecting := false
var _response_disc := ""
var _selected_tile: TileView
var _declaring_ready := false
var _ready_discards: Array = []
var _round_number := 0
var _result_shown := false
var _felt: NoiseTexture2D
var _connection_dialog: AcceptDialog
var _speed_buttons := {}

func _ready() -> void:
	_build_static_ui()
	resized.connect(_layout)
	_layout()
	var mode := _net_mode()
	if mode == "host":
		_setup_host_view()
	elif mode == "client":
		_setup_client_view()
	else:
		new_game()

func _net_mode() -> String:
	var network := get_node_or_null("/root/Network")
	return network.mode if network != null else ""

func _net_node():
	var network := get_node_or_null("/root/Network")
	return network.net_node if network != null else null

func enable_net(turn_cb: Callable, response_cb: Callable) -> void:
	net_submit_turn = turn_cb
	net_submit_response = response_cb

func _emit_turn(decision: Dictionary) -> void:
	if net_submit_turn.is_valid():
		net_submit_turn.call(decision)
	else:
		round.submit_turn(human_seat, decision)

func _emit_response(tile: String, decision: Dictionary) -> void:
	if net_submit_response.is_valid():
		net_submit_response.call(tile, decision)
	else:
		round.submit_response(human_seat, tile, decision)

func new_game() -> void:
	var scores: Array = []
	var chicken_multiplier := round.next_chicken_multiplier if round != null else 1
	if round != null:
		for player in round.players:
			scores.append(player.score)
	_clear_actions()
	_result_shown = false
	_declaring_ready = false
	_selected_tile = null
	if result_layer != null:
		result_layer.hide()
	_round_number += 1
	round = RoundState.new()
	round.next_chicken_multiplier = chicken_multiplier
	round.require_turn.connect(_on_require_turn)
	round.require_response.connect(_on_require_response)
	round.round_finished.connect(_on_round_finished)
	round.state_update.connect(_refresh)
	var controllers: Array = []
	for seat in 4:
		controllers.append(null if seat == human_seat else AiPlayer.new("AI%d" % seat))
	round.controllers = controllers
	round.ai_delay_seconds = GameConfig.ai_delay_seconds()
	round.randomize_seed()
	round.start_round(human_seat)
	if scores.size() == 4:
		round.apply_scores(scores)
	_refresh()

func _setup_host_view() -> void:
	var network = _net_node()
	human_seat = network.my_seat
	round = network.game
	_round_number = 1
	round.require_turn.connect(_on_require_turn)
	round.require_response.connect(_on_require_response)
	round.round_finished.connect(_on_round_finished)
	round.state_update.connect(_refresh)
	if round.phase == "idle":
		network.start_net_game()
	else:
		_on_net_prompt(human_seat)
		_refresh()
	network.connection_error.connect(_on_connection_error)

func _setup_client_view() -> void:
	var network = _net_node()
	round = network.game
	_round_number = 1
	network.room_ready.connect(func(seat):
		human_seat = seat
		_refresh())
	network.state_updated.connect(_on_client_state_updated)
	network.prompted.connect(_on_net_prompt)
	network.connection_error.connect(_on_connection_error)
	enable_net(network.submit_client_turn, network.submit_client_response)
	if network.my_seat >= 0:
		human_seat = network.my_seat
	_refresh()

func _build_static_ui() -> void:
	var theme_resource := Theme.new()
	theme_resource.default_font = TileView._font()
	theme_resource.default_font_size = 18
	theme = theme_resource
	surface = Control.new()
	surface.name = "TableSurface"
	surface.size = DESIGN_SIZE
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(surface)
	var noise := FastNoiseLite.new()
	noise.seed = 81
	noise.frequency = 0.7
	_felt = NoiseTexture2D.new()
	_felt.width = 512
	_felt.height = 512
	_felt.noise = noise
	_felt.changed.connect(queue_redraw)
	_label(surface, "安顺麻将", Vector2(36, 21), Vector2(180, 36), 27)
	_label(surface, "捉鸡  /  万 · 条 · 筒", Vector2(222, 28), Vector2(250, 30), 16, MUTED)
	round_label = _label(surface, "", Vector2(570, 28), Vector2(300, 30), 16, MUTED)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(surface, "AI速度", Vector2(950, 24), Vector2(82, 32), 15, MUTED)
	var speed_bar := HBoxContainer.new()
	speed_bar.position = Vector2(1030, 20)
	speed_bar.size = Vector2(250, 40)
	speed_bar.add_theme_constant_override("separation", 6)
	surface.add_child(speed_bar)
	for item in [["快1秒", "fast"], ["中2秒", "medium"], ["慢3秒", "slow"]]:
		var speed_key: String = item[1]
		var speed_button := _button(item[0], func(): _set_ai_speed(speed_key), Vector2(72, 36))
		speed_button.add_theme_font_size_override("font_size", 14)
		speed_bar.add_child(speed_button)
		_speed_buttons[speed_key] = speed_button
	_update_speed_buttons()
	var back := _button("←", _on_quit, Vector2(48, 42))
	back.position = Vector2(1354, 20)
	back.tooltip_text = "返回大厅"
	surface.add_child(back)
	for seat in 4:
		var station := Control.new()
		station.name = "SeatRoot%d" % seat
		station.position = TABLE_CENTER
		station.mouse_filter = Control.MOUSE_FILTER_IGNORE
		surface.add_child(station)
		seat_roots[seat] = station
		hand_box[seat] = _box(station)
		hand_box[seat].name = "Hand%d" % seat
		draw_box[seat] = _box(station)
		draw_box[seat].name = "Draw%d" % seat
		meld_box[seat] = _box(station)
		meld_box[seat].name = "Meld%d" % seat
		chicken_box[seat] = _box(station)
		chicken_box[seat].name = "Chicken%d" % seat
		wall_box[seat] = _box(station)
		wall_box[seat].name = "Wall%d" % seat
		discard_box[seat] = []
		var river := ScrollContainer.new()
		river.name = "River%d" % seat
		river.position = RIVER_POSITION
		river.size = RIVER_SIZE
		river.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		river.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		station.add_child(river)
		discard_scroll[seat] = river
		var river_content := _box(river)
		river_content.name = "Tiles"
		for _row in 18:
			var discard_row := _box(river_content)
			discard_row.name = "Discard%dRow%d" % [seat, _row]
			discard_box[seat].append(discard_row)
		var avatar := _label(surface, WINDS[seat], Vector2.ZERO, Vector2(54, 54), 26)
		avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		avatars[seat] = avatar
		center_labels[seat] = _label(surface, "", Vector2.ZERO, Vector2(164, 78), 19)
		var wind := _label(surface, WINDS[seat], Vector2.ZERO, Vector2(32, 32), 19, MUTED)
		wind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		wind_labels[seat] = wind
		wind.hide()
	_label(surface, "余牌", Vector2(680, 705), Vector2(80, 24), 14, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_info = _label(surface, "", Vector2(664, 733), Vector2(112, 58), 40)
	center_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_bar = HBoxContainer.new()
	action_bar.position = Vector2(810, 1450)
	action_bar.size = Vector2(560, 58)
	action_bar.alignment = BoxContainer.ALIGNMENT_END
	action_bar.add_theme_constant_override("separation", 12)
	surface.add_child(action_bar)
	status_label = _label(surface, "", Vector2(60, 1464), Vector2(710, 30), 20, MUTED)
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	result_layer = _box(surface)
	result_layer.size = DESIGN_SIZE
	result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	result_layer.hide()

func _layout() -> void:
	if surface == null:
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	surface.scale = Vector2.ONE * factor
	surface.position = (size - DESIGN_SIZE * factor) / 2.0
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#141d1b"))
	if surface == null:
		return
	draw_set_transform(surface.position, 0.0, surface.scale)
	draw_style_box(_style(Color("#293430"), Color("#42524b"), 8, 2), Rect2(24, 72, 1392, 1376))
	draw_style_box(_style(Color("#174f3c"), Color("#688275"), 8, 1), Rect2(42, 80, 1356, 1360))
	if _felt != null:
		draw_texture_rect(_felt, Rect2(62, 119, 1316, 1282), false, Color(0.58, 0.8, 0.66, 0.07))
	draw_style_box(_style(Color(0, 0, 0, 0), Color("#39725a"), 8, 1), Rect2(65, 122, 1310, 1275))
	draw_line(Vector2(30, 68), Vector2(1410, 68), Color("#38453f"), 1)
	draw_style_box(_style(Color("#15382e"), Color("#618373"), 8, 2), Rect2(636, 676, 168, 168))
	if round == null:
		return
	for seat in 4:
		var avatar: Label = avatars[seat]
		var active := round.phase == "playing" and round.current_turn == seat
		draw_style_box(_style(Color("#263f35"), GOLD if active else Color("#61786b"), 8, 2), Rect2(avatar.position, avatar.size))
		var wind: Label = wind_labels[seat]
		if active and wind.visible:
			draw_style_box(_style(Color("#3b6150"), GOLD, 4, 1), Rect2(wind.position, wind.size))
		if seat < round.players.size() and round.players[seat].is_dealer:
			var badge := Rect2(avatar.position + Vector2(39, -8), Vector2(24, 24))
			draw_style_box(_style(Color("#b84b43"), Color("#edb29a"), 4, 1), badge)
			draw_string(TileView._font(), badge.position + Vector2(4, 18), "庄", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	_draw_die(int(round.round_meta.get("die", 1)), Vector2(702, 798))

func _draw_die(value: int, pos: Vector2) -> void:
	draw_style_box(_style(Color("#f1f3e9"), Color("#b2bfb3"), 5, 1), Rect2(pos, Vector2(36, 36)))
	var points: Array = []
	if value % 2 == 1:
		points.append(Vector2(18, 18))
	if value >= 2:
		points.append_array([Vector2(9, 9), Vector2(27, 27)])
	if value >= 4:
		points.append_array([Vector2(27, 9), Vector2(9, 27)])
	if value == 6:
		points.append_array([Vector2(9, 18), Vector2(27, 18)])
	for point in points:
		draw_circle(pos + point, 3.0, Color("#bc453e") if value == 1 else Color("#243d32"))

func _relative_seat(seat: int) -> int:
	return posmod(seat - human_seat, 4)

func _refresh() -> void:
	if round == null:
		return
	if round.phase != "settled":
		_result_shown = false
		result_layer.hide()
	_selected_tile = null
	for seat in 4:
		_refresh_seat(seat)
	_refresh_walls()
	_refresh_center()
	_refresh_status()
	_update_interactivity()
	queue_redraw()
	if round.phase == "settled" and not _result_shown:
		_result_shown = true
		_show_result.call_deferred()

func _refresh_seat(seat: int) -> void:
	var relative := _relative_seat(seat)
	seat_roots[seat].rotation = ROTATIONS[relative]
	var avatar_positions := [Vector2(622, 854), Vector2(814, 682), Vector2(770, 606), Vector2(578, 794)]
	var label_positions := [Vector2(682, 854), Vector2(810, 742), Vector2(602, 606), Vector2(566, 678)]
	avatars[seat].position = avatar_positions[relative]
	center_labels[seat].position = label_positions[relative]
	center_labels[seat].size = Vector2(70, 110) if relative == 1 or relative == 3 else Vector2(164, 64)
	center_labels[seat].autowrap_mode = TextServer.AUTOWRAP_OFF
	center_labels[seat].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if seat >= round.players.size():
		center_labels[seat].text = "等待入座"
		return
	var player: PlayerState = round.players[seat]
	var title: String = ["你", "下家", "对家", "上家"][relative]
	var tags := "已听" if player.ready else ""
	if player.charge_chicken:
		tags += (" · " if tags != "" else "") + "冲锋鸡"
	center_labels[seat].text = "%s\n%.0f 分" % [title, player.score] if relative == 1 or relative == 3 else "%s · %.0f 分" % [title, player.score]
	if tags != "":
		center_labels[seat].text += "\n" + (tags.replace(" · ", "\n") if relative == 1 or relative == 3 else tags)
	var label_font_size := 15 if relative == 1 or relative == 3 else 17
	for line in center_labels[seat].text.split("\n"):
		while label_font_size > 10 and TileView._font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size).x > center_labels[seat].size.x:
			label_font_size -= 1
	center_labels[seat].add_theme_font_size_override("font_size", label_font_size)
	center_labels[seat].add_theme_color_override("font_color", GOLD if player.ready else INK)
	center_labels[seat].size = Vector2(70, 110) if relative == 1 or relative == 3 else Vector2(164, 64)
	_clear_box(meld_box[seat])
	_clear_box(chicken_box[seat])
	var cards := Tiles.sort_hand(player.concealed)
	var has_draw := player.just_drew != "" and cards.has(player.just_drew)
	if has_draw:
		cards.erase(player.just_drew)
	var width := TileView.BASE_W * PLAYER_TILE_UNIT
	var height := TileView.BASE_H * PLAYER_TILE_UNIT
	# Both ends stay fixed: exposed tiles grow from the left table edge; the hand
	# shrinks toward its right edge as tiles move into melds. Reserve the draw slot
	# even between draws so taking/discarding a tile cannot recenter the whole row.
	var draw_x := PLAYER_RIGHT_X - width
	var hand_right := draw_x - DRAW_GAP
	var hand_span := maxf(0.0, cards.size() * (width + TILE_GAP) - TILE_GAP)
	var hand_x := hand_right - hand_span
	var row_end := hand_x - EXPOSED_HAND_GAP
	var meld_x := EXPOSED_LEFT_X
	var meld_y := HAND_ROW_Y
	for group in _exposed_groups(seat):
		if group.has("chicken"):
			var chicken: Dictionary = group.chicken
			var tile := _make_tile(chicken.tile, true, PLAYER_TILE_UNIT)
			var tile_width := height if chicken.charge else width
			if meld_x + tile_width > row_end:
				meld_x = EXPOSED_OVERFLOW_X
				meld_y = EXPOSED_OVERFLOW_Y
				row_end = EXPOSED_OVERFLOW_RIGHT_X
			tile.set_meta("charge_chicken", chicken.charge)
			tile.set_highlight(chicken.latest)
			if chicken.charge:
				tile.rotation = -PI / 2.0
				_put_tile(chicken_box[seat], tile, Vector2(meld_x, meld_y + height))
				tile.tooltip_text = "冲锋鸡 · " + _cn(chicken.tile)
			else:
				_put_tile(chicken_box[seat], tile, Vector2(meld_x, meld_y))
			meld_x += tile_width + TILE_GAP
			continue
		var meld: Dictionary = group.meld
		var count := 3 if meld.kind == "pung" else 4
		# Only an exposed kong marks its source; the added fourth tile marks a self upgrade.
		var marks_source: bool = meld.kind == "kong" and meld.has("from_seat") and not meld.get("concealed", false)
		var source: int = posmod(int(meld.get("from_seat", seat)) - seat, 4) if marks_source else -1
		var claimed: int = {1: 2, 2: 1, 3: 0}.get(source, -1)
		if meld.kind == "add_kong":
			claimed = 3
		var charge_index := -1
		if round.is_charge_meld(seat, group.meld_index):
			charge_index = claimed if marks_source else 0
		var sideways: Array = []
		if claimed >= 0:
			sideways.append(claimed)
		if charge_index >= 0 and not sideways.has(charge_index):
			sideways.append(charge_index)
		var group_width := count * (width + TILE_GAP) - TILE_GAP + (height - width) * sideways.size()
		if meld_x + group_width > row_end:
			meld_x = EXPOSED_OVERFLOW_X
			meld_y = EXPOSED_OVERFLOW_Y
			row_end = EXPOSED_OVERFLOW_RIGHT_X
		for index in count:
			var up: bool = not (meld.get("concealed", false) and index in [0, 3] and round.phase != "settled")
			if meld.get("concealed", false) and seat != human_seat and round.phase != "settled":
				up = false
			var tile := _make_tile(meld.tile if up else "", up, PLAYER_TILE_UNIT)
			tile.set_meta("charge_chicken", index == charge_index)
			if index == charge_index:
				tile.tooltip_text = "冲锋鸡 · " + _cn(meld.tile)
				tile.set_highlight(true)
			if index in sideways:
				tile.rotation = -PI / 2.0
				_put_tile(meld_box[seat], tile, Vector2(meld_x, meld_y + height))
				meld_x += height + TILE_GAP
			else:
				_put_tile(meld_box[seat], tile, Vector2(meld_x, meld_y))
				meld_x += width + TILE_GAP
		meld_x += 10.0
	_clear_box(hand_box[seat])
	_clear_box(draw_box[seat])
	var own := seat == human_seat
	var x := hand_x
	var y := HAND_ROW_Y
	var reveal := own or round.phase == "settled"
	for card in cards:
		var tile := _make_tile(card if reveal else "", reveal, PLAYER_TILE_UNIT)
		_put_tile(hand_box[seat], tile, Vector2(x, y))
		if own:
			tile.gui_input.connect(_on_human_tile_gui.bind(tile))
			tile.set_meta("drawn", false)
		x += width + TILE_GAP
	if has_draw:
		var drawn := _make_tile(player.just_drew if reveal else "", reveal, PLAYER_TILE_UNIT)
		_put_tile(draw_box[seat], drawn, Vector2(draw_x, y))
		drawn.set_meta("drawn", true)
		if own:
			drawn.gui_input.connect(_on_human_tile_gui.bind(drawn))
	_refresh_discards(seat)

func _chicken_discards(seat: int) -> Array:
	var player: PlayerState = round.players[seat]
	var chickens: Array = []
	for index in player.discards.size():
		var card: String = player.discards[index]
		if Tiles.is_chicken(card):
			var latest: bool = round.last_discard.get("seat", -1) == seat and round.last_discard.get("tile", "") == card and index == player.discards.size() - 1
			var discard_id: int = player.discard_ids[index] if index < player.discard_ids.size() else index
			chickens.append({"tile": card, "charge": round.is_charge_discard(seat, index), "latest": latest, "history_index": discard_id})
	return chickens

func _exposed_groups(seat: int) -> Array:
	# Append groups in play order, including chickens between two melds. An added
	# kong keeps the original pung's position. The metadata travels with each meld.
	var groups: Array = []
	for index in round.players[seat].melds.size():
		var meld: Dictionary = round.players[seat].melds[index]
		groups.append({"meld": meld, "meld_index": index, "order": int(meld.get("after_discard", 0)) * 2, "tie": groups.size()})
	for chicken in _chicken_discards(seat):
		groups.append({"chicken": chicken, "order": int(chicken.history_index) * 2 + 1, "tie": groups.size()})
	groups.sort_custom(func(a, b): return a.tie < b.tie if a.order == b.order else a.order < b.order)
	return groups

func _refresh_discards(seat: int) -> void:
	var player: PlayerState = round.players[seat]
	for box in discard_box[seat]:
		_clear_box(box)
	var width := TileView.BASE_W * TILE_UNIT
	var height := TileView.BASE_H * TILE_UNIT
	var regular_index := 0
	for index in player.discards.size():
		if Tiles.is_chicken(player.discards[index]):
			continue
		var tile := _make_tile(player.discards[index], true)
		var latest: bool = round.last_discard.get("seat", -1) == seat and round.last_discard.get("tile", "") == tile.tile and index == player.discards.size() - 1
		tile.set_highlight(latest)
		var row_index := regular_index / RIVER_COLUMNS
		_put_tile(discard_box[seat][row_index], tile, Vector2(4 + (regular_index % RIVER_COLUMNS) * (width + TILE_GAP), 4 + row_index * (height + TILE_GAP)))
		regular_index += 1
	var river: ScrollContainer = discard_scroll[seat]
	var content: Control = river.get_child(0)
	content.custom_minimum_size = Vector2(344, maxf(RIVER_SIZE.y, ceili(regular_index / float(RIVER_COLUMNS)) * (height + TILE_GAP) + 8))
	var river_key := ",".join(player.discards)
	if river.get_meta("cards", "") != river_key:
		river.set_meta("cards", river_key)
		_scroll_to_latest.call_deferred(river)

func _scroll_to_latest(river: ScrollContainer) -> void:
	await get_tree().process_frame
	if is_instance_valid(river):
		river.scroll_vertical = int(river.get_v_scroll_bar().max_value)

func _wall_stacks(seat: int) -> Array:
	if round.wall != null:
		return round.wall.wall_stack_counts(seat)
	if round.wall_stacks.has(seat):
		return round.wall_stacks[seat]
	var fallback: Array = []
	var remaining := _wall_remain(seat)
	for index in (14 if seat == 0 or seat == 2 else 13):
		fallback.append(clampi(remaining - index * 2, 0, 2))
	return fallback

func _refresh_walls() -> void:
	for seat in 4:
		_clear_box(wall_box[seat])
		var stacks := _wall_stacks(seat)
		var step := TileView.BASE_W * TILE_UNIT + TILE_GAP
		for index in stacks.size():
			var x := (stacks.size() / 2.0 - index - 1.0) * step
			for layer in int(stacks[index]):
				var tile := _make_tile("", false)
				_put_tile(wall_box[seat], tile, Vector2(x, 416.0 - layer * 7.0))

func _refresh_center() -> void:
	center_info.text = str(_sum_wall()) if not round.players.is_empty() else "--"
	var number: int = _round_number if _net_mode() == "" else _net_node().round_number
	round_label.text = "第 %02d 局    ·    %s" % [maxi(1, number), "单机对局" if _net_mode() == "" else "联机对局"]
	if round.round_meta.get("chicken_multiplier", 1) > 1:
		round_label.text += "    ·    鸡分 ×%d" % round.round_meta.chicken_multiplier
	for seat in 4:
		wind_labels[seat].add_theme_color_override("font_color", GOLD if round.current_turn == seat and round.phase == "playing" else MUTED)
	_update_speed_buttons()

func _set_ai_speed(speed_key: String) -> void:
	GameConfig.set_ai_speed(speed_key)
	if round != null:
		round.ai_delay_seconds = GameConfig.ai_delay_seconds()
	var network := get_node_or_null("/root/Network")
	if network != null and network.net_node != null and network.net_node.game != null:
		network.net_node.game.ai_delay_seconds = GameConfig.ai_delay_seconds()
	_update_speed_buttons()

func _update_speed_buttons() -> void:
	for speed_key in _speed_buttons:
		var button: Button = _speed_buttons[speed_key]
		button.modulate = Color("#f4df9f") if speed_key == GameConfig.ai_speed else Color.WHITE

func _sum_wall() -> int:
	var count := 0
	for seat in 4:
		count += _wall_remain(seat)
	return count

func _wall_remain(seat: int) -> int:
	if round != null and round.wall != null:
		return round.wall.wall_remaining(seat)
	return int(round.wall_remain.get(seat, 0)) if round != null else 0

func _seat_name(seat: int) -> String:
	if seat < 0 or seat > 3:
		return "-"
	return ["你", "下家", "对家", "上家"][_relative_seat(seat)]

func _refresh_status() -> void:
	if round.phase == "settled":
		var winner := int(round.round_meta.get("winner", -1))
		status_label.text = _draw_result_title() if winner < 0 else "%s%s" % [_seat_name(winner), "自摸" if round.round_meta.get("self_draw", false) else "胡牌"]
	elif not _response_disc.is_empty():
		var response: Dictionary = round._awaiting_response
		var source := int(response.get("disc_seat", round.last_discard.get("seat", -1)))
		var robbed: bool = response.get("options", {}).get("rob_kong", false)
		status_label.text = "%s%s %s" % [_seat_name(source), "加杠" if robbed else "打出", _cn(_response_disc)]
	elif _declaring_ready:
		status_label.text = "报听"
	elif _selecting:
		status_label.text = "你的回合" + ("  ·  已报听" if round.players[human_seat].ready else "")
	else:
		status_label.text = "%s的回合" % _seat_name(round.current_turn)

func _on_human_tile_gui(event: InputEvent, tile: TileView) -> void:
	if not _selecting or not tile.interactive:
		return
	var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var keyboard: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_SPACE]
	if not clicked and not keyboard:
		return
	if _selected_tile == tile:
		_submit_discard(tile.tile)
		return
	if is_instance_valid(_selected_tile):
		_selected_tile.set_selected(false)
	_selected_tile = tile
	tile.set_selected(true)
	for button in action_bar.get_children():
		if button.get_meta("discard", false):
			button.disabled = false

func _on_require_turn(seat: int) -> void:
	if seat != human_seat:
		return
	_selecting = true
	_declaring_ready = false
	_response_disc = ""
	_build_turn_options(round.players[seat])

func _build_turn_options(player: PlayerState) -> void:
	_clear_actions()
	if player.just_drew != "" and RuleEngine.analyze(player.concealed, player.melds).win:
		_add_action("自摸", func(): _commit_turn({"self_win": true}), true)
	var concealed_kongs: Array = []
	for card in (Tiles.sort_hand(player.concealed) if not player.ready and round._wall_count() > 0 else []):
		if Tiles.count(player.concealed, card) >= 4 and not concealed_kongs.has(card):
			concealed_kongs.append(card)
	_add_kong_choices("暗杠", "kong_declares", concealed_kongs)
	var added_kongs: Array = []
	for meld in (player.melds if not player.ready and round._wall_count() > 0 else []):
		if meld.kind == "pung" and Tiles.count(player.concealed, meld.tile) > 0:
			added_kongs.append(meld.tile)
	_add_kong_choices("加杠", "add_kong", added_kongs)
	_ready_discards.clear()
	if round.can_declare_ready(human_seat):
		for card in player.concealed:
			if _ready_discards.has(card):
				continue
			var after := player.concealed.duplicate()
			after.erase(card)
			if RuleEngine.is_tenpai(after, player.melds):
				_ready_discards.append(card)
	if not _ready_discards.is_empty():
		_add_action("报听", _toggle_ready)
	var discard := _add_action("出牌", _discard_selected, true)
	discard.set_meta("discard", true)
	discard.disabled = true

func _add_kong_choices(title: String, decision_key: String, cards: Array) -> void:
	if cards.is_empty():
		return
	if cards.size() == 1:
		_add_action(title, func(): _commit_turn({decision_key: [cards[0]]}), false, title + " " + _cn(cards[0]))
		return
	var choices := PopupMenu.new()
	choices.name = "TileChoices"
	choices.add_theme_font_size_override("font_size", 24)
	choices.add_theme_constant_override("v_separation", 24)
	for index in cards.size():
		choices.add_item(_cn(cards[index]), index)
	choices.id_pressed.connect(func(index): _commit_turn({decision_key: [cards[index]]}))
	var button := _add_action(title, func(): choices.popup_centered(Vector2i(240, 0)))
	button.add_child(choices)

func _discard_selected() -> void:
	if is_instance_valid(_selected_tile):
		_submit_discard(_selected_tile.tile)

func _toggle_ready() -> void:
	_declaring_ready = not _declaring_ready
	if is_instance_valid(_selected_tile):
		_selected_tile.set_selected(false)
	_selected_tile = null
	for button in action_bar.get_children():
		if button.get_meta("discard", false):
			button.disabled = true
		elif button.text == "报听" or button.text == "取消":
			button.text = "取消" if _declaring_ready else "报听"
	_update_interactivity()
	_refresh_status()

func _update_interactivity() -> void:
	if round == null or human_seat >= round.players.size():
		return
	var player: PlayerState = round.players[human_seat]
	for box in [hand_box[human_seat], draw_box[human_seat]]:
		for tile in box.get_children():
			var enabled: bool = _selecting and (not player.ready or tile.get_meta("drawn", false))
			if _declaring_ready:
				enabled = enabled and _ready_discards.has(tile.tile)
			tile.set_interactive(enabled)
			tile.modulate = Color.WHITE if enabled or not _selecting else Color(0.7, 0.76, 0.7)

func _safe_discard() -> String:
	if is_instance_valid(_selected_tile):
		return _selected_tile.tile
	var player: PlayerState = round.players[human_seat]
	return player.just_drew if player.just_drew != "" else (player.concealed[0] if not player.concealed.is_empty() else "")

func _commit_turn(decision: Dictionary) -> void:
	_selecting = false
	_declaring_ready = false
	_clear_actions()
	_update_interactivity()
	_emit_turn(decision)

func _submit_discard(tile: String) -> void:
	if not _selecting or (_declaring_ready and not _ready_discards.has(tile)):
		return
	_commit_turn({"discard": tile, "ready": _declaring_ready})

func _on_require_response(seat: int, discarded_seat: int, tile: String, options: Dictionary) -> void:
	if seat != human_seat:
		return
	_selecting = false
	_declaring_ready = false
	_response_disc = tile
	_clear_actions()
	if options.get("can_win", false):
		_add_action("胡", func(): _commit_response("win"), true)
	if options.get("can_pong", false):
		_add_action("碰", func(): _commit_response("pong"), true)
	if options.get("can_kong", false):
		_add_action("杠", func(): _commit_response("kong"), true)
	_add_action("过", func(): _commit_response("pass"))
	_update_interactivity()
	status_label.text = "%s%s %s" % [_seat_name(discarded_seat), "加杠" if options.get("rob_kong", false) else "打出", _cn(tile)]

func _commit_response(action: String) -> void:
	var tile := _response_disc
	_response_disc = ""
	_clear_actions()
	_emit_response(tile, {"action": action})

func _on_client_state_updated() -> void:
	_selecting = false
	_response_disc = ""
	_clear_actions()
	if round.awaiting:
		_on_net_prompt(human_seat)
	if round.phase == "settled":
		_add_action("结算", _show_result)
	_refresh()

func _on_net_prompt(seat: int) -> void:
	if seat != human_seat or seat >= round.players.size():
		return
	var response: Dictionary = round._awaiting_response
	if not response.is_empty():
		if int(response.get("seat", -1)) == human_seat:
			var tile: String = response.tile
			var player: PlayerState = round.players[seat]
			var options: Dictionary = response.get("options", {
				"can_win": RuleEngine.can_win_on(player.concealed, player.melds, tile),
				"can_pong": Tiles.count(player.concealed, tile) >= 2,
				"can_kong": Tiles.count(player.concealed, tile) >= 3,
			})
			_on_require_response(seat, response.disc_seat, tile, options)
	elif round.current_turn == human_seat and round.phase == "playing":
		_on_require_turn(seat)
	_update_interactivity()

func _on_round_finished(_result: Dictionary) -> void:
	_selecting = false
	_response_disc = ""
	_clear_actions()
	_add_action("结算", _show_result)
	_refresh()

func _draw_result_title() -> String:
	return "四家叫牌 · 流局" if round.round_meta.get("all_called_draw", false) else "牌墙摸完 · 查叫"

func _show_result() -> void:
	_clear_box(result_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.04, 0.78)
	shade.size = DESIGN_SIZE
	result_layer.add_child(shade)
	var panel := Panel.new()
	panel.position = (DESIGN_SIZE - Vector2(560, 590)) / 2.0
	panel.size = Vector2(560, 590)
	panel.add_theme_stylebox_override("panel", _style(Color("#243b31"), Color("#739383"), 8, 1))
	result_layer.add_child(panel)
	var winner := int(round.round_meta.get("winner", -1))
	var title := _draw_result_title() if winner < 0 else "%s%s" % [_seat_name(winner), "自摸" if round.round_meta.get("self_draw", false) else "胡牌"]
	_label(panel, title, Vector2(32, 24), Vector2(496, 48), 30, GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var flip: String = round.round_meta.get("flip_tile", "")
	if flip != "":
		_label(panel, "翻牌鸡", Vector2(176, 88), Vector2(92, 38), 17, MUTED)
		_put_tile(panel, _make_tile(flip, true), Vector2(290, 76))
	elif winner < 0:
		var notice := "本局不计分 · 下局鸡分 ×%d" % round.next_chicken_multiplier if round.round_meta.get("all_called_draw", false) else "未叫牌者补出牌鸡与杠分 · 叫牌者不补差"
		_label(panel, notice, Vector2(24, 92), Vector2(512, 38), 19, GOLD).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for relative in 4:
		var seat := posmod(human_seat + relative, 4)
		var player: PlayerState = round.players[seat]
		var delta := 0.0
		var deltas: Array = round.last_result.get("deltas", round._last_deltas)
		if deltas.size() == 4:
			delta = float(deltas[seat])
		var y := 153.0 + relative * 49.0
		_label(panel, _seat_name(seat), Vector2(38, y), Vector2(150, 36), 20)
		_label(panel, "%.0f 分" % player.score, Vector2(202, y), Vector2(130, 36), 22)
		var change := _label(panel, "%+.0f" % delta, Vector2(382, y), Vector2(128, 36), 23, GOLD if delta > 0 else MUTED)
		change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var detail := RichTextLabel.new()
	detail.position = Vector2(38, 366)
	detail.size = Vector2(484, 118)
	detail.add_theme_font_size_override("normal_font_size", 16)
	detail.add_theme_color_override("default_color", MUTED)
	detail.text = "\n".join(round.last_result.get("lines", []))
	for transfer in round.last_result.get("transfers", []):
		detail.text += "\n%s → %s  %.0f  %s" % [_seat_name(transfer.from), _seat_name(transfer.to), transfer.amount, transfer.reason]
	panel.add_child(detail)
	var view := _button("牌桌", func(): result_layer.hide(), Vector2(146, 48))
	view.position = Vector2(42, 516)
	panel.add_child(view)
	var next := _button("下一局" if _net_mode() != "client" else "返回大厅", _next_round if _net_mode() != "client" else _on_quit, Vector2(290, 48), true)
	next.position = Vector2(222, 516)
	panel.add_child(next)
	result_layer.show()

func _next_round() -> void:
	if _net_mode() == "host":
		_result_shown = false
		result_layer.hide()
		_net_node().next_round()
	else:
		new_game()

func _on_connection_error(message: String) -> void:
	_selecting = false
	_clear_actions()
	_connection_dialog = AcceptDialog.new()
	_connection_dialog.dialog_text = message
	_connection_dialog.title = "联机"
	_connection_dialog.confirmed.connect(_on_quit)
	add_child(_connection_dialog)
	_connection_dialog.popup_centered()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_quit()

func _make_tile(card: String, up: bool, unit: float = TILE_UNIT) -> TileView:
	var tile := TileView.new()
	tile.set_card(card, up)
	tile.set_unit(unit)
	return tile

func _put_tile(parent: Control, tile: TileView, pos: Vector2) -> void:
	parent.add_child(tile)
	tile.set_table_position(pos)

func _box(parent: Control) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box

func _label(parent: Control, text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.size = dimensions
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _style(color: Color, border: Color, radius: int, border_width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border_width)
	return style

func _button(text: String, callback: Callable, dimensions: Vector2, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = dimensions
	button.size = dimensions
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", Color("#203b2d") if primary else INK)
	button.add_theme_color_override("font_hover_color", Color("#203b2d") if primary else INK)
	button.add_theme_stylebox_override("normal", _style(GOLD if primary else Color("#345344"), Color("#8caa94"), 6, 1))
	button.add_theme_stylebox_override("hover", _style(Color("#f4df9f") if primary else Color("#49735b"), GOLD, 6, 1))
	button.add_theme_stylebox_override("pressed", _style(Color("#c6aa67") if primary else Color("#244432"), GOLD, 6, 1))
	button.add_theme_stylebox_override("disabled", _style(Color("#34483b"), Color("#4c6251"), 6, 1))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), GOLD, 6, 2))
	button.pressed.connect(callback)
	return button

func _add_action(text: String, callback: Callable, primary: bool = false, tooltip: String = "") -> Button:
	var button := _button(text, callback, Vector2(82, 54), primary)
	button.tooltip_text = tooltip
	action_bar.add_child(button)
	return button

func _clear_actions() -> void:
	if action_bar != null:
		_clear_box(action_bar)

func _clear_box(box: Node) -> void:
	# Detach immediately: consecutive synchronous state updates share a frame.
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func _cn(card: String) -> String:
	if card == "":
		return "-"
	return "%d%s" % [Tiles.rank(card), {"wan": "万", "tiao": "条", "tong": "筒"}.get(Tiles.suit(card), "")]

func _on_quit() -> void:
	quit_to_menu.emit()
	if _net_mode() != "":
		Network.reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
