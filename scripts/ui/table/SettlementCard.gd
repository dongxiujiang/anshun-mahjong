extends "res://scripts/ui/table/TableComponent.gd"
## 管理四家结算展示、卡片切换与联机下一局准备。

const UI := preload("res://scripts/ui/table/TableUiConfig.gd")

var result_layer: Control
var _result_shown := false
var _result_panel: Control
var _result_shade: ColorRect
var _result_restore: Button
var _next_round_button: Button
var _next_round_status: Label
var _next_round_hint: Label
var _ready_chips: Array[Panel] = []

func build() -> void:
	result_layer = table._box(table.surface)
	result_layer.size = UI.DESIGN_SIZE
	result_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	result_layer.hide()

func _result_card_size() -> Vector2:
	return UI.LANDSCAPE_RESULT_SIZE if table._landscape else UI.RESULT_CARD_SIZE

func _result_toggle_position() -> Vector2:
	return Vector2(UI.LANDSCAPE_RESULT_SIZE.x - UI.RESULT_TOGGLE_EDGE_GAP.x, UI.RESULT_TOGGLE_EDGE_GAP.y) if table._landscape else UI.RESULT_TOGGLE_LOCAL_POSITION

func _draw_result_title() -> String:
	return "四家叫牌 · 流局" if table.round.round_meta.get("all_called_draw", false) else "牌墙摸完 · 查叫"

func _show_result() -> void:
	_ready_chips.clear()
	_next_round_status = null
	_next_round_hint = null
	table._clear_box(result_layer)
	var shade = ColorRect.new()
	shade.color = UI.RESULT_SHADE
	shade.size = table._design_size()
	result_layer.add_child(shade)
	_result_shade = shade
	var panel = Panel.new()
	panel.name = "SettlementCard"
	panel.position = (table._design_size() - table._result_card_size()) / 2.0
	panel.size = table._result_card_size()
	panel.add_theme_stylebox_override("panel", table._style(UI.RESULT_BACKGROUND, UI.RESULT_BORDER, UI.RESULT_RADIUS, 1))
	result_layer.add_child(panel)
	_result_panel = panel
	table._label(panel, "本局结算", Vector2(42, 26), Vector2(320, 64), 42, UI.GOLD)
	var winner = int(table.round.round_meta.get("winner", -1))
	var flip: String = table.round.round_meta.get("flip_tile", "")
	if flip != "":
		table._label(panel, "翻鸡牌", Vector2(480, 24), Vector2(180, 72), 42)
		var flip_tile: TileView = table._make_tile(flip, true, UI.RESULT_TILE_UNIT)
		flip_tile.name = "FlippedChickenTile"
		table._put_tile(panel, flip_tile, Vector2(682, 12))
	elif winner < 0:
		table._label(panel, table._draw_result_title(), Vector2(380, 16), Vector2(740, 52), 34, UI.GOLD)
		var notice = "本局不计分 · 下局鸡分 ×%d" % table.round.next_chicken_multiplier if table.round.round_meta.get("all_called_draw", false) else "未叫牌者补出牌鸡与杠分 · 叫牌者不补差"
		table._label(panel, notice, Vector2(42, 74), Vector2(1700, 32), 22, UI.MUTED)
	else:
		table._label(panel, "牌墙已空 · 无翻鸡", Vector2(42, 28), Vector2(800, 64), 34, UI.MUTED)
	var round_points: Array = table.round.last_result.get("round_points", table.round._last_round_points)
	var pairs: Array = table.round.last_result.get("pairwise", ScoringEngine.pairwise_payments(table.round.last_result.get("transfers", table.round._last_transfers)))
	var status: Array = table.round.last_result.get("status", [])
	var items: Array = table.round.last_result.get("items", [])
	for row_index in 4:
		var relative: int = [0, 3, 2, 1][row_index]
		var seat = posmod(table.human_seat + relative, 4)
		var player: PlayerState = table.round.players[seat]
		var own_points = float(round_points[seat]) if round_points.size() == 4 else 0.0
		var row = Control.new()
		row.name = "ResultSeat%d" % seat
		row.position = UI.RESULT_GRID_ORIGIN + Vector2(row_index % 2, row_index / 2) * UI.RESULT_GRID_STRIDE if table._landscape else Vector2(42, 108 + row_index * 306)
		row.size = UI.RESULT_ROW_SIZE if table._landscape else Vector2(1236, 298)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(row)
		table._label(row, table._seat_name(seat), Vector2(0, 12), Vector2(110, 60) if table._landscape else Vector2(164, 60), 34 if table._landscape else 42).name = "SeatName"
		table._label(row, "%.0f分" % player.score, Vector2(118 if table._landscape else 206, 12), Vector2(164 if table._landscape else 250, 60), 32 if table._landscape else 40).name = "TotalScore"
		var own_label: Label = table._label(row, "本局%.0f分" % own_points, Vector2(300 if table._landscape else 472, 12), Vector2(260 if table._landscape else 290, 60), 32 if table._landscape else 40)
		own_label.name = "RoundPoints"
		own_label.add_theme_color_override("font_color", UI.GOLD)
		var name_label := row.get_node("SeatName") as Label
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.tooltip_text = table._seat_name(seat)
		own_label.tooltip_text = "本人的得分点合计；明杠基础4分只向放杠者收，单独列在杠牌组内"
		var payments = ScoringEngine.relative_payments(pairs, seat)
		for index in 3:
			var x = (588.0 if table._landscape else 786.0) + index * 150.0
			var direction: String = ["上家", "对家", "下家"][index]
			var amount = float(payments[index])
			var direction_label: Label = table._label(row, direction, Vector2(x, 0), Vector2(140, 26), 18, UI.MUTED)
			direction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var change: Label = table._label(row, "%+.0f" % amount if not is_zero_approx(amount) else "0", Vector2(x, 24), Vector2(140, 52), 40)
			change.name = "Payment%d" % index
			change.add_theme_color_override("font_color", Color("#e4a391") if amount < 0 else (UI.GOLD if amount > 0 else UI.MUTED))
			change.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			change.tooltip_text = "该玩家自己的%s：%s%.0f分" % [direction, "收取" if amount >= 0 else "付出", absf(amount)]
		var first: String = str(status[seat]) if status.size() == 4 else ""
		var list: Array = items[seat] if items.size() == 4 else []
		table._draw_result_details(row, seat, first, list, winner)
	var eye: Button = table._button("看牌桌", func(): table._toggle_result_panel(false), UI.RESULT_TOGGLE_SIZE)
	eye.tooltip_text = "隐藏结算卡片，查看牌桌上的牌"
	eye.position = table._result_toggle_position()
	panel.add_child(eye)
	var next: Button = table._button("下一局" if table._net_mode() == "" else "准备下一局", table._next_round, UI.NEXT_ROUND_BUTTON_SIZE, true)
	next.name = "NextRoundButton"
	next.add_theme_font_size_override("font_size", UI.NEXT_ROUND_FONT_SIZE)
	next.position = Vector2((table._result_card_size().x - UI.NEXT_ROUND_BUTTON_SIZE.x) / 2.0, table._result_card_size().y - UI.NEXT_ROUND_BUTTON_SIZE.y - UI.RESULT_BOTTOM_GAP)
	panel.add_child(next)
	_next_round_button = next
	if table._net_mode() != "":
		next.position = Vector2(panel.size.x - UI.NEXT_ROUND_BUTTON_SIZE.x - 32, panel.size.y - UI.NEXT_ROUND_BUTTON_SIZE.y - 24)
		var footer := Panel.new()
		footer.name = "ReadinessFooter"
		footer.position = Vector2(32, 1000)
		footer.size = Vector2(panel.size.x - 64, 216)
		footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		footer.add_theme_stylebox_override("panel", table._style(UI.RESULT_DETAILS_BACKGROUND, UI.BUTTON_DISABLED_BORDER, 18, 1))
		panel.add_child(footer)
		panel.move_child(next, panel.get_child_count() - 1)
		_next_round_status = table._label(footer, "下一局准备", Vector2(20, 12), Vector2(900, 36), 26, UI.GOLD)
		_next_round_status.name = "NextRoundReadiness"
		for index in 4:
			var chip := Panel.new()
			chip.name = "ReadySeat%d" % posmod(table.human_seat + [0, 3, 2, 1][index], 4)
			chip.position = Vector2(20 + index * 400, 60)
			chip.size = Vector2(380, 82)
			chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			footer.add_child(chip)
			var label: Label = table._label(chip, "", Vector2(14, 8), Vector2(352, 66), 24)
			label.name = "MemberStatus"
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_ready_chips.append(chip)
		_next_round_hint = table._label(footer, "", Vector2(20, 156), Vector2(1580, 40), 26, UI.MUTED)
		table._refresh_next_round_controls()
	table._ensure_restore_button()
	table._toggle_result_panel(true)
	preload("res://scripts/ui/UiMotion.gd").appear(result_layer)
	preload("res://scripts/ui/UiMotion.gd").slide_in(panel)

func _draw_result_details(row: Control, seat: int, status: String, list: Array, winner: int) -> void:
	var background = Panel.new()
	background.name = "Details"
	background.position = Vector2(0, UI.RESULT_DETAILS_TOP)
	background.size = Vector2(row.size.x, row.size.y - UI.RESULT_DETAILS_TOP)
	background.add_theme_stylebox_override("panel", table._style(UI.RESULT_DETAILS_BACKGROUND, Color.TRANSPARENT, 6))
	row.add_child(background)
	var state: Label = table._label(background, status if status != "" else "未叫牌", Vector2(12, 12) if table._landscape else Vector2(22, 65), Vector2(132, background.size.y - 24) if table._landscape else Vector2(162, 112), 24, UI.GOLD if seat == winner else UI.INK)
	state.name = "CallStatus"
	state.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var scroll = ScrollContainer.new()
	scroll.name = "ScoreGroups"
	scroll.position = Vector2(152, 8) if table._landscape else Vector2(194, 8)
	scroll.size = Vector2(886 if table._landscape else 1024, background.size.y - 16)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	background.add_child(scroll)
	var flow = HFlowContainer.new()
	flow.name = "Groups"
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", UI.RESULT_GROUP_GAP.x)
	flow.add_theme_constant_override("v_separation", UI.RESULT_GROUP_GAP.y)
	scroll.add_child(flow)
	# 胡牌奖在前，鸡牌按类型/单张分值归组，所有杠集中放在最后。
	for category in ["text", "chicken", "kong"]:
		for item in list:
			var kind = str(item.get("kind", ""))
			var item_category = "kong" if kind == "kong" else ("chicken" if kind in ["chicken", "charge", "flip"] else "text")
			if item_category == category:
				table._draw_result_group(flow, item, seat, 862.0 if table._landscape else 1000.0)

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
	var text = ""
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
	var tile_width = TileView.BASE_W * UI.RESULT_TILE_UNIT
	var tile_height = TileView.BASE_H * UI.RESULT_TILE_UNIT
	var sideways = table._result_sideways_index(item, seat)
	var positions: Array = []
	var rotations: Array = []
	var x = 0.0
	var y = 28.0
	var widest = 0.0
	var content_height = tile_height
	if item.get("kind", "") == "kong":
		var meld = {"kind": "add_kong" if item.get("kong_kind", RoundState.KongKind.NONE) == RoundState.KongKind.ADD_KONG else "kong",
			"concealed": item.get("kong_kind", RoundState.KongKind.NONE) == RoundState.KongKind.CONCEALED, "from_seat": item.get("from_seat", -1)}
		var layout: Dictionary = table._meld_tile_layout(meld, seat, UI.RESULT_TILE_UNIT, UI.RESULT_TILE_GAP)
		for index in tiles.size():
			positions.append(Vector2(layout.positions[index]) + Vector2(0, y))
			rotations.append(index == int(layout.sideways))
		x = float(layout.size.x) + UI.RESULT_TILE_GAP
		widest = x
		content_height = float(layout.size.y)
	else:
		for index in tiles.size():
			var rotated: bool = index == sideways or item.get("kind", "") == "charge"
			var width = tile_height if rotated else tile_width
			if x + width + 76.0 > max_width:
				x = 0.0
				y += tile_height + UI.RESULT_TILE_GAP
			positions.append(Vector2(x, y + tile_height if rotated else y))
			rotations.append(rotated)
			x += width + UI.RESULT_TILE_GAP
			widest = maxf(widest, x)
	var is_kong: bool = item.get("kind", "") == "kong"
	var dimensions = Vector2(maxf(UI.RESULT_GROUP_MIN_WIDTH, widest + UI.RESULT_SCORE_WIDTH), y + content_height + (8.0 if is_kong else 28.0))
	if tiles.is_empty():
		dimensions = Vector2(152, 158)
	var group = Control.new()
	group.name = "ScoreGroup"
	group.custom_minimum_size = dimensions
	group.set_meta("score_item", item.duplicate(true))
	group.mouse_filter = Control.MOUSE_FILTER_PASS
	group.tooltip_text = table._result_group_note(item, seat)
	flow.add_child(group)
	var heading = str(item.get("label", ""))
	if is_kong:
		if item.get("kong_kind", RoundState.KongKind.NONE) == RoundState.KongKind.EXPOSED:
			var direction: String = ["本人", "下家", "对家", "上家"][posmod(int(item.get("from_seat", -1)) - seat, 4)]
			heading += " · %s杠分%.0f" % [direction, float(item.get("base_amount", 0.0))]
		else:
			heading += " · 杠分%.0f" % float(item.get("base_amount", 0.0))
		if float(item.get("chicken_amount", 0.0)) > 0:
			heading += " · 鸡分%.0f" % float(item.chicken_amount)
	var heading_label: Label = table._label(group, heading, Vector2.ZERO, Vector2(dimensions.x, 26), 18, UI.MUTED)
	heading_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for index in tiles.size():
		var tile: TileView = table._make_tile(str(tiles[index]), true, UI.RESULT_TILE_UNIT)
		var position: Vector2 = positions[index]
		if bool(rotations[index]):
			tile.rotation = -PI / 2.0
		table._put_tile(group, tile, position)
	var amount = float(item.get("amount", 0.0))
	var score_pos = Vector2(x, y + content_height / 2.0 - 24.0) if not tiles.is_empty() else Vector2(0, 62)
	var amount_label: Label = table._label(group, "%+.0f" % amount, score_pos, Vector2(66 if not tiles.is_empty() else 152, 48), 32)
	amount_label.name = "GroupAmount"
	if not is_kong:
		var note: Label = table._label(group, table._result_group_note(item, seat), Vector2(0, dimensions.y - 24), Vector2(dimensions.x, 24), 16, UI.MUTED)
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _ensure_restore_button() -> void:
	# _clear_box 会把旧按钮排队释放，所以失效的引用必须重建，否则收不起卡片后就唤不回来。
	if _result_restore != null and is_instance_valid(_result_restore):
		_result_restore.position = table.panel_position_for_result_toggle()
		return
	_result_restore = table._button("查看结算", func(): table._toggle_result_panel(true), UI.RESULT_TOGGLE_SIZE, true)
	_result_restore.position = table.panel_position_for_result_toggle()
	_result_restore.tooltip_text = "重新显示结算卡片"
	# Keep the restore button outside the result overlay so it remains clickable
	# while the card and its input layer are hidden.
	table.surface.add_child(_result_restore)

func panel_position_for_result_toggle() -> Vector2:
	return (table._design_size() - table._result_card_size()) / 2.0 + table._result_toggle_position()

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
	if table._net_mode() != "":
		var network = table._net_node()
		if network.lobby.get("ready_round", -1) != network.round_number: return
		var me: Dictionary = network.lobby.seats[table.human_seat]
		network.set_ready(not bool(me.ready))
	else:
		table.new_game()

func _refresh_next_round_controls() -> void:
	if table._net_mode() == "" or table.round == null or table.round.phase != RoundState.Phase.SETTLED or not is_instance_valid(_next_round_button): return
	var network = table._net_node()
	var state: Dictionary = network.lobby
	var seats: Array = state.get("seats", [])
	_next_round_button.disabled = state.get("ready_round", -1) != network.round_number or seats.size() != 4
	if _next_round_button.disabled: return
	var seconds = int(state.get("countdown", -1))
	var ready: bool = seats[table.human_seat].ready
	_next_round_button.text = "%d 秒后开始 · 取消" % seconds if seconds >= 0 else ("已准备 · 点击取消" if ready else "准备下一局")
	_next_round_button.add_theme_font_size_override("font_size", UI.READY_NEXT_ROUND_FONT_SIZE)
	var waiting = PackedStringArray()
	var ready_count := 0
	var index := 0
	for relative in [0, 3, 2, 1]:
		var seat = posmod(table.human_seat + relative, 4)
		var name_value: String = ["你", "下家", "对家", "上家"][relative]
		var member: Dictionary = seats[seat]
		var prepared := bool(member.ready)
		if prepared: ready_count += 1
		if index < _ready_chips.size():
			var chip := _ready_chips[index]
			chip.add_theme_stylebox_override("panel", table._style(UI.BUTTON_NORMAL if prepared else UI.RESULT_BACKGROUND, UI.GOLD if prepared else UI.BUTTON_DISABLED_BORDER, 12, 1))
			var label: Label = chip.get_node("MemberStatus")
			var detail := "人机已准备" if member.ai else ("已准备" if prepared else "等待准备")
			if member.get("disconnected", false): detail = "断线 · 等待重连"
			label.text = "%s · %s\n%s" % [name_value, str(member.get("name", table._seat_name(seat))), detail]
			label.tooltip_text = label.text
			label.add_theme_color_override("font_color", UI.GOLD if prepared else UI.MUTED)
		index += 1
		if not seats[seat].ready: waiting.append(name_value)
	_next_round_status.text = "下一局准备  %d / 4" % ready_count
	_next_round_hint.text = "全部准备，%d 秒后自动开局" % seconds if seconds >= 0 else ("等待：" + "、".join(waiting) + " · 人机默认准备")
