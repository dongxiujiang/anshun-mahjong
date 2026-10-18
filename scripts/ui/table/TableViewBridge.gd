extends Control
## 组件宿主和旧 UI 接口桥接；这里只保留转发，不实现布局或交互。
## 联机与既有测试仍可访问原字段；尺寸/颜色数值只在 TableUiConfig 定义。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const LAYOUT := preload("res://scripts/ui/table/TableLayout.gd")
const PLAYER_AREAS := preload("res://scripts/ui/table/PlayerTileAreas.gd")
const ACTIONS_UI := preload("res://scripts/ui/table/TableActions.gd")
const SETTLEMENT_UI := preload("res://scripts/ui/table/SettlementCard.gd")
const ANIMATIONS := preload("res://scripts/ui/table/TableAnimationController.gd")
const SETTLEMENT_ANIMATIONS := preload("res://scripts/ui/table/SettlementAnimationController.gd")
const WIDGETS := preload("res://scripts/ui/table/TableWidgets.gd")

var _table_layout = LAYOUT.new(self)
var _player_tile_areas = PLAYER_AREAS.new(self)
var _table_actions = ACTIONS_UI.new(self)
var _settlement_card = SETTLEMENT_UI.new(self)
var _table_animation_controller = ANIMATIONS.new(self)
var _settlement_animation_controller = SETTLEMENT_ANIMATIONS.new(self)
var _table_widgets = WIDGETS.new()

## The table is deliberately designed in landscape.  Both the desktop build and
## Android use this same canvas so a device rotation never switches to the old
## portrait table.
const DESIGN_SIZE := UI.DESIGN_SIZE
## Reference origin for the small center-panel labels authored before landscape.
const TABLE_CENTER := UI.TABLE_CENTER
const LANDSCAPE_SIZE := UI.LANDSCAPE_SIZE
const LANDSCAPE_CENTER := UI.LANDSCAPE_CENTER
const LANDSCAPE_RESULT_SIZE := UI.LANDSCAPE_RESULT_SIZE
const TILE_UNIT := UI.TILE_UNIT
const RIVER_TILE_UNIT := UI.RIVER_TILE_UNIT
const PLAYER_TILE_UNIT := UI.PLAYER_TILE_UNIT
const OWN_PLAYER_TILE_UNIT := UI.OWN_PLAYER_TILE_UNIT
const OWN_HAND_TILE_UNIT := UI.OWN_HAND_TILE_UNIT
const ACTION_BUTTON_SIZE := UI.ACTION_BUTTON_SIZE
const DISCARD_BUTTON_SIZE := UI.DISCARD_BUTTON_SIZE
const ACTION_HAND_GAP := UI.ACTION_HAND_GAP
## 结算卡片里的牌图单独放大，便于看清是哪张牌。
const RESULT_TILE_UNIT := UI.RESULT_TILE_UNIT
const RESULT_CARD_SIZE := UI.RESULT_CARD_SIZE
const RESULT_TOGGLE_SIZE := UI.RESULT_TOGGLE_SIZE
const RESULT_TOGGLE_LOCAL_POSITION := UI.RESULT_TOGGLE_LOCAL_POSITION
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
var wall_box: Dictionary:
	get: return _player_tile_areas.wall_box
	set(value): _player_tile_areas.wall_box = value
var seat_roots: Dictionary:
	get: return _player_tile_areas.seat_roots
	set(value): _player_tile_areas.seat_roots = value
var wind_labels: Dictionary:
	get: return _player_tile_areas.wind_labels
	set(value): _player_tile_areas.wind_labels = value
var avatars: Dictionary:
	get: return _player_tile_areas.avatars
	set(value): _player_tile_areas.avatars = value
var status_label: Label:
	get: return _table_layout.status_label
	set(value): _table_layout.status_label = value
var action_bar: HBoxContainer:
	get: return _table_actions.action_bar
	set(value): _table_actions.action_bar = value
var center_info: Label:
	get: return _table_layout.center_info
	set(value): _table_layout.center_info = value
var round_label: Label:
	get: return _table_layout.round_label
	set(value): _table_layout.round_label = value
var surface: Control:
	get: return _table_layout.surface
	set(value): _table_layout.surface = value
var result_layer: Control:
	get: return _settlement_card.result_layer
	set(value): _settlement_card.result_layer = value
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
var _result_shown: bool:
	get: return _settlement_card._result_shown
	set(value): _settlement_card._result_shown = value
var _felt: NoiseTexture2D:
	get: return _table_layout._felt
	set(value): _table_layout._felt = value
var _result_panel: Control:
	get: return _settlement_card._result_panel
	set(value): _settlement_card._result_panel = value
var _result_shade: ColorRect:
	get: return _settlement_card._result_shade
	set(value): _settlement_card._result_shade = value
var _result_restore: Button:
	get: return _settlement_card._result_restore
	set(value): _settlement_card._result_restore = value
var _next_round_button: Button:
	get: return _settlement_card._next_round_button
	set(value): _settlement_card._next_round_button = value
var _next_round_status: Label:
	get: return _settlement_card._next_round_status
	set(value): _settlement_card._next_round_status = value
var _next_round_hint: Label:
	get: return _settlement_card._next_round_hint
	set(value): _settlement_card._next_round_hint = value
var _post_controls: Panel:
	get: return _settlement_card._post_controls
	set(value): _settlement_card._post_controls = value
var _post_view_button: Button:
	get: return _settlement_card._post_view_button
	set(value): _settlement_card._post_view_button = value
var _post_next_button: Button:
	get: return _settlement_card._post_next_button
	set(value): _settlement_card._post_next_button = value
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
var _remaining_label: Label:
	get: return _table_layout._remaining_label
	set(value): _table_layout._remaining_label = value
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

func _start_settlement_animation() -> void:
	_settlement_animation_controller.start()

func _on_settlement_animation_finished() -> void:
	_settlement_card.show_post_settlement_controls()
	_update_interactivity()

func _settlement_animation_active() -> bool:
	return _settlement_animation_controller.is_active()

func _settlement_animation_started() -> bool:
	return _settlement_animation_controller.has_started()

func _settlement_animation_done() -> bool:
	return _settlement_animation_controller.is_completed()

func _skip_settlement_animation() -> void:
	_settlement_animation_controller.skip()

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

func _result_card_size() -> Vector2:
	return _settlement_card._result_card_size()

func _result_toggle_position() -> Vector2:
	return _settlement_card._result_toggle_position()

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

func _wall_stacks(seat: int) -> Array:
	return _player_tile_areas._wall_stacks(seat)

func _refresh_walls() -> void:
	_player_tile_areas._refresh_walls()

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

func _draw_result_title() -> String:
	return _settlement_card._draw_result_title()

func _show_result() -> void:
	_settlement_card._show_result()

func _draw_result_details(row: Control, seat: int, status: String, list: Array, winner: int) -> void:
	_settlement_card._draw_result_details(row, seat, status, list, winner)

func _result_sideways_index(item: Dictionary, seat: int) -> int:
	return _settlement_card._result_sideways_index(item, seat)

func _result_group_note(item: Dictionary, seat: int) -> String:
	return _settlement_card._result_group_note(item, seat)

func _draw_result_group(flow: HFlowContainer, item: Dictionary, seat: int, max_width: float) -> void:
	_settlement_card._draw_result_group(flow, item, seat, max_width)

func _ensure_restore_button() -> void:
	_settlement_card._ensure_restore_button()

func panel_position_for_result_toggle() -> Vector2:
	return _settlement_card.panel_position_for_result_toggle()

func _toggle_result_panel(show_card: bool) -> void:
	_settlement_card._toggle_result_panel(show_card)

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
