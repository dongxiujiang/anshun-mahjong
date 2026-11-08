extends Control
## Read-only player score inspection. The detail panel occupies the cleared river.

const DETAILS := preload("res://scripts/ui/table/SettlementScoreDetails.gd")
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")

var _view_ref: WeakRef
var _groups: Array
var _win_parts: Dictionary = {}
var _multiplier: int
var _called: Array
var _seat_details: Dictionary = {}
var _hit_buttons: Dictionary = {}
var _selected := -1
var _detail_panel: Panel
var _heading: Label
var _breakdown: Label
var _scroll: ScrollContainer

func _init(view: Control, result: Dictionary, meta: Dictionary, players: Array, plan: Dictionary) -> void:
	_view_ref = weakref(view)
	name = "ScoreInspection"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = UI.DESIGN_SIZE
	DETAILS.set_debug_enabled(GameConfig.debug_enabled)
	_groups = DETAILS.build(result, meta, players, plan)
	_multiplier = maxi(1, int(meta.get("chicken_multiplier", 1)))
	_called = plan.called.duplicate()
	for seat in 4:
		var parts := {}
		for stage in plan.stages:
			if stage.key != "win" or int(stage.winner) != seat:
				continue
			for row in stage.transfers:
				var reason := str(row.reason)
				var label := str({"报听胡牌": "报听", "自摸基础分": "自摸", "抢杠胡基础分": "抢杠",
					"点炮基础分（叫牌）": "点炮", "点炮基础分（未叫牌）": "点炮"}.get(reason, reason))
				parts[label] = float(row.amount)
		for row in result.get("transfers", []):
			if int(row.to) == seat and str(row.reason) in ["荒牌牌型分", "荒牌基础补付"]:
				parts[str(row.reason)] = float(row.amount)
		_win_parts[seat] = parts

func _ready() -> void:
	var view = _view_ref.get_ref()
	var settlement: Rect2 = view._native_settlement.get_rect()
	_detail_panel = Panel.new()
	_detail_panel.name = "PlayerScoreDetail"
	_detail_panel.position = settlement.position - Vector2(0, 244)
	_detail_panel.size = Vector2(settlement.size.x, 232)
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
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(24, 48)
	_scroll.size = Vector2(settlement.size.x - 48, 172)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(_scroll)
	_breakdown = view._table_text(_scroll, "", 24, UI.INK)
	_breakdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_seat_details.clear()
	for seat in 4:
		var parts: Dictionary = _win_parts.get(seat, {}).duplicate()
		for group in _groups:
			if int(group.seat) != seat or group.stages.is_empty():
				continue
			if group.area == "meld":
				var tile_name: String = view._tile_short(str(group.tiles[0]))
				for label in group.inspection_parts:
					var term := tile_name + " · " + str(label)
					parts[term] = float(parts.get(term, 0.0)) + float(group.inspection_parts[label])
			else:
				for key in group.tile_scores:
					var score: Dictionary = group.tile_scores[key]
					var charged: bool = str(key).ends_with(":charge")
					var card := str(key).trim_suffix(":charge")
					var copies: int = group.tiles.count(card)
					if group.tile_scores.has(card + ":charge"):
						copies = 1 if charged else copies - 1
					var tile_name: String = "幺鸡" if card == "tiao1" else ("八筒" if card == "tong8" else view._tile_short(card))
					var term := tile_name + " · " + str(score.label)
					parts[term] = float(parts.get(term, 0.0)) + float(score.amount) * copies
		var relative: String = ["你", "上家", "对家", "下家"][posmod(seat - view.human_seat, 4)]
		var names: Dictionary = view._seat_display_names(view.snapshot.get("seats", []))
		var player_name := str(names.get(seat, relative))
		var title := relative if player_name == relative else relative + " · " + player_name
		_seat_details[seat] = {"title": title + " · 得分明细（单倍）", "parts": parts, "called": bool(_called[seat])}
		var bounds := Rect2()
		var has_hand := false
		for tile in view._native_tiles_for_seat(seat):
			if not tile.is_visible_in_tree() or str(tile.get_meta("new_kind", "")) not in ["hand", "draw"]:
				continue
			var local: Transform2D = get_global_transform().affine_inverse() * tile.get_global_transform()
			var rect: Rect2 = local * Rect2(Vector2.ZERO, tile.size)
			bounds = bounds.merge(rect) if has_hand else rect
			has_hand = true
		var button := _hit_button(seat)
		button.visible = has_hand
		button.position = bounds.position
		button.size = bounds.size
	if _selected in range(4):
		_show_seat(_selected)

func _hit_button(id: int) -> Button:
	if _hit_buttons.has(id):
		return _hit_buttons[id]
	var button := Button.new()
	button.name = "InspectPlayer_%d" % id
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.pressed.connect(_select_seat.bind(id))
	add_child(button)
	_hit_buttons[id] = button
	return button

func _select_seat(seat: int) -> void:
	_show_seat(seat)

func _show_seat(seat: int) -> void:
	if not _seat_details.has(seat):
		return
	var changed := _selected != seat
	_selected = seat
	var detail: Dictionary = _seat_details[seat]
	_heading.text = detail.title
	var terms: Array[String] = []
	var total := 0.0
	for label in detail.parts:
		var amount := float(detail.parts[label]) / _multiplier
		total += amount
		terms.append("%s %.0f分" % [label, amount])
	var status := "叫牌" if detail.called else "未叫牌"
	if terms.is_empty() or is_zero_approx(total):
		status += "0分"
	elif not detail.called:
		status += "%.0f分" % total
	terms.push_front(status)
	_breakdown.text = "\n".join(terms)
	if changed:
		_scroll.scroll_vertical = 0
	_detail_panel.show()

func _hide_detail() -> void:
	_selected = -1
	_detail_panel.hide()
