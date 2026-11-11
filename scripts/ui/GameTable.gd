extends Control
## 组件宿主和旧 UI 接口桥接；这里只保留转发，不实现布局或交互。
## 联机与既有测试仍可访问原字段；尺寸/颜色数值只在 TableUiConfig 定义。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const LAYOUT := preload("res://scripts/ui/table/TableLayout.gd")
const PLAYER_AREAS := preload("res://scripts/ui/table/PlayerTileAreas.gd")
const ACTIONS_UI := preload("res://scripts/ui/table/v2/TableV2Actions.gd")
const SETTLEMENT_UI := preload("res://scripts/ui/table/v2/TableV2SettlementCard.gd")
const ANIMATIONS := preload("res://scripts/ui/table/v2/TableV2AnimationController.gd")
const SETTLEMENT_ANIMATIONS := preload("res://scripts/ui/table/v2/TableV2SettlementAnimationController.gd")
const WIDGETS := preload("res://scripts/ui/table/TableWidgets.gd")

var _table_layout = LAYOUT.new(self)
var _player_tile_areas = PLAYER_AREAS.new(self)
var _new_areas: Control = null
var _table_actions = ACTIONS_UI.new(self)
var _settlement_card = SETTLEMENT_UI.new(self)
var _table_animation_controller = ANIMATIONS.new(self)
var _settlement_animation_controller = SETTLEMENT_ANIMATIONS.new(self)
var _table_widgets = WIDGETS.new()

func _on_settlement_speed_changed() -> void:
	_settlement_animation_controller.update_speed()

## The table is deliberately designed in landscape.  Both the desktop build and
## Android use this same canvas so a device rotation never switches to the old
## portrait table.
const DESIGN_SIZE := UI.DESIGN_SIZE
## Reference origin for the small center-panel labels authored before landscape.
const TABLE_CENTER := UI.TABLE_CENTER
const LANDSCAPE_SIZE := UI.LANDSCAPE_SIZE
const LANDSCAPE_CENTER := UI.LANDSCAPE_CENTER
const TILE_UNIT := UI.TILE_UNIT
const RIVER_TILE_UNIT := UI.RIVER_TILE_UNIT
const PLAYER_TILE_UNIT := UI.PLAYER_TILE_UNIT
const OWN_PLAYER_TILE_UNIT := UI.OWN_PLAYER_TILE_UNIT
const OWN_HAND_TILE_UNIT := UI.OWN_HAND_TILE_UNIT
const ACTION_BUTTON_SIZE := UI.ACTION_BUTTON_SIZE
const DISCARD_BUTTON_SIZE := UI.DISCARD_BUTTON_SIZE
const ACTION_HAND_GAP := UI.ACTION_HAND_GAP
const NEXT_ROUND_BUTTON_SIZE := UI.NEXT_ROUND_BUTTON_SIZE
const TILE_GAP := UI.TILE_GAP
const EXPOSED_HAND_GAP := UI.EXPOSED_HAND_GAP
const DRAW_GAP := UI.DRAW_GAP
const RIVER_POSITION := UI.RIVER_POSITION
const RIVER_SIZE := UI.RIVER_SIZE
const ROTATIONS := UI.ROTATIONS
const WINDS := UI.WINDS
const INK := UI.INK
const MUTED := UI.MUTED
const GOLD := UI.GOLD
const SAFE_MARGIN := UI.SAFE_MARGIN
const TOUCH_MARGIN := UI.TOUCH_MARGIN
const VISUAL_ANIMATIONS := UI.VISUAL_ANIMATIONS

var hand_box: Dictionary:
	get: return _player_tile_areas.hand_box
	set(value): _player_tile_areas.hand_box = value
var ready_frames: Dictionary:
	get: return _player_tile_areas.ready_frames
	set(value): _player_tile_areas.ready_frames = value
var draw_box: Dictionary:
	get: return _player_tile_areas.draw_box
	set(value): _player_tile_areas.draw_box = value
var meld_box: Dictionary:
	get: return _player_tile_areas.meld_box
	set(value): _player_tile_areas.meld_box = value
var discard_box: Dictionary:
	get: return _player_tile_areas.discard_box
	set(value): _player_tile_areas.discard_box = value
var discard_scroll: Dictionary:
	get: return _player_tile_areas.discard_scroll
	set(value): _player_tile_areas.discard_scroll = value
var chicken_box: Dictionary:
	get: return _player_tile_areas.chicken_box
	set(value): _player_tile_areas.chicken_box = value
var center_labels: Dictionary:
	get: return _player_tile_areas.center_labels
	set(value): _player_tile_areas.center_labels = value
var net_labels: Dictionary:
	get: return _player_tile_areas.net_labels
	set(value): _player_tile_areas.net_labels = value
var seat_roots: Dictionary:
	get: return _player_tile_areas.seat_roots
	set(value): _player_tile_areas.seat_roots = value
var wind_labels: Dictionary:
	get: return _player_tile_areas.wind_labels
	set(value): _player_tile_areas.wind_labels = value
var avatars: Dictionary:
	get: return _player_tile_areas.avatars
	set(value): _player_tile_areas.avatars = value
var dealer_badges: Dictionary:
	get: return _player_tile_areas.dealer_badges
	set(value): _player_tile_areas.dealer_badges = value
var status_label: Label:
	get: return _table_layout.status_label
	set(value): _table_layout.status_label = value
var action_bar: Control:
	get: return _table_actions.action_bar
	set(value): _table_actions.action_bar = value
var surface: Control:
	get: return _table_layout.surface
	set(value): _table_layout.surface = value
var _selecting: bool:
	get: return _table_actions._selecting
	set(value): _table_actions._selecting = value
var _response_disc: String:
	get: return _table_actions._response_disc
	set(value): _table_actions._response_disc = value
var _selected_tile: TileView:
	get: return _table_actions._selected_tile
	set(value): _table_actions._selected_tile = value
var _declaring_ready: bool:
	get: return _table_actions._declaring_ready
	set(value): _table_actions._declaring_ready = value
var _ready_discards: Array:
	get: return _table_actions._ready_discards
	set(value): _table_actions._ready_discards = value
var _felt: NoiseTexture2D:
	get: return _table_layout._felt
	set(value): _table_layout._felt = value
var _next_round_button: Button:
	get: return _settlement_card._next_round_button
	set(value): _settlement_card._next_round_button = value
var _next_round_status: Label:
	get: return _settlement_card._next_round_status
	set(value): _settlement_card._next_round_status = value
var _next_round_hint: Label:
	get: return _settlement_card._next_round_hint
	set(value): _settlement_card._next_round_hint = value
var _post_controls: Control:
	get: return _settlement_card._post_controls
	set(value): _settlement_card._post_controls = value
var _status_labels: Dictionary:
	get: return _player_tile_areas._status_labels
	set(value): _player_tile_areas._status_labels = value
var _exposed_layouts: Dictionary:
	get: return _player_tile_areas._exposed_layouts
	set(value): _player_tile_areas._exposed_layouts = value
var _landscape: bool:
	get: return _table_layout._landscape
	set(value): _table_layout._landscape = value
var _seat_visual_keys: Dictionary:
	get: return _player_tile_areas._seat_visual_keys
	set(value): _player_tile_areas._seat_visual_keys = value
var _animation_layer:
	get: return _table_animation_controller._animation_layer
	set(value): _table_animation_controller._animation_layer = value
var _animation_busy: bool:
	get: return _table_animation_controller._animation_busy
	set(value): _table_animation_controller._animation_busy = value
var _animation_last_id: int:
	get: return _table_animation_controller._animation_last_id
	set(value): _table_animation_controller._animation_last_id = value
var _animation_queue: Array:
	get: return _table_animation_controller._animation_queue
	set(value): _table_animation_controller._animation_queue = value
var _skip_visual_once: bool:
	get: return _table_animation_controller._skip_visual_once
	set(value): _table_animation_controller._skip_visual_once = value
var _last_tile_input_ms: int:
	get: return _table_actions._last_tile_input_ms
	set(value): _table_actions._last_tile_input_ms = value

func _on_visual_event(event: Dictionary) -> void:
	_table_animation_controller._on_visual_event(event)

func _pump_visual_animation() -> void:
	_table_animation_controller._pump_visual_animation()

func _on_visual_animation_finished() -> void:
	_table_animation_controller._on_visual_animation_finished()

func _start_settlement_animation(immediate: bool = false) -> void:
	_settlement_animation_controller.start(immediate)

func _on_settlement_animation_finished() -> void:
	_settlement_card.show_post_settlement_controls()
	_update_interactivity()

func _refresh_ready_hint() -> void:
	if _player_tile_areas != null:
		_player_tile_areas.refresh_ready_hint(int(get("human_seat")))

func _show_pending_ready(seat: int) -> void:
	if _player_tile_areas != null:
		_player_tile_areas.show_pending_ready(seat)

func _settlement_animation_active() -> bool:
	if _new_areas != null and DisplayServer.get_name() != "headless" \
			and _new_areas.has_method("native_settlement_active"):
		return _new_areas.native_settlement_active()
	return _settlement_animation_controller.is_active()

func _settlement_animation_done() -> bool:
	if _new_areas != null and DisplayServer.get_name() != "headless" \
			and _new_areas.has_method("native_settlement_complete"):
		return _new_areas.native_settlement_started() and _new_areas.native_settlement_complete()
	return _settlement_animation_controller.is_completed()

func _animation_target_for_seat(seat: int) -> Vector2:
	return _table_animation_controller._animation_target_for_seat(seat)

func _build_static_ui() -> void:
	_table_layout._build_static_ui()

func _layout() -> void:
	_table_layout._layout()

func _refresh_layout_contents() -> void:
	_table_layout._refresh_layout_contents()

func _usable_rect() -> Rect2:
	return _table_layout._usable_rect()

func _design_size() -> Vector2:
	return _table_layout._design_size()

func _table_center() -> Vector2:
	return _table_layout._table_center()

func _table_bounds() -> Rect2:
	return _table_layout._table_bounds()

func _seat_metrics(seat: int) -> Dictionary:
	return _table_layout._seat_metrics(seat)

func _player_tile_unit(seat: int) -> float:
	return _table_layout._player_tile_unit(seat)

func _hand_tile_unit(seat: int) -> float:
	return _table_layout._hand_tile_unit(seat)

func _hand_layout(seat: int) -> Dictionary:
	return _table_layout._hand_layout(seat)

func _layout_actions() -> void:
	_table_actions._layout_actions()

func _draw() -> void:
	_table_layout._draw()

func _draw_die(value: int, pos: Vector2) -> void:
	_table_layout._draw_die(value, pos)

func _relative_seat(seat: int) -> int:
	return _table_layout._relative_seat(seat)

func _refresh_seat(seat: int) -> void:
	_player_tile_areas._refresh_seat(seat)

func _meld_tile_layout(meld: Dictionary, seat: int, unit: float, gap: float) -> Dictionary:
	return _player_tile_areas._meld_tile_layout(meld, seat, unit, gap)

func _prepare_exposed_layouts() -> void:
	_player_tile_areas._prepare_exposed_layouts()

func _exposed_rects(layout: Dictionary, origin: Vector2, transform: Transform2D, width: float, height: float) -> Array[Rect2]:
	return _player_tile_areas._exposed_rects(layout, origin, transform, width, height)

func _exposed_space_clear(rects: Array[Rect2], occupied: Array[Rect2]) -> bool:
	return _player_tile_areas._exposed_space_clear(rects, occupied)

func _refresh_status_text(seat: int) -> void:
	_player_tile_areas._refresh_status_text(seat)

func _chicken_discards(seat: int) -> Array:
	return _player_tile_areas._chicken_discards(seat)

func _exposed_groups(seat: int) -> Array:
	return _player_tile_areas._exposed_groups(seat)

func _refresh_discards(seat: int) -> void:
	_player_tile_areas._refresh_discards(seat)

func _scroll_to_latest(river: ScrollContainer) -> void:
	_player_tile_areas._scroll_to_latest(river)

func _on_human_tile_gui(event: InputEvent, tile: TileView) -> void:
	_table_actions._on_human_tile_gui(event, tile)

func _on_require_turn(seat: int) -> void:
	_table_actions._on_require_turn(seat)

func _build_turn_options(player: PlayerState) -> void:
	_table_actions._build_turn_options(player)

func _add_kong_choices(title: String, decision_key: String, cards: Array) -> void:
	_table_actions._add_kong_choices(title, decision_key, cards)

func _discard_selected() -> void:
	_table_actions._discard_selected()

func _toggle_ready() -> void:
	_table_actions._toggle_ready()

func _update_interactivity() -> void:
	_table_actions._update_interactivity()

func _safe_discard() -> String:
	return _table_actions._safe_discard()

func _commit_turn(decision: Dictionary) -> void:
	_table_actions._commit_turn(decision)

func _submit_discard(tile: String, discard_index: int = -1) -> void:
	_table_actions._submit_discard(tile, discard_index)

func _on_require_response(seat: int, discarded_seat: int, tile: String, options: Dictionary) -> void:
	_table_actions._on_require_response(seat, discarded_seat, tile, options)

func _commit_response(action: String) -> void:
	_table_actions._commit_response(action)

func _next_round() -> void:
	_settlement_card._next_round()

func _refresh_next_round_controls() -> void:
	_settlement_card._refresh_next_round_controls()

func _make_tile(card: String, up: bool, unit: float = TILE_UNIT) -> TileView:
	return _table_widgets._make_tile(card, up, unit)

func _put_tile(parent: Control, tile: TileView, pos: Vector2) -> void:
	_table_widgets._put_tile(parent, tile, pos)

func _box(parent: Control) -> Control:
	return _table_widgets._box(parent)

func _label(parent: Control, text: String, pos: Vector2, dimensions: Vector2, font_size: int, color: Color = INK) -> Label:
	return _table_widgets._label(parent, text, pos, dimensions, font_size, color)

func _style(color: Color, border: Color, radius: int, border_width: int = 0) -> StyleBoxFlat:
	return _table_widgets._style(color, border, radius, border_width)

func _button(text: String, callback: Callable, dimensions: Vector2, primary: bool = false) -> Button:
	return _table_widgets._button(text, callback, dimensions, primary)

func _add_action(text: String, callback: Callable, primary: bool = false, tooltip: String = "") -> Button:
	return _table_actions._add_action(text, callback, primary, tooltip)

func _clear_actions() -> void:
	_table_actions._clear_actions()

func _clear_box(box: Node) -> void:
	_table_widgets._clear_box(box)

func _cn(card: String) -> String:
	return _table_widgets._cn(card)

signal quit_to_menu

const CONNECTION_OVERLAY := preload("res://scripts/ui/ConnectionOverlay.gd")
const TEST_PATTERNS := preload("res://scripts/core/TestPatterns.gd")


## 牌局与联机事件协调器。视觉状态由 table/ 组件持有。
## 保留既有联机和测试接口；视觉参数统一在 TableUiConfig。

var round: RoundState
var human_seat := 1
var net_submit_turn: Callable
var net_submit_response: Callable
var _round_number := 0
var _connection_overlay: Control
var _sound_settings: SoundSettings
var _audio_round: RoundState
var _sound_button: Button
var _settings_button: Button
var _ai_proxy_button: Button
var _test_pattern_button: Button
var _ai_teach_button: Button
var _test_choice_panel: Panel
var _test_choice_box: VBoxContainer
var _test_vote_panel: Panel
var _test_vote_label: Label
var _test_vote_buttons: HBoxContainer
var _test_vote_id := ""
var _test_mode_ui := false

var _ai_teach_token := 0
var _ai_teach_task := 0
var _ai_teach_worker = null
var _ai_teach_message := ""
var _ai_teach_response_pending := false
var _ai_teach_response_tile := ""
var _ai_teach_response_options: Dictionary = {}
var _refresh_queued := false

var _ai_assist_enabled := false
var _auto_test_rounds := 0
var _auto_test_completed := 0
var _auto_test_online_ai: AiPlayer
var _auto_test_prompt_seen := -1
var _auto_test_settled_round := -1
var _ai_proxy_active := false
var _ai_proxy_ai: AiPlayer
var _ai_proxy_worker = null
var _ai_proxy_task := 0
var _ai_proxy_response_tile := ""
var _ai_proxy_response_pending := false
var _voice_pack_dialog: Control
var _voice_pack_layer: CanvasLayer
var _settlement_round_id := 0
var _settlement_session := ""
var _settlement_round_number := -1
var _settlement_phase := -1
var _settlement_immediate := false
var _awaiting_rejoin_snapshot := false
var _quitting := false
var _opening_primed := false
var _ai_service = null
var _return_vote_overlay: Control
var _return_vote_panel: Panel
var _return_vote_message: Label
var _return_vote_token := -1
var _return_vote_status: Label
var _resume_generation := 0

func _ready() -> void:
	AudioManager.begin_table(self)
	_build_static_ui()
	_build_table_overlays()
	# 新牌区已显示真实牌墙，debug 牌墙测试不再提供。
	var connection_layer := CanvasLayer.new()
	connection_layer.name = "ConnectionLayer"
	connection_layer.layer = 30
	add_child(connection_layer)
	_connection_overlay = CONNECTION_OVERLAY.new()
	connection_layer.add_child(_connection_overlay)
	_connection_overlay.retry_requested.connect(_retry_connection)
	_connection_overlay.leave_requested.connect(func(): _on_quit(true))
	_connect_voice_ui()
	get_window().focus_exited.connect(_on_input_focus_changed)
	get_window().focus_entered.connect(_on_input_focus_changed)
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
	_opening_primed = false
	AudioManager.reset_round(round.audio_session, round.audio_event_id)
	_table_animation_controller.reset()
	_settlement_animation_controller.reset()
	_settlement_card.hide_post_settlement_controls()
	_settlement_round_id = 0
	_settlement_phase = -1
	_last_tile_input_ms = -1000
	round.audio_event.connect(_on_audio_event)
	if not round.visual_event.is_connected(_on_visual_event):
		round.visual_event.connect(_on_visual_event)

func _on_audio_event(event: Dictionary) -> void:
	AudioManager.play_event(event, _table_animation_controller.defers_discard_sound())

func _connect_voice_ui() -> void:
	var net = _net_node()
	if net == null:
		return
	if net.has_signal("voice_status") and not net.voice_status.is_connected(_on_voice_status):
		net.voice_status.connect(_on_voice_status)
	if net.has_signal("lobby_updated") and not net.lobby_updated.is_connected(_refresh_remote_voice):
		net.lobby_updated.connect(_refresh_remote_voice)
	if net.has_signal("returned_to_lobby") and not net.returned_to_lobby.is_connected(_on_returned_to_lobby):
		net.returned_to_lobby.connect(_on_returned_to_lobby)
	if net.has_signal("return_vote_updated") and not net.return_vote_updated.is_connected(_on_return_vote_updated):
		net.return_vote_updated.connect(_on_return_vote_updated)

func _ensure_return_vote_ui() -> void:
	if _return_vote_overlay != null:
		return
	_return_vote_overlay = Control.new()
	_return_vote_overlay.name = "ReturnRoomVote"
	_return_vote_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_return_vote_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_return_vote_overlay.z_index = 400
	add_child(_return_vote_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.04, 0.03, 0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_return_vote_overlay.add_child(shade)
	_return_vote_panel = Panel.new()
	_return_vote_panel.size = Vector2(820, 360)
	_return_vote_panel.add_theme_stylebox_override("panel", _style(Color("#1e4234"), Color("#cbb279"), 24, 2))
	_return_vote_overlay.add_child(_return_vote_panel)
	var title := _label(_return_vote_panel, "返回房间", Vector2(52, 30), Vector2(716, 54), 40, UI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_return_vote_message = _label(_return_vote_panel, "", Vector2(52, 96), Vector2(716, 120), 28, UI.INK)
	_return_vote_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_return_vote_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var agree := _button("同意", _answer_return_vote.bind(true), Vector2(300, 92), true)
	agree.position = Vector2(80, 238)
	agree.name = "ReturnVoteAgree"
	_return_vote_panel.add_child(agree)
	var reject := _button("拒绝", _answer_return_vote.bind(false), Vector2(300, 92))
	reject.position = Vector2(440, 238)
	reject.name = "ReturnVoteReject"
	_return_vote_panel.add_child(reject)
	_return_vote_overlay.hide()

func _answer_return_vote(value: bool) -> void:
	var net = _net_node()
	if net != null and net.has_method("answer_return_vote"):
		net.answer_return_vote(value)
	if _return_vote_overlay != null:
		_return_vote_overlay.hide()

func _on_return_vote_updated(data: Dictionary) -> void:
	_ensure_return_vote_ui()
	if not bool(data.get("active", false)):
		_return_vote_overlay.hide()
		_return_vote_status.hide()
		_return_vote_token = -1
		return
	var humans: Array = data.get("humans", [])
	var yes: Dictionary = data.get("yes", {})
	var agree_count := 0
	for seat_value in humans:
		if bool(yes.get(int(seat_value), false)): agree_count += 1
	_return_vote_status.text = "返回房间同意 %d/%d" % [agree_count, humans.size()]
	_return_vote_status.show()
	if human_seat not in humans or bool(yes.get(human_seat, false)):
		_return_vote_overlay.hide()
		return
	var initiator := int(data.get("initiator", -1))
	var who := "其他玩家" if initiator < 0 or initiator == human_seat else _seat_name(initiator)
	var token := initiator * 10 + int(data.get("rejecter", -1))
	if _return_vote_overlay.visible and _return_vote_token == token:
		return
	_return_vote_token = token
	_return_vote_message.text = "%s 发起返回房间。\n全部真人同意后，大家一起回到选座等待。" % who
	var design := _design_size()
	_return_vote_panel.position = (design - _return_vote_panel.size) * 0.5
	_return_vote_overlay.show()

func _on_returned_to_lobby() -> void:
	if _quitting:
		return
	_quitting = true
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _toggle_voice_chat() -> void:
	var net = _net_node()
	if net == null or not net.has_method("toggle_voice_chat"):
		return
	net.toggle_voice_chat()

func _build_table_overlays() -> void:
	_return_vote_status = Label.new()
	_return_vote_status.name = "ReturnVoteStatus"
	_return_vote_status.position = Vector2(24, 154)
	_return_vote_status.size = Vector2(1040, 40)
	_return_vote_status.add_theme_font_override("font", TileView._font())
	_return_vote_status.add_theme_font_size_override("font_size", 24)
	_return_vote_status.add_theme_color_override("font_color", Color("#ffe6a8"))
	_return_vote_status.add_theme_color_override("font_outline_color", Color("#102018"))
	_return_vote_status.add_theme_constant_override("outline_size", 4)
	_return_vote_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_return_vote_status.z_index = 100
	add_child(_return_vote_status)
	_return_vote_status.hide()
	_build_test_pattern_ui()

func _build_test_pattern_ui() -> void:
	_test_vote_panel = Panel.new()
	_test_vote_panel.name = "TestPatternVote"
	_test_vote_panel.size = Vector2(760, 170)
	_test_vote_panel.position = Vector2((_design_size().x - 760.0) / 2.0, 130.0)
	_test_vote_panel.z_index = 210
	_test_vote_panel.add_theme_stylebox_override("panel", _style(Color("#102018f2"), UI.GOLD, 16, 2))
	add_child(_test_vote_panel)
	_test_vote_label = Label.new()
	_test_vote_label.position = Vector2(24, 18)
	_test_vote_label.size = Vector2(712, 64)
	_test_vote_label.add_theme_font_override("font", TileView._font())
	_test_vote_label.add_theme_font_size_override("font_size", 26)
	_test_vote_label.add_theme_color_override("font_color", UI.INK)
	_test_vote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_test_vote_panel.add_child(_test_vote_label)
	_test_vote_buttons = HBoxContainer.new()
	_test_vote_buttons.position = Vector2(24, 96)
	_test_vote_buttons.size = Vector2(712, 64)
	_test_vote_buttons.add_theme_constant_override("separation", 20)
	_test_vote_panel.add_child(_test_vote_buttons)
	var agree := _button("同意", func(): _answer_test_vote(true), Vector2(220, 60), true)
	agree.name = "AgreeTestPattern"
	var reject := _button("拒绝", func(): _answer_test_vote(false), Vector2(220, 60))
	reject.name = "RejectTestPattern"
	_test_vote_buttons.add_child(agree)
	_test_vote_buttons.add_child(reject)
	_test_vote_panel.hide()

func _on_test_pattern_pressed() -> void:
	if not GameConfig.debug_enabled:
		return
	var net = _net_node()
	if net == null or net.mode == "":
		return
	if _test_choice_panel == null:
		_test_choice_panel = Panel.new()
		_test_choice_panel.name = "TestPatternChooser"
		_test_choice_panel.size = Vector2(620, 390)
		_test_choice_panel.position = Vector2((_design_size().x - 620.0) / 2.0, 150.0)
		_test_choice_panel.z_index = 220
		_test_choice_panel.add_theme_stylebox_override("panel", _style(Color("#102018f5"), UI.GOLD, 18, 2))
		add_child(_test_choice_panel)
		var title := Label.new()
		title.text = "选择测试牌型"
		title.position = Vector2(24, 18)
		title.size = Vector2(572, 44)
		title.add_theme_font_override("font", TileView._font())
		title.add_theme_font_size_override("font_size", 30)
		title.add_theme_color_override("font_color", UI.GOLD)
		_test_choice_panel.add_child(title)
		_test_choice_box = VBoxContainer.new()
		_test_choice_box.position = Vector2(24, 74)
		_test_choice_box.size = Vector2(572, 300)
		_test_choice_box.add_theme_constant_override("separation", 8)
		_test_choice_panel.add_child(_test_choice_box)
		for entry in TEST_PATTERNS.CATALOG:
			var pattern := str(entry.id)
			var button := _button(str(entry.name),
				func(): _choose_test_pattern(pattern), Vector2(572, 68))
			button.tooltip_text = str(entry.description)
			button.add_theme_font_size_override("font_size", 26)
			_test_choice_box.add_child(button)
		var cancel := _button("取消", func(): _test_choice_panel.hide(), Vector2(572, 48))
		cancel.add_theme_font_size_override("font_size", 20)
		_test_choice_box.add_child(cancel)
	_test_choice_panel.show()

func _choose_test_pattern(pattern: String) -> void:
	if _test_choice_panel != null:
		_test_choice_panel.hide()
	var net = _net_node()
	if net != null:
		net.propose_test_pattern(pattern)

func _answer_test_vote(agree: bool) -> void:
	var net = _net_node()
	if net != null:
		net.answer_test_vote(agree, _test_vote_id)
	_refresh_test_pattern_ui()

func _refresh_test_pattern_ui() -> void:
	if _test_vote_panel == null:
		return
	if not GameConfig.debug_enabled:
		_test_vote_panel.hide()
		return
	var net = _net_node()
	var vote: Dictionary = net.lobby.get("test_vote", {}) if net != null else {}
	if vote.is_empty():
		_test_vote_id = ""
		_test_vote_panel.hide()
		return
	_test_vote_id = str(vote.get("proposal_id", ""))
	var pattern := str(vote.get("pattern", ""))
	var entry: Dictionary = TEST_PATTERNS.get_entry(pattern)
	var humans: Array = vote.get("humans", [])
	var yes: Array = vote.get("yes", [])
	var me := int(net.my_seat)
	if me in yes:
		_test_vote_label.text = "测试牌型：%s\n已同意，等待其他真人同意（%d/%d）" % [entry.get("name", pattern), yes.size(), humans.size()]
	else:
		_test_vote_label.text = "有玩家申请测试牌型：%s\n是否同意立即重开本局并给发起者发这套牌？" % entry.get("name", pattern)
	_test_vote_buttons.visible = me not in yes
	_test_vote_panel.show()

func _on_voice_status(_enabled: bool, message: String) -> void:
	if _new_areas != null:
		_new_areas.refresh_voice_control(human_seat, message)

func _refresh_remote_voice() -> void:
	if _new_areas == null: return
	for seat in 4:
		if seat != human_seat: _new_areas.refresh_voice_control(seat)

func _on_ai_assist_pressed() -> void:
	if _ai_teach_button == null:
		return
	_ai_assist_enabled = _ai_teach_button.button_pressed
	_ai_teach_button.text = "AI教学 开" if _ai_assist_enabled else "AI教学"
	if not _ai_assist_enabled:
		_clear_ai_teach()
		return
	# 非出牌回合打开开关只记录状态，不弹“不是你的回合”；下一次
	# 自己摸牌出牌时会自动提示。
	if _is_ai_turn_now():
		request_ai_teach()

func open_voice_packs() -> void:
	if _voice_pack_dialog == null:
		_voice_pack_layer = CanvasLayer.new()
		_voice_pack_layer.layer = 30
		add_child(_voice_pack_layer)
		_voice_pack_dialog = load("res://scripts/ui/VoicePackDialog.gd").new()
		_voice_pack_layer.add_child(_voice_pack_dialog)
		_voice_pack_dialog.pack_selected.connect(_on_voice_pack_selected)
		_voice_pack_dialog.preview_requested.connect(_on_voice_pack_preview)
		_voice_pack_dialog.test_all_requested.connect(func(): AudioManager.start_voice_test())
	var packs: Array = []
	for index in 4:
		packs.append(AudioManager.get_seat_voice_pack(index))
	_voice_pack_dialog.open(packs, human_seat, true)

func _on_voice_pack_selected(seat: int, pack_id: String) -> void:
	# 每位玩家独立保存本机的四个座位音色。
	AudioManager.set_seat_voice_pack(seat, pack_id, true)

func _on_voice_pack_preview(seat: int, pack_id: String) -> void:
	AudioManager.preview_voice_pack(seat, pack_id)

func _is_ai_turn_now() -> bool:
	return round != null and round.players.size() == 4 \
		and round.phase == RoundState.Phase.PLAYING \
		and round.awaiting and round.current_turn == human_seat

func _refresh_ai_assist() -> void:
	if not _ai_assist_enabled or _ai_proxy_active:
		return
	# 把教打分析从摸牌/刷新手牌那一帧挪开，避免 120Hz 下多一次主线程尖峰。
	await get_tree().create_timer(0.10).timeout
	if not _ai_assist_enabled or _ai_proxy_active or not _is_ai_turn_now():
		return
	request_ai_teach()

func _clear_ai_teach() -> void:
	_ai_teach_token += 1
	_ai_teach_message = ""
	_ai_teach_response_pending = false
	_ai_teach_response_tile = ""
	_ai_teach_response_options = {}
	var pending := _ai_teach_task
	_ai_teach_task = 0
	if pending > 0 and _ai_teach_worker != null:
		_ai_teach_worker.cancel(pending)
	if _player_tile_areas != null:
		_player_tile_areas.clear_ai_teach_highlight()
	if _new_areas != null and _new_areas.has_method("clear_ai_teach_highlights"):
		_new_areas.clear_ai_teach_highlights()

func request_ai_teach() -> void:
	if round == null or round.players.size() != 4:
		return
	if not _is_ai_turn_now():
		return
	_clear_ai_teach()
	if _ai_proxy_active:
		# 两个开关同时开时，教打必须展示代打真正会提交的牌，不能再独立算一套。
		_ai_teach_message = "AI代打分析中…"
		if status_label != null:
			status_label.text = _ai_teach_message
			status_label.show()
		return
	if _ai_teach_worker == null:
		_ai_teach_worker = load("res://scripts/core/AiTurnWorker.gd").new()
	# 教打和代打使用同一套完整 AI；只传公开快照并在线程中计算。
	var token: int = int(_ai_teach_worker.submit_turn(round, human_seat, _submitted_proxy_level()))
	if token <= 0:
		return
	_ai_teach_task = token
	_ai_teach_message = "AI分析中…"
	if status_label != null:
		status_label.text = _ai_teach_message
		status_label.show()

func request_ai_response_teach(source: int, tile: String, options: Dictionary) -> void:
	if not _ai_assist_enabled or _ai_proxy_active or round == null:
		return
	if not _is_ai_turn_now() and round._awaiting_response.is_empty():
		return
	if _ai_teach_worker == null:
		_ai_teach_worker = load("res://scripts/core/AiTurnWorker.gd").new()
	if _ai_teach_task > 0:
		_ai_teach_worker.cancel(_ai_teach_task)
	_ai_teach_response_pending = true
	_ai_teach_response_tile = tile
	_ai_teach_response_options = options.duplicate(true)
	_ai_teach_task = int(_ai_teach_worker.submit_response(round, human_seat, source, tile,
		options, _submitted_proxy_level()))
	_ai_teach_message = "AI分析中…"
	if status_label != null:
		status_label.text = _ai_teach_message
		status_label.show()

func _apply_ai_teach_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	var tiles: Array = result.get("tiles", [])
	if tiles.is_empty() and str(result.get("tile", "")) != "":
		tiles = [str(result.get("tile", ""))]
	if _player_tile_areas != null:
		_player_tile_areas.highlight_ai_teach_tiles(tiles)
	if _new_areas != null and _new_areas.has_method("highlight_ai_teach"):
		_new_areas.highlight_ai_teach(tiles)
	if result.has("message"):
		_ai_teach_message = str(result.message)
		if status_label != null:
			status_label.text = _ai_teach_message
			status_label.show()

func _poll_ai_teach() -> void:
	if _ai_proxy_active or _ai_teach_task <= 0 or _ai_teach_worker == null:
		return
	var result: Dictionary = _ai_teach_worker.take_result(_ai_teach_task)
	if result.is_empty():
		return
	_ai_teach_task = 0
	if _ai_teach_response_pending:
		_ai_teach_response_pending = false
		_ai_teach_response_tile = ""
		_ai_teach_response_options = {}
		var action := str(result.get("action", "pass"))
		var label: String = {"win": "胡", "kong": "杠", "pong": "碰", "pass": "过"}.get(action, "过")
		var text: String = {"win": "胡", "kong": "杠", "pong": "碰", "pass": "过"}.get(action, "过")
		_ai_teach_message = "AI教学：建议%s；当前强度：%s" % [text, _strength_label()]
		_apply_ai_teach_result({"message": _ai_teach_message})
		if _table_actions != null:
			_table_actions._highlight_ai_action_buttons("" if action == "pass" else label)
		return
	var tile := str(result.get("discard", result.get("tile", "")))
	var message := ""
	if bool(result.get("self_win", false)):
		message = "AI教学：建议自摸；当前强度：%s" % _strength_label()
	elif not result.get("kong_declares", []).is_empty():
		tile = str(result.kong_declares[0])
		message = "AI教学：建议暗杠；当前强度：%s" % _strength_label()
	elif not result.get("add_kong", []).is_empty():
		tile = str(result.add_kong[0])
		message = "AI教学：建议加杠；当前强度：%s" % _strength_label()
	elif tile != "":
		var tiles := _recommendation_tiles(result)
		if tiles.is_empty():
			tiles = [tile]
		message = "AI教学：建议打%s；当前强度：%s" % [" / ".join(tiles), _strength_label()]
	_apply_ai_teach_result({"tile": tile, "tiles": _recommendation_ids(result), "message": message})

func _recommendation_ids(result: Dictionary) -> Array:
	var output: Array = []
	for item in result.get("recommendations", []):
		var tile := str(item.get("tile", "")) if item is Dictionary else str(item)
		if tile != "" and not output.has(tile):
			output.append(tile)
	return output

func _recommendation_tiles(result: Dictionary) -> Array:
	var output: Array = []
	for item in result.get("recommendations", []):
		var tile := str(item.get("tile", "")) if item is Dictionary else str(item)
		if tile == "":
			continue
		var label := AiTeaching._display(tile)
		if not output.has(label):
			output.append(label)
	return output

func _strength_label() -> String:
	return {"weak": "弱", "medium": "中", "strong": "强"}.get(GameConfig.effective_ai_strength(), "中")

func _can_toggle_voice_chat() -> bool:
	var net = _net_node()
	return net != null and net.has_method("voice_chat_allowed") and net.voice_chat_allowed()

func _local_voice_enabled() -> bool:
	var net = _net_node()
	return net != null and net.has_method("voice_chat_enabled") and net.voice_chat_enabled()

func _toggle_remote_voice(seat: int) -> void:
	var net = _net_node()
	var chat = net.get("voice_chat") if net != null else null
	if chat == null or not chat.has_method("speaker_enabled"):
		return
	chat.set_speaker_enabled(seat, not bool(chat.speaker_enabled(seat)))

func _remote_voice_enabled(seat: int) -> bool:
	var net = _net_node()
	var chat = net.get("voice_chat") if net != null else null
	return chat != null and chat.has_method("speaker_enabled") and bool(chat.speaker_enabled(seat))

func _remote_microphone_on(seat: int) -> bool:
	var net = _net_node()
	return net != null and net.has_method("seat_microphone_on") and net.seat_microphone_on(seat)

func _process(_delta: float) -> void:
	if round == null:
		return
	_poll_ai_teach()
	_poll_ai_proxy()
	# Online authority and clients already poll in NetGameNode._process.
	var network = get_node_or_null("/root/Network")
	if network == null or network.net_node == null or str(network.mode) == "":
		round.poll_ai()
	elif _auto_test_rounds > 0 or _ai_proxy_active:
		_auto_test_poll_online()

func _exit_tree() -> void:
	var net = _net_node()
	if net != null:
		var chat = net.get("voice_chat")
		if chat != null and chat.has_method("set_enabled"):
			chat.set_enabled(false)
		if net.has_signal("voice_status") and net.voice_status.is_connected(_on_voice_status):
			net.voice_status.disconnect(_on_voice_status)
	if _ai_service != null:
		var tree := get_tree()
		if tree != null:
			_ai_service.stop_async(tree)
		else:
			_ai_service.stop()
		_ai_service = null
	if _ai_teach_worker != null:
		var teach_tree := get_tree()
		if teach_tree != null:
			_ai_teach_worker.stop_async(teach_tree)
		else:
			_ai_teach_worker.stop()
		_ai_teach_worker = null
	if _ai_proxy_worker != null:
		var proxy_tree := get_tree()
		if proxy_tree != null:
			_ai_proxy_worker.stop_async(proxy_tree)
		_ai_proxy_worker = null
	_ai_proxy_active = false
	_ai_proxy_task = 0
	if round != null and _net_mode() == "": round.cancel_opening()
	if _audio_round != null and _audio_round.audio_event.is_connected(_on_audio_event):
		_audio_round.audio_event.disconnect(_on_audio_event)
	if _audio_round != null and _audio_round.visual_event.is_connected(_on_visual_event):
		_audio_round.visual_event.disconnect(_on_visual_event)
	_audio_round = null
	_table_animation_controller.cancel()
	_table_animation_controller.dispose_pool()
	_settlement_animation_controller.reset()
	AudioManager.end_table(self)

func _net_mode() -> String:
	# Some UI smoke tests construct the table before attaching it to the scene
	# tree.  Absolute lookups are invalid in that state; treat it as offline
	# until the node has a tree owner, matching the normal standalone mode.
	if not is_inside_tree():
		return ""
	var network := get_node_or_null("/root/Network")
	return network.mode if network != null else ""

func _net_node():
	if not is_inside_tree():
		return null
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

func start_auto_test(rounds: int = 100) -> void:
	var online := _net_mode() != ""
	if online:
		var net = _net_node()
		if net == null or net.game == null or net.game.phase == RoundState.Phase.IDLE:
			return
	_auto_test_rounds = maxi(1, rounds)
	_auto_test_completed = 0
	_auto_test_prompt_seen = -1
	_auto_test_settled_round = -1
	if online:
		# 真实速度：不修改任何动画/人机延迟，只代替玩家点击。
		_auto_test_online_ai = null
		print("[auto-test] start rounds=%d mode=online real-speed" % _auto_test_rounds)
		return
	GameConfig.set_ai_speed("fast", false)
	GameConfig.animation_speed = "instant"
	GameConfig.set_tile_animation_seconds(0.0, false)
	GameConfig.settlement_speed = "fast"
	_auto_test_online_ai = null
	print("[auto-test] start rounds=", _auto_test_rounds)
	new_game()

func _auto_test_poll_online() -> void:
	if round == null or _awaiting_rejoin_snapshot or (_auto_test_rounds <= 0 and not _ai_proxy_active):
		return
	if round.phase == RoundState.Phase.SETTLED:
		var settled_round := int(_net_node().round_number) if _net_node() != null else 0
		if _ai_proxy_active and _auto_test_rounds <= 0:
			if not _settlement_animation_done():
				return
			if _auto_test_settled_round != settled_round:
				_auto_test_settled_round = settled_round
				_auto_test_prompt_seen = -1
				if _net_node() != null:
					_net_node().next_round()
			return
		if _auto_test_settled_round != settled_round:
			_auto_test_settled_round = settled_round
			_auto_test_prompt_seen = -1
			_auto_test_completed += 1
			print("[auto-test] round=%d fps=%.1f nodes=%d static_mb=%.1f mode=online" % [
				_auto_test_completed,
				Performance.get_monitor(Performance.TIME_FPS),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				float(OS.get_static_memory_usage()) / (1024.0 * 1024.0),
			])
			if _auto_test_completed >= _auto_test_rounds:
				print("[auto-test] done rounds=", _auto_test_completed)
				_auto_test_rounds = 0
				_auto_test_online_ai = null
			else:
				get_tree().create_timer(0.15).timeout.connect(_auto_test_next)
		return
	if round.phase != RoundState.Phase.PLAYING:
		return
	if not round._awaiting_response.is_empty():
		var response_seat := int(round._awaiting_response.get("seat", -1))
		if response_seat == human_seat and _auto_test_prompt_seen != round.prompt_id:
			_auto_test_prompt_seen = round.prompt_id
			_auto_test_online_response(response_seat, int(round._awaiting_response.get("disc_seat", -1)),
				str(round._awaiting_response.get("tile", "")), round.legal_response_options(response_seat,
					int(round._awaiting_response.get("disc_seat", -1)), str(round._awaiting_response.get("tile", "")),
					int(round._awaiting_response.get("stage", RoundState.ResponseStage.NONE))))
	elif round.awaiting and round.current_turn == human_seat and _auto_test_prompt_seen != round.prompt_id:
		_auto_test_prompt_seen = round.prompt_id
		_auto_test_online_turn(human_seat)

func toggle_ai_proxy() -> void:
	if _net_mode() == "":
		return
	_ai_proxy_active = not _ai_proxy_active
	_clear_ai_teach()
	if _ai_proxy_active:
		var level: String = {"weak": "low", "medium": "medium", "strong": "high"}.get(GameConfig.effective_ai_strength(), "medium")
		_ai_proxy_ai = AiPlayer.new("AI代打", level)
		_ai_proxy_worker = load("res://scripts/core/AiTurnWorker.gd").new()
		_ai_proxy_task = 0
		_ai_proxy_response_pending = false
		_auto_test_prompt_seen = -1
		_auto_test_settled_round = -1
	else:
		_ai_proxy_ai = null
		if _ai_proxy_worker != null:
			var tree := get_tree()
			if tree != null:
				_ai_proxy_worker.stop_async(tree)
			_ai_proxy_worker = null
		_ai_proxy_task = 0
	_refresh_ai_proxy_button()

func _refresh_ai_proxy_button() -> void:
	if _ai_proxy_button == null:
		return
	_ai_proxy_button.text = "AI代打 开" if _ai_proxy_active else "AI代打"
	_ai_proxy_button.tooltip_text = "点击关闭 AI 代打" if _ai_proxy_active else "AI 代替你操作当前座位"

func _submitted_proxy_level() -> String:
	return {"weak": "low", "medium": "medium", "strong": "high"}.get(GameConfig.effective_ai_strength(), "medium")

func _poll_ai_proxy() -> void:
	if _awaiting_rejoin_snapshot or _ai_proxy_task <= 0 or _ai_proxy_worker == null:
		return
	var decision: Dictionary = _ai_proxy_worker.take_result(_ai_proxy_task)
	if decision.is_empty():
		return
	_ai_proxy_task = 0
	if round.phase != RoundState.Phase.PLAYING or round.prompt_id != _auto_test_prompt_seen:
		return
	if _ai_proxy_response_pending:
		var tile := _ai_proxy_response_tile
		_ai_proxy_response_pending = false
		_ai_proxy_response_tile = ""
		_apply_proxy_response_teach(tile, decision)
		_emit_response(tile, decision)
	else:
		_apply_proxy_teach(decision)
		_emit_turn(decision)

func _apply_proxy_response_teach(tile: String, decision: Dictionary) -> void:
	if not _ai_assist_enabled:
		return
	var action := str(decision.get("action", "pass"))
	var label: String = {"win": "胡", "kong": "杠", "pong": "碰", "pass": "过"}.get(action, "过")
	_ai_teach_message = "AI教学：建议%s；当前强度：%s" % [label, _strength_label()]
	_apply_ai_teach_result({"message": _ai_teach_message})
	if _table_actions != null:
		_table_actions._highlight_ai_action_buttons("" if action == "pass" else label)

func _apply_proxy_teach(decision: Dictionary) -> void:
	if not _ai_assist_enabled:
		return
	var result := {}
	var tile := str(decision.get("discard", decision.get("tile", "")))
	if bool(decision.get("self_win", false)):
		result = {"message": "AI教学：建议自摸；当前强度：%s" % _strength_label()}
	elif not decision.get("kong_declares", []).is_empty():
		result = {"tile": str(decision.kong_declares[0]),
			"message": "AI教学：建议暗杠；当前强度：%s" % _strength_label()}
	elif not decision.get("add_kong", []).is_empty():
		result = {"tile": str(decision.add_kong[0]),
			"message": "AI教学：建议加杠；当前强度：%s" % _strength_label()}
	elif tile != "":
		var tiles := _recommendation_tiles(decision)
		if tiles.is_empty():
			tiles = [AiTeaching._display(tile)]
		result = {"tile": tile, "tiles": _recommendation_ids(decision),
			"message": "AI教学：建议打%s；当前强度：%s" % [" / ".join(tiles), _strength_label()]}
	if not result.is_empty():
		_apply_ai_teach_result(result)

func _auto_test_online_turn(seat: int) -> void:
	if round == null:
		return
	if _ai_proxy_active and _ai_proxy_worker != null:
		if _ai_proxy_task > 0:
			_ai_proxy_worker.cancel(_ai_proxy_task)
		_ai_proxy_response_pending = false
		_ai_proxy_task = int(_ai_proxy_worker.submit_turn(round, seat, _submitted_proxy_level()))
		return
	var options: Dictionary = round.legal_turn_options(seat)
	if options.get("self_win", false):
		_emit_turn({"self_win": true})
		return
	var player: PlayerState = round.players[seat]
	var tile := str(player.just_drew)
	if not options.get("discards", []).has(tile):
		if options.get("discards", []).is_empty():
			if _auto_test_online_ai != null:
				_emit_turn(_auto_test_online_ai.decide_turn(round, seat))
			return
		tile = str(options.discards[0])
	_emit_turn({"discard": tile})

func _auto_test_online_response(seat: int, discarded_seat: int, tile: String, options: Dictionary) -> void:
	if _ai_proxy_active and _ai_proxy_worker != null:
		if _ai_proxy_task > 0:
			_ai_proxy_worker.cancel(_ai_proxy_task)
		_ai_proxy_response_pending = true
		_ai_proxy_response_tile = tile
		_ai_proxy_task = int(_ai_proxy_worker.submit_response(round, seat, discarded_seat, tile, options, _submitted_proxy_level()))
		return
	# Auto-play only measures the online/UI frame budget; human input is not AI work.
	_emit_response(tile, {"action": "win"} if options.get("can_win", false) else {"action": "pass"})

func new_game(reset_scores: bool = false, dealer_override: int = -1,
		die_override: int = -1) -> void:
	var scores: Array = []
	var chicken_multiplier := 1 if reset_scores else (round.next_chicken_multiplier if round != null else 1)
	# 单机第一局固定南方玩家坐庄；联机/重开仍按原庄家传递。
	var first_dealer := human_seat if _net_mode() == "" else 0
	var next_dealer := dealer_override if dealer_override >= 0 else (first_dealer if reset_scores else (round.next_dealer_seat if round != null else first_dealer))
	if round != null:
		if not reset_scores:
			for player in round.players:
				scores.append(player.score)
		round.cancel_opening()
	if reset_scores:
		_round_number = 0
	_clear_actions()
	_settlement_animation_controller.reset()
	_settlement_card.hide_post_settlement_controls()
	_settlement_immediate = false
	_declaring_ready = false
	_selected_tile = null
	_round_number += 1
	round = RoundState.new()
	round.pause_after_opening = DisplayServer.get_name() != "headless"
	round.opening_speed = GameConfig.opening_speed_key()
	if _net_mode() == "" and DisplayServer.get_name() != "headless":
		if _ai_service == null:
			_ai_service = load("res://scripts/ai/AiDecisionService.gd").new()
		round.ai_service = _ai_service
	round._recorder.auto_save = true
	_connect_audio_round()
	round.next_chicken_multiplier = chicken_multiplier
	round.next_dealer_seat = next_dealer
	round.require_turn.connect(_on_require_turn)
	round.require_response.connect(_on_require_response)
	round.round_finished.connect(_on_round_finished)
	round.state_update.connect(_queue_refresh)
	var controllers: Array = []
	var ai_level: String = {"weak": "low", "medium": "medium", "strong": "high"}.get(GameConfig.effective_ai_strength(), "low")
	for seat in 4:
		var table_ai := AiPlayer.new("AI%d" % seat, ai_level) if _auto_test_rounds > 0 or seat != human_seat else null
		controllers.append(table_ai)
	round.controllers = controllers
	round.ai_delay_seconds = 0.0 if _auto_test_rounds > 0 else GameConfig.ai_delay_seconds()
	round.ai_response_delay_seconds = 0.0 if _auto_test_rounds > 0 else GameConfig.ai_response_delay_seconds()
	round.opening_delay_seconds = 0.0 if _auto_test_rounds > 0 else (
		GameConfig.opening_wait_seconds(round.opening_speed) \
		if DisplayServer.get_name() != "headless" else 0.0)
	round.randomize_seed()
	# 先带入累计分数，再让新庄家开始行动（AI 庄家也可能马上结算）。
	if scores.size() == 4:
		round.build_players(human_seat)
		round.apply_scores(scores)
	round.start_round(human_seat, die_override)
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
	round.state_update.connect(_queue_refresh)
	if round.phase != RoundState.Phase.IDLE:
		_prime_opening_visuals()
		_on_net_prompt(human_seat)
		_refresh()
	network.connection_error.connect(_on_connection_error)
	network.lobby_updated.connect(_on_net_lobby_updated)

func _setup_client_view() -> void:
	var network = _net_node()
	round = network.game
	_connect_audio_round()
	_round_number = network.round_number
	_awaiting_rejoin_snapshot = round.phase == RoundState.Phase.IDLE
	network.room_ready.connect(func(seat):
		human_seat = seat
		if _awaiting_rejoin_snapshot:
			if _connection_overlay != null: _connection_overlay.show_syncing()
		elif _connection_overlay != null:
			_connection_overlay.close()
		_refresh())
	network.state_updated.connect(_on_client_state_updated)
	network.prompted.connect(_on_net_prompt)
	network.connection_error.connect(_on_connection_error)
	network.reconnecting.connect(func(attempt, maximum):
		_awaiting_rejoin_snapshot = true
		_table_animation_controller.cancel()
		_settlement_animation_controller.reset()
		_settlement_card.hide_post_settlement_controls()
		round._presentation.sync_initialized = false
		_selecting = false
		_clear_actions()
		status_label.hide()
		if _connection_overlay != null: _connection_overlay.show_reconnecting(attempt, maximum))
	network.lobby_updated.connect(_on_net_lobby_updated)
	enable_net(network.submit_client_turn, network.submit_client_response)
	if network.my_seat >= 0:
		human_seat = network.my_seat
	_prime_opening_visuals()
	_refresh()
	_on_net_prompt(human_seat)

func _prime_opening_visuals() -> void:
	# The lobby may hand us the first snapshot before the table has connected.
	# Prime the opening before the first hand refresh; otherwise the final hand
	# is painted for one frame and immediately replaced by the deal animation.
	if _opening_primed or round == null: return
	if round.phase not in [RoundState.Phase.DEALING, RoundState.Phase.PLAYING] or round.players.size() != 4: return
	for player in round.players:
		if player.discard_count > 0 or not player.melds.is_empty():
			_opening_primed = true
			_table_animation_controller.recover_after_resume()
			return
	if round.phase == RoundState.Phase.PLAYING and (not round.visual_events.any(func(event): return event.get("type", "") == "deal_batch") \
			or round.visual_events.any(func(event): return event.get("type", "") == "draw")):
		_opening_primed = true
		_table_animation_controller.recover_after_resume()
		return
	_opening_primed = true
	for event in round.visual_events: _on_visual_event(event)

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_flush_refresh")

func _flush_refresh() -> void:
	_refresh_queued = false
	_refresh()

func _refresh() -> void:
	if round == null or _awaiting_rejoin_snapshot:
		return
	_sync_settlement_round()
	if not _landscape:
		_layout()
	if round.phase != RoundState.Phase.SETTLED:
		_settlement_card.hide_post_settlement_controls()
	elif _settlement_immediate:
		# A restored settlement is a final snapshot, including any queued play
		# visuals received before this table connected to the network.
		_table_animation_controller.cancel()
	_layout_actions()
	if _new_areas == null or DisplayServer.get_name() == "headless":
		# 正式运行只用 V2；headless 旧回归仍需要旧牌区节点。
		for seat in 4: _player_tile_areas._refresh_identity(seat)
		_prepare_exposed_layouts()
		for seat in 4:
			if _table_animation_controller.holds_seat_refresh(seat) or _table_animation_controller.sorting_active():
				_player_tile_areas._refresh_exposed(seat)
				_player_tile_areas._refresh_discards(seat)
				continue
			_refresh_seat(seat)
		_player_tile_areas.refresh_ready_frames()
		_refresh_center()
		_refresh_status()
		_table_animation_controller.refresh_masks()
	if _new_areas != null:
		_new_areas.refresh()
		_new_areas.sync_animation_proxies()
	_update_interactivity()
	if _table_layout != null:
		# V2 始终是唯一牌桌画面；结算卡/结算动画仍是独立覆盖层。
		if _new_areas != null:
			_new_areas.show()
			_new_areas.adopt_action_bar(_table_actions.action_bar)
			_new_areas.adopt_settlement_node(_settlement_card._post_controls)
		_table_layout._hide_legacy_visuals(_player_tile_areas)
		_table_actions._layout_actions()
	queue_redraw()
	if round.phase == RoundState.Phase.SETTLED and round.players.size() == 4 \
			and not _table_animation_controller.has_pending():
		var immediate := _settlement_immediate
		_settlement_immediate = false
		if _new_areas != null and DisplayServer.get_name() != "headless":
			_new_areas.start_native_settlement(immediate)
		elif not _settlement_animation_controller.has_started():
			_start_settlement_animation(immediate)
	if _new_areas == null or DisplayServer.get_name() == "headless":
		# 旧结算控制器仅用于无 V2 的 headless/兼容路径；图形模式由 V2 独占。
		_settlement_animation_controller.apply_displays()
	if round.phase == RoundState.Phase.SETTLED and _settlement_animation_done():
		# Completion and the next network snapshot can arrive in either order.
		# Keep the post-settlement controls visible once the preview is done.
		_settlement_card.show_post_settlement_controls()
	_refresh_next_round_controls()
func _sync_settlement_round() -> void:
	# Clients and hosts reuse RoundState between rounds. Object identity alone
	# would leave the previous completed animation (and invisible rivers) alive.
	var number: int = _round_number if _net_mode() == "" else _net_node().round_number
	var changed := _settlement_round_id != round.get_instance_id() \
		or _settlement_session != round.audio_session \
		or _settlement_round_number != number \
		or (_settlement_phase == RoundState.Phase.SETTLED and round.phase != RoundState.Phase.SETTLED)
	if changed:
		_settlement_animation_controller.reset()
		_settlement_card.hide_post_settlement_controls()
		_seat_visual_keys.clear()
		_settlement_immediate = round.phase == RoundState.Phase.SETTLED
		if _new_areas != null and _new_areas.has_method("reset_native_settlement"):
			_new_areas.reset_native_settlement()
	elif _settlement_phase == RoundState.Phase.IDLE and round.phase == RoundState.Phase.SETTLED:
		_settlement_immediate = true
	_settlement_round_id = round.get_instance_id()
	_settlement_session = round.audio_session
	_settlement_round_number = number
	_settlement_phase = round.phase

func _refresh_center() -> void:
	# 中央 168×168 只负责骰子；不再写余牌/局数标签。
	_table_layout.refresh_turn_indicator()

func _set_ai_strength(strength_key: String) -> void:
	if _net_mode() == "" and round != null:
		for actor in round.controllers:
			if actor is AiPlayer: actor.set_difficulty({"weak": "low", "medium": "medium", "strong": "high"}.get(strength_key, "medium"))

func _set_ai_speed(speed_key: String) -> void:
	var persist := _sound_settings == null or _sound_settings.persist_changes
	if _net_mode() == "":
		GameConfig.set_ai_speed(speed_key, persist)
		if round != null:
			round.ai_delay_seconds = GameConfig.ai_delay_seconds()
			round.ai_response_delay_seconds = GameConfig.ai_response_delay_seconds()
	elif _net_node().is_room_owner():
		GameConfig.set_ai_speed(speed_key, persist)
		_net_node().set_ai_speed(speed_key)

func _seat_name(seat: int) -> String:
	if seat < 0 or seat > 3:
		return "-"
	if _net_mode() != "" and round != null and seat < round.players.size():
		var player_name := str(round.players[seat].name_label).strip_edges()
		if player_name != "": return player_name
	return ["你", "下家", "对家", "上家"][_relative_seat(seat)]

func _refresh_status() -> void:
	if _ai_assist_enabled and _ai_teach_message != "":
		status_label.text = _ai_teach_message
		status_label.show()
		return
	status_label.text = ""
	status_label.hide()

func _on_client_state_updated() -> void:
	# 普通快照保留正在播放的视觉队列；重连回调单独清理并跳过历史。
	if _awaiting_rejoin_snapshot:
		if _opening_primed:
			_table_animation_controller.recover_after_resume()
		_settlement_immediate = round.phase == RoundState.Phase.SETTLED
		_awaiting_rejoin_snapshot = false
		if _ai_proxy_worker != null and _ai_proxy_task > 0:
			_ai_proxy_worker.cancel(_ai_proxy_task)
		_ai_proxy_task = 0
		_ai_proxy_response_pending = false
		_ai_proxy_response_tile = ""
		_auto_test_prompt_seen = -1
		if _connection_overlay != null: _connection_overlay.close()
		status_label.hide()
	_selecting = false
	_response_disc = ""
	_clear_actions()
	# The first client snapshot can arrive after the table scene is ready. Prime
	# its untouched opening before the hand refresh exposes the final deal.
	_prime_opening_visuals()
	_refresh()
	_on_opening_visual_finished()

func _on_net_lobby_updated() -> void:
	_on_settlement_speed_changed()
	if _sound_settings != null: _sound_settings.sync_timing_controls()
	_refresh_next_round_controls()
	var net = _net_node()
	if net != null and bool(net.test_mode) != _test_mode_ui:
		_test_mode_ui = bool(net.test_mode)
		_layout()

	if net != null and net.lobby is Dictionary and net.lobby.has("return_vote"):
		_on_return_vote_updated(net.lobby.get("return_vote", {}))
	_refresh_test_pattern_ui()

func _on_opening_visual_finished() -> void:
	if round == null or _new_areas == null or not _new_areas._sort_started \
			or _new_areas._sort_animating or _table_animation_controller.deal_sequence_active(): return
	var session := round.audio_session
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	if round == null or round.audio_session != session: return
	if _net_mode() != "":
		var net = _net_node()
		if net != null: net.report_opening_finished()
	else:
		round.resume_after_opening()

func _on_net_prompt(seat: int) -> void:
	if seat != human_seat or seat >= round.players.size():
		return
	var response: Dictionary = round._awaiting_response
	if not response.is_empty():
		if int(response.get("seat", -1)) == human_seat:
			var tile: String = response.tile
			var options := round.legal_response_options(seat, int(response.get("disc_seat", -1)), tile, int(response.get("stage", RoundState.ResponseStage.NONE)))
			_on_require_response(seat, response.disc_seat, tile, options)
	elif round.awaiting and round._awaiting_response.is_empty() \
		and round.current_turn == human_seat and round.phase == RoundState.Phase.PLAYING \
		and str(round.allowed_actions(seat).get("kind", "")) == "turn":
		_on_require_turn(seat)
	_update_interactivity()

func _on_round_finished(_result: Dictionary) -> void:
	_clear_ai_teach()
	_selecting = false
	_response_disc = ""
	_clear_actions()
	_refresh()
	if _auto_test_rounds > 0 and _net_mode() == "":
		_auto_test_prompt_seen = -1
		_auto_test_completed += 1
		print("[auto-test] round=%d fps=%.1f nodes=%d static_mb=%.1f mode=%s" % [
			_auto_test_completed,
			Performance.get_monitor(Performance.TIME_FPS),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			float(OS.get_static_memory_usage()) / (1024.0 * 1024.0),
			"online" if _net_mode() != "" else "offline",
		])
		if _auto_test_completed < _auto_test_rounds:
			get_tree().create_timer(0.15).timeout.connect(_auto_test_next)
		else:
			print("[auto-test] done rounds=", _auto_test_completed)
			_auto_test_rounds = 0
			_auto_test_completed = 0
			_auto_test_online_ai = null

func _auto_test_next() -> void:
	if _auto_test_rounds > 0 and is_inside_tree():
		if _net_mode() != "":
			var net = _net_node()
			if net != null:
				net.next_round()
		else:
			new_game()

func _on_connection_error(message: String) -> void:
	_selecting = false
	_clear_actions()
	status_label.hide()
	if _connection_overlay != null:
		_connection_overlay.show_error(message)

func _retry_connection() -> void:
	var net = _net_node()
	if net == null or not net.retry_connection():
		if _connection_overlay != null:
			_connection_overlay.show_error("当前没有可恢复的原房间，请返回大厅重新加入。")
		return
	if _connection_overlay != null:
		_connection_overlay.show_reconnecting(0, 5)

func _on_input_focus_changed() -> void:
	# Windows may omit the release when Alt-Tab interrupts a click. With
	# emulate_touch_from_mouse enabled, that also leaves a held touch index
	# which suppresses the next mouse AND touch press. Drop only the gesture;
	# preserve prompts, ready selection, and authoritative animation locks.
	_table_actions._reset_press()
	_last_tile_input_ms = -1000
	if is_node_ready(): _update_interactivity()

func _notification(what: int) -> void:
	if GameConfig.debug_enabled and what in [NOTIFICATION_APPLICATION_FOCUS_OUT,
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_PAUSED,
		NOTIFICATION_APPLICATION_RESUMED]:
		print("[debug] GameTable notification=", what, " turn=", human_seat,
			" selecting=", _selecting, " locked=", _table_actions != null and _table_actions.input_locked())
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_IN,
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED]:
		_on_input_focus_changed()
	if what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN] and not _quitting and round != null:
		# Android can lose the pressed-touch/UI prompt while backgrounded.
		# Re-arm the current authoritative prompt after returning to foreground,
		# then safely skip any animation that did not resume within a short
		# grace period (Tweens may be frozen while the process is stopped).
		call_deferred("_on_net_prompt", human_seat)
		_resume_generation += 1
		_arm_resume_animation_recovery(_resume_generation)
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _sound_settings != null and _sound_settings.is_open():
			_sound_settings.close()
		else:
			_confirm_quit()

func _arm_resume_animation_recovery(generation: int) -> void:
	await get_tree().create_timer(0.45).timeout
	if generation != _resume_generation or _quitting or round == null:
		return
	if _awaiting_rejoin_snapshot:
		return
	var v2_stuck: bool = _new_areas != null and _new_areas.has_method("visual_recovery_pending") \
		and _new_areas.visual_recovery_pending()
	if _table_animation_controller.input_locked() or v2_stuck:
		if _new_areas != null and _new_areas.has_method("recover_after_resume"):
			_new_areas.recover_after_resume()
		_table_animation_controller.recover_after_resume()
		_on_opening_visual_finished()
		_refresh()
		_on_net_prompt(human_seat)
		_update_interactivity()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _sound_settings.is_open(): _sound_settings.close()
		else: _confirm_quit()
		get_viewport().set_input_as_handled()

func _on_quit(forget_connection: bool = true) -> void:
	if _quitting: return
	_quitting = true
	if round != null: round.export_replay()
	quit_to_menu.emit()
	if _net_mode() != "":
		if forget_connection: await Network.leave_room()
		else: Network.reset()
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _export_current_replay() -> void:
	_sound_settings.export_replay(round, human_seat)

func _confirm_quit() -> void:
	_sound_settings.confirm_exit()
