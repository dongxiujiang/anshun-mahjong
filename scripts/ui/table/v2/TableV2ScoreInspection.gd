extends Control
## Read-only tile score inspection. The detail panel occupies the cleared river.

const DETAILS := preload("res://scripts/ui/table/SettlementScoreDetails.gd")
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")

var _view_ref: WeakRef
var _groups: Array
var _win_details: Dictionary = {}
var _tile_details: Dictionary = {}
var _hit_buttons: Dictionary = {}
var _selected := -1
var _detail_panel: Panel
var _heading: Label
var _total: Label
var _body: RichTextLabel

func _init(view: Control, result: Dictionary, meta: Dictionary, players: Array, plan: Dictionary) -> void:
	_view_ref = weakref(view)
	name = "ScoreInspection"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = UI.DESIGN_SIZE
	DETAILS.set_debug_enabled(GameConfig.debug_enabled)
	_groups = DETAILS.build(result, meta, players, plan)
	for stage in plan.stages:
		if stage.key != "win":
			continue
		if not stage.transfers.is_empty():
			var seat := int(stage.winner)
			_win_details[seat] = _winning_tile_detail(stage.transfers, seat, bool(meta.get("self_draw", false)))

static func _winning_tile_detail(rows: Array, seat: int, self_draw: bool) -> Dictionary:
	var by_reason := {}
	var total := 0.0
	for row in rows:
		var reason := str(row.reason)
		var payer := int(row.from)
		var amount := float(row.amount)
		if not by_reason.has(reason):
			by_reason[reason] = {}
		by_reason[reason][payer] = float(by_reason[reason].get(payer, 0.0)) + amount
		total += amount
	var lines: Array[String] = []
	for reason in by_reason:
		var by_amount := {}
		for offset in [1, 2, 3]:
			var payer := posmod(seat + offset, 4)
			if not by_reason[reason].has(payer):
				continue
			var amount: float = by_reason[reason][payer]
			if not by_amount.has(amount):
				by_amount[amount] = []
			by_amount[amount].append(["上家", "对家", "下家"][offset - 1])
		for amount in by_amount:
			var payers: Array = by_amount[amount]
			var payer_text := "三家各付" if payers.size() == 3 else "、".join(payers) + ("各付" if payers.size() > 1 else "付")
			if self_draw:
				payer_text = "自摸 · " + payer_text
			var label := "报听" if reason == "报听胡牌" else str(reason)
			lines.append("%s %+.0f（%s）" % [label, amount, payer_text])
	return {"text": "\n".join(lines), "total": total}

func _ready() -> void:
	var view = _view_ref.get_ref()
	var settlement: Rect2 = view._native_settlement.get_rect()
	_detail_panel = Panel.new()
	_detail_panel.name = "TileScoreDetail"
	_detail_panel.position = settlement.position - Vector2(0, 138)
	_detail_panel.size = Vector2(settlement.size.x, 126)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#102c24")
	style.border_color = Color(UI.GOLD, 0.65)
	style.set_border_width_all(2)
	style.set_corner_radius_all(16)
	_detail_panel.add_theme_stylebox_override("panel", style)
	add_child(_detail_panel)
	_heading = view._table_text(_detail_panel, "", 24, UI.GOLD)
	_heading.position = Vector2(24, 8)
	_heading.size = Vector2(settlement.size.x - 434, 35)
	_heading.clip_text = true
	_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_total = view._table_text(_detail_panel, "", 24, UI.SCORE_GAIN)
	_total.position = Vector2(settlement.size.x - 390, 8)
	_total.size = Vector2(308, 35)
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_body = RichTextLabel.new()
	_body.position = Vector2(24, 43)
	_body.size = Vector2(settlement.size.x - 48, 74)
	_body.add_theme_font_override("normal_font", TileView._font())
	_body.add_theme_font_size_override("normal_font_size", 24)
	_body.add_theme_color_override("default_color", UI.INK)
	_detail_panel.add_child(_body)
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
			var lines: Array[String] = []
			var title: String = view._tile_short(tile.tile)
			var total := 0.0
			var total_caption := "分项合计" if area == "meld" else "合计"
			for group in _groups:
				if int(group.seat) != seat or group.area != area or group.stages.is_empty():
					continue
				if area == "meld":
					if int(group.meld_index) == meld_index:
						title = str(group.title) + " " + title
						lines.append(str(group.inspection))
						total += float(group.inspection_total)
				else:
					var key := DETAILS.tile_detail_key(tile.tile, bool(tile.get_meta("v2_charge", false)))
					if group.tile_details.has(key):
						lines.append(str(group.tile_details[key]))
						var value := float(group.tile_scores[key])
						total += value
						if area == "chicken" and value < 0.0:
							total_caption = "每位叫牌者"
			if area == "draw" and _win_details.has(seat):
				var win_detail: Dictionary = _win_details[seat]
				lines.append(str(win_detail.text))
				# A winning tile may also have a chicken contribution. Its
				# contribution and the cash paid for the win are separate.
				total = float(win_detail.total)
				total_caption = "胡牌实收"
			if lines.is_empty():
				continue
			var owner := str(view._name_labels[seat].tooltip_text) if seat < view._name_labels.size() else "玩家%d" % (seat + 1)
			var id: int = tile.get_instance_id()
			_tile_details[id] = {"heading": owner + " · " + title, "text": "\n".join(lines),
				"total": total, "total_caption": total_caption}
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
	_heading.text = detail.heading
	_body.text = detail.text
	var total := float(detail.total)
	_total.text = "%s %s" % [detail.total_caption, "%+.0f" % total if not is_zero_approx(total) else "0"]
	_total.add_theme_color_override("font_color", UI.SCORE_LOSS if total < 0 else UI.SCORE_GAIN)
	_body.scroll_to_line(0)
	_detail_panel.show()

func _hide_detail() -> void:
	_selected = -1
	_detail_panel.hide()
