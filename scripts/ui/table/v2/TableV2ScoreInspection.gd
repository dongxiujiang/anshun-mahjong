extends Control
## Read-only tile score inspection. The detail panel occupies the cleared river.

const DETAILS := preload("res://scripts/ui/table/SettlementScoreDetails.gd")
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")

var _view_ref: WeakRef
var _groups: Array
var _win_parts: Dictionary = {}
var _multiplier: int
var _tile_details: Dictionary = {}
var _hit_buttons: Dictionary = {}
var _selected := -1
var _detail_panel: Panel
var _heading: Label
var _breakdown: Label

func _init(view: Control, result: Dictionary, meta: Dictionary, players: Array, plan: Dictionary) -> void:
	_view_ref = weakref(view)
	name = "ScoreInspection"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = UI.DESIGN_SIZE
	DETAILS.set_debug_enabled(GameConfig.debug_enabled)
	_groups = DETAILS.build(result, meta, players, plan)
	_multiplier = maxi(1, int(meta.get("chicken_multiplier", 1)))
	for stage in plan.stages:
		if stage.key == "win" and not stage.transfers.is_empty():
			var parts := {}
			for row in stage.transfers:
				var reason := str(row.reason)
				var label := str({"报听胡牌": "报听", "自摸基础分": "自摸", "抢杠胡基础分": "抢杠",
					"点炮基础分（叫牌）": "点炮", "点炮基础分（未叫牌）": "点炮"}.get(reason, reason))
				# A transfer already carries the amount from one payer.
				parts[label] = float(row.amount)
			_win_parts[int(stage.winner)] = parts

func _ready() -> void:
	var view = _view_ref.get_ref()
	var settlement: Rect2 = view._native_settlement.get_rect()
	_detail_panel = Panel.new()
	_detail_panel.name = "TileScoreDetail"
	_detail_panel.position = settlement.position - Vector2(0, 128)
	_detail_panel.size = Vector2(settlement.size.x, 116)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#102c24")
	style.border_color = Color(UI.GOLD, 0.65)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	_detail_panel.add_theme_stylebox_override("panel", style)
	add_child(_detail_panel)
	_heading = view._table_text(_detail_panel, "", 24, UI.GOLD)
	_heading.position = Vector2(24, 8)
	_heading.size = Vector2(settlement.size.x - 100, 36)
	_breakdown = view._table_text(_detail_panel, "", 24, UI.INK)
	_breakdown.position = Vector2(24, 44)
	_breakdown.size = Vector2(settlement.size.x - 48, 64)
	_breakdown.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_breakdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "关闭得分明细"
	close.focus_mode = Control.FOCUS_NONE
	close.position = Vector2(settlement.size.x - 66, 8)
	close.size = Vector2(48, 38)
	close.pressed.connect(_hide_detail)
	_detail_panel.add_child(close)
	_detail_panel.hide()
	refresh()

func refresh() -> void:
	var view = _view_ref.get_ref()
	if not is_instance_valid(view):
		return
	_tile_details.clear()
	for seat in 4:
		for tile in view._native_tiles_for_seat(seat):
			if not tile.face_up or not tile.is_visible_in_tree():
				continue
			var area := str(tile.get_meta("new_kind", ""))
			var meld_index := int(tile.get_meta("meld_index", -1))
			if area == "red":
				area = "meld" if meld_index >= 0 else "chicken"
			var in_hand := area in ["hand", "draw"]
			var areas := ["hand", "draw"] if in_hand else [area]
			var parts: Dictionary = _win_parts.get(seat, {}).duplicate() if area == "draw" else {}
			var key := DETAILS.tile_detail_key(tile.tile, bool(tile.get_meta("v2_charge", false)))
			for group in _groups:
				if int(group.seat) != seat or group.area not in areas or group.stages.is_empty():
					continue
				if area == "meld" and int(group.meld_index) == meld_index:
					parts.merge(group.inspection_parts)
				elif area != "meld" and group.tile_scores.has(key):
					var score: Dictionary = group.tile_scores[key]
					var copies: int = group.tiles.count(tile.tile) if in_hand else 1
					parts[score.label] = float(parts.get(score.label, 0.0)) + float(score.amount) * copies
			if parts.is_empty():
				continue
			var title: String = "幺鸡" if tile.tile == "tiao1" else ("八筒" if tile.tile == "tong8" else view._tile_short(tile.tile))
			var id: int = tile.get_instance_id()
			_tile_details[id] = {"title": title, "parts": parts}
			var button := _hit_button(id)
			var local: Transform2D = get_global_transform().affine_inverse() * tile.get_global_transform()
			var bounds: Rect2 = local * Rect2(Vector2.ZERO, tile.size)
			button.position = bounds.position
			button.size = bounds.size
	for id in _hit_buttons.keys():
		if not _tile_details.has(id):
			var button: Button = _hit_buttons[id]
			remove_child(button)
			button.queue_free()
			_hit_buttons.erase(id)
	if not _tile_details.has(_selected):
		_hide_detail()

func _hit_button(id: int) -> Button:
	if _hit_buttons.has(id):
		return _hit_buttons[id]
	var button := Button.new()
	button.name = "InspectTile_%d" % id
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(_select_tile.bind(id))
	add_child(button)
	_hit_buttons[id] = button
	return button

func _select_tile(id: int) -> void:
	if id == _selected or not _tile_details.has(id):
		_hide_detail()
		return
	_selected = id
	var detail: Dictionary = _tile_details[id]
	_heading.text = detail.title
	var labels: Array = detail.parts.keys()
	if labels.has("杠"):
		labels.erase("杠")
		labels.push_front("杠")
	var terms: Array[String] = []
	for label in labels:
		terms.append("%s%.0f分" % [label, float(detail.parts[label]) / _multiplier])
	_breakdown.text = "　".join(terms)
	_detail_panel.show()

func _hide_detail() -> void:
	_selected = -1
	_detail_panel.hide()
