extends "res://scripts/ui/table/TableComponent.gd"
## 管理选牌、合法操作按钮、报听和提交；不自行改变牌局规则。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const LEGAL := preload("res://scripts/core/LegalActions.gd")

var action_bar: HBoxContainer
var auto_ready_enabled := DisplayServer.get_name() != "headless"
var _ready_auto_serial := 0
var _selecting := false
var _response_disc := ""
var _selected_tile: TileView
var _declaring_ready := false
var _ready_discards: Array = []
var _ready_button: Button
var _last_tile_input_ms := -1000
var _pressed_tile: TileView
var _press_position := Vector2.ZERO
var _dragged := false
var _touch_index := -1

func input_locked() -> bool:
	return table.round == null or table.round.phase != RoundState.Phase.PLAYING \
		or table._table_animation_controller.input_locked() \
		or table._settlement_animation_controller.is_active()

func build() -> void:
	action_bar = HBoxContainer.new()
	action_bar.position = Vector2(810, 1450)
	action_bar.size = Vector2(560, 58)
	action_bar.alignment = BoxContainer.ALIGNMENT_END
	action_bar.add_theme_constant_override("separation", UI.ACTION_SEPARATION)
	table.surface.add_child(action_bar)

func _layout_actions() -> void:
	if action_bar == null:
		return
	var right: float = table._table_center().x + 574.0
	var top: float = table._table_center().y + float(table._seat_metrics(table.human_seat).hand_y)
	if table.round != null and table.round.players.size() == 4:
		right = table._table_center().x + float(table._hand_layout(table.human_seat).draw_x) + TileView.BASE_W * UI.OWN_HAND_TILE_UNIT
	# The rightmost action aligns with the right edge of the drawn tile.  The row
	# grows leftwards as optional actions appear, keeping all actions above it.
	var count = action_bar.get_child_count()
	action_bar.visible = count > 0 and not input_locked()
	var row_size = Vector2(0, UI.ACTION_BUTTON_SIZE.y)
	for button in action_bar.get_children():
		row_size.x += button.custom_minimum_size.x
		row_size.y = maxf(row_size.y, button.custom_minimum_size.y)
	row_size.x += maxi(0, count - 1) * action_bar.get_theme_constant("separation")
	action_bar.size = row_size
	# With a short hand, keep the buttons to the right of our river. The
	# next player's river may sit underneath, as requested, but our tiles stay clear.
	var metrics: Dictionary = table._seat_metrics(table.human_seat)
	var river = Rect2(table._table_center() + Vector2(metrics.river_position), Vector2(metrics.river_size))
	var next_hand_left: float = table._table_center().x + table._seat_metrics(posmod(table.human_seat + 1, 4)).hand_y
	var right_limit = minf(table._table_bounds().end.x - UI.ACTION_EDGE_GAP, next_hand_left - UI.ACTION_EDGE_GAP)
	var left = minf(maxf(right - row_size.x, river.end.x + UI.ACTION_EDGE_GAP), right_limit - row_size.x)
	var row_top = top - row_size.y - UI.ACTION_HAND_GAP
	if Rect2(Vector2(left, row_top), row_size).intersects(river):
		row_top = minf(row_top, river.position.y - row_size.y - UI.ACTION_EDGE_GAP)
	action_bar.position = Vector2(left, row_top)

func _on_human_tile_gui(event: InputEvent, tile: TileView) -> void:
	# Cancellation is not a completed tap, even when the pointer is still over
	# the original tile. Process it before locks so no interrupted finger sticks.
	if event is InputEventScreenTouch and event.canceled:
		if event.index == _touch_index: _reset_press()
		return
	if not _selecting or not tile.interactive or input_locked():
		return
	var released := false
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index >= 0: return
			_touch_index = event.index
			_begin_press(tile, event.position)
		elif event.index == _touch_index:
			_touch_index = -1
			released = true
	elif event is InputEventScreenDrag:
		if event.index == _touch_index and event.position.distance_to(_press_position) > 20.0: _dragged = true
	elif event is InputEventMouseMotion:
		if is_instance_valid(_pressed_tile) and event.position.distance_to(_press_position) > 20.0: _dragged = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# 原生触控优先，忽略系统模拟的鼠标事件，避免一指提交两次。
		if OS.has_feature("android") or _touch_index >= 0: return
		if event.pressed: _begin_press(tile, event.position)
		else: released = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_SPACE]:
		_begin_press(tile, Vector2.ZERO)
		released = true
	if not released: return
	var valid := is_instance_valid(_pressed_tile) and _pressed_tile == tile and not _dragged and tile._has_point(event.position if not event is InputEventKey else Vector2.ZERO)
	_pressed_tile = null
	if not valid: return
	var now := Time.get_ticks_msec()
	if now - _last_tile_input_ms < UI.TILE_INPUT_DEBOUNCE_MS: return
	_last_tile_input_ms = now
	table._submit_discard(tile.tile, int(tile.get_meta("concealed_index", -1)))

func _begin_press(tile: TileView, position: Vector2) -> void:
	_pressed_tile = tile
	_press_position = position
	_dragged = false

func _reset_press() -> void:
	_pressed_tile = null
	_touch_index = -1
	_dragged = false

func _on_require_turn(seat: int) -> void:
	if seat != table.human_seat:
		return
	_ready_auto_serial += 1
	var serial := _ready_auto_serial
	_selecting = true
	_declaring_ready = false
	_response_disc = ""
	table._build_turn_options(table.round.players[seat])
	if table.round.players[seat].ready:
		_auto_ready_discard(seat, serial)

func _ready_auto_delay() -> float:
	# Use the same fast/medium/slow wait as AI turns. In an online room the
	# shared lobby value is authoritative; offline uses the local setting.
	if table._net_mode() != "":
		var net = table._net_node()
		if net != null:
			var key := str(net.lobby.get("ai_speed", "fast"))
			return float(GameConfig.AI_SPEED_DELAYS.get(key, GameConfig.AI_SPEED_DELAYS["fast"]))
	return GameConfig.ai_delay_seconds()

func _auto_ready_discard(seat: int, serial: int) -> void:
	if not auto_ready_enabled:
		return
	var tree: SceneTree = table.get_tree()
	if tree == null:
		return
	# Let the draw/last-action animation land first. The player still sees the
	# drawn tile; only the discard action is automatic.
	await tree.create_timer(_ready_auto_delay()).timeout
	var deadline := Time.get_ticks_msec() + 1800
	while is_instance_valid(table) and table.is_inside_tree() and input_locked():
		if serial != _ready_auto_serial or Time.get_ticks_msec() > deadline:
			return
		await tree.process_frame
	if not is_instance_valid(table) or serial != _ready_auto_serial or not _selecting:
		return
	if table.round == null or table.round.phase != RoundState.Phase.PLAYING:
		return
	if table.human_seat != seat or seat >= table.round.players.size():
		return
	var player: PlayerState = table.round.players[seat]
	if not player.ready or player.just_drew == "":
		return
	var options: Dictionary = table.round.legal_turn_options(seat)
	# A winning draw is a stop condition: keep the 自摸 button and let the user
	# choose it instead of silently discarding the winning tile.
	if options.self_win:
		return
	if not options.discards.has(player.just_drew):
		return
	# The user may have tapped the tile or another action while waiting.
	if not _selecting:
		return
	table._submit_discard(player.just_drew, -1)

func _build_turn_options(player: PlayerState) -> void:
	table._clear_actions()
	var window: Dictionary = table.round.allowed_actions(player.seat)
	var options: Dictionary = window.get("options", {})
	# 保留测试和重连快照尚未重新发出 prompt 时的只读回退；真实操作窗口
	# 始终使用 LegalActions 返回的当前清单。
	if window.get("kind", "") != "turn":
		options = table.round.legal_turn_options(player.seat)
	if options.self_win:
		table._add_action("自摸", func(): table._commit_turn({"self_win": true}), true)
	table._add_kong_choices("暗杠", "kong_declares", Tiles.sort_hand(options.kong_declares))
	table._add_kong_choices("加杠", "add_kong", options.add_kong)
	_ready_discards = options.ready_discards.duplicate()
	if not _ready_discards.is_empty():
		_ready_button = table._add_action("报听", table._toggle_ready)

func _add_kong_choices(title: String, decision_key: String, cards: Array) -> void:
	if cards.is_empty():
		return
	if cards.size() == 1:
		table._add_action(title, func(): table._commit_turn({decision_key: [cards[0]]}), false, title + " " + table._cn(cards[0]))
		return
	var choices = PopupMenu.new()
	choices.name = "TileChoices"
	choices.add_theme_font_size_override("font_size", 24)
	choices.add_theme_constant_override("v_separation", 24)
	for index in cards.size():
		choices.add_item(table._cn(cards[index]), index)
	choices.id_pressed.connect(func(index): table._commit_turn({decision_key: [cards[index]]}))
	var button = table._add_action(title, func(): choices.popup_centered(Vector2i(240, 0)))
	button.add_child(choices)

func _discard_selected() -> void:
	if is_instance_valid(_selected_tile):
		table._submit_discard(_selected_tile.tile, int(_selected_tile.get_meta("concealed_index", -1)))

func _toggle_ready() -> void:
	_declaring_ready = not _declaring_ready
	if is_instance_valid(_selected_tile):
		_selected_tile.set_selected(false)
	_selected_tile = null
	for button in action_bar.get_children():
		if button.get_meta("discard", false):
			button.disabled = true
	if is_instance_valid(_ready_button):
		_ready_button.text = "取消" if _declaring_ready else "报听"
	table._update_interactivity()
	table._refresh_status()

func _update_interactivity() -> void:
	if not _selecting or input_locked(): _reset_press()
	if table.round == null or table.human_seat >= table.round.players.size():
		return
	if _selecting and str(table.round.allowed_actions(table.human_seat).get("kind", "")) != "turn":
		_selecting = false
	var player: PlayerState = table.round.players[table.human_seat]
	var legal_discards: Array = table.round.legal_turn_options(table.human_seat).discards if _selecting else []
	for box in [table.hand_box[table.human_seat], table.draw_box[table.human_seat]]:
		for tile in box.get_children():
			var enabled: bool = not input_locked() and _selecting and legal_discards.has(tile.tile) and (not player.ready or tile.get_meta("drawn", false))
			if _declaring_ready:
				enabled = enabled and _ready_discards.has(tile.tile)
			tile.set_interactive(enabled)
			# Keep the hand visually calm while waiting for a draw/response; legal
			# input is still controlled by interactive and the turn state.
			tile.modulate = Color.WHITE
	for button in action_bar.get_children(): button.disabled = input_locked()
	action_bar.visible = action_bar.get_child_count() > 0 and not input_locked()

func _safe_discard() -> String:
	if is_instance_valid(_selected_tile):
		return _selected_tile.tile
	var player: PlayerState = table.round.players[table.human_seat]
	return player.just_drew if player.just_drew != "" else (player.concealed[0] if not player.concealed.is_empty() else "")

func _commit_turn(decision: Dictionary) -> void:
	if not _selecting or input_locked() or not LEGAL.validate_turn_submission(table.round, table.human_seat, decision): return
	_selecting = false
	_declaring_ready = false
	table._clear_actions()
	table._update_interactivity()
	table._emit_turn(decision)

func _submit_discard(tile: String, discard_index: int = -1) -> void:
	if not _selecting or (_declaring_ready and not _ready_discards.has(tile)):
		return
	var decision := {"discard": tile, "ready": _declaring_ready}
	if discard_index >= 0:
		decision["discard_index"] = discard_index
	table._commit_turn(decision)

func _on_require_response(seat: int, discarded_seat: int, tile: String, options: Dictionary) -> void:
	if seat != table.human_seat:
		return
	_ready_auto_serial += 1
	_selecting = false
	_declaring_ready = false
	_response_disc = tile
	table._clear_actions()
	if options.get("can_win", false):
		table._add_action("胡", func(): table._commit_response("win"), true)
	if options.get("can_pong", false):
		table._add_action("碰", func(): table._commit_response("pong"), true)
	if options.get("can_kong", false):
		table._add_action("杠", func(): table._commit_response("kong"), true)
	table._add_action("过", func(): table._commit_response("pass"))
	table._update_interactivity()

func _commit_response(action: String) -> void:
	if input_locked() or _response_disc == "": return
	var prompt: Dictionary = table.round.allowed_actions(table.human_seat)
	if prompt.get("kind", "") != "response": return
	var tile = _response_disc
	_response_disc = ""
	table._clear_actions()
	table._emit_response(tile, {"action": action})

func _add_action(text: String, callback: Callable, primary: bool = false, tooltip: String = "") -> Button:
	# 仅需要选择的操作显示大按钮；出牌直接轻点手牌。
	var button: Button = table._button(text, callback, UI.DISCARD_BUTTON_SIZE, primary)
	button.add_theme_font_size_override("font_size", UI.ACTION_FONT_SIZE)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.tooltip_text = tooltip
	action_bar.add_child(button)
	table._layout_actions()
	return button

func _clear_actions() -> void:
	_reset_press()
	_ready_button = null
	if action_bar != null:
		table._clear_box(action_bar)
		table._layout_actions()
