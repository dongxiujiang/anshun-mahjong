extends Control

signal quit_to_menu

## The table is deliberately designed in landscape.  Both the desktop build and
## Android use this same canvas so a device rotation never switches to the old
## portrait table.
const DESIGN_SIZE := Vector2(2280, 1280)
## Reference origin for the small center-panel labels authored before landscape.
const TABLE_CENTER := Vector2(720, 760)
const LANDSCAPE_SIZE := Vector2(2280, 1280)
const LANDSCAPE_CENTER := Vector2(1140, 650)
const LANDSCAPE_RESULT_SIZE := Vector2(2200, 1232)
const TILE_UNIT := 1.1
const PLAYER_TILE_UNIT := 1.35
const OWN_PLAYER_TILE_UNIT := 1.60
const OWN_HAND_TILE_UNIT := OWN_PLAYER_TILE_UNIT * 1.5
const ACTION_BUTTON_SIZE := Vector2(118, 84)
const DISCARD_BUTTON_SIZE := ACTION_BUTTON_SIZE * 1.5
const ACTION_HAND_GAP := 56.0
## 结算卡片里的牌图单独放大，便于看清是哪张牌。
const RESULT_TILE_UNIT := 1.6
const RESULT_CARD_SIZE := Vector2(1320, 1496)
const RESULT_TOGGLE_SIZE := Vector2(132, 54)
const RESULT_TOGGLE_LOCAL_POSITION := Vector2(1166, 22)
const NEXT_ROUND_BUTTON_SIZE := Vector2(440, 126)
const TILE_GAP := 4.0
const EXPOSED_HAND_GAP := 36.0
const DRAW_GAP := 24.0
const RIVER_POSITION := Vector2(-180, 180)
const RIVER_SIZE := Vector2(360, 228)
const ROTATIONS := [0.0, -PI / 2.0, PI, PI / 2.0]
const WINDS := ["东", "南", "西", "北"]
const INK := Color("#edf3ee")
const MUTED := Color("#aac5b9")
const GOLD := Color("#edcc80")
const SAFE_MARGIN := 28.0
const TOUCH_MARGIN := 16.0
const VISUAL_ANIMATIONS := true

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
var _result_panel: Control
var _result_shade: ColorRect
var _result_restore: Button
var _next_round_button: Button
var _next_round_status: Label
var _next_round_hint: Label
var _status_labels := {}
var _exposed_layouts := {}
var _sound_settings: SoundSettings
var _audio_round: RoundState
var _landscape := false
var _sound_button: Button
var _settings_button: Button
var _seat_visual_keys := {}
var _remaining_label: Label
var _animation_layer: TableAnimationLayer
var _animation_busy := false
var _animation_last_id := 0
var _animation_queue: Array = []
var _skip_visual_once := false
var _last_tile_input_ms := -1000

func _ready() -> void:
	AudioManager.begin_table(self)
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

func _connect_audio_round() -> void:
	if _audio_round != null and _audio_round.audio_event.is_connected(_on_audio_event):
		_audio_round.audio_event.disconnect(_on_audio_event)
	if _audio_round != null and _audio_round.visual_event.is_connected(_on_visual_event):
		_audio_round.visual_event.disconnect(_on_visual_event)
	_audio_round = round
	AudioManager.reset_round(round.audio_session, round.audio_event_id)
	_animation_last_id = 0
	_animation_queue.clear()
	_animation_busy = false
	_last_tile_input_ms = -1000
	if _animation_layer != null:
		_animation_layer.cancel()
	round.audio_event.connect(_on_audio_event)
	if not round.visual_event.is_connected(_on_visual_event):
		round.visual_event.connect(_on_visual_event)

func _on_audio_event(event: Dictionary) -> void:
	AudioManager.play_event(event)

func _on_visual_event(event: Dictionary) -> void:
	if _animation_layer == null:
		return
	var event_id := int(event.get("id", 0))
	if event_id <= _animation_last_id:
		return
	_animation_last_id = event_id
	if _skip_visual_once:
		_skip_visual_once = false
		return
	_animation_queue.append(event.duplicate(true))
	call_deferred("_pump_visual_animation")

func _pump_visual_animation() -> void:
	if _animation_busy or _animation_queue.is_empty() or _animation_layer == null:
		return
	var event: Dictionary = _animation_queue.pop_front()
	_animation_busy = true
	var type := str(event.get("type", ""))
	var target := Callable(self, "_on_visual_animation_finished")
	if type == "deal" or type == "draw":
		event["to"] = _animation_target_for_seat(int(event.get("seat", 0)))
		event["from"] = _table_center()
	if type == "deal_batch":
		var deals: Array = event.get("deals", [])
		if deals.is_empty():
			_on_visual_animation_finished()
			return
		var deal: Dictionary = deals[0]
		for index in range(1, deals.size()):
			var rest: Dictionary = deals[index].duplicate(true)
			_animation_queue.push_front({"id": event.get("id", 0), "type": "deal", "seat": rest.get("seat", 0), "cards": rest.get("cards", [])})
		event["type"] = "deal"
		event["seat"] = deal.get("seat", 0)
		event["cards"] = deal.get("cards", [])
		event["to"] = _animation_target_for_seat(int(event.seat))
		event["from"] = _table_center()
	_animation_layer.play(event, target)

func _on_visual_animation_finished() -> void:
	_animation_busy = false
	call_deferred("_pump_visual_animation")

func _animation_target_for_seat(seat: int) -> Vector2:
	var relative := _relative_seat(seat)
	return [Vector2(1140, 1010), Vector2(1640, 650), Vector2(1140, 430), Vector2(640, 650)][relative]

func _exit_tree() -> void:
	if _audio_round != null and _audio_round.audio_event.is_connected(_on_audio_event):
		_audio_round.audio_event.disconnect(_on_audio_event)
	_audio_round = null
	if _animation_layer != null:
		_animation_layer.cancel()
	AudioManager.end_table(self)

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
	var next_dealer := round.next_dealer_seat if round != null else 0
	if round != null:
		for player in round.players:
			scores.append(player.score)
	_clear_actions()
	_result_shown = false
	_declaring_ready = false
	_selected_tile = null
	if result_layer != null:
		result_layer.hide()
	if _result_restore != null and is_instance_valid(_result_restore):
		_result_restore.hide()
	_round_number += 1
	round = RoundState.new()
	round._recorder.auto_save = true
	_connect_audio_round()
	round.next_chicken_multiplier = chicken_multiplier
	round.next_dealer_seat = next_dealer
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
	# 先带入累计分数，再让新庄家开始行动（AI 庄家也可能马上结算）。
	if scores.size() == 4:
		round.build_players(human_seat)
		round.apply_scores(scores)
	round.start_round(human_seat)
	_refresh()

func _setup_host_view() -> void:
	var network = _net_node()
	human_seat = network.my_seat
	round = network.game
	_connect_audio_round()
	_round_number = network.round_number
	round.require_turn.connect(_on_require_turn)
	round.require_response.connect(_on_require_response)
	round.round_finished.connect(_on_round_finished)
	round.state_update.connect(_refresh)
	if round.phase != RoundState.Phase.IDLE:
		_on_net_prompt(human_seat)
		_refresh()
	network.connection_error.connect(_on_connection_error)
	network.lobby_updated.connect(_on_net_lobby_updated)

func _setup_client_view() -> void:
	var network = _net_node()
	round = network.game
	_connect_audio_round()
	_round_number = 1
	network.room_ready.connect(func(seat):
		human_seat = seat
		_refresh())
	network.state_updated.connect(_on_client_state_updated)
	network.prompted.connect(_on_net_prompt)
	network.connection_error.connect(_on_connection_error)
	network.reconnecting.connect(func(attempt, maximum):
		_skip_visual_once = true
		_animation_queue.clear()
		_animation_busy = false
		_animation_layer.cancel()
		_selecting = false
		_clear_actions()
		status_label.text = "连接中断，正在重连（%d/%d）…" % [attempt, maximum]
		status_label.show())
	network.lobby_updated.connect(_on_net_lobby_updated)
	enable_net(network.submit_client_turn, network.submit_client_response)
	if network.my_seat >= 0:
		human_seat = network.my_seat
	_refresh()
	_on_net_prompt(human_seat)

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
	_sound_settings = SoundSettings.new()
	_sound_settings.table_mode = true
	add_child(_sound_settings)
	_speed_buttons = _sound_settings.speed_buttons
	_sound_settings.ai_speed_selected.connect(_set_ai_speed)
	_update_speed_buttons()
	var sound_button := _button("设置", _sound_settings.open, DISCARD_BUTTON_SIZE, true)
	sound_button.name = "SoundButton"
	sound_button.add_theme_font_size_override("font_size", 32)
	sound_button.position = Vector2(1287, 20)
	surface.add_child(sound_button)
	_sound_button = sound_button
	# 返回、声音和 AI 速度统一收进大号设置面板，避免右上角小按钮难以点击。
	_sound_settings.exit_requested.connect(_confirm_quit)
	_sound_settings.exit_confirmed.connect(_on_quit)
	_sound_settings.replay_export_requested.connect(_export_current_replay)
	_settings_button = sound_button
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
		# Keep the larger river usable on touch screens without drawing a scrollbar
		# over the tiles.  The wheel/touch scrolling behavior remains available.
		river.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		wall_box[seat].hide()
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
		_status_labels[seat] = _label(surface, "", Vector2.ZERO, Vector2(300, 74), 17, GOLD)
		_status_labels[seat].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_status_labels[seat].mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_labels[seat].hide()
		var wind := _label(surface, WINDS[seat], Vector2.ZERO, Vector2(32, 32), 19, MUTED)
		wind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		wind_labels[seat] = wind
		wind.hide()
	_remaining_label = _label(surface, "余牌", Vector2(680, 705), Vector2(80, 24), 14, MUTED)
	_remaining_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	status_label.hide()
	result_layer = _box(surface)
	result_layer.size = DESIGN_SIZE
	result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	result_layer.hide()
	_animation_layer = TableAnimationLayer.new()
	_animation_layer.name = "AnimationLayer"
	_animation_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_animation_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_animation_layer)

func _layout() -> void:
	if surface == null:
		return
	var available := _usable_rect()
	# The product layout is always landscape, including square and portrait
	# windows used by editor previews.  The canvas simply letterboxes there.
	var changed := not _landscape
	_landscape = true
	var design := _design_size()
	var factor := minf(available.size.x / design.x, available.size.y / design.y)
	surface.size = design
	surface.scale = Vector2.ONE * factor
	surface.position = available.position + (available.size - design * factor) / 2.0
	_animation_layer.position = surface.position
	_animation_layer.size = design
	_animation_layer.scale = Vector2.ONE * factor
	result_layer.size = design
	for seat in 4:
		seat_roots[seat].position = _table_center()
		seat_roots[seat].show()
		var metrics := _seat_metrics(seat)
		# Release the previous content width before shrinking the scroll container.
		# Otherwise its minimum size keeps the wider landscape river in portrait.
		var content: Control = discard_scroll[seat].get_child(0)
		content.custom_minimum_size.x = metrics.river_size.x - 16
		discard_scroll[seat].position = metrics.river_position
		discard_scroll[seat].size = metrics.river_size
	var delta := _table_center() - TABLE_CENTER
	_remaining_label.position = Vector2(680, 705) + delta
	center_info.position = Vector2(664, 733) + delta
	round_label.position.x = (design.x - round_label.size.x) / 2.0
	_sound_button.position = Vector2(design.x - DISCARD_BUTTON_SIZE.x - 24, 12 if _landscape else 20)
	_sound_button.custom_minimum_size = DISCARD_BUTTON_SIZE
	_sound_button.size = _sound_button.custom_minimum_size
	# Actions sit immediately above the local player's draw slot.
	_layout_actions()
	status_label.position = Vector2(60, design.y - 54)
	if round != null and changed:
		# Rebuild after the resize notification, even if nobody is taking a turn.
		_refresh_layout_contents.call_deferred()
	queue_redraw()

func _refresh_layout_contents() -> void:
	var had_result := _result_panel != null and is_instance_valid(_result_panel) and _result_shown
	var showing_result := had_result and _result_panel.visible
	_refresh()
	if had_result and round.phase == RoundState.Phase.SETTLED:
		_show_result()
		_toggle_result_panel(showing_result)
	if _result_restore != null and is_instance_valid(_result_restore):
		_result_restore.position = panel_position_for_result_toggle()

func _usable_rect() -> Rect2:
	var bounds := Rect2(Vector2.ZERO, size)
	if OS.has_feature("android"):
		var safe := Rect2(DisplayServer.get_display_safe_area())
		if safe.has_area():
			var transform := get_viewport().get_screen_transform() * get_global_transform()
			bounds = bounds.intersection(transform.affine_inverse() * safe)
	if OS.has_feature("android") and bounds.has_area():
		bounds = bounds.grow(-SAFE_MARGIN)
	return bounds

func _design_size() -> Vector2:
	return LANDSCAPE_SIZE

func _table_center() -> Vector2:
	return LANDSCAPE_CENTER

func _table_bounds() -> Rect2:
	return Rect2(24, 80, 2232, 1120) if _landscape else Rect2(24, 72, 1392, 1376)

func _seat_metrics(seat: int) -> Dictionary:
	var side := _relative_seat(seat) % 2 == 1
	var exposed_y := 1010.0 if side else (430.0 if seat == human_seat else 458.0)
	# Keep the local hand's bottom edge; the larger faces grow upwards.
	var hand_y := exposed_y - TileView.BASE_H * (OWN_HAND_TILE_UNIT - OWN_PLAYER_TILE_UNIT) if seat == human_seat else exposed_y
	return {"hand_y": hand_y, "exposed_y": exposed_y,
		"left": -494.0 if side else -1000.0, "overflow_x": -544.0 if side else -1000.0,
		"overflow_right": 530.0 if side else 1000.0,
		# Side-player discard zones are wider in their local axis.  Tile units stay
		# at TILE_UNIT; only the available area grows.
		"river_position": Vector2(-300, 390) if side else Vector2(-350, 180),
		"river_size": Vector2(720, 170) if side else Vector2(700, 150), "river_columns": 12}

func _player_tile_unit(seat: int) -> float:
	return OWN_PLAYER_TILE_UNIT if seat == human_seat else PLAYER_TILE_UNIT

func _hand_tile_unit(seat: int) -> float:
	return OWN_HAND_TILE_UNIT if seat == human_seat else PLAYER_TILE_UNIT

## 手牌与独立摸牌位整体居中；预留摸牌位，摸打时整排不会来回跳动。
func _hand_layout(seat: int) -> Dictionary:
	var player: PlayerState = round.players[seat]
	var width := TileView.BASE_W * _hand_tile_unit(seat)
	var count := player.concealed.size() - (1 if player.just_drew != "" and player.concealed.has(player.just_drew) else 0)
	var span := maxf(0.0, count * (width + TILE_GAP) - TILE_GAP)
	var right := (span + DRAW_GAP + width) / 2.0
	return {"draw_x": right - width, "hand_x": right - width - DRAW_GAP - span, "count": count}

func _layout_actions() -> void:
	if action_bar == null:
		return
	var right := _table_center().x + 574.0
	var top := _table_center().y + float(_seat_metrics(human_seat).hand_y)
	if round != null and round.players.size() == 4:
		right = _table_center().x + float(_hand_layout(human_seat).draw_x) + TileView.BASE_W * OWN_HAND_TILE_UNIT
	# The rightmost action aligns with the right edge of the drawn tile.  The row
	# grows leftwards as optional actions appear, keeping all actions above it.
	var count := action_bar.get_child_count()
	action_bar.visible = count > 0
	var row_size := Vector2(0, ACTION_BUTTON_SIZE.y)
	for button in action_bar.get_children():
		row_size.x += button.custom_minimum_size.x
		row_size.y = maxf(row_size.y, button.custom_minimum_size.y)
	row_size.x += maxi(0, count - 1) * action_bar.get_theme_constant("separation")
	action_bar.size = row_size
	# With a short hand, keep the buttons to the right of our river. The
	# next player's river may sit underneath, as requested, but our tiles stay clear.
	var metrics := _seat_metrics(human_seat)
	var river := Rect2(_table_center() + Vector2(metrics.river_position), Vector2(metrics.river_size))
	var next_hand_left: float = _table_center().x + _seat_metrics(posmod(human_seat + 1, 4)).hand_y
	var right_limit := minf(_table_bounds().end.x - 16.0, next_hand_left - 16.0)
	var left := minf(maxf(right - row_size.x, river.end.x + 16.0), right_limit - row_size.x)
	var row_top := top - row_size.y - ACTION_HAND_GAP
	if Rect2(Vector2(left, row_top), row_size).intersects(river):
		row_top = minf(row_top, river.position.y - row_size.y - 16.0)
	action_bar.position = Vector2(left, row_top)

func _result_card_size() -> Vector2:
	return LANDSCAPE_RESULT_SIZE if _landscape else RESULT_CARD_SIZE

func _result_toggle_position() -> Vector2:
	return Vector2(LANDSCAPE_RESULT_SIZE.x - 154, 22) if _landscape else RESULT_TOGGLE_LOCAL_POSITION

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#141d1b"))
	if surface == null:
		return
	draw_set_transform(surface.position, 0.0, surface.scale)
	var bounds := _table_bounds()
	var delta := _table_center() - TABLE_CENTER
	draw_style_box(_style(Color("#293430"), Color("#42524b"), 8, 2), bounds)
	draw_style_box(_style(Color("#174f3c"), Color("#688275"), 8, 1), bounds.grow(-12))
	if _felt != null:
		draw_texture_rect(_felt, bounds.grow(-38), false, Color(0.58, 0.8, 0.66, 0.07))
	draw_style_box(_style(Color(0, 0, 0, 0), Color("#39725a"), 8, 1), bounds.grow(-40))
	draw_line(Vector2(30, 68), Vector2(_design_size().x - 30, 68), Color("#38453f"), 1)
	draw_style_box(_style(Color("#15382e"), Color("#618373"), 8, 2), Rect2(Vector2(636, 676) + delta, Vector2(168, 168)))
	if round == null:
		return
	for seat in 4:
		var avatar: Label = avatars[seat]
		var active := round.phase == RoundState.Phase.PLAYING and round.current_turn == seat
		draw_style_box(_style(Color("#263f35"), GOLD if active else Color("#61786b"), 8, 2), Rect2(avatar.position, avatar.size))
		var wind: Label = wind_labels[seat]
		if active and wind.visible:
			draw_style_box(_style(Color("#3b6150"), GOLD, 4, 1), Rect2(wind.position, wind.size))
		if seat < round.players.size() and round.players[seat].is_dealer:
			var badge := Rect2(avatar.position + Vector2(39, -8), Vector2(24, 24))
			draw_style_box(_style(Color("#b84b43"), Color("#edb29a"), 4, 1), badge)
			draw_string(TileView._font(), badge.position + Vector2(4, 18), "庄", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	_draw_die(int(round.round_meta.get("die", 1)), Vector2(702, 798) + delta)

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
	if not _landscape:
		_layout()
	if round.phase != RoundState.Phase.SETTLED:
		_result_shown = false
		result_layer.hide()
		if _result_restore != null and is_instance_valid(_result_restore):
			_result_restore.hide()
		# 新一局开始前把结算层的状态复位，避免遮罩残留挡住牌桌。
		result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_actions()
	_prepare_exposed_layouts()
	for seat in 4:
		_refresh_seat(seat)
	_refresh_walls()
	_refresh_center()
	_refresh_status()
	_update_interactivity()
	queue_redraw()
	if round.phase == RoundState.Phase.SETTLED and not _result_shown:
		_result_shown = true
		_show_result.call_deferred()

func _refresh_seat(seat: int) -> void:
	var relative := _relative_seat(seat)
	seat_roots[seat].rotation = ROTATIONS[relative]
	var avatar_positions := [Vector2(622, 854), Vector2(814, 682), Vector2(770, 606), Vector2(578, 794)]
	var label_positions := [Vector2(682, 854), Vector2(810, 742), Vector2(602, 606), Vector2(566, 678)]
	# Reserved positions for the hidden per-seat status labels. Settlement details
	# are shown only in the result card so the active table stays uncluttered.
	var status_positions := [
		Vector2(500, 1312), Vector2(1140, 1072), Vector2(500, 1152), Vector2(20, 1072),
	]
	avatars[seat].position = avatar_positions[relative] + _table_center() - TABLE_CENTER
	center_labels[seat].position = label_positions[relative] + _table_center() - TABLE_CENTER
	_status_labels[seat].position = status_positions[relative]
	_status_labels[seat].size = Vector2(320, 84)
	center_labels[seat].size = Vector2(70, 110) if relative == 1 or relative == 3 else Vector2(164, 64)
	center_labels[seat].autowrap_mode = TextServer.AUTOWRAP_OFF
	center_labels[seat].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if seat >= round.players.size():
		center_labels[seat].text = "等待入座"
		_status_labels[seat].hide()
		return
	var player: PlayerState = round.players[seat]
	var title: String = ["你", "下家", "对家", "上家"][relative]
	center_labels[seat].text = "%s\n%.0f分" % [title, player.score]
	var label_font_size := 15 if relative == 1 or relative == 3 else 17
	for line in center_labels[seat].text.split("\n"):
		while label_font_size > 10 and TileView._font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label_font_size).x > center_labels[seat].size.x:
			label_font_size -= 1
	center_labels[seat].add_theme_font_size_override("font_size", label_font_size)
	center_labels[seat].add_theme_color_override("font_color", GOLD if player.ready else INK)
	center_labels[seat].size = Vector2(70, 110) if relative == 1 or relative == 3 else Vector2(164, 64)
	var plans: Array = _exposed_layouts.get(seat, [])
	var key := var_to_bytes([human_seat, _design_size(), round.audio_session, player.concealed, player.just_drew, player.melds,
		player.discards, player.discard_ids, player.discard_count, round.phase == RoundState.Phase.SETTLED, round.last_discard, plans,
		round.round_meta.get("charge_chickens", {}), _hand_layout(seat)])
	if _seat_visual_keys.get(seat) == key: return
	_seat_visual_keys[seat] = key
	if seat == human_seat: _selected_tile = null
	_clear_box(meld_box[seat])
	_clear_box(chicken_box[seat])
	var cards := Tiles.sort_hand(player.concealed)
	var has_draw := player.just_drew != "" and cards.has(player.just_drew)
	if has_draw:
		cards.erase(player.just_drew)
	var player_unit := _player_tile_unit(seat)
	var width := TileView.BASE_W * player_unit
	var height := TileView.BASE_H * player_unit
	# Exposed tiles grow from the left table edge.  The horizontal players' hand
	# and reserved draw slot are centered together without changing tile sizes.
	var metrics := _seat_metrics(seat)
	var row := _hand_layout(seat)
	var draw_x: float = row.draw_x
	var hand_x: float = row.hand_x
	for group in _exposed_layouts.get(seat, []):
		var group_origin: Vector2 = group.origin
		if group.has("chicken"):
			var chicken: Dictionary = group.chicken
			var tile := _make_tile(chicken.tile, true, player_unit)
			tile.set_meta("charge_chicken", chicken.charge)
			tile.set_highlight(chicken.latest)
			if chicken.charge:
				tile.rotation = -PI / 2.0
				_put_tile(chicken_box[seat], tile, group_origin + Vector2(0, height))
				tile.tooltip_text = "冲锋鸡 · " + _cn(chicken.tile)
			else:
				_put_tile(chicken_box[seat], tile, group_origin)
			continue
		var meld: Dictionary = group.meld
		var count := 3 if meld.kind == "pung" else 4
		var layout: Dictionary = group.layout
		var charge_index := -1
		if round.is_charge_meld(seat, group.meld_index) and meld.kind != "pung":
			charge_index = int(layout.sideways) if int(layout.sideways) >= 0 else 0
		var up: bool = round.is_meld_revealed(seat, group.meld_index)
		for index in count:
			var tile := _make_tile(meld.tile if up else "", up, player_unit)
			tile.set_meta("charge_chicken", index == charge_index)
			if index == charge_index:
				tile.tooltip_text = "冲锋鸡 · " + _cn(meld.tile)
				tile.set_highlight(true)
			if index == int(layout.sideways):
				tile.rotation = -PI / 2.0
			_put_tile(meld_box[seat], tile, group_origin + Vector2(layout.positions[index]))
	_clear_box(hand_box[seat])
	_clear_box(draw_box[seat])
	var own := seat == human_seat
	var hand_unit := _hand_tile_unit(seat)
	width = TileView.BASE_W * hand_unit
	var x := hand_x
	var y: float = metrics.hand_y
	var reveal := own or round.phase == RoundState.Phase.SETTLED
	for card in cards:
		var tile := _make_tile(card if reveal else "", reveal, hand_unit)
		_put_tile(hand_box[seat], tile, Vector2(x, y))
		if own:
			tile.gui_input.connect(_on_human_tile_gui.bind(tile))
			tile.set_meta("drawn", false)
		x += width + TILE_GAP
	if has_draw:
		var drawn := _make_tile(player.just_drew if reveal else "", reveal, hand_unit)
		_put_tile(draw_box[seat], drawn, Vector2(draw_x, y))
		drawn.set_meta("drawn", true)
		if own:
			drawn.gui_input.connect(_on_human_tile_gui.bind(drawn))
	_refresh_discards(seat)

## 牌桌和结算共用的碰杠布局。暗杠/加杠四竖；明杠下家右横、上家左横、对家上横。
func _meld_tile_layout(meld: Dictionary, seat: int, unit: float, gap: float) -> Dictionary:
	var width := TileView.BASE_W * unit
	var height := TileView.BASE_H * unit
	var kind := str(meld.get("kind", ""))
	var count := 3 if kind == "pung" else 4
	var source := posmod(int(meld.get("from_seat", -1)) - seat, 4)
	var exposed: bool = kind == "kong" and not meld.get("concealed", false) and int(meld.get("from_seat", -1)) in range(4)
	var sideways := int({1: 3, 2: 3, 3: 0}.get(source, -1)) if exposed else -1
	# 碰牌没有来源标记：即使碰到幺鸡，三张牌也全部竖放。
	var positions: Array = []
	if exposed and source == 2:
		var span := 3 * width + 2 * gap
		for index in 3:
			positions.append(Vector2(index * (width + gap), width + gap))
		positions.append(Vector2((span - height) / 2.0, width))
		return {"positions": positions, "size": Vector2(span, width + gap + height), "sideways": sideways}
	var x := 0.0
	for index in count:
		positions.append(Vector2(x, height if index == sideways else 0.0))
		x += (height if index == sideways else width) + gap
	return {"positions": positions, "size": Vector2(x - gap, height), "sideways": sideways}

## 先安排四家所有牌组，避开手牌、弃牌区和按钮，给叠放明杠留足高度。
func _prepare_exposed_layouts() -> void:
	_exposed_layouts.clear()
	# 联机客户端可能尚未收到四家数据，等待期间不规划牌组。
	if round.players.size() != 4:
		return
	var occupied: Array[Rect2] = []
	if action_bar.visible:
		occupied.append(Rect2(action_bar.position, action_bar.size))
	# The score avatars remain in the center after the wall is hidden; exposed
	# groups may now use that free space but must never cover the center panel.
	for control in avatars.values() + center_labels.values() + [center_info, _remaining_label]:
		occupied.append(Rect2(control.position, control.size).grow(6.0))
	occupied.append(Rect2(Vector2(1056, 566), Vector2(168, 168)).grow(6.0))
	for seat in 4:
		var hand_unit := _hand_tile_unit(seat)
		var width := TileView.BASE_W * hand_unit
		var height := TileView.BASE_H * hand_unit
		var transform := Transform2D(ROTATIONS[_relative_seat(seat)], _table_center())
		var metrics := _seat_metrics(seat)
		var player: PlayerState = round.players[seat]
		var hand_count := player.concealed.size() - (1 if player.just_drew != "" and player.concealed.has(player.just_drew) else 0)
		var row := _hand_layout(seat)
		var draw_x: float = row.draw_x
		var hand_x: float = row.hand_x
		for index in hand_count:
			occupied.append(transform * Rect2(Vector2(hand_x + index * (width + TILE_GAP), metrics.hand_y), Vector2(width, height)))
		occupied.append(transform * Rect2(Vector2(draw_x, metrics.hand_y), Vector2(width, height)))
		occupied.append(transform * Rect2(metrics.river_position, metrics.river_size))
	for seat in 4:
		var player_unit := _player_tile_unit(seat)
		var width := TileView.BASE_W * player_unit
		var height := TileView.BASE_H * player_unit
		var transform := Transform2D(ROTATIONS[_relative_seat(seat)], _table_center())
		var metrics := _seat_metrics(seat)
		var player: PlayerState = round.players[seat]
		var hand_left: float = _hand_layout(seat).hand_x
		var next_x: float = metrics.left
		var plans: Array = []
		for group in _exposed_groups(seat):
			var layout: Dictionary
			if group.has("chicken"):
				var charge: bool = group.chicken.charge
				layout = {"positions": [Vector2(0, height if charge else 0)], "size": Vector2(height if charge else width, height), "sideways": 0 if charge else -1}
			else:
				var meld: Dictionary = group.meld.duplicate()
				meld["charge_marker"] = round.is_charge_meld(seat, group.meld_index)
				layout = _meld_tile_layout(meld, seat, player_unit, TILE_GAP)
			var origin := Vector2.ZERO
			var rects: Array[Rect2] = []
			var placed := false
			var row_index := 0
			while row_index < 20 and not placed:
				# Scan inward for free space, checking every tile's actual bounds;
				# opposite-player kongs include their upper sideways tile.
				var bottom: float = metrics.exposed_y + height if row_index == 0 else metrics.exposed_y - 16.0 - (row_index - 1) * 24.0
				var right: float = hand_left - EXPOSED_HAND_GAP if row_index == 0 else metrics.overflow_right
				var x: float = next_x if row_index == 0 else metrics.overflow_x
				while x + float(layout.size.x) <= right:
					origin = Vector2(x, bottom - float(layout.size.y))
					rects = _exposed_rects(layout, origin, transform, width, height)
					if _exposed_space_clear(rects, occupied):
						placed = true
						break
					x += TILE_GAP
				if not placed:
					row_index += 1
			if not placed:
				push_error("碰杠/鸡牌区域无法容纳当前牌组")
			group["origin"] = origin
			group["layout"] = layout
			plans.append(group)
			occupied.append_array(rects)
			next_x = origin.x + float(layout.size.x) + TILE_GAP + (10.0 if group.has("meld") else 0.0)
		_exposed_layouts[seat] = plans

func _exposed_rects(layout: Dictionary, origin: Vector2, transform: Transform2D, width: float, height: float) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for index in layout.positions.size():
		var pos := origin + Vector2(layout.positions[index])
		var rect := Rect2(pos, Vector2(width, height))
		if index == int(layout.sideways):
			# -90° 绕左上角旋转后，纵向占位是原牌宽，不能减去原牌高。
			rect = Rect2(pos - Vector2(0, width), Vector2(height, width))
		rects.append(transform * rect)
	return rects

func _exposed_space_clear(rects: Array[Rect2], occupied: Array[Rect2]) -> bool:
	var bounds := _table_bounds()
	for rect in rects:
		if not bounds.encloses(rect):
			return false
		for other in occupied:
			if rect.grow(2.0).intersects(other.grow(-0.5)):
				return false
	return true

## 结算时每家面前两行：第一行叫牌/未叫牌与胡牌方式，第二行得分点。
func _refresh_status_text(seat: int) -> void:
	var label: Label = _status_labels[seat]
	label.text = ""
	label.hide()

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
	var metrics := _seat_metrics(seat)
	var columns: int = metrics.river_columns
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
		var row_index := regular_index / columns
		_put_tile(discard_box[seat][row_index], tile, Vector2(4 + (regular_index % columns) * (width + TILE_GAP), 4 + row_index * (height + TILE_GAP)))
		regular_index += 1
	var river: ScrollContainer = discard_scroll[seat]
	var content: Control = river.get_child(0)
	content.custom_minimum_size = Vector2(metrics.river_size.x - 16, maxf(metrics.river_size.y, ceili(regular_index / float(columns)) * (height + TILE_GAP) + 8))
	river.position = metrics.river_position
	river.size = metrics.river_size
	var river_key := ",".join(player.discards)
	if river.get_meta("cards", "") != river_key:
		river.set_meta("cards", river_key)
		_scroll_to_latest.call_deferred(river)

func _scroll_to_latest(river: ScrollContainer) -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_inside_tree() and is_instance_valid(river):
		river.scroll_vertical = int(river.get_v_scroll_bar().max_value)

func _wall_stacks(seat: int) -> Array:
	if round.wall != null:
		return round.wall.wall_stack_counts(seat)
	if round.wall_stacks.has(seat):
		return round.wall_stacks[seat]
	var fallback: Array = []
	var remaining := _wall_remain(seat)
	for index in (14 if posmod(seat - round.dealer_seat, 2) == 0 else 13):
		fallback.append(clampi(remaining - index * 2, 0, 2))
	return fallback

func _refresh_walls() -> void:
	for seat in 4:
		_clear_box(wall_box[seat])
		wall_box[seat].hide()

func _refresh_center() -> void:
	center_info.text = str(_sum_wall()) if not round.players.is_empty() else "--"
	var number: int = _round_number if _net_mode() == "" else _net_node().round_number
	round_label.text = "第 %02d 局    ·    %s" % [maxi(1, number), "单机对局" if _net_mode() == "" else "联机对局"]
	for seat in 4:
		wind_labels[seat].add_theme_color_override("font_color", GOLD if round.current_turn == seat and round.phase == RoundState.Phase.PLAYING else MUTED)
	_update_speed_buttons()

func _set_ai_speed(speed_key: String) -> void:
	if _net_mode() == "":
		GameConfig.set_ai_speed(speed_key)
		if round != null: round.ai_delay_seconds = GameConfig.ai_delay_seconds()
	elif _net_node().is_room_owner():
		GameConfig.set_ai_speed(speed_key)
		_net_node().set_ai_speed(speed_key)
	_update_speed_buttons()

func _update_speed_buttons() -> void:
	var selected: String = GameConfig.ai_speed if _net_mode() == "" else str(_net_node().lobby.get("ai_speed", "fast"))
	for speed_key in _speed_buttons:
		var button: Button = _speed_buttons[speed_key]
		button.modulate = Color("#f4df9f") if speed_key == selected else Color.WHITE
		button.disabled = _net_mode() != "" and not _net_node().is_room_owner()
		button.tooltip_text = "联机房间人机速度由房主设置" if button.disabled else ""

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
	if _net_mode() != "" and round != null and seat < round.players.size():
		var player_name := str(round.players[seat].name_label).strip_edges()
		if player_name != "": return player_name
	return ["你", "下家", "对家", "上家"][_relative_seat(seat)]

func _refresh_status() -> void:
	status_label.text = ""
	status_label.hide()

func _on_human_tile_gui(event: InputEvent, tile: TileView) -> void:
	if not _selecting or not tile.interactive:
		return
	var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var keyboard: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_SPACE]
	if not clicked and not keyboard:
		return
	if clicked:
		var now := Time.get_ticks_msec()
		if now - _last_tile_input_ms < 100:
			return
		_last_tile_input_ms = now
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
	var options := round.legal_turn_options(player.seat)
	if options.self_win:
		_add_action("自摸", func(): _commit_turn({"self_win": true}), true)
	_add_kong_choices("暗杠", "kong_declares", Tiles.sort_hand(options.kong_declares))
	_add_kong_choices("加杠", "add_kong", options.add_kong)
	_ready_discards = options.ready_discards.duplicate()
	if not _ready_discards.is_empty():
		_add_action("报听", _toggle_ready)
	var discard := _add_action("出牌", _discard_selected, true)
	discard.set_meta("discard", true)
	discard.disabled = not is_instance_valid(_selected_tile)

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
	var legal_discards: Array = round.legal_turn_options(human_seat).discards if _selecting else []
	for box in [hand_box[human_seat], draw_box[human_seat]]:
		for tile in box.get_children():
			var enabled: bool = _selecting and legal_discards.has(tile.tile) and (not player.ready or tile.get_meta("drawn", false))
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
	if not round._valid_turn(human_seat, decision): return
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

func _commit_response(action: String) -> void:
	var tile := _response_disc
	_response_disc = ""
	_clear_actions()
	_emit_response(tile, {"action": action})

func _on_client_state_updated() -> void:
	# 快照更新是联机的最终事实；重连后跳过尚未完成的视觉过渡。
	if _net_mode() == "client" and _animation_layer != null and _animation_busy:
		_animation_queue.clear()
		_animation_busy = false
		_animation_layer.cancel()
	_selecting = false
	_response_disc = ""
	_clear_actions()
	if round.phase == RoundState.Phase.SETTLED:
		_add_action("结算", _show_result)
	_refresh()

func _on_net_lobby_updated() -> void:
	_update_speed_buttons()
	_refresh_next_round_controls()

func _on_net_prompt(seat: int) -> void:
	if seat != human_seat or seat >= round.players.size():
		return
	var response: Dictionary = round._awaiting_response
	if not response.is_empty():
		if int(response.get("seat", -1)) == human_seat:
			var tile: String = response.tile
			var options := round.legal_response_options(seat, int(response.get("disc_seat", -1)), tile, int(response.get("stage", RoundState.ResponseStage.NONE)))
			_on_require_response(seat, response.disc_seat, tile, options)
	elif round.current_turn == human_seat and round.phase == RoundState.Phase.PLAYING:
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
	shade.color = Color(0.02, 0.06, 0.04, 0.72)
	shade.size = _design_size()
	result_layer.add_child(shade)
	_result_shade = shade
	var panel := Panel.new()
	panel.name = "SettlementCard"
	panel.position = (_design_size() - _result_card_size()) / 2.0
	panel.size = _result_card_size()
	panel.add_theme_stylebox_override("panel", _style(Color("#22392f"), Color("#739383"), 10, 1))
	result_layer.add_child(panel)
	_result_panel = panel
	var winner := int(round.round_meta.get("winner", -1))
	var flip: String = round.round_meta.get("flip_tile", "")
	if flip != "":
		_label(panel, "翻鸡牌", Vector2(480, 24), Vector2(180, 72), 42)
		var flip_tile := _make_tile(flip, true, RESULT_TILE_UNIT)
		flip_tile.name = "FlippedChickenTile"
		_put_tile(panel, flip_tile, Vector2(682, 12))
	elif winner < 0:
		_label(panel, _draw_result_title(), Vector2(42, 16), Vector2(740, 52), 34, GOLD)
		var notice := "本局不计分 · 下局鸡分 ×%d" % round.next_chicken_multiplier if round.round_meta.get("all_called_draw", false) else "未叫牌者补出牌鸡与杠分 · 叫牌者不补差"
		_label(panel, notice, Vector2(42, 74), Vector2(950, 32), 22, MUTED)
	else:
		_label(panel, "牌墙已空 · 无翻鸡", Vector2(42, 28), Vector2(800, 64), 34, MUTED)
	var round_points: Array = round.last_result.get("round_points", round._last_round_points)
	var pairs: Array = round.last_result.get("pairwise", ScoringEngine.pairwise_payments(round.last_result.get("transfers", round._last_transfers)))
	var status: Array = round.last_result.get("status", [])
	var items: Array = round.last_result.get("items", [])
	for row_index in 4:
		var relative: int = [0, 3, 2, 1][row_index]
		var seat := posmod(human_seat + relative, 4)
		var player: PlayerState = round.players[seat]
		var own_points := float(round_points[seat]) if round_points.size() == 4 else 0.0
		var row := Control.new()
		row.name = "ResultSeat%d" % seat
		row.position = Vector2(32 + (row_index % 2) * 1080, 112 + (row_index / 2) * 474) if _landscape else Vector2(42, 108 + row_index * 306)
		row.size = Vector2(1056, 464) if _landscape else Vector2(1236, 298)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		_label(row, _seat_name(seat), Vector2(0, 12), Vector2(110, 60) if _landscape else Vector2(164, 60), 34 if _landscape else 42).name = "SeatName"
		_label(row, "%.0f分" % player.score, Vector2(118 if _landscape else 206, 12), Vector2(164 if _landscape else 250, 60), 32 if _landscape else 40).name = "TotalScore"
		var own_label := _label(row, "本局%.0f分" % own_points, Vector2(300 if _landscape else 472, 12), Vector2(260 if _landscape else 290, 60), 32 if _landscape else 40)
		own_label.name = "RoundPoints"
		own_label.tooltip_text = "本人的得分点合计；明杠基础4分只向放杠者收，单独列在杠牌组内"
		var payments := ScoringEngine.relative_payments(pairs, seat)
		for index in 3:
			var x := (588.0 if _landscape else 786.0) + index * 150.0
			var direction: String = ["上家", "对家", "下家"][index]
			var amount := float(payments[index])
			var direction_label := _label(row, direction, Vector2(x, 0), Vector2(140, 26), 18, MUTED)
			direction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var change := _label(row, "%+.0f" % amount if not is_zero_approx(amount) else "0", Vector2(x, 24), Vector2(140, 52), 40)
			change.name = "Payment%d" % index
			change.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			change.tooltip_text = "该玩家自己的%s：%s%.0f分" % [direction, "收取" if amount >= 0 else "付出", absf(amount)]
		var first: String = str(status[seat]) if status.size() == 4 else ""
		var list: Array = items[seat] if items.size() == 4 else []
		_draw_result_details(row, seat, first, list, winner)
	var eye := _button("看牌桌", func(): _toggle_result_panel(false), RESULT_TOGGLE_SIZE)
	eye.tooltip_text = "隐藏结算卡片，查看牌桌上的牌"
	eye.position = _result_toggle_position()
	panel.add_child(eye)
	var next := _button("下一局" if _net_mode() == "" else "准备下一局", _next_round, NEXT_ROUND_BUTTON_SIZE, true)
	next.name = "NextRoundButton"
	next.add_theme_font_size_override("font_size", 38)
	next.position = Vector2((_result_card_size().x - NEXT_ROUND_BUTTON_SIZE.x) / 2.0, _result_card_size().y - NEXT_ROUND_BUTTON_SIZE.y - 24)
	panel.add_child(next)
	_next_round_button = next
	if _net_mode() != "":
		var side_width := next.position.x - 64.0
		_next_round_status = _label(panel, "", Vector2(32, next.position.y + 12), Vector2(side_width, 100), 26, MUTED)
		_next_round_status.name = "NextRoundReadiness"
		_next_round_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_next_round_hint = _label(panel, "", Vector2(next.position.x + NEXT_ROUND_BUTTON_SIZE.x + 32, next.position.y + 12), Vector2(side_width, 100), 26, GOLD)
		_next_round_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_refresh_next_round_controls()
	_ensure_restore_button()
	_toggle_result_panel(true)
	result_layer.show()

## 各家明细独立滚动，极端多鸡/多杠也不会覆盖其他玩家或下一局按钮。
func _draw_result_details(row: Control, seat: int, status: String, list: Array, winner: int) -> void:
	var background := Panel.new()
	background.name = "Details"
	background.position = Vector2(0, 76)
	background.size = Vector2(row.size.x, row.size.y - 76)
	background.add_theme_stylebox_override("panel", _style(Color("#1b3027"), Color.TRANSPARENT, 6))
	row.add_child(background)
	var state := _label(background, status if status != "" else "未叫牌", Vector2(12, 12) if _landscape else Vector2(22, 65), Vector2(132, background.size.y - 24) if _landscape else Vector2(162, 112), 24, GOLD if seat == winner else INK)
	state.name = "CallStatus"
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var scroll := ScrollContainer.new()
	scroll.name = "ScoreGroups"
	scroll.position = Vector2(152, 8) if _landscape else Vector2(194, 8)
	scroll.size = Vector2(886 if _landscape else 1024, background.size.y - 16)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	background.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.name = "Groups"
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 20)
	flow.add_theme_constant_override("v_separation", 14)
	scroll.add_child(flow)
	# 胡牌奖在前，鸡牌按类型/单张分值归组，所有杠集中放在最后。
	for category in ["text", "chicken", "kong"]:
		for item in list:
			var kind := str(item.get("kind", ""))
			var item_category := "kong" if kind == "kong" else ("chicken" if kind in ["chicken", "charge", "flip"] else "text")
			if item_category == category:
				_draw_result_group(flow, item, seat, 862.0 if _landscape else 1000.0)

func _result_sideways_index(item: Dictionary, seat: int) -> int:
	if item.get("kind", "") == "charge":
		return 0
	if item.get("kind", "") != "kong":
		return -1
	if item.get("kong_kind", RoundState.KongKind.NONE) == RoundState.KongKind.EXPOSED:
		return int({1: 3, 2: 3, 3: 0}.get(posmod(int(item.get("from_seat", -1)) - seat, 4), -1))
	return -1

func _result_group_note(item: Dictionary, seat: int) -> String:
	if item.get("kind", "") != "kong":
		return str(item.get("note", ""))
	var text := ""
	if item.get("kong_kind", RoundState.KongKind.NONE) == RoundState.KongKind.EXPOSED:
		var direction: String = ["本人", "下家", "对家", "上家"][posmod(int(item.get("from_seat", -1)) - seat, 4)]
		text = "只收%s杠分%.0f" % [direction, float(item.get("base_amount", 0.0))]
	else:
		text = "未叫牌者各付杠分4" if item.get("draw", false) else "每家杠分4"
	if float(item.get("chicken_amount", 0.0)) > 0:
		text += (" · 未叫牌者鸡分%.0f" if item.get("draw", false) else " · 每家鸡分%.0f") % float(item.chicken_amount)
	if float(item.get("flip_amount", 0.0)) > 0:
		text += " · 翻鸡%.0f" % float(item.flip_amount)
	return text

func _draw_result_group(flow: HFlowContainer, item: Dictionary, seat: int, max_width: float) -> void:
	var tiles: Array = item.get("tiles", []).duplicate()
	if tiles.is_empty() and str(item.get("tile", "")) != "":
		tiles.append(str(item.tile))
	var tile_width := TileView.BASE_W * RESULT_TILE_UNIT
	var tile_height := TileView.BASE_H * RESULT_TILE_UNIT
	var sideways := _result_sideways_index(item, seat)
	var positions: Array = []
	var rotations: Array = []
	var x := 0.0
	var y := 28.0
	var widest := 0.0
	var content_height := tile_height
	if item.get("kind", "") == "kong":
		var meld := {"kind": "add_kong" if item.get("kong_kind", RoundState.KongKind.NONE) == RoundState.KongKind.ADD_KONG else "kong",
			"concealed": item.get("kong_kind", RoundState.KongKind.NONE) == RoundState.KongKind.CONCEALED, "from_seat": item.get("from_seat", -1)}
		var layout := _meld_tile_layout(meld, seat, RESULT_TILE_UNIT, 8.0)
		for index in tiles.size():
			positions.append(Vector2(layout.positions[index]) + Vector2(0, y))
			rotations.append(index == int(layout.sideways))
		x = float(layout.size.x) + 8.0
		widest = x
		content_height = float(layout.size.y)
	else:
		for index in tiles.size():
			var rotated: bool = index == sideways or item.get("kind", "") == "charge"
			var width := tile_height if rotated else tile_width
			if x + width + 76.0 > max_width:
				x = 0.0
				y += tile_height + 8.0
			positions.append(Vector2(x, y + tile_height if rotated else y))
			rotations.append(rotated)
			x += width + 8.0
			widest = maxf(widest, x)
	var is_kong: bool = item.get("kind", "") == "kong"
	var dimensions := Vector2(maxf(152.0, widest + 66.0), y + content_height + (8.0 if is_kong else 28.0))
	if tiles.is_empty():
		dimensions = Vector2(152, 158)
	var group := Control.new()
	group.name = "ScoreGroup"
	group.custom_minimum_size = dimensions
	group.set_meta("score_item", item.duplicate(true))
	group.mouse_filter = Control.MOUSE_FILTER_PASS
	group.tooltip_text = _result_group_note(item, seat)
	flow.add_child(group)
	var heading := str(item.get("label", ""))
	if is_kong:
		if item.get("kong_kind", RoundState.KongKind.NONE) == RoundState.KongKind.EXPOSED:
			var direction: String = ["本人", "下家", "对家", "上家"][posmod(int(item.get("from_seat", -1)) - seat, 4)]
			heading += " · %s杠分%.0f" % [direction, float(item.get("base_amount", 0.0))]
		else:
			heading += " · 杠分%.0f" % float(item.get("base_amount", 0.0))
		if float(item.get("chicken_amount", 0.0)) > 0:
			heading += " · 鸡分%.0f" % float(item.chicken_amount)
	var heading_label := _label(group, heading, Vector2.ZERO, Vector2(dimensions.x, 26), 18, MUTED)
	heading_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for index in tiles.size():
		var tile := _make_tile(str(tiles[index]), true, RESULT_TILE_UNIT)
		var position: Vector2 = positions[index]
		if bool(rotations[index]):
			tile.rotation = -PI / 2.0
		_put_tile(group, tile, position)
	var amount := float(item.get("amount", 0.0))
	var score_pos := Vector2(x, y + content_height / 2.0 - 24.0) if not tiles.is_empty() else Vector2(0, 62)
	var amount_label := _label(group, "%+.0f" % amount, score_pos, Vector2(66 if not tiles.is_empty() else 152, 48), 32)
	amount_label.name = "GroupAmount"
	if not is_kong:
		var note := _label(group, _result_group_note(item, seat), Vector2(0, dimensions.y - 24), Vector2(dimensions.x, 24), 16, MUTED)
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _ensure_restore_button() -> void:
	# _clear_box 会把旧按钮排队释放，所以失效的引用必须重建，否则收不起卡片后就唤不回来。
	if _result_restore != null and is_instance_valid(_result_restore):
		_result_restore.position = panel_position_for_result_toggle()
		return
	_result_restore = _button("查看结算", func(): _toggle_result_panel(true), RESULT_TOGGLE_SIZE, true)
	_result_restore.position = panel_position_for_result_toggle()
	_result_restore.tooltip_text = "重新显示结算卡片"
	# Keep the restore button outside the result overlay so it remains clickable
	# while the card and its input layer are hidden.
	surface.add_child(_result_restore)

func panel_position_for_result_toggle() -> Vector2:
	return (_design_size() - _result_card_size()) / 2.0 + _result_toggle_position()

## 眼睛开关：隐藏卡片露出牌桌，再点一次回来。
func _toggle_result_panel(show_card: bool) -> void:
	if _result_shade != null and is_instance_valid(_result_shade):
		_result_shade.visible = show_card
	if _result_panel != null and is_instance_valid(_result_panel):
		_result_panel.visible = show_card
	# 隐藏卡片后把遮罩也放掉，否则牌桌仍然点不动。
	result_layer.mouse_filter = Control.MOUSE_FILTER_STOP if show_card else Control.MOUSE_FILTER_IGNORE
	if _result_restore != null and is_instance_valid(_result_restore):
		_result_restore.visible = not show_card

func _next_round() -> void:
	if _net_mode() != "":
		var network = _net_node()
		if network.lobby.get("ready_round", -1) != network.round_number: return
		var me: Dictionary = network.lobby.seats[human_seat]
		network.set_ready(not bool(me.ready))
	else:
		new_game()

func _refresh_next_round_controls() -> void:
	if _net_mode() == "" or round == null or round.phase != RoundState.Phase.SETTLED or not is_instance_valid(_next_round_button): return
	var network = _net_node()
	var state: Dictionary = network.lobby
	var seats: Array = state.get("seats", [])
	_next_round_button.disabled = state.get("ready_round", -1) != network.round_number or seats.size() != 4
	if _next_round_button.disabled: return
	var seconds := int(state.get("countdown", -1))
	var ready: bool = seats[human_seat].ready
	_next_round_button.text = "%d 秒后开始 · 取消" % seconds if seconds >= 0 else ("已准备 · 点击取消" if ready else "准备下一局")
	_next_round_button.add_theme_font_size_override("font_size", 34)
	var statuses := PackedStringArray()
	var waiting := PackedStringArray()
	for relative in [0, 3, 2, 1]:
		var seat := posmod(human_seat + relative, 4)
		var name_value: String = ["你", "下家", "对家", "上家"][relative]
		statuses.append("%s %s" % [name_value, "人机已准备" if seats[seat].ai else ("已准备" if seats[seat].ready else "未准备")])
		if not seats[seat].ready: waiting.append(name_value)
	_next_round_status.text = " · ".join(statuses)
	_next_round_hint.text = "全部准备 · %d 秒后开始" % seconds if seconds >= 0 else "等待：" + "、".join(waiting)

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
		if _sound_settings != null and _sound_settings.is_open():
			_sound_settings.close()
		else:
			_confirm_quit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _sound_settings.is_open(): _sound_settings.close()
		else: _confirm_quit()
		get_viewport().set_input_as_handled()

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
	# 报听、碰、杠、胡等操作与出牌使用相同的大按钮和字号。
	var button := _button(text, callback, DISCARD_BUTTON_SIZE, primary)
	button.add_theme_font_size_override("font_size", 42)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = tooltip
	action_bar.add_child(button)
	_layout_actions()
	return button

func _clear_actions() -> void:
	if action_bar != null:
		_clear_box(action_bar)
		_layout_actions()

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
	if round != null: round.export_replay()
	quit_to_menu.emit()
	if _net_mode() != "":
		Network.reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _export_current_replay() -> void:
	var path := round.export_replay() if round != null else ""
	_sound_settings.replay_status.text = "已保存到本机对局记录目录" if path != "" else "完整记录保存在房主或服务器上"

func _confirm_quit() -> void:
	_sound_settings.confirm_exit()
