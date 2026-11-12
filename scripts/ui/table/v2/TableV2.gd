class_name TableV2
extends Control
signal hand_tile_pressed(seat: int, slot: int)
## 唯一正式牌桌视图：负责快照渲染、输入代理、开局/摸打/碰杠动画和 V2 结算。
## 规则状态仍由 RoundState 权威推进；旧 PlayerTileAreas 仅保留兼容接口。

const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const MODEL := preload("res://scripts/ui/table/v2/TableV2Model.gd")
const UI := preload("res://scripts/ui/table/TableUiConfig.gd")
const TILES := preload("res://scripts/core/Tiles.gd")
const DICE := preload("res://scripts/ui/DiceView.gd")
const PLAN := preload("res://scripts/ui/table/SettlementAnimationPlan.gd")
const EXPOSED := preload("res://scripts/ui/table/v2/ExposedLayout.gd")
var _exposed_specs: Array = []
var _exposed_key := 0

const SCORE_INSPECTION := preload("res://scripts/ui/table/v2/TableV2ScoreInspection.gd")
const VOICE_PACKS := preload("res://scripts/core/VoicePackRegistry.gd")
const HAND_ARRANGEMENT := preload("res://scripts/ui/table/v2/HandArrangement.gd")
const STYLE := preload("res://scripts/ui/UiStyle.gd")

var round = null
var human_seat := 1
var table = null
var snapshot: Dictionary = {}

var _wall_layer: Control
var _hand_layer: Control
var _discard_layer: Control
var _red_layer: Control
var _action_layer: Control
var _settlement_layer: Control
var _dice_layer: Control
var _dice_red: Control
var _dice_white: Control
var _dice_shadow: Control
var _dice_tween: Tween
var _native_settlement: Control
var _score_inspection: Control
var _settlement_tween: Tween
var _settlement_plan: Dictionary = {}
var _settlement_started := false
var _settlement_complete := true
var _settlement_pairs: Array = []
var _settlement_start_scores: Array = []
var _settlement_target_scores: Array = []
var _settlement_display_scores: Array = []
var _settlement_final_scores: Array = []
var _settlement_stage_key := ""
var _settlement_flip_view: TileView = null
var _settlement_flip_index := -1
var _settlement_flip_revealed := false
var _settlement_notice: Label = null
var _settlement_score_rows: Array = []
var _settlement_total_label: Label
var _settlement_count_duration := 0.0
var _meld_layer: Control
var _label_layer: Control
var _control_layer: Control
const ROUND_STATE := preload("res://scripts/core/RoundState.gd")
const TILE_POOL := preload("res://scripts/ui/TileViewPool.gd")
var _tile_pool = TILE_POOL.new()
var hand_boxes: Array = []
var draw_boxes: Array = []
var _debug_layer: Control
var _deal_layer: Control
var deal_animation_active := false
var show_wall_debug := false
## 正式模式：牌墙背面、拿走后消失、四家手牌只显示自己正面。
var formal_mode := true
var wall_face_up := false
var auto_sort_hands := true
var test_deal_only := false
var keep_removed_wall_gray := false
var test_reveal_all_hands := false
var test_frozen := false
var _frozen_hands: Array = []
var _started_ms := 0
var _sort_started := false
var _sort_animating := false
var _deal_tween: Tween
var _sort_tween: Tween
var _draw_flights: Dictionary = {}
var _draw_animating: bool:
	get: return not _draw_flights.is_empty()
# 碰杠后保持剩余牌的触点，直到该玩家出牌再重新居中。
var _held_hand_centers: Dictionary = {}
var _pending_draws := {0: "", 1: "", 2: "", 3: ""}
var _deal_done_callback := Callable()
var _deal_moving: Array = []
var _deal_generation := 0
var _discard_flight_id := 0
var _discard_flights := {}
var _visual_action_id := 0
var _visual_actions: Dictionary = {}
var _motion_tweens: Array[Tween] = []
var _render_tiles: Dictionary = {}
var _render_seen: Dictionary = {}
var _reconciling := false
var _label_signature := ""
var _hud_bounds := {}
var _latest_discard_seat := -1
var _latest_discard_id := -1
var _labels: Array = []
var _name_labels: Array = []
const SEAT_BADGE_SIZE := 56.0

var _voice_buttons: Dictionary = {}
var _ready_meld_badges: Array[Label] = []
var _dealer_meld_badges: Array[Label] = []
var _sort_button: Button
var _restore_button: Button
var _hand_groups: Control
var _local_arrangement := {}
var _arrangement_choices: Array = []
var _arrangement_key := ""
var _arrangement_thread: Thread
var _arrangement_job_key := ""
var _arrangement_done_key := ""
var _arrangement_caption: Label

func _ready() -> void:
	if _started_ms == 0: _started_ms = Time.get_ticks_msec()
	if size == Vector2.ZERO:
		size = G.DESIGN_SIZE
	_build_layers()
	AudioManager.seat_voice_pack_changed.connect(_refresh_hud, CONNECT_DEFERRED)
	GameConfig.score_details_changed.connect(_sync_score_inspection)
	GameConfig.settlement_speed_changed.connect(_native_apply_speed)

func _build_layers() -> void:
	if _wall_layer != null: return
	_wall_layer = _layer("WallLayer")
	_discard_layer = _layer("DiscardLayer")
	_red_layer = _layer("RedLayer")
	_meld_layer = _layer("MeldLayer")
	_hand_layer = _layer("HandLayer")
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	for seat in 4:
		var hb := Control.new()
		hb.name = "HandBox%d" % seat
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hand_layer.add_child(hb)
		hand_boxes.append(hb)
		var db := Control.new()
		db.name = "DrawBox%d" % seat
		db.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		db.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hand_layer.add_child(db)
		draw_boxes.append(db)
	_dice_layer = _layer("DiceLayer")
	_label_layer = _layer("LabelLayer")
	_control_layer = _layer("ControlLayer")
	_control_layer.z_index = 4
	_action_layer = _layer("ActionLayer")
	_action_layer.z_index = 90
	_hand_groups = Control.new()
	_hand_groups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_action_layer.add_child(_hand_groups)
	_arrangement_caption = _table_text(_action_layer, "", 22, UI.GOLD)
	_arrangement_caption.position = Vector2(520, G.HAND_BOTTOM + 24)
	_arrangement_caption.size = Vector2(1190, 50)
	_arrangement_caption.clip_text = true
	_arrangement_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sort_button = _arrangement_button("排序", _sort_own_hand)
	_restore_button = _arrangement_button("恢复", _restore_own_hand)
	_deal_layer = _layer("DealLayer")
	_deal_layer.z_index = 10
	_debug_layer = _layer("WallDebugLayer")
	_settlement_layer = _layer("SettlementLayer")
	# 牌墙/手牌使用 z_index，结算卡必须压过它们，否则庄家卡会被南墙和手牌遮住。
	_settlement_layer.z_index = 100
	_build_ready_decorations()

func _arrangement_button(caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.size = Vector2(148, 76)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", TileView._font())
	button.add_theme_font_size_override("font_size", 30)
	STYLE.button(button)
	button.pressed.connect(callback)
	_action_layer.add_child(button)
	button.hide()
	return button

func _can_arrange_hand() -> bool:
	return round != null and round.phase == ROUND_STATE.Phase.PLAYING and not test_frozen \
		and human_seat in range(round.players.size()) and round.players[human_seat].concealed.size() == 13 \
		and str(round.players[human_seat].just_drew).is_empty() and not _opening_mode() \
		and not native_presentation_pending()

func _hand_choices(cards: Array) -> Array:
	var key := str(TILES.sort_hand(cards)) + GameConfig.hand_sort_priority
	if key != _arrangement_key:
		_arrangement_key = key
		_arrangement_choices = HAND_ARRANGEMENT.build(cards, GameConfig.hand_sort_priority == "pattern")
	return _arrangement_choices

func _sort_own_hand() -> void:
	if not _can_arrange_hand(): return
	var previous_key := _arrangement_key
	var choices := _hand_choices(round.players[human_seat].concealed)
	if choices.is_empty(): return
	var current := -1
	if _arrangement_key == previous_key:
		for i in choices.size():
			if choices[i].key == _local_arrangement.get("key", ""): current = i
	_local_arrangement = choices[(current + 1) % choices.size()]
	if _arrangement_thread == null and _arrangement_done_key != _arrangement_key:
		_arrangement_job_key = _arrangement_key
		var input: Array = round.players[human_seat].concealed.duplicate()
		var priority: bool = GameConfig.hand_sort_priority == "pattern"
		_arrangement_thread = Thread.new()
		_arrangement_thread.start(func(): return HAND_ARRANGEMENT.with_one_tile_changes(input, priority))
	refresh()

func _restore_own_hand() -> void:
	if not _can_arrange_hand(): return
	_local_arrangement = {}
	refresh()

func _order_local_cards(cards: Array) -> Array:
	if _local_arrangement.is_empty() or cards.size() != 13: return cards
	if cards == TILES.sort_hand(_local_arrangement.cards): return _local_arrangement.cards
	var best := -1
	var chosen := {}
	for choice in _hand_choices(cards):
		var retained := HAND_ARRANGEMENT.retained_groups(_local_arrangement, choice)
		if retained > best:
			best = retained
			chosen = choice
	_local_arrangement = chosen
	return _local_arrangement.get("cards", cards)

func _refresh_hand_arrangement() -> void:
	var show_buttons := _can_arrange_hand()
	_arrangement_caption.visible = show_buttons and not _local_arrangement.is_empty()
	if not _local_arrangement.is_empty():
		var at := -1
		for i in _arrangement_choices.size():
			if _arrangement_choices[i].key == _local_arrangement.key: at = i
		var waits: Array = _local_arrangement.waits.keys().map(func(i): return AiTeaching._display(Tiles.from_index(i)) + "(" + str(_local_arrangement.patterns.get(i, "平胡")) + ")")
		var change := ""
		if _local_arrangement.has("change_from"):
			change = "打%s、换入%s后 " % [AiTeaching._display(_local_arrangement.change_from), AiTeaching._display(_local_arrangement.change_to)]
		_arrangement_caption.text = "%d/%d  %s%s%s" % [at+1, _arrangement_choices.size(), change,
			"听 " + "、".join(waits) if not waits.is_empty() else "尚未叫牌", " · 计算换牌方案中" if _arrangement_thread != null else ""]
		_arrangement_caption.tooltip_text = _arrangement_caption.text
	_sort_button.visible = show_buttons
	_restore_button.visible = show_buttons and not _local_arrangement.is_empty()
	var anchor := Vector2(G.draw_slot_center(human_seat, human_seat).x - _sort_button.size.x / 2.0, G.HAND_BOTTOM + 14.0)
	_sort_button.position = anchor
	_restore_button.position = anchor - Vector2(_restore_button.size.x + 12.0, 0.0)
	_clear(_hand_groups)
	if round.phase != ROUND_STATE.Phase.PLAYING or _local_arrangement.is_empty() \
			or hand_boxes[human_seat].get_child_count() != 13: return
	var slot := 0
	for length in _local_arrangement.lengths:
		var first := _hand_center(human_seat, slot, 13)
		var last := _hand_center(human_seat, slot + int(length) - 1, 13)
		var half := G.hand_tile_size(human_seat, human_seat).x / 2.0
		var line := ColorRect.new()
		line.color = Color(UI.GOLD, 0.8)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.position = Vector2(first.x - half + 8.0, G.HAND_BOTTOM + 4.0)
		line.size = Vector2(last.x - first.x + 2.0 * half - 16.0, 4.0)
		_hand_groups.add_child(line)
		slot += int(length)

func _build_ready_decorations() -> void:
	for seat in 4:
		_ready_meld_badges.append(_meld_badge("听", "ReadyMeldBadge%d" % seat, Color("#504221"), UI.GOLD))
		_dealer_meld_badges.append(_meld_badge("庄", "DealerMeldBadge%d" % seat, UI.DEALER_BACKGROUND, UI.DEALER_BORDER))

func _meld_badge(caption: String, node_name: String, background: Color, border: Color) -> Label:
	var badge := _hud_badge(caption, Vector2.ZERO, background, border)
	badge.reparent(_control_layer, false)
	badge.name = node_name
	badge.add_theme_font_size_override("font_size", 34)
	badge.get_theme_stylebox("normal").set_border_width_all(2)
	badge.size = Vector2.ONE * SEAT_BADGE_SIZE
	badge.hide()
	return badge

func _layout_meld_badges() -> void:
	if round == null or _ready_meld_badges.is_empty(): return
	for seat in 4:
		var rel := G.relative_seat(human_seat, seat)
		var axis: Vector2 = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN][rel]
		var center := G.meld_anchor(seat, human_seat)


		var dealer: Label = _dealer_meld_badges[seat]
		var ready_badge: Label = _ready_meld_badges[seat]
		dealer.visible = round.dealer_seat == seat
		ready_badge.visible = bool(round.players[seat].ready)
		var badges: Array[Label] = []
		if dealer.visible: badges.append(dealer)
		if ready_badge.visible: badges.append(ready_badge)
		for index in badges.size():
			badges[index].position = center - Vector2(28, 28) + axis * 64.0 * (index - (badges.size() - 1) / 2.0)

func clear_dice_visual() -> void:
	if _dice_tween != null and _dice_tween.is_valid(): _dice_tween.kill()
	_dice_tween = null
	if _dice_layer != null:
		for node in _dice_layer.get_children():
			node.hide()
			node.queue_free()
	_dice_red = null
	_dice_white = null
	_dice_shadow = null

func animate_dice(value: int, white: int) -> void:
	clear_dice_visual()
	AudioManager.play_dice()
	var die_size := Vector2(UI.DICE_SIZE, UI.DICE_SIZE)
	var center := UI.LANDSCAPE_CENTER
	var red := DICE.new()
	red.size = die_size
	red.pivot_offset = die_size / 2.0
	red.face_color = Color("#f3d8cf")
	red.border_color = Color("#a55043")
	red.pip_color = Color("#a62b21")
	_dice_layer.add_child(red)
	var white_die := DICE.new()
	white_die.size = die_size
	white_die.pivot_offset = die_size / 2.0
	white_die.face_color = Color("#eef2e8")
	white_die.border_color = Color("#8c9d8b")
	white_die.pip_color = Color("#243a30")
	_dice_layer.add_child(white_die)
	var shadow := Panel.new()
	shadow.size = Vector2(UI.DICE_SIZE * 2.0 + 8.0, 16.0)
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0, 0, 0, 0.34)
	shadow_style.set_corner_radius_all(8)
	shadow.add_theme_stylebox_override("panel", shadow_style)
	_dice_layer.add_child(shadow)
	_dice_red = red
	_dice_white = white_die
	_dice_shadow = shadow
	var red_rest := center + Vector2(-UI.DICE_SIZE - 4.0, -UI.DICE_SIZE * 0.5)
	var white_rest := center + Vector2(4.0, -UI.DICE_SIZE * 0.5)
	red.position = red_rest + Vector2(-8, -30)
	white_die.position = white_rest + Vector2(8, -30)
	red.rotation = -0.55
	white_die.rotation = 0.62
	red.scale = Vector2.ONE * 0.8
	white_die.scale = Vector2.ONE * 0.8
	shadow.position = center + Vector2(-UI.DICE_SIZE - 4.0, UI.DICE_SIZE * 0.5 + 4.0)
	_dice_tween = create_tween()
	_dice_tween.tween_method(Callable(self, "_tick_dice").bind(value, white, red_rest, white_rest),
		0.0, 1.0, UI.DICE_DURATION)
	_dice_tween.tween_interval(GameConfig.OPENING_DICE_HOLD_SECONDS)

func _tick_dice(progress: float, value: int, white: int,
		red_rest: Vector2, white_rest: Vector2) -> void:
	if not is_instance_valid(_dice_red) or not is_instance_valid(_dice_white): return
	var bounce := _dice_bounce(progress, 46.0)
	var bounce2 := _dice_bounce(progress, 40.0)
	_dice_red.rotation = lerpf(-0.55, TAU, progress)
	_dice_white.rotation = lerpf(0.62, TAU + 0.4, progress)
	_dice_red.scale = Vector2.ONE * lerpf(0.8, 1.0, progress)
	_dice_white.scale = Vector2.ONE * lerpf(0.8, 1.0, progress)
	_dice_red.position = red_rest + Vector2(22 * sin(progress * PI) * (1.0 - progress), bounce)
	_dice_white.position = white_rest + Vector2(-18 * sin(progress * PI) * (1.0 - progress), bounce2)
	if is_instance_valid(_dice_shadow):
		_dice_shadow.modulate.a = clampf(1.0 + bounce / 46.0, 0.22, 1.0)
		_dice_shadow.scale.x = clampf(1.0 + bounce / 46.0, 0.5, 1.0)
	_dice_red.value = (int(progress * 36) % 6 + 1) if progress < 1.0 else value
	_dice_white.value = ((int(progress * 30) + 2) % 6 + 1) if progress < 1.0 else white

func _dice_bounce(progress: float, height: float) -> float:
	if progress < 0.5: return lerpf(-height, 0.0, pow(progress / 0.5, 2.2))
	if progress < 0.68: return -height * 0.38 * sin((progress - 0.5) / 0.18 * PI)
	if progress < 0.82: return -height * 0.16 * sin((progress - 0.68) / 0.14 * PI)
	if progress < 0.92: return -height * 0.05 * sin((progress - 0.82) / 0.10 * PI)
	return 0.0

func adopt_action_bar(bar: Control) -> void:
	if bar == null or _action_layer == null: return
	if bar.get_parent() != _action_layer:
		bar.reparent(_action_layer)

func _settlement_result_title() -> String:
	var winners: Array = _settlement_plan.winners
	if winners.is_empty():
		return "四家叫牌流局" if _settlement_plan.all_called_draw else "本局流局"
	var meta: Dictionary = round.round_meta
	var relative := ["你", "上家", "对家", "下家"]
	var source := int(meta.get("discard_seat", -1))
	var source_name: String = relative[posmod(source - human_seat, 4)] if source in range(4) else ""
	var self_draw := bool(meta.get("self_draw", false))
	var robbed := bool(meta.get("robbed_kong", false))
	var prefix := ""
	if not self_draw and source_name != "":
		var cause := "被抢杠" if robbed else ("杠后放炮" if meta.get("burn_chicken_reason", "") == "after_kong_discard" else "放炮")
		prefix = source_name + cause + " · "
	var titles: Array[String] = []
	for winner in winners:
		var title: String = relative[posmod(int(winner) - human_seat, 4)]
		if round.players[winner].ready: title += "报听"
		if self_draw:
			if int(meta.get("kong_draw_seat", -1)) == winner: title += "杠开"
			if int(meta.get("last_four_self_draw_seat", -1)) == winner: title += "海底"
			title += "自摸"
		elif robbed:
			title += "抢杠胡"
		else:
			title += "胡牌"
		var patterns: Array[String] = []
		var items: Array = round.last_result.get("items", [])
		for item in items[winner] if winner < items.size() else []:
			if str(item.get("kind", "")) != "pattern": continue
			var caption := str(item.get("label", ""))
			if caption == "清龙对": caption = "清龙七对"
			if caption != "" and caption not in patterns: patterns.append(caption)
		if not patterns.is_empty(): title += "-" + "·".join(patterns)
		titles.append(title)
	return prefix + "、".join(titles)

func _settlement_multiplier_title() -> String:
	var meta: Dictionary = round.round_meta
	if int(meta.get("chicken_multiplier", 1)) <= 1: return ""
	var dice := bool(meta.get("dice_double", false))
	# Legacy snapshots only identify the previous draw if the dice differ.
	var previous_draw := bool(meta.get("previous_draw_double", not dice))
	if previous_draw and dice: return "上局流局、双骰同点 · 本局双倍"
	if dice: return "双骰同点 · 本局双倍"
	if previous_draw: return "上局流局 · 本局双倍"
	return "本局双倍"

func _build_native_settlement_panel() -> void:
	var panel := Panel.new()
	panel.name = "V2PersonalSettlement"
	panel.size = Vector2(G.SETTLEMENT_AREA.size.x, 280)
	panel.position = G.SETTLEMENT_AREA.get_center() - panel.size / 2.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#102c24")
	style.border_color = Color(UI.GOLD, 0.65)
	style.set_border_width_all(2)
	style.set_corner_radius_all(20)
	panel.add_theme_stylebox_override("panel", style)
	_settlement_layer.add_child(panel)
	_native_settlement = panel
	get_node("/root/FpsOverlay").hide_during_settlement(panel)

	var title := _table_text(panel, _settlement_result_title(), 30, UI.GOLD)
	title.name = "ResultTitle"
	title.position = Vector2(28, 4)
	title.size = Vector2(panel.size.x - 56, 40)
	title.add_theme_font_size_override("font_size", clampi(floori(30.0 * title.size.x / maxf(_hud_text_width(title.text, 30), title.size.x)), 18, 30))
	title.clip_text = true
	title.tooltip_text = title.text
	var multiplier := _table_text(panel, _settlement_multiplier_title(), 24, UI.GOLD)
	multiplier.name = "MultiplierTitle"
	multiplier.position = Vector2(28, 41)
	multiplier.size = Vector2(panel.size.x - 56, 29)
	var header_y := 72.0
	var column_start := 188.0
	var column_width := (panel.size.x - 468.0) / 3.0
	var row_height := 50.0
	for index in 4:
		var seat := posmod(human_seat + index, 4)
		var center := 102.0 if index == 0 else column_start + (index - 1) * column_width + column_width / 2.0
		var direction := _table_text(panel, ["我", "上", "对", "下"][index], 36, UI.GOLD)
		direction.name = "SettlementSeat%d" % seat
		direction.position = Vector2(center - 35.0, header_y)
		direction.size = Vector2(36, 44)
		direction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var called := bool(_settlement_plan.called[seat])
		if not called: continue
		var background := Color("#30784e")
		var border := Color("#a2d3ac")
		var badge := _hud_badge("叫", Vector2(center + 9.0, header_y + 8.0), background, border)
		badge.name = "CalledStatus%d" % seat
		badge.tooltip_text = "叫牌"
		badge.reparent(panel, false)

	for row in 3:
		var top := 119.0 + row * row_height
		var divider := ColorRect.new()
		divider.color = Color(UI.GOLD, 0.28 if row == 2 else 0.13)
		divider.position = Vector2(24, top)
		divider.size = Vector2(panel.size.x - 48, 1)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(divider)
		var caption := _table_text(panel, ["我的分数", "对方分数", "结算"][row], 28, UI.INK)
		caption.position = Vector2(28, top + 1)
		caption.size = Vector2(148, row_height - 1)
		var labels: Array[Label] = []
		for index in 3:
			var value := _table_text(panel, "0", 42 if row == 2 else 38, UI.MUTED)
			value.position = Vector2(column_start + index * column_width, top + 1)
			value.size = Vector2(column_width, row_height - 1)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			labels.append(value)
		_settlement_score_rows.append(labels)

	var total_bg := ColorRect.new()
	total_bg.color = Color(UI.GOLD, 0.10)
	total_bg.position = Vector2(panel.size.x - 258, 220)
	total_bg.size = Vector2(232, 49)
	total_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(total_bg)
	var total_title := _table_text(total_bg, "合计", 28, UI.GOLD)
	total_title.position = Vector2(14, 0)
	total_title.size = Vector2(70, total_bg.size.y)
	total_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settlement_total_label = _table_text(total_bg, "0", 42, UI.MUTED)
	_settlement_total_label.name = "Total"
	_settlement_total_label.position = Vector2(84, 0)
	_settlement_total_label.size = Vector2(136, total_bg.size.y)
	_settlement_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func adopt_settlement_node(node: Control) -> void:
	if node == null or _settlement_layer == null: return
	if node.get_parent() != _settlement_layer:
		node.reparent(_settlement_layer)

func reset_native_settlement() -> void:
	_settlement_started = false
	_settlement_complete = true
	_settlement_stage_key = ""
	_settlement_plan.clear()
	_settlement_pairs.clear()
	_settlement_final_scores.clear()
	_settlement_start_scores.clear()
	_settlement_target_scores.clear()
	_settlement_display_scores.clear()
	_clear_native_settlement_visuals()

func start_native_settlement(immediate: bool = false) -> void:
	if table == null or round == null or round.phase != ROUND_STATE.Phase.SETTLED or round.players.size() != 4:
		return
	if _settlement_started:
		return
	_settlement_plan = PLAN.build(round.last_result, round.round_meta, round.players, human_seat)
	_settlement_started = true
	_settlement_complete = false
	_settlement_stage_key = ""
	_settlement_pairs = _settlement_zero_matrix()
	_settlement_final_scores = _settlement_zero_matrix()
	for stage in _settlement_plan.stages:
		_settlement_final_scores = _settlement_add_matrix(_settlement_final_scores, stage.scores)
	_settlement_start_scores.clear()
	_settlement_target_scores.clear()
	_settlement_display_scores.clear()
	for seat in 4:
		var score := float(round.players[seat].score)
		_settlement_target_scores.append(score)
		_settlement_start_scores.append(score - float(_settlement_plan.get("deltas", [0.0, 0.0, 0.0, 0.0])[seat]))
	_settlement_display_scores = _settlement_start_scores.duplicate()
	for seat in mini(4, _labels.size()):
		_set_seat_score(_labels[seat], _settlement_start_scores[seat])
	_clear_native_settlement_visuals()
	_discard_layer.hide()
	_settlement_flip_index = MODEL.flip_wall_index(round)
	_build_native_settlement_panel()
	if table.has_method("_clear_actions"):
		table._clear_actions()
	if table.get("_settlement_card") != null:
		table._settlement_card.hide_post_settlement_controls()
	if table.has_method("_update_interactivity"):
		table._update_interactivity()
	if immediate or DisplayServer.get_name() == "headless" or GameConfig.settlement_step_seconds() == 0.0:
		_finish_native_settlement()
	else:
		_play_native_settlement()

func native_settlement_started() -> bool:
	return _settlement_started

func native_settlement_active() -> bool:
	return _settlement_started and not _settlement_complete

func native_settlement_complete() -> bool:
	return _settlement_complete

func _clear_native_settlement_visuals() -> void:
	_kill_native_settlement_tween()
	_clear_native_tile_highlights()
	_remove_native_node(_score_inspection)
	_score_inspection = null
	_remove_native_node(_native_settlement)
	_restore_native_wall_flip(false)
	_remove_native_node(_settlement_notice)
	_native_settlement = null
	_settlement_flip_index = -1
	_settlement_notice = null
	_settlement_score_rows.clear()
	_settlement_total_label = null
	if _discard_layer != null:
		_discard_layer.show()
	if _red_layer != null:
		for tile in _red_layer.get_children():
			if int(tile.get_meta("meld_index", -1)) < 0: tile.show()

func _kill_native_settlement_tween() -> void:
	if _settlement_tween != null and _settlement_tween.is_valid():
		_settlement_tween.kill()
	_settlement_tween = null

func _remove_native_node(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()

func _play_native_settlement() -> void:
	if _settlement_plan.is_empty():
		return
	_kill_native_settlement_tween()
	_settlement_tween = create_tween()
	if bool(_settlement_plan.get("all_called_draw", false)):
		_show_native_settlement_notice("黄牌 · 下局收付 ×2")
		_settlement_tween.tween_interval(1.5)
		_settlement_tween.tween_callback(_finish_native_settlement)
		return
	_animate_native_wall_flip()
	var cumulative := _settlement_zero_matrix()
	for stage in _settlement_plan.get("stages", []):
		var before := cumulative.duplicate(true)
		var scores: Array = stage.scores
		var after := _settlement_add_matrix(before, scores)
		cumulative = after
		if not _settlement_matrix_changed(scores):
			_settlement_tween.tween_interval(0.24)
			continue
		_settlement_tween.tween_callback(_begin_native_stage.bind(stage))
		_settlement_tween.tween_interval(UI.SETTLEMENT_HIGHLIGHT_SECONDS)
		_settlement_tween.tween_interval(UI.SETTLEMENT_PAUSE_SECONDS)
		_settlement_tween.tween_method(_roll_native_pairs.bind(before, after), 0.0, 1.0, UI.SETTLEMENT_ROLL_SECONDS)
		_settlement_tween.tween_interval(UI.SETTLEMENT_PAUSE_SECONDS)
		_settlement_tween.tween_callback(_end_native_stage)
	_settlement_count_duration = UI.SETTLEMENT_PARTICLE_SECONDS
	for delta in _settlement_plan.get("deltas", [0.0, 0.0, 0.0, 0.0]):
		_settlement_count_duration = maxf(_settlement_count_duration, _native_score_duration_for_delta(float(delta)))
	_settlement_tween.tween_callback(_begin_native_final)
	_settlement_tween.tween_method(_roll_native_final, 0.0, 1.0, _settlement_count_duration)
	_settlement_tween.tween_callback(_finish_native_settlement)
	_native_apply_speed()

func _finish_native_settlement() -> void:
	if not _settlement_started or _settlement_complete:
		return
	_kill_native_settlement_tween()
	_clear_native_tile_highlights()
	_settlement_display_scores = _settlement_target_scores.duplicate()
	for seat in mini(4, _labels.size()):
		_set_seat_score(_labels[seat], _settlement_target_scores[seat])
	_restore_native_wall_flip(true)
	_remove_native_node(_settlement_notice)
	_settlement_notice = null
	_settlement_complete = true
	_settlement_stage_key = ""
	_render_native_pairs(_settlement_final_scores)
	_sync_score_inspection()
	if table != null and table.has_method("_on_settlement_animation_finished"):
		table._on_settlement_animation_finished()

func _sync_score_inspection() -> void:
	if not GameConfig.score_details_enabled:
		_remove_native_node(_score_inspection)
		_score_inspection = null
	elif _settlement_started and _settlement_complete and _score_inspection == null:
		_score_inspection = SCORE_INSPECTION.new(self, round.last_result, round.round_meta, round.players, _settlement_plan)
		_settlement_layer.add_child(_score_inspection)

func _native_flip_tile() -> String:
	if round == null or bool(_settlement_plan.get("is_draw", false)):
		return ""
	return str(round.round_meta.get("flip_tile", ""))

func _native_wall_flip_tile() -> TileView:
	if _settlement_flip_index < 0 or _wall_layer == null:
		return null
	for node in _wall_layer.get_children():
		if node is TileView and int(node.get_meta("wall_ring_index", -1)) == _settlement_flip_index:
			return node
	return null

func _animate_native_wall_flip() -> void:
	var tile := _native_wall_flip_tile()
	var card := _native_flip_tile()
	if tile == null or card == "":
		return
	_settlement_flip_view = tile
	var source := tile.position
	var lift := source + (G.CENTER - (source + tile.size / 2.0)).normalized() * 24.0
	var lift_scale := 1.12
	if _motion_would_cover(tile, lift + tile.size / 2.0, tile.size * lift_scale, tile.rotation):
		lift = source
		lift_scale = 1.0
	var duration := UI.SETTLEMENT_FLIP_SECONDS
	_settlement_tween.tween_callback(func():
		tile.z_index = 4
		tile.set_card("", false))
	_settlement_tween.tween_property(tile, "position", lift, duration * 0.28).set_ease(Tween.EASE_OUT)
	_settlement_tween.parallel().tween_property(tile, "scale", Vector2.ONE * lift_scale, duration * 0.28)
	_settlement_tween.tween_property(tile, "scale", Vector2(lift_scale, 0.03), duration * 0.28).set_ease(Tween.EASE_IN)
	_settlement_tween.tween_callback(func():
		tile.set_card(card, true)
		_show_native_settlement_notice("翻鸡  " + _tile_short(card)))
	_settlement_tween.tween_property(tile, "scale", Vector2.ONE, duration * 0.44).set_ease(Tween.EASE_OUT)
	_settlement_tween.parallel().tween_property(tile, "position", source, duration * 0.44)
	_settlement_tween.tween_callback(_restore_native_wall_flip.bind(true))

func _restore_native_wall_flip(reveal: bool) -> void:
	var card := _native_flip_tile()
	_settlement_flip_revealed = reveal and card != "" and _settlement_flip_index >= 0
	var tile := _native_wall_flip_tile()
	if tile != null:
		tile.position = wall_center_for_index(_settlement_flip_index) - tile.size / 2.0
		tile.scale = Vector2.ONE
		# A revealed lower tile still needs to be readable if its upper tile remains.
		tile.z_index = 2 if _settlement_flip_revealed else int(_settlement_flip_index % 2 == 0)
		tile.set_card(card if _settlement_flip_revealed else "", _settlement_flip_revealed)
		tile.set_score_highlight(false)
	_settlement_flip_view = null

func _show_native_settlement_notice(caption: String) -> void:
	if _settlement_notice == null:
		_settlement_notice = _table_text(_settlement_layer, "", 30, UI.GOLD)
		_settlement_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_settlement_notice.size = Vector2(700, 48)
		_settlement_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_settlement_notice.position = Vector2(790, 16)
	_settlement_notice.text = caption

func _begin_native_stage(stage: Dictionary) -> void:
	_settlement_stage_key = str(stage.get("key", ""))
	var caption := str({"flip": "翻鸡计分", "chicken": "鸡分结算", "kong": "杠分结算",
		"win": "胡牌与牌型结算", "other": "补付与调整结算"}.get(_settlement_stage_key, "计分"))
	var winner := int(stage.get("winner", -1))
	if _settlement_stage_key == "win" and _settlement_plan.get("winners", []).size() > 1 and winner in range(round.players.size()):
		var relative_name: String = ["你", "上家", "对家", "下家"][posmod(winner - human_seat, 4)]
		var names := _seat_display_names(snapshot.get("seats", []))
		caption += " · " + str(names.get(winner, relative_name))
	_show_native_settlement_notice(caption)
	_highlight_native_stage(stage)

func _end_native_stage() -> void:
	_settlement_stage_key = ""
	_clear_native_tile_highlights()

func _highlight_native_stage(stage: Dictionary) -> void:
	_clear_native_tile_highlights()
	var key := str(stage.get("key", ""))
	var called: Array = _settlement_plan.get("called", [false, false, false, false])
	var burned := int(_settlement_plan.get("burned", -1))
	if key in ["flip", "chicken"] and not bool(_settlement_plan.get("is_draw", false)):
		var gold: Array = _settlement_plan.get("gold_tiles", [])
		var flip_tiles: Array = _settlement_plan.get("flip_tiles", [])
		for seat in 4:
			if seat == burned or seat >= called.size() or not bool(called[seat]):
				continue
			for tile in _native_tiles_for_seat(seat):
				var value: String = tile.tile
				var matches: bool = value in flip_tiles if key == "flip" else (TILES.is_chicken(value) and value not in gold)
				tile.set_score_highlight(matches)
	elif key == "kong":
		var matrix: Array = stage.get("matrix", _settlement_zero_matrix())
		for seat in 4:
			if seat == burned or seat >= called.size() or not bool(called[seat]):
				continue
			var has_kong := false
			for other in 4:
				if not is_zero_approx(float(matrix[seat][other])):
					has_kong = true
					break
			if not has_kong:
				continue
			for tile in _native_meld_tiles(seat):
				tile.set_score_highlight(true)

func _native_tiles_for_seat(seat: int) -> Array[TileView]:
	var out: Array[TileView] = []
	for box in [hand_boxes[seat], draw_boxes[seat]]:
		if box == null:
			continue
		for child in box.get_children():
			if child is TileView:
				out.append(child)
	for child in _meld_layer.get_children():
		if child is TileView and int(child.get_meta("v2_seat", -1)) == seat:
			out.append(child)
	for child in _red_layer.get_children():
		if child is TileView and int(child.get_meta("v2_seat", -1)) == seat:
			out.append(child)
	return out

func _native_meld_tiles(seat: int) -> Array[TileView]:
	var out: Array[TileView] = []
	for child in _meld_layer.get_children():
		if child is TileView and int(child.get_meta("v2_seat", -1)) == seat:
			out.append(child)
	for child in _red_layer.get_children():
		if child is TileView and int(child.get_meta("v2_seat", -1)) == seat and str(child.get_meta("v2_red_kind", "")) in ["kong", "add_kong"]:
			out.append(child)
	return out

func _clear_native_tile_highlights() -> void:
	for seat in 4:
		for tile in _native_tiles_for_seat(seat):
			if is_instance_valid(tile):
				tile.set_score_highlight(false)

func _roll_native_pairs(progress: float, before: Array, after: Array) -> void:
	var scores := _settlement_zero_matrix()
	for seat in 4:
		for other in 4:
			scores[seat][other] = roundf(lerpf(float(before[seat][other]), float(after[seat][other]), progress))
	_render_native_pairs(scores)

func _render_native_pairs(scores: Array) -> void:
	for first in 4:
		for second in range(first + 1, 4):
			var net: float = scores[first][second] - scores[second][first]
			_settlement_pairs[first][second] = net
			_settlement_pairs[second][first] = -net
	var total := 0.0
	for index in 3:
		# Each player sees their own upper, opposite and lower seats.
		var other := posmod(human_seat + index + 1, 4)
		var net: float = _settlement_pairs[human_seat][other]
		_set_native_score(_settlement_score_rows[0][index], scores[human_seat][other])
		_set_native_score(_settlement_score_rows[1][index], scores[other][human_seat])
		_set_native_score(_settlement_score_rows[2][index], net)
		total += net
	_set_native_score(_settlement_total_label, total)

func _set_native_score(label: Label, value: float) -> void:
	label.text = _settlement_signed(value)
	label.add_theme_color_override("font_color", _settlement_net_color(value))

func _begin_native_final() -> void:
	_end_native_stage()
	_show_native_settlement_notice("本局得分汇总")
	_render_native_pairs(_settlement_final_scores)

func _roll_native_final(progress: float) -> void:
	var elapsed := progress * _settlement_count_duration
	for seat in 4:
		var delta := float(_settlement_plan.get("deltas", [0.0, 0.0, 0.0, 0.0])[seat])
		var duration := _native_score_duration_for_delta(delta)
		var fraction := clampf(elapsed / duration, 0.0, 1.0) if duration > 0 else 1.0
		_settlement_display_scores[seat] = _native_counted_score(float(_settlement_start_scores[seat]), float(_settlement_target_scores[seat]), fraction)
		if seat < _labels.size(): _set_seat_score(_labels[seat], _settlement_display_scores[seat])

func _native_counted_score(from: float, to: float, progress: float) -> float:
	if progress >= 1.0:
		return to
	var difference := to - from
	var step := 2.0 if absf(difference) > 60.0 else 1.0
	var ticks := floorf(clampf(progress, 0.0, 1.0) * ceilf(absf(difference) / step))
	return from + signf(difference) * minf(absf(difference), ticks * step)

func _native_score_duration_for_delta(delta: float) -> float:
	var step := 2.0 if absf(delta) > 60.0 else 1.0
	return minf(UI.SETTLEMENT_COUNT_MAX_SECONDS, ceilf(absf(delta) / step) * UI.SETTLEMENT_COUNT_SECONDS)

func _settlement_zero_matrix() -> Array:
	return [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]

func _settlement_add_matrix(first: Array, second: Array) -> Array:
	var sum := first.duplicate(true)
	for seat in 4:
		for other in 4:
			sum[seat][other] = float(sum[seat][other]) + float(second[seat][other])
	return sum

func _settlement_matrix_changed(matrix: Array) -> bool:
	for row in matrix:
		for value in row:
			if not is_zero_approx(float(value)):
				return true
	return false

func _table_text(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", TileView._font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label

func _settlement_signed(value: float) -> String:
	return "%+.0f" % value if not is_zero_approx(value) else "0"

func _settlement_net_color(value: float) -> Color:
	return UI.SCORE_GAIN if value > 0.0 else (UI.SCORE_LOSS if value < 0.0 else UI.MUTED)

func _native_apply_speed() -> void:
	if not native_settlement_active():
		return
	if GameConfig.settlement_step_seconds() == 0.0:
		_finish_native_settlement()
		return
	if bool(_settlement_plan.get("all_called_draw", false)):
		return
	if _settlement_tween != null and _settlement_tween.is_valid():
		_settlement_tween.set_speed_scale(1.0 / GameConfig.settlement_duration(1.0))

func _layer(node_name: String) -> Control:
	var layer := Control.new()
	layer.name = node_name
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	return layer

func set_round(value, seat: int) -> void:
	if value != round or seat != human_seat:
		_reset_round_visual_state()
	round = value
	human_seat = seat
	refresh()

func set_table(host) -> void:
	table = host
	if table != null:
		round = table.round
		human_seat = table.human_seat
	refresh()

func _exit_tree() -> void:
	if _arrangement_thread != null: _arrangement_thread.wait_to_finish()
	_cancel_motion_tweens()
	if _tile_pool != null:
		_tile_pool.clear()

func sync_animation_proxies() -> void:
	pass

func hand_slot_center(seat: int, slot: int) -> Vector2:
	return _hand_center(seat, slot, _current_hand_count(seat))

func draw_slot_center(seat: int) -> Vector2:
	return _draw_center(seat, _current_hand_count(seat))

func _hand_center(seat: int, slot: int, count: int) -> Vector2:
	var held: Array = _held_hand_centers.get(seat, [])
	return Vector2(held[slot]) if slot >= 0 and slot < held.size() else G.hand_slot_center(seat, slot, human_seat, count)

func _draw_center(seat: int, count: int) -> Vector2:
	var held: Array = _held_hand_centers.get(seat, [])
	if held.is_empty(): return G.draw_slot_center(seat, human_seat, count)
	var direction: Vector2 = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN][G.relative_seat(human_seat, seat)]
	var edge: Vector2 = held[0]
	for center: Vector2 in held:
		if center.dot(direction) > edge.dot(direction): edge = center
	var separation := G.hand_tile_size(seat, human_seat).x + 20.0
	var target := edge + direction * separation
	if target.dot(direction) <= G.draw_slot_center(seat, human_seat, 13).dot(direction): return target
	# 原摸牌未参与暗杠时，补牌利用杠牌腾出的空位，避免伸入邻家区域。
	for slot in range(12, -1, -1):
		var candidate := G.hand_slot_center(seat, slot, human_seat, 13)
		if held.all(func(center): return absf((candidate - Vector2(center)).dot(direction)) >= separation):
			return candidate
	return G.draw_slot_center(seat, human_seat, count)

func _current_hand_count(seat: int) -> int:
	if round == null or seat < 0 or seat >= round.players.size(): return 13
	var player = round.players[seat]
	return maxi(1, player.concealed.size() - (1 if player.just_drew != "" else 0))

func action_bar_rect(row_size: Vector2) -> Rect2:
	var count := _current_hand_count(human_seat)
	var size := G.hand_tile_size(human_seat, human_seat)
	var right := G.hand_slot_center(human_seat, count - 1, human_seat, count).x + size.x / 2.0
	var held: Array = _held_hand_centers.get(human_seat, [])
	if not held.is_empty():
		right = -INF
		for center: Vector2 in held: right = maxf(right, center.x + size.x / 2.0)
	return Rect2(Vector2(right - row_size.x, G.ACTION_TOP), row_size)

## 新弃牌落点（屏幕坐标）。普通弃牌按非鸡牌顺序，鸡牌用红色区落点。
func hand_source_global(seat: int, concealed_index: int) -> Vector2:
	for box in [hand_boxes[seat], draw_boxes[seat]]:
		for tile in box.get_children():
			if int(tile.get_meta("concealed_index", -2)) == concealed_index:
				return tile.get_global_transform() * (tile.size / 2.0)
	return Vector2.ZERO

func draw_source_global(seat: int) -> Vector2:
	for tile in draw_boxes[seat].get_children():
		return tile.get_global_transform() * (tile.size / 2.0)
	return Vector2.ZERO

func meld_tile_global(seat: int, meld_index: int, meld_slot: int = -1) -> Vector2:
	for tile in _red_layer.get_children():
		if int(tile.get_meta("v2_seat", -1)) != seat: continue
		if int(tile.get_meta("meld_index", -2)) != meld_index: continue
		if meld_slot >= 0 and int(tile.get_meta("meld_slot", -2)) != meld_slot: continue
		return tile.get_global_transform() * (tile.size / 2.0)
	return Vector2.ZERO

func discard_target_global(seat: int, discard_id: int) -> Vector2:
	if table == null or table.round == null: return Vector2.ZERO
	var p = table.round.players[seat]
	var idx: int = -1
	for i in p.discard_ids.size():
		if int(p.discard_ids[i]) == discard_id:
			idx = i
			break
	if idx < 0: return Vector2.ZERO
	var chicken := TILES.is_chicken(str(p.discards[idx]))
	var index := 0
	for i in idx:
		if TILES.is_chicken(str(p.discards[i])) == chicken: index += 1
	var center := _chicken_slot_center(seat, index) if chicken \
		else G.ordinary_slot_center(seat, index, human_seat, _ordinary_count(seat))
	return get_global_transform() * center

## WallRing 单张下标 -> 牌墙牌背中心。
func wall_center_for_index(index: int) -> Vector2:
	var segment := _wall_segment_for_index(index)
	if segment.is_empty(): return G.CENTER
	var side := _wall_screen_seat(int(segment.seat))
	var columns := int(segment.len) / 2
	var slot := (index - int(segment.start)) / 2
	if side in [1, 2]: slot = columns - 1 - slot
	return G.wall_block_center(side, slot, index % 2, columns)

func _wall_screen_seat(seat: int) -> int:
	# 牌墙逻辑座位固定，屏幕南侧始终对应本家。
	return posmod(seat - human_seat + 1, 4)

func _wall_segment_for_index(index: int) -> Dictionary:
	for segment in WallRing.SEG.values():
		if index >= int(segment.start) and index < int(segment.start) + int(segment.len):
			return segment
	return {}

func _wall_angle_for_index(index: int) -> float:
	var segment := _wall_segment_for_index(index)
	return G.wall_angle(_wall_screen_seat(int(segment.seat))) if not segment.is_empty() else 0.0

func refresh() -> void:
	if table != null and table.round != null \
			and (table.round != round or table.human_seat != human_seat):
		_reset_round_visual_state()
		round = table.round
		human_seat = table.human_seat
	if native_presentation_pending():
		return
	if table != null:
		round = table.round
		human_seat = table.human_seat
	if round == null:
		return
	if _wall_layer == null: _build_layers()
	if round.phase == ROUND_STATE.Phase.SETTLED: _held_hand_centers.clear()
	snapshot = MODEL.build(round, human_seat)
	var all_dealt_now := false
	if auto_sort_hands and not test_frozen and table != null \
			and table._table_animation_controller != null:
		all_dealt_now = true
		for seat in 4:
			if table._table_animation_controller.dealt_count(seat) < 13: all_dealt_now = false
	_begin_tile_reconcile()
	_clear(_debug_layer)
	_build_wall()
	_build_hands()
	_exposed_specs.clear()
	if not test_frozen:
		_build_discards()
		_build_melds()
	_refresh_hand_arrangement()
	_end_tile_reconcile()
	_refresh_hud()
	_layout_meld_badges()
	if is_instance_valid(_score_inspection):
		_score_inspection.refresh()
	if all_dealt_now and not _sort_started:
		_begin_hand_sort()
	_build_wall_debug()
	if round.phase == ROUND_STATE.Phase.SETTLED and is_instance_valid(_dice_red):
		clear_dice_visual()
	queue_redraw()

## 同一牌桌实例会跨局复用；RoundState 变化时必须清掉上一局的瞬时视觉状态。
func _reset_round_visual_state() -> void:
	_local_arrangement = {}
	_arrangement_key = ""
	_arrangement_choices.clear()
	for badge in _ready_meld_badges + _dealer_meld_badges: badge.hide()
	if _settlement_started:
		reset_native_settlement()
	_deal_generation += 1
	_cancel_motion_tweens()
	_visual_actions.clear()
	_render_tiles.clear()
	_render_seen.clear()
	_reconciling = false
	_label_signature = ""
	_latest_discard_seat = -1
	_latest_discard_id = -1
	if _deal_tween != null and _deal_tween.is_valid():
		_deal_tween.kill()
	if _sort_tween != null and _sort_tween.is_valid():
		_sort_tween.kill()
	_deal_tween = null
	_sort_tween = null
	deal_animation_active = false
	_sort_started = false
	_sort_animating = false
	_draw_flights.clear()
	_pending_draws = {0: "", 1: "", 2: "", 3: ""}
	_held_hand_centers.clear()
	_deal_moving.clear()
	_deal_done_callback = Callable()
	_frozen_hands.clear()
	_discard_flights.clear()
	if _deal_layer != null:
		_clear(_deal_layer)
	clear_dice_visual()

func visual_recovery_pending() -> bool:
	return native_actions_pending() or deal_animation_active or _sort_animating or _draw_animating \
		or not _discard_flights.is_empty() \
		or (_deal_tween != null and _deal_tween.is_valid()) \
		or (_sort_tween != null and _sort_tween.is_valid())

func native_actions_pending() -> bool:
	return not _visual_actions.is_empty()

func native_presentation_pending() -> bool:
	return native_actions_pending() or deal_animation_active or _sort_animating \
		or _draw_animating or not _discard_flights.is_empty()

func _begin_visual_action() -> int:
	_visual_action_id += 1
	_visual_actions[_visual_action_id] = true
	deal_animation_active = true
	return _visual_action_id

func _complete_visual_action(action_id: int, done: Callable) -> void:
	if not _visual_actions.erase(action_id): return
	deal_animation_active = native_actions_pending()
	_layout_meld_badges()
	if done.is_valid(): done.call()
	if not native_actions_pending() and is_instance_valid(table) and table.is_inside_tree():
		table.call_deferred("_refresh")

func _motion_tween() -> Tween:
	var tween := create_tween()
	_motion_tweens.append(tween)
	tween.finished.connect(_forget_motion_tween.bind(weakref(tween)), CONNECT_ONE_SHOT)
	return tween

func _forget_motion_tween(ref: WeakRef) -> void:
	_motion_tweens.erase(ref.get_ref())

func _cancel_motion_tweens() -> void:
	for tween in _motion_tweens:
		if is_instance_valid(tween): tween.kill()
	_motion_tweens.clear()

func recover_after_resume() -> void:
	# Do not keep suspended mobile Tweens alive. The caller refreshes from the
	# authoritative round after this method clears every transient visual.
	_reset_round_visual_state()
	# A resumed game restores an authoritative in-progress snapshot; replaying
	# the opening sort would move already-settled hands again.
	_sort_started = true

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, G.DESIGN_SIZE), UI.BACKGROUND)
	# 外层阴影
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0.01, 0.04, 0.03, 0.55)
	shadow.set_corner_radius_all(20)
	draw_style_box(shadow, G.TABLE_BOUNDS.grow(10))
	# 深色木质外框 + 金色细线
	var frame := StyleBoxFlat.new()
	frame.bg_color = UI.TABLE_FRAME
	frame.border_color = UI.TABLE_FRAME_BORDER
	frame.set_border_width_all(3)
	frame.set_corner_radius_all(16)
	draw_style_box(frame, G.TABLE_BOUNDS)
	var gold_line := StyleBoxFlat.new()
	gold_line.bg_color = Color.TRANSPARENT
	gold_line.border_color = Color(UI.GOLD, 0.32)
	gold_line.set_border_width_all(1)
	gold_line.set_corner_radius_all(13)
	draw_style_box(gold_line, G.TABLE_BOUNDS.grow(-6))
	# 绒面内桌 + 内侧收边
	var felt := StyleBoxFlat.new()
	felt.bg_color = UI.FELT
	felt.border_color = UI.FELT_BORDER
	felt.set_border_width_all(2)
	felt.set_corner_radius_all(12)
	draw_style_box(felt, G.TABLE_BOUNDS.grow(-14))
	var felt_inner := StyleBoxFlat.new()
	felt_inner.bg_color = Color.TRANSPARENT
	felt_inner.border_color = Color(UI.FELT_INNER_BORDER, 0.55)
	felt_inner.set_border_width_all(1)
	felt_inner.set_corner_radius_all(10)
	draw_style_box(felt_inner, G.TABLE_BOUNDS.grow(-22))
	# 当前行动玩家：手牌外侧金色引导线。
	if table != null and table.round != null \
			and table.round.phase == ROUND_STATE.Phase.PLAYING:
		var active := int(table.round.current_turn)
		var rect := G.hand13_rect(active, human_seat)
		var rel := G.relative_seat(human_seat, active)
		var line_color := Color(UI.GOLD, 0.58)
		match rel:
			0:
				draw_line(Vector2(rect.position.x, rect.end.y + 10.0),
					Vector2(rect.end.x, rect.end.y + 10.0), line_color, 3.0)
			2:
				draw_line(Vector2(rect.position.x, rect.position.y - 10.0),
					Vector2(rect.end.x, rect.position.y - 10.0), line_color, 3.0)
			1:
				draw_line(Vector2(rect.end.x + 10.0, rect.position.y),
					Vector2(rect.end.x + 10.0, rect.end.y), line_color, 3.0)
			_:
				draw_line(Vector2(rect.position.x - 10.0, rect.position.y),
					Vector2(rect.position.x - 10.0, rect.end.y), line_color, 3.0)

func _clear(layer: Control) -> void:
	for child in layer.get_children():
		_release_visual_node(child)

func _clear_hand_tiles() -> void:
	for box in hand_boxes + draw_boxes:
		for child in box.get_children():
			_release_visual_node(child)

func _release_visual_node(node: Node) -> void:
	if not is_instance_valid(node): return
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	if node is TileView:
		_tile_pool.release(node)
	else:
		node.queue_free()

func highlight_ai_teach(tiles: Array) -> void:
	for seat in 4:
		for box in [hand_boxes[seat], draw_boxes[seat]]:
			for node in box.get_children():
				if node is TileView:
					node.ai_teach_highlight = str(node.tile) in tiles
					node.queue_redraw()

func clear_ai_teach_highlights() -> void:
	highlight_ai_teach([])

func _face_visible(seat: int) -> bool:
	var settled_reveal: bool = round != null and round.phase == ROUND_STATE.Phase.SETTLED
	return seat == human_seat or settled_reveal or (test_reveal_all_hands and not formal_mode)

func _tile(layer: Control, card: String, face_up: bool, center: Vector2, unit: float, angle: float) -> TileView:
	var tile := _tile_pool.acquire()
	tile.set_card(card, face_up)
	tile.set_unit(unit)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.z_index = 0
	tile.back_depth_top = false
	tile.modulate = Color.WHITE
	tile.self_modulate = Color.WHITE
	tile.scale = Vector2.ONE
	layer.add_child(tile)
	# A pooled Control can retain the previous container-assigned size even
	# though set_unit() already changed its minimum size.  Reset the rectangle
	# after parenting so every visual layer obeys the requested unit.
	tile.reset_size()
	tile.pivot_offset = tile.size / 2.0
	tile.position = center - tile.size / 2.0
	tile.rotation = angle
	return tile

## Keep unchanged public tiles and hand entities in the tree. A snapshot is a
## reconciliation, not an entrance animation for every tile already on the table.
func _render_key(node: TileView) -> String:
	var seat := int(node.get_meta("v2_seat", -1))
	match str(node.get_meta("new_kind", "")):
		"wall": return "wall:%d" % int(node.get_meta("wall_ring_index", -1))
		"ordinary": return "discard:%d:%d" % [seat, int(node.get_meta("discard_id", -1))]
		"hand": return "hand:%d:%d" % [seat, int(node.get_meta("concealed_index", -1))]
		"draw": return "draw:%d" % seat
		"meld": return "meld:%d:%d:%d" % [seat, int(node.get_meta("meld_index", -1)), int(node.get_meta("meld_slot", -1))]
		"red":
			if int(node.get_meta("meld_index", -1)) >= 0:
				return "red-meld:%d:%d:%d" % [seat, int(node.get_meta("meld_index", -1)), int(node.get_meta("meld_slot", -1))]
			return "red-discard:%d:%d" % [seat, int(node.get_meta("discard_id", -1))]
	return ""

func _render_layers() -> Array:
	return [_wall_layer, _discard_layer, _red_layer, _meld_layer] + hand_boxes + draw_boxes

func _begin_tile_reconcile() -> void:
	_render_tiles.clear()
	_render_seen.clear()
	_reconciling = true
	for layer in _render_layers():
		for node in layer.get_children():
			if not (node is TileView): continue
			var key := _render_key(node)
			if key != "" and not _render_tiles.has(key): _render_tiles[key] = node

func _sync_tile(layer: Control, key: String, card: String, face: bool, center: Vector2,
		unit: float, angle: float, visual_scale: Vector2 = Vector2.ONE) -> TileView:
	var node: TileView = _render_tiles.get(key) if _reconciling else null
	if node == null or not is_instance_valid(node) or node.get_parent() != layer:
		node = _tile(layer, card, face, center, unit, angle)
	else:
		if node.tile != card or node.face_up != face: node.set_card(card, face)
		if not is_equal_approx(node.unit, unit): node.set_unit(unit)
		node.pivot_offset = node.size / 2.0
		node.position = center - node.size / 2.0
		node.rotation = angle
		node.modulate = Color.WHITE
		node.visible = true
	node.scale = visual_scale
	if _reconciling: _render_seen[node.get_instance_id()] = true
	return node

func _end_tile_reconcile() -> void:
	for layer in _render_layers():
		for node in layer.get_children():
			if node is TileView and not _render_seen.has(node.get_instance_id()):
				_release_visual_node(node)
	_render_tiles.clear()
	_render_seen.clear()
	_reconciling = false

func _build_discards() -> void:
	for data in snapshot.get("seats", []):
		var seat := int(data.seat)
		var rel := G.relative_seat(human_seat, seat)
		var ordinary_index := 0
		var chicken_index := 0
		for i in range(data.discards.size()):
			var card := str(data.discards[i])
			var chicken := TILES.is_chicken(card)
			if not chicken and ordinary_index >= G.river_capacity(rel): continue
			var charge := chicken and bool(data.discard_charge[i])
			var discard_id := int(data.discard_ids[i]) if i < data.discard_ids.size() else i
			var center := _chicken_slot_center(seat, chicken_index) if chicken \
				else G.ordinary_slot_center(seat, ordinary_index, human_seat, _ordinary_count(seat))
			var layer := _red_layer if chicken else _discard_layer
			var key := "red-discard" if chicken else "discard"
			var tile := _sync_tile(layer, "%s:%d:%d" % [key, seat, discard_id], card, true, center,
				1.0 if chicken else G.ORDINARY_UNIT, UI.ROTATIONS[rel] + (PI / 2.0 if charge else 0.0),
				_exposed_size(seat) / G.TILE_BASE if chicken else Vector2.ONE)
			_set_river_tile(tile, seat, discard_id, chicken, charge)
			if chicken: chicken_index += 1
			else: ordinary_index += 1

func _exposed_layout() -> Array:
	if round == null: return []
	var state: Array = [human_seat, round.phase, round.dealer_seat, _held_hand_centers]
	for player in round.players:
		state.append([player.concealed, player.just_drew, player.melds, player.discards,
			player.discard_ids, player.discard_count, player.ready])
	var key := hash(state)
	if _exposed_specs.is_empty() or key != _exposed_key:
		_exposed_key = key
		_exposed_specs = EXPOSED.solve(self)
	return _exposed_specs

func _exposed_size(seat: int) -> Vector2:
	return EXPOSED.size_for(G.relative_seat(human_seat,seat))

func _chicken_slot_center(seat: int, index: int) -> Vector2:
	var ids: Array = []
	for i in round.players[seat].discards.size():
		if TILES.is_chicken(str(round.players[seat].discards[i])): ids.append(round.players[seat].discard_ids[i])
	for spec in _exposed_layout():
		if spec.seat == seat and spec.meld_index < 0 and index < ids.size() and spec.discard_id == ids[index]: return spec.center
	return G.meld_anchor(seat,human_seat)

func _set_river_tile(tile: TileView, seat: int, discard_id: int, chicken: bool, charge: bool) -> void:
	tile.set_meta("new_kind", "red" if chicken else "ordinary")
	tile.set_meta("v2_seat", seat)
	tile.set_meta("discard_id", discard_id)
	tile.set_meta("meld_index", -1)
	tile.set_meta("v2_charge", charge)
	tile.modulate = Color.WHITE
	# 出牌鸡归属碰杠区；结算只隐藏普通牌河。
	tile.visible = chicken or not _settlement_started
	tile.set_latest_highlight(seat == _latest_discard_seat and discard_id == _latest_discard_id)

## Use the same positions for live fly-in, reconnect and the revealed settlement hand.
func meld_layout(_melds: Array, seat: int, _rel: int) -> Array:
	return _exposed_layout().filter(func(spec): return int(spec.seat)==seat and int(spec.meld_index)>=0)

func _visual_rect(node: Control) -> Rect2:
	# Red tiles are direct children. Stay in the parent coordinate space;
	# inverse global transforms introduce scale-dependent rounding drift.
	var xf: Transform2D = node.get_transform()
	var points := [
		xf * Vector2.ZERO,
		xf * Vector2(node.size.x, 0.0),
		xf * node.size,
		xf * Vector2(0.0, node.size.y),
	]
	var rect := Rect2(points[0], Vector2.ZERO)
	for i in range(1, points.size()):
		rect = rect.expand(points[i])
	return rect

## A flight can cross a board area even when both endpoints are clear.
## Use the largest projected footprint along the path. Blocked movements
## commit at their destination without drawing a crossing frame.
func _motion_would_cover(node: Control, target: Vector2, target_size: Vector2, angle: float) -> bool:
	var start := _visual_rect(node)
	var axes := Vector2(absf(cos(angle)), absf(sin(angle)))
	var end_size := Vector2(target_size.dot(axes), target_size.dot(Vector2(axes.y, axes.x)))
	var half := start.size.max(end_size) / 2.0
	if not is_zero_approx(angle_difference(node.rotation, angle)):
		var radius := maxf(start.size.length(), target_size.length()) / 2.0
		half = Vector2.ONE * radius
	var from := start.get_center()
	for layer in _render_layers() + [_label_layer, _action_layer]:
		for other in layer.get_children():
			if other == node or not (other is Control) or not other.is_visible_in_tree():
				continue
			var obstacle := _visual_rect(other).grow(-0.1)
			obstacle = Rect2(obstacle.position - half, obstacle.size + half * 2.0)
			if _segment_crosses_rect(from, target, obstacle):
				return true
	return false

func _segment_crosses_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	if rect.has_point(from) or rect.has_point(to):
		return true
	var a := rect.position
	var c := rect.end
	var corners := [a, Vector2(c.x, a.y), c, Vector2(a.x, c.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(from, to, corners[i], corners[(i + 1) % 4]) != null:
			return true
	return false

func _opening_mode() -> bool:
	if table == null or table.round == null: return false
	if table.round.phase == ROUND_STATE.Phase.SETTLED: return false
	if test_frozen: return true
	if table._table_animation_controller != null \
			and table._table_animation_controller.visual_hold_active():
		return true
	if table.round.phase == ROUND_STATE.Phase.DEALING: return true
	if table._table_animation_controller != null \
			and table._table_animation_controller.deal_sequence_active():
		return true
	return table._table_animation_controller != null \
		and table._table_animation_controller.opening_active()

func _opening_visual_gate() -> bool:
	return table != null and table._table_animation_controller != null \
		and table._table_animation_controller.dice_gate_active()

func _shown_draws() -> int:
	if not _opening_mode() or table == null: return -1
	if table._table_animation_controller == null: return 0
	if _opening_visual_gate(): return 0
	var total := 0
	for seat in 4: total += table._table_animation_controller.dealt_count(seat)
	return total

func _wall_slots(seat: int) -> Array:
	var shown := _shown_draws()
	if table != null and table.round != null and table.round.wall != null:
		if shown >= 0:
			return table.round.wall.debug_stack_slots_at(seat, shown)
		return table.round.wall.wall_stack_slots(seat)
	var slots: Array = snapshot.get("wall_slots", [])[seat] if seat < snapshot.get("wall_slots", []).size() else []
	if shown >= 0 and table != null and table.round != null:
		var meta: Dictionary = table.round.round_meta
		var start := int(meta.get("break", -1))
		# A current server sends the post-deal wall before the animation plays.
		# The opening takes consecutive head slots, so replay only the shown draws.
		if meta.has("die_white") and start >= 0 and start < WallRing.N:
			var opening_slots: Array = []
			for col in slots.size():
				var index := _wall_ring_index(seat, col, 0)
				opening_slots.append([posmod(index - start, WallRing.N) >= shown,
					posmod(index + 1 - start, WallRing.N) >= shown])
			return opening_slots
	return slots

func _build_wall() -> void:
	if keep_removed_wall_gray and round != null and round.wall != null:
		_build_wall_with_gray()
		return
	var slots: Array = []
	for seat in 4: slots.append(_wall_slots(seat))
	for seat in mini(4, slots.size()):
		var blocks: Array = slots[seat]
		for slot in blocks.size():
			var layers: Array = blocks[slot]
			for row in [1, 0]:
				var present := bool(layers[row])
				if not present and not keep_removed_wall_gray: continue
				var wall_card := _wall_value(seat, slot, row) if wall_face_up else ""
				var tile := _sync_wall_tile(seat, slot, row, wall_card, wall_face_up)
				if not present:
					tile.modulate = Color(0.34, 0.34, 0.34, 1.0)

func _build_wall_with_gray() -> void:
	var shown := _shown_draws()
	if shown < 0: shown = round.wall.draw_log.size()
	var removed := {}
	for i in mini(shown, round.wall.draw_log.size()):
		removed[int(round.wall.draw_log[i].get("index", -1))] = true
	for seat in 4:
		var count := 14 if seat in [1, 3] else 13
		for slot in count:
			for row in [1, 0]:
				var index := _wall_ring_index(seat, slot, row)
				var tile := _sync_wall_tile(seat, slot, row, _wall_value(seat, slot, row), true)
				if removed.has(index):
					tile.modulate = Color(0.34, 0.34, 0.34, 1.0)

func _sync_wall_tile(seat: int, slot: int, row: int, card: String, face: bool) -> TileView:
	var index := _wall_ring_index(seat, slot, row)
	if index == _settlement_flip_index and is_instance_valid(_settlement_flip_view):
		_render_seen[_settlement_flip_view.get_instance_id()] = true
		return _settlement_flip_view
	var revealed := _settlement_flip_revealed and index == _settlement_flip_index
	var side := _wall_screen_seat(seat)
	var tile := _sync_tile(_wall_layer, "wall:%d" % index, _native_flip_tile() if revealed else card,
		revealed or face, wall_center_for_index(index), G.WALL_UNIT, G.wall_angle(side))
	tile.back_depth_top = side == 1
	tile.z_index = 2 if revealed else (1 if row == 0 else 0)
	tile.set_meta("new_kind", "wall")
	tile.set_meta("wall_ring_index", index)
	if tile.score_highlight:
		tile.set_score_highlight(false)
	return tile

func _wall_ring_index(seat: int, physical_slot: int, row: int) -> int:
	var starts := {3: 0, 0: 28, 1: 54, 2: 82}
	var counts := {3: 14, 0: 13, 1: 14, 2: 13}
	var logical := physical_slot
	if seat in [1, 2]:
		logical = int(counts[seat]) - 1 - physical_slot
	return int(starts[seat]) + logical * 2 + row

## 测试模式：牌墙按实际墙列取真实牌面。
func _wall_value(seat: int, physical_slot: int, row: int) -> String:
	if round == null or round.wall == null: return ""
	var ring: Array = round.wall._ring
	if ring.size() != 108: return ""
	var index := _wall_ring_index(seat, physical_slot, row)
	return str(ring[index]) if index >= 0 and index < 108 else ""

## 开局四张整体拿牌：下层两张在左、上层两张在右；第二批/第三批先到右侧再居中。
func animate_deal_group(seat: int, cards: Array, indices: Array, existing: int, done: Callable, time_scale: float = 1.0) -> void:
	if cards.is_empty() or cards.size() != indices.size() \
			or indices.any(func(index): return int(index) < 0 or int(index) >= WallRing.N):
		# Old rooms omit the source slots. Keep the deal order without a false flight.
		done.call()
		return
	deal_animation_active = true
	_deal_generation += 1
	var generation := _deal_generation
	_clear(_deal_layer)
	var rel := G.relative_seat(human_seat, seat)
	var hand_unit := G.hand_unit(seat, human_seat)
	var entries: Array = []
	for i in cards.size():
		var idx := int(indices[i])
		entries.append({"card": str(cards[i]), "index": idx, "row": idx % 2, "pos": i})
	# 下层(index奇数)在左，上层(index偶数)在右；同层保持摸牌先后。
	entries.sort_custom(func(a, b):
		if a.row == b.row: return a.pos < b.pos
		return a.row > b.row)
	var final_count := existing + cards.size()
	# 四家统一用实际手牌槽位推导“右方向”和步进，不写死座位方向。
	var slot0 := G.hand_slot_center(seat, 0, human_seat, final_count, false)
	var slot1 := G.hand_slot_center(seat, 1, human_seat, final_count, false)
	var dir: Vector2 = (slot1 - slot0).normalized()
	var hand_step: float = slot0.distance_to(slot1)

	if dir == Vector2.ZERO: dir = Vector2(1, 0)
	var last_center := Vector2.ZERO
	if existing > 0:
		last_center = G.hand_slot_center(seat, existing - 1, human_seat, existing, false)
	var right_targets: Array = []
	for k in cards.size():
		if existing > 0:
			right_targets.append(last_center + dir * hand_step * float(k + 1))
		else:
			right_targets.append(G.hand_slot_center(seat, k, human_seat, final_count, false))
	var final_targets: Array = []
	for k in cards.size():
		final_targets.append(G.hand_slot_center(seat, existing + k, human_seat, final_count, false))
	var moving: Array = []
	_deal_moving = moving
	_deal_done_callback = done
	for entry in entries:
		var index := int(entry.index)
		var tile := _tile(_deal_layer, entry.card, _face_visible(seat),
			wall_center_for_index(index), hand_unit, _wall_angle_for_index(index))
		tile.scale = Vector2.ONE * (G.WALL_UNIT / hand_unit)
		moving.append(tile)
	# 起飞前移除对应墙牌。
	var remove := {}
	for idx in indices: remove[int(idx)] = true
	for node in _wall_layer.get_children():
		if remove.has(int(node.get_meta("wall_ring_index", -2))):
			node.visible = false
	var flight := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var flight_seconds := GameConfig.DEAL_FLIGHT_SECONDS * time_scale
	var recenter_seconds := GameConfig.DEAL_RECENTER_SECONDS * time_scale
	_deal_tween = flight
	for k in moving.size():
		var tile: TileView = moving[k]
		flight.tween_property(tile, "position", right_targets[k] - tile.size / 2.0, flight_seconds)
		flight.tween_property(tile, "scale", Vector2.ONE, flight_seconds)
		flight.tween_property(tile, "rotation", UI.ROTATIONS[rel], flight_seconds)
	flight.chain().tween_callback(func():
		if existing == 0:
			_finish_deal_group(moving, done)
			return
		var recenter := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_deal_tween = recenter
		var nodes: Array = hand_boxes[seat].get_children()
		for s in mini(existing, nodes.size()):
			var node: Control = nodes[s]
			recenter.tween_property(node, "position",
				G.hand_slot_center(seat, s, human_seat, final_count, false) - node.size / 2.0, recenter_seconds)
		for k in moving.size():
			var tile: TileView = moving[k]
			recenter.tween_property(tile, "position",
				final_targets[k] - tile.size / 2.0, recenter_seconds)
		recenter.chain().tween_callback(func(): _finish_deal_group(moving, done))
	)
	# 动画异常中断时兜底结束，避免整局卡在某一组。
	var timer := get_tree().create_timer(flight_seconds + recenter_seconds + 0.4)
	timer.timeout.connect(_on_deal_anim_timeout.bind(generation))

func _on_deal_anim_timeout(generation: int) -> void:
	if generation == _deal_generation and deal_animation_active:
		_finish_deal_group(_deal_moving, _deal_done_callback)

func _finish_deal_group(moving: Array, done: Callable) -> void:
	_deal_generation += 1
	if _deal_tween != null and _deal_tween.is_valid(): _deal_tween.kill()
	_deal_tween = null
	_deal_moving = []
	_deal_done_callback = Callable()
	for tile in moving:
		_release_visual_node(tile)
	deal_animation_active = false
	if done.is_valid(): done.call()

## 排序后摸牌：从墙牌位置飞到摸牌区，同时放大到手牌尺寸。
func animate_draw(seat: int, card: String, wall_index: int, done: Callable) -> void:
	_finish_pending_draw(seat)
	var action_id := _begin_visual_action()
	_pending_draws[seat] = card
	var hand_unit := G.hand_unit(seat, human_seat)
	var rel := G.relative_seat(human_seat, seat)
	# 摸牌事件前的刷新可能已按14张建了手牌；移掉其中一张摸牌，恢复13张。
	var existing: Array = hand_boxes[seat].get_children()
	if existing.size() > 13:
		for node in existing:
			if str(node.tile) == card:
				_release_visual_node(node)
				break
	for node in draw_boxes[seat].get_children():
		_release_visual_node(node)
	existing = hand_boxes[seat].get_children()
	for slot in mini(13, existing.size()):
		var node: Control = existing[slot]
		node.position = _hand_center(seat, slot, 13) - node.size / 2.0
	var hand_count: int = mini(13, hand_boxes[seat].get_child_count())
	# 开始飞行前把现有手牌校准到“无摸牌”的居中位置，避免第一次摸牌用到旧位置。
	var hand_nodes: Array = hand_boxes[seat].get_children()
	for slot in mini(hand_count, hand_nodes.size()):
		var node: Control = hand_nodes[slot]
		node.position = _hand_center(seat, slot, hand_count) - node.size / 2.0
	var target := _draw_center(seat, hand_count)
	var has_wall_source := wall_index >= 0 and wall_index < WallRing.N
	var start := wall_center_for_index(wall_index) if has_wall_source else target
	var tile := _tile(_deal_layer, card, _face_visible(seat),
		start, hand_unit, _wall_angle_for_index(wall_index))
	tile.scale = Vector2.ONE * (G.WALL_UNIT / hand_unit)
	for node in _wall_layer.get_children():
		if int(node.get_meta("wall_ring_index", -2)) == wall_index:
			node.visible = false
	var complete := func():
		_draw_flights.erase(seat)
		_release_visual_node(tile)
		var drawn := _tile(draw_boxes[seat], card, _face_visible(seat),
			target, hand_unit, UI.ROTATIONS[rel])
		drawn.set_meta("new_kind", "draw")
		drawn.set_meta("v2_seat", seat)
		drawn.set_meta("drawn", true)
		drawn.set_meta("concealed_index", hand_count)
		if seat == human_seat:
			drawn.set_interactive(true)
			if table != null and table.has_method("_on_human_tile_gui"):
				drawn.gui_input.connect(table._on_human_tile_gui.bind(drawn))
		_complete_visual_action(action_id, done)
	var duration := GameConfig.tile_motion_seconds()
	if duration <= 0.0 or not has_wall_source:
		complete.call()
		return
	var tween := _motion_tween()
	_draw_flights[seat] = {"tween": tween, "complete": complete}
	tween.set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(tile, "position", target - tile.size / 2.0, duration)
	tween.tween_property(tile, "scale", Vector2.ONE, duration)
	tween.tween_property(tile, "rotation", UI.ROTATIONS[rel], duration)
	tween.chain().tween_callback(complete)

func _finish_pending_draw(seat: int) -> void:
	if not _draw_flights.has(seat): return
	var flight: Dictionary = _draw_flights[seat]
	var tween: Tween = flight.tween
	tween.kill()
	_motion_tweens.erase(tween)
	flight.complete.call()

## 弃牌飞行动画：同时插值位置、缩放、旋转。
func _noop() -> void:
	pass

func _fly_discard(node: Control, seat: int, card: String, on_finish: Callable) -> void:
	var rel := G.relative_seat(human_seat, seat)
	_exposed_specs.clear()
	var player = table.round.players[seat] if table != null and table.round != null else null
	var discard_id := int(player.discard_ids.back()) if player != null and not player.discard_ids.is_empty() else -1
	var missing_source := node == null
	if missing_source:
		# The public tile can land even when a prior snapshot had no visual source.
		if discard_id < 0 or player.discards.is_empty() or str(player.discards.back()) != card:
			if on_finish.is_valid(): on_finish.call()
			return
		for other in _discard_layer.get_children() + _red_layer.get_children():
			if int(other.get_meta("v2_seat", -1)) == seat and int(other.get_meta("discard_id", -1)) == discard_id:
				if on_finish.is_valid(): on_finish.call()
				return
	# A discard is public even when its origin was a hidden opponent tile.
	if node is TileView: node.set_card(card, true)
	var chicken := TILES.is_chicken(card)
	var charge: bool = player != null and chicken and not player.discards.is_empty() \
		and table.round.is_charge_discard(seat, player.discards.size() - 1)
	var index := 0
	if player != null:
		for i in maxi(0, player.discards.size() - 1):
			if TILES.is_chicken(str(player.discards[i])) == chicken: index += 1
	var target := _chicken_slot_center(seat, index) if chicken \
		else G.ordinary_slot_center(seat, index, human_seat, _ordinary_count(seat))
	var centered_target := target
	var columns := 6 if rel in [1,3] else 12
	if not chicken and index % columns > 0:
		# Land on the old row's right edge before shifting the entire row by half a tile.
		target += [Vector2.RIGHT,Vector2.UP,Vector2.LEFT,Vector2.DOWN][rel] * 34.4
	var target_size := _exposed_size(seat) if chicken else G.TILE_BASE * G.ORDINARY_UNIT
	var target_angle: float = UI.ROTATIONS[rel] + (PI / 2.0 if charge else 0.0)
	if missing_source:
		node = _tile(_deal_layer, card, true, target, 1.0, target_angle)
	if node.get_parent() != _deal_layer: node.reparent(_deal_layer)
	var target_scale := target_size / node.size
	var duration := 0.0 if missing_source else GameConfig.tile_motion_seconds()
	if not chicken and index % columns > 0: duration *= 0.7
	_latest_discard_seat = seat
	_latest_discard_id = discard_id
	for layer in [_discard_layer, _red_layer]:
		for previous in layer.get_children():
			if previous is TileView: previous.set_latest_highlight(false)
	_discard_flight_id += 1
	var flight_id := _discard_flight_id
	_discard_flights[flight_id] = {"node_id": node.get_instance_id(), "card": card, "seat": seat,
		"chicken": chicken, "charge": charge, "target": target, "angle": target_angle,
		"discard_id": discard_id, "centered_target": centered_target, "index": index, "instant": missing_source,
		"tween": null, "finish": on_finish}
	if duration <= 0.0:
		_finish_discard_flight(flight_id)
		return
	var tw := _motion_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_discard_flights[flight_id].tween = tw
	if chicken: _move_existing_exposed(tw, duration)
	tw.tween_property(node, "position", target - node.size / 2.0, duration)
	tw.tween_property(node, "scale", target_scale, duration)
	tw.tween_property(node, "rotation", target_angle, duration)
	tw.chain().tween_callback(Callable(self, "_finish_discard_flight").bind(flight_id))

func _finish_discard_flight(flight_id: int) -> void:
	var data: Dictionary = _discard_flights.get(flight_id, {})
	if data.is_empty(): return
	if not bool(data.chicken) and not bool(data.get("centered",false)):
		data.centered = true
		var seat: int=data.seat
		var rel: int=G.relative_seat(human_seat,seat)
		var columns:=6 if rel in [1,3] else 12
		var target: Vector2=data.centered_target
		data.target=target
		var duration:=0.0 if data.instant else GameConfig.tile_motion_seconds()*0.3
		var moves: Array=[]
		var river: Array=round.players[seat].discards
		var index:=0
		for i in river.size():
			if TILES.is_chicken(str(river[i])):continue
			if index / columns == int(data.index) / columns:
				var tile=_take_river_node(seat,int(round.players[seat].discard_ids[i]))
				if tile!=null:moves.append([tile,G.ordinary_slot_center(seat,index,human_seat,_ordinary_count(seat))])
			index+=1
		var flying=instance_from_id(int(data.node_id))
		if flying!=null:moves.append([flying,target])
		if duration>0 and int(data.index)%columns>0:
			var tween:=_motion_tween().set_parallel(true)
			data.tween=tween
			for move in moves:tween.tween_property(move[0],"position",move[1]-move[0].size/2,duration)
			tween.chain().tween_callback(_finish_discard_flight.bind(flight_id))
			return
		for move in moves:move[0].position=move[1]-move[0].size/2
	_discard_flights.erase(flight_id)
	var node = instance_from_id(int(data.get("node_id", 0)))
	var card := str(data.get("card", ""))
	var seat := int(data.get("seat", 0))
	var chicken := bool(data.get("chicken", false))
	var target: Vector2 = data.get("target", Vector2.ZERO)
	var angle := float(data.get("angle", 0.0))
	if node is TileView:
		var destination: Control = _red_layer if chicken else _discard_layer
		if node.get_parent() != destination: node.reparent(destination, false)
		node.set_interactive(false)
		node.set_card(card, true)
		node.set_unit(1.0 if chicken else G.ORDINARY_UNIT)
		node.pivot_offset = node.size / 2.0
		node.position = target - node.size / 2.0
		node.rotation = angle
		node.scale = _exposed_size(seat) / G.TILE_BASE if chicken else Vector2.ONE
		_set_river_tile(node, seat, int(data.get("discard_id", -1)), chicken, bool(data.get("charge", false)))
	var action_already_done := not native_actions_pending()
	var finish: Callable = data.get("finish", Callable())
	if finish.is_valid(): finish.call()
	if action_already_done and not native_presentation_pending() and is_instance_valid(table) and table.is_inside_tree():
		table.call_deferred("_refresh")

func _take_discard_source(seat: int, discard_id: int, chicken: bool) -> Control:
	if seat == _latest_discard_seat and discard_id == _latest_discard_id:
		_latest_discard_seat = -1
		_latest_discard_id = -1
	var layer: Control = _red_layer if chicken else _discard_layer
	for node in layer.get_children():
		if int(node.get_meta("v2_seat", -1)) == seat \
				and int(node.get_meta("discard_id", -2)) == discard_id:
			return node
	# A claim can arrive before the discard lands. Transfer the same entity to
	# the meld flight and cancel its old landing callback to avoid a ghost tile.
	for flight_id in _discard_flights.keys():
		var data: Dictionary = _discard_flights[flight_id]
		if int(data.seat) != seat or int(data.discard_id) != discard_id: continue
		var node = instance_from_id(int(data.node_id))
		var tween: Tween = data.tween
		if is_instance_valid(tween): tween.kill()
		_discard_flights.erase(flight_id)
		var finish: Callable = data.finish
		if finish.is_valid(): finish.call()
		return node as Control
	return null

## 打出刚摸的牌：摸牌飞到弃牌区，不插入手牌。
func animate_draw_discard(seat: int, done: Callable, discard_card: String = "") -> void:
	_finish_pending_draw(seat)
	var action_id := _begin_visual_action()
	var node: Control = null
	for child in draw_boxes[seat].get_children():
		if child is TileView: node = child
	var card := discard_card if discard_card != "" else (str(node.tile) if node != null else "")
	_pending_draws[seat] = ""
	if _held_hand_centers.has(seat):
		_held_hand_centers.erase(seat)
		for slot in hand_boxes[seat].get_child_count():
			var kept: Control = hand_boxes[seat].get_child(slot)
			_motion_tween().tween_property(kept, "position", G.hand_slot_center(seat, slot, human_seat, hand_boxes[seat].get_child_count()) - kept.size / 2.0, GameConfig.tile_motion_seconds() * 0.4)
	if card != "":
		_fly_discard(node, seat, card, func(): _complete_visual_action(action_id, done))
	else:
		for child in draw_boxes[seat].get_children(): _release_visual_node(child)
		_complete_visual_action(action_id, done)

## 碰牌等无摸牌回合出牌：先让旧牌飞走，再只移动剩余手牌填补空位。
func animate_hand_discard(seat: int, discard_card: String, discard_index: int,
		done: Callable) -> void:
	var action_id := _begin_visual_action()
	_held_hand_centers.erase(seat)
	var discard_node: Control = null
	var remaining: Array = []
	for node in hand_boxes[seat].get_children():
		if not (node is TileView): continue
		var same_index := discard_index >= 0 \
			and int(node.get_meta("concealed_index", -2)) == discard_index
		if discard_node == null and (same_index or (discard_index < 0 and str(node.tile) == discard_card)):
			discard_node = node
		else:
			remaining.append(node)
	if discard_node == null:
		_fly_discard(null, seat, discard_card, func(): _complete_visual_action(action_id, done))
		return
	_fly_discard(discard_node, seat, discard_card, Callable(self, "_noop"))
	var ordered: Array = remaining.duplicate()
	ordered.sort_custom(func(a, b):
		return TILES.value_index(str(a.tile)) < TILES.value_index(str(b.tile)))
	var move := _motion_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_IN_OUT)
	var duration := GameConfig.tile_motion_seconds()
	for slot in ordered.size():
		var node: Control = ordered[slot]
		move.tween_property(node, "position",
			G.hand_slot_center(seat, slot, human_seat, ordered.size()) - node.size / 2.0,
			duration * 0.4).set_delay(duration * (0.5 + slot * 0.006))
	move.chain().tween_callback(func():
		for i in ordered.size():
			var tile: Control = ordered[i]
			var old_index := int(tile.get_meta("concealed_index", -1))
			if discard_index >= 0 and old_index > discard_index: tile.set_meta("concealed_index", old_index - 1)
			tile.set_meta("v2_hand_slot", i)
			hand_boxes[seat].move_child(tile, i)
		_complete_visual_action(action_id, done))

## 弃牌后：弃牌先离手，再移动手牌让出插入位置，最后把摸牌插入手牌。
func animate_draw_insert(seat: int, discard_card: String, draw_card: String, done: Callable,
		discard_index: int = -1, hand_slot_map: Dictionary = {}) -> void:
	_finish_pending_draw(seat)
	var action_id := _begin_visual_action()
	_held_hand_centers.erase(seat)
	var nodes: Array = hand_boxes[seat].get_children().duplicate()
	var draw_node: TileView = null
	for node in draw_boxes[seat].get_children():
		if node is TileView: draw_node = node
	var discard_node: Control = null
	var remaining: Array = []
	for node in nodes:
		var matches := int(node.get_meta("concealed_index", -2)) == discard_index \
			if discard_index >= 0 else str(node.tile) == discard_card
		if discard_node == null and matches:
			discard_node = node
		else:
			remaining.append(node)
	if discard_node == null or draw_node == null:
		_pending_draws[seat] = ""
		_fly_discard(discard_node, seat, discard_card, func(): _complete_visual_action(action_id, done))
		return
	# 弃牌先飞离手牌区。
	_fly_discard(discard_node, seat, discard_card, Callable(self, "_noop"))
	# 摸牌加入后按排序位置插入。
	var cards: Array = []
	for node in remaining: cards.append(str(node.tile))
	cards.append(draw_card)
	var sorted := TILES.sort_hand(cards)
	var custom_order := seat == human_seat and not _local_arrangement.is_empty() and sorted.size() == 13
	if custom_order: sorted = _order_local_cards(sorted)
	var used: Dictionary = {}
	var moves: Array = []
	if not hand_slot_map.is_empty() and not custom_order:
		for node in remaining + [draw_node]:
			var old_index := int(node.get_meta("concealed_index", -1))
			var slot := int(hand_slot_map.get(old_index, hand_slot_map.get(str(old_index), -1)))
			if slot >= 0: moves.append({"node": node, "slot": slot})
		moves.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	elif not _face_visible(seat):
		var hidden_order := remaining.duplicate()
		hidden_order.insert(mini(nodes.find(discard_node), hidden_order.size()), draw_node)
		for slot in hidden_order.size(): moves.append({"node": hidden_order[slot], "slot": slot})
	for slot in (sorted.size() if moves.is_empty() else 0):
		var card := str(sorted[slot])
		if card == draw_card and draw_node != null and not used.has("draw"):
			moves.append({"node": draw_node, "slot": slot})
			used["draw"] = true
			continue
		for node in remaining:
			if used.has(node): continue
			if str(node.tile) == card:
				moves.append({"node": node, "slot": slot})
				used[node] = true
				break
	var tw := _motion_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	var duration := GameConfig.tile_motion_seconds()
	for m in moves:
		var node: Control = m.node
		tw.tween_property(node, "position",
			G.hand_slot_center(seat, int(m.slot), human_seat, moves.size()) - node.size / 2.0, duration * 0.4) \
			.set_delay(duration * (0.5 + int(m.slot) * 0.006))
	tw.chain().tween_callback(func():
		if draw_node != null and is_instance_valid(draw_node):
			draw_boxes[seat].remove_child(draw_node)
			hand_boxes[seat].add_child(draw_node)
			draw_node.set_meta("new_kind", "hand")
			draw_node.set_meta("v2_seat", seat)
			draw_node.set_meta("drawn", false)
		# 不重建整手：把节点顺序和 concealed_index 校正到排序后的状态。
		var ordered: Array = []
		for m in moves:
			var n = m.node
			if is_instance_valid(n): ordered.append(n)
		for i in ordered.size():
			var n: Control = ordered[i]
			hand_boxes[seat].move_child(n, i)
			n.set_meta("v2_hand_slot", i)
		for n in ordered:
			var old_index := int(n.get_meta("concealed_index", -1))
			if discard_index >= 0 and old_index > discard_index:
				n.set_meta("concealed_index", old_index - 1)
		_pending_draws[seat] = ""
		_complete_visual_action(action_id, done)
	)

func _live_exposed_layout(seat: int) -> Array:
	if round == null: return []
	return meld_layout(MODEL.melds_for_seat(round, seat), seat, G.relative_seat(human_seat, seat))

func _place_exposed_tiles(seat: int, excluded_meld: int) -> void:
	var layout := _exposed_layout()
	for node in _red_layer.get_children() + _meld_layer.get_children():
		if not (node is TileView) or int(node.get_meta("v2_seat", -1)) != seat: continue
		var mi := int(node.get_meta("meld_index", -1))
		if mi >= 0 and mi == excluded_meld: continue
		for spec in layout:
			if int(spec.seat) != seat or int(spec.meld_index) != mi: continue
			if mi >= 0 and int(spec.meld_slot) != int(node.get_meta("meld_slot", -2)): continue
			if mi < 0 and int(spec.discard_id) != int(node.get_meta("discard_id", -2)): continue
			node.position = Vector2(spec.center) - node.size / 2.0
			break

func _move_existing_exposed(tween: Tween, duration: float) -> void:
	var layout := _exposed_layout()
	for node in _red_layer.get_children() + _meld_layer.get_children():
		if not node is TileView: continue
		for spec in layout:
			if int(spec.seat) != int(node.get_meta("v2_seat", -1)): continue
			if int(spec.meld_index) != int(node.get_meta("meld_index", -1)): continue
			if spec.meld_index >= 0:
				if int(spec.meld_slot) != int(node.get_meta("meld_slot", -2)): continue
			elif int(spec.discard_id) != int(node.get_meta("discard_id", -2)): continue
			tween.tween_property(node, "position", Vector2(spec.center) - node.size / 2.0, duration)
			break

## 碰/杠：手牌和来源弃牌飞到碰杠区。
func animate_meld(event: Dictionary, done: Callable) -> void:
	var action_id := _begin_visual_action()
	_exposed_specs.clear()
	var seat := int(event.get("seat", 0))
	var tile := str(event.get("tile", ""))
	var kind := str(event.get("kind", "pung"))
	if tile == "" and table != null and table.round != null:
		var mi := int(event.get("index", -1))
		if mi >= 0 and mi < table.round.players[seat].melds.size():
			tile = str(table.round.players[seat].melds[mi].get("tile", ""))
	var count := 4 if kind in ["kong", "add_kong", "concealed"] else 3
	var chicken := TILES.is_chicken(tile)
	var targets: Array = []
	var target_angles: Array = []
	var meld_index := int(event.get("index", 0))
	var rel := G.relative_seat(human_seat, seat)
	var source_slot := G.exposed_kong_source_slot(seat, int(event.get("source", -1))) if kind == "kong" else -1
	var nodes: Array = []
	var candidates: Array = hand_boxes[seat].get_children() + draw_boxes[seat].get_children()
	var indices: Array = event.get("hand_indices", [])
	var hand_count := 1 if kind == "add_kong" else count - (1 if event.has("source") else 0)
	for node in candidates:
		if not indices.is_empty():
			if not indices.has(int(node.get_meta("concealed_index", -2))): continue
		elif str(node.tile) != tile:
			continue
		nodes.append(node)
		if nodes.size() >= hand_count: break
	if event.has("source"):
		var sid := int(event.get("source_discard_id", -1))
		var source_seat := int(event.get("source", -1))
		var source_node := _take_discard_source(source_seat, sid, chicken)
		if source_node != null:
			if source_slot == 0:
				nodes.push_front(source_node)
			else:
				nodes.append(source_node)
	# 加杠：已有碰牌组先作为飞行起点保留，新牌飞入最后一个槽位。
	if kind == "add_kong":
		var added_tiles := nodes.duplicate()
		nodes.clear()
		var existing_layer: Control = _red_layer if chicken else _meld_layer
		for node in existing_layer.get_children():
			if int(node.get_meta("v2_seat", -1)) != seat: continue
			if int(node.get_meta("meld_index", -2)) != meld_index: continue
			if not nodes.has(node): nodes.append(node)
			if nodes.size() >= 3: break
		nodes.append_array(added_tiles)
	# A merged/recovered snapshot may no longer have an origin entity. Rebuild
	# from authority instead of substituting an unrelated concealed tile.
	if nodes.size() != count:
		_complete_visual_action(action_id, done)
		return
	var concealed := kind == "concealed" or bool(event.get("concealed", false))
	if round != null and meld_index < round.players[seat].melds.size():
		concealed = bool(round.players[seat].melds[meld_index].get("concealed", concealed))
	var visible_face := not concealed or seat == human_seat
	var removed_indices: Array = indices.duplicate()
	if removed_indices.is_empty():
		for source in nodes:
			if source.get_parent() in [hand_boxes[seat], draw_boxes[seat]]:
				removed_indices.append(int(source.get_meta("concealed_index", -1)))
	var remaining_sources: Array = []
	var live_hand: Array = round.players[seat].concealed if round != null else []
	for remaining_node in candidates:
		if nodes.has(remaining_node): continue
		var old_index := int(remaining_node.get_meta("concealed_index", -1))
		var new_index := old_index
		for removed in removed_indices:
			if int(removed) < old_index: new_index -= 1
		remaining_sources.append({"node": remaining_node, "index": new_index,
			"card": str(live_hand[new_index]) if new_index >= 0 and new_index < live_hand.size() else str(remaining_node.tile)})
	remaining_sources.sort_custom(func(a, b):
		var av := TILES.value_index(str(a.card))
		var bv := TILES.value_index(str(b.card))
		return int(a.index) < int(b.index) if av == bv else av < bv)
	var held: Array = remaining_sources.map(func(source): return source.node.position + source.node.size / 2.0)
	_held_hand_centers[seat] = held
	for node in nodes: node.reparent(_deal_layer)
	_exposed_specs.clear()
	for spec in _live_exposed_layout(seat):
		if int(spec.meld_index) != meld_index: continue
		targets.append(Vector2(spec.center))
		target_angles.append(UI.ROTATIONS[rel] + (PI / 2.0 if spec.sideways else 0.0))
	if targets.size() != count:
		_complete_visual_action(action_id, done)
		return
	var land := func():
		_place_exposed_tiles(seat, meld_index)
		for i in nodes.size():
			var node: TileView = nodes[i]
			var destination: Control = _red_layer if chicken else _meld_layer
			if node.get_parent() != destination: node.reparent(destination, false)
			node.set_card(tile if visible_face else "", visible_face)
			node.set_interactive(false)
			node.set_latest_highlight(false)
			node.set_unit(G.OPPONENT_UNIT)
			node.modulate = Color.WHITE
			node.pivot_offset = node.size / 2.0
			node.scale = _exposed_size(seat) / G.MELD_SIZE
			node.position = Vector2(targets[i]) - node.size / 2.0
			node.rotation = float(target_angles[i])
			node.set_meta("new_kind", "red" if chicken else "meld")
			if chicken: node.set_meta("v2_red_kind", kind if kind != "concealed" else "kong")
			node.set_meta("v2_seat", seat)
			node.set_meta("meld_index", meld_index)
			node.set_meta("meld_slot", i)
			node.set_meta("meld_sideways", i if i == source_slot else -1)
			node.set_meta("meld_concealed", concealed)
			node.set_meta("meld_revealed", visible_face)
		for slot in remaining_sources.size():
			var kept: TileView = remaining_sources[slot].node
			if kept.get_parent() != hand_boxes[seat]: kept.reparent(hand_boxes[seat], false)
			kept.set_meta("new_kind", "hand")
			kept.set_meta("drawn", false)
			kept.set_meta("concealed_index", int(remaining_sources[slot].index))
			kept.set_meta("v2_hand_slot", slot)
			hand_boxes[seat].move_child(kept, slot)
	var duration := GameConfig.tile_motion_seconds()
	if duration <= 0.0:
		land.call()
		_complete_visual_action(action_id, done)
		return
	var flight := _motion_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_existing_exposed(flight, duration)
	for i in nodes.size():
		var node: TileView = nodes[i]
		# 飞行实体置于动画层，经过牌墙和弃牌时保持可见。
		if node.get_parent() != _deal_layer: node.reparent(_deal_layer)
		node.set_card(tile if visible_face else "", visible_face)
		node.set_interactive(false)
		node.set_latest_highlight(false)
		var target: Vector2 = targets[i]
		var tile_size := _exposed_size(seat)
		flight.tween_property(node, "position", target - node.size / 2.0, duration)
		flight.tween_property(node, "scale", tile_size / node.size, duration)
		flight.tween_property(node, "rotation", target_angles[i], duration)
	flight.chain().tween_callback(func():
		land.call()
		_complete_visual_action(action_id, done))

func _build_melds() -> void:
	for data in snapshot.get("seats", []):
		var seat := int(data.seat)
		var rel := G.relative_seat(human_seat, seat)
		for spec in meld_layout(data.melds, seat, rel):
			var meld_index := int(spec.meld_index)
			if meld_index < 0: continue
			var slot := int(spec.meld_slot)
			var card := str(spec.tile)
			var chicken := TILES.is_chicken(card)
			var revealed := bool(spec.revealed) or seat == human_seat
			var face := not bool(spec.concealed) or revealed
			var angle: float = UI.ROTATIONS[rel] + (PI / 2.0 if spec.sideways else 0.0)
			var layer := _red_layer if chicken else _meld_layer
			var key := "red-meld" if chicken else "meld"
			var tile := _sync_tile(layer, "%s:%d:%d:%d" % [key, seat, meld_index, slot],
				card if face else "", face, spec.center, G.OPPONENT_UNIT, angle, _exposed_size(seat) / G.MELD_SIZE)
			tile.set_meta("new_kind", "red" if chicken else "meld")
			tile.set_meta("v2_seat", seat)
			tile.set_meta("meld_index", meld_index)
			tile.set_meta("meld_slot", slot)
			tile.set_meta("meld_sideways", slot if spec.sideways else -1)
			tile.set_meta("meld_concealed", spec.concealed)
			tile.set_meta("meld_revealed", revealed)
			if chicken: tile.set_meta("v2_red_kind", spec.kind)

func _build_hands() -> void:
	var seats: Array = snapshot.get("seats", [])
	for data in seats:
		var seat := int(data.get("seat", 0))
		var rel := G.relative_seat(human_seat, seat)
		var own := seat == human_seat
		var hand: Array = data.get("hand", [])
		var cards: Array = hand.duplicate()
		var drew := str(data.get("just_drew", ""))
		# Settlement snapshots contain the real hands. A queued network draw
		# can still carry the placeholder used to conceal an opponent's tile.
		var pending_draw := "" if round.phase == ROUND_STATE.Phase.SETTLED else str(_pending_draws.get(seat, ""))
		if pending_draw != "":
			# TODO: test-stage pending draw is excluded from hand until discard.
			if drew == "": drew = pending_draw
		if _draw_flights.has(seat): drew = ""
		var opening := _opening_mode()
		if test_frozen and _opening_visual_gate():
			hand = _frozen_hands[seat].duplicate() if seat < _frozen_hands.size() else []
			cards = []
			drew = ""
			opening = false
		elif test_frozen and seat < _frozen_hands.size():
			hand = _frozen_hands[seat].duplicate()
			cards = hand.duplicate()
			drew = ""
			opening = false
		elif opening and not (auto_sort_hands and _sort_started and not _sort_animating):
			var shown: int = 0
			if table != null and table._table_animation_controller != null \
					and not _opening_visual_gate():
				shown = table._table_animation_controller.dealt_count(seat)
			if table != null \
					and table._table_animation_controller != null and shown > 0:
				var shown_hand: Array = table._table_animation_controller.dealt_cards(seat)
				cards = shown_hand.slice(0, shown) if shown_hand.size() >= shown else hand.slice(0, shown)
			else:
				cards = hand.slice(0, mini(shown, hand.size()))
			drew = ""
		else:
			cards = TILES.sort_hand(hand)
			# 摸牌是否显示在摸牌区，与“是否已从手牌移除”分开处理：
			# 动画期间隐藏摸牌区，也必须从手牌里移除这张。
			var remove_card := drew if drew != "" else pending_draw
			if remove_card != "":
				var idx := cards.rfind(remove_card)
				if idx >= 0: cards.remove_at(idx)
			if own and round.phase == ROUND_STATE.Phase.PLAYING:
				if cards.size() == 13:
					cards = _order_local_cards(cards)
				else:
					_local_arrangement = {}
			if table != null and table._table_animation_controller != null \
				and table._table_animation_controller.holds_draw_slot(seat):
				drew = ""
		var count := cards.size()
		var unit := G.hand_unit(seat, human_seat)
		var angle: float = UI.ROTATIONS[rel]
		var used: Dictionary = {}
		for slot in cards.size():
			var source_index := -1
			for candidate in hand.size():
				if used.has(candidate): continue
				if str(hand[candidate]) == str(cards[slot]):
					source_index = candidate
					used[candidate] = true
					break
			var face_visible := _face_visible(seat)
			var key := "hand:%d:%d" % [seat, source_index] if source_index >= 0 else "hand:%d:transient:%d" % [seat, slot]
			var tile: TileView = _sync_tile(hand_boxes[seat], key, str(cards[slot]) if face_visible else "",
				face_visible, _hand_center(seat, slot, count), unit, angle)
			tile.set_meta("v2_hand_slot", slot)
			tile.set_meta("v2_seat", seat)
			tile.set_meta("new_kind", "hand")
			tile.set_meta("concealed_index", source_index)
			hand_boxes[seat].move_child(tile, slot)
			if own:
				tile.set_interactive(source_index >= 0)
				if table != null and table.has_method("_on_human_tile_gui"):
					var input_callback: Callable = table._on_human_tile_gui.bind(tile)
					if not tile.gui_input.is_connected(input_callback): tile.gui_input.connect(input_callback)
				else:
					var input_callback := _on_retained_hand_input.bind(tile)
					if not tile.gui_input.is_connected(input_callback): tile.gui_input.connect(input_callback)
		if drew != "":
			var draw_visible := _face_visible(seat)
			var drawn_tile := _sync_tile(draw_boxes[seat], "draw:%d" % seat, drew if draw_visible else "", draw_visible,
				_draw_center(seat, count), unit, angle)
			var winning: bool = round.phase == ROUND_STATE.Phase.SETTLED and round.round_meta.get("winners", []).has(seat)
			if winning != (drawn_tile._win_glow > 0.0): drawn_tile.set_winning(winning)
			drawn_tile.set_meta("new_kind", "draw")
			drawn_tile.set_meta("v2_seat", seat)
			drawn_tile.set_meta("concealed_index", hand.rfind(drew))
			drawn_tile.set_meta("drawn", true)
			if own:
				drawn_tile.set_interactive(true)
				if table != null and table.has_method("_on_human_tile_gui"):
					var input_callback: Callable = table._on_human_tile_gui.bind(drawn_tile)
					if not drawn_tile.gui_input.is_connected(input_callback): drawn_tile.gui_input.connect(input_callback)

func _tile_short(tile: String) -> String:
	if tile == "": return ""
	var suit := TILES.suit(tile)
	var rank := TILES.rank(tile)
	if suit == "wan": return "%d万" % rank
	if suit == "tiao": return "%d条" % rank
	return "%d筒" % rank

func _begin_hand_sort() -> void:
	if _sort_started: return
	_sort_started = true
	_sort_animating = true
	var time_scale: float = table._table_animation_controller.opening_deal_scale()
	if time_scale == 0.0:
		_finish_hand_sort()
		return
	var max_end := 0.0
	for seat in 4:
		var nodes: Array = hand_boxes[seat].get_children()
		var cards: Array = table._table_animation_controller.dealt_cards(seat)
		if cards.size() != 13 or nodes.size() != 13: continue
		var sorted := TILES.sort_hand(cards)
		var used: Dictionary = {}
		var available: Array = nodes.duplicate()
		for slot in 13:
			var card := str(sorted[slot])
			var node: Control = null
			for candidate in available:
				var candidate_index := int(candidate.get_meta("concealed_index", -1))
				var source_hand: Array = table.round.players[seat].concealed
				var candidate_card := str(source_hand[candidate_index]) if candidate_index >= 0 and candidate_index < source_hand.size() else str(candidate.tile)
				if candidate_card == card and not used.has(candidate):
					node = candidate
					used[candidate] = true
					break
			if node == null: continue
			var target := G.hand_slot_center(seat, slot, human_seat, 13, false) - node.size / 2.0
			var from := node.position
			var mid := from.lerp(target, 0.58)
			var lift := Vector2(0, -14) if seat in [1, 3] else Vector2(-14, 0)
			mid += lift
			var delay := slot * GameConfig.DEAL_SORT_STAGGER * time_scale
			var seconds := GameConfig.DEAL_SORT_SECONDS * time_scale
			var tw := _motion_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(node, "position", mid, seconds * 0.47).set_delay(delay)
			tw.tween_property(node, "position", target, seconds * 0.53)
			max_end = maxf(max_end, delay + seconds)
	var wait := create_tween()
	_sort_tween = wait
	wait.tween_interval(max_end + 0.04)
	wait.tween_callback(_finish_hand_sort)

func _finish_hand_sort() -> void:
	_frozen_hands.clear()
	for seat in 4:
		_frozen_hands.append(TILES.sort_hand(table._table_animation_controller.dealt_cards(seat)))
	test_frozen = false
	test_deal_only = false
	_sort_animating = false
	refresh()
	if is_instance_valid(table) and table.round != null:
		table.call_deferred("_refresh")
		# 等这一帧手牌重排落地，再开始庄家摸牌。
		if table.has_method("_on_opening_visual_finished"):
			table.call_deferred("_on_opening_visual_finished")
		else:
			table.round.call_deferred("resume_after_opening")

func _build_wall_debug() -> void:
	if not show_wall_debug or not _opening_mode() or round == null or round.wall == null: return
	var ring: Array = round.wall._ring
	if ring.size() != 108: return
	var north := _wall_pairs(ring, 0, 28, false)
	var east := _wall_pairs(ring, 28, 26, false)
	var south := _wall_pairs(ring, 54, 28, false)
	var west := _wall_pairs(ring, 82, 26, false)
	var all_pairs: Array = north + east + south + west
	# 数组第一行固定为上层，第二行为下层。
	var rows: Array = []
	for column in 54:
		rows.append(all_pairs[column * 2])
		rows.append(all_pairs[column * 2 + 1])
	var blocks: Array = [
		{"title": "整墙 2×54", "data": _short_array(rows), "columns": 54,
			"pos": Vector2(114, 1150), "cell": Vector2(38, 17), "font": 10},
	]
	var overlay := WallArrayOverlay.new()
	overlay.blocks = blocks
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_debug_layer.add_child(overlay)

## 把一段逻辑环拆成实际墙列顺序，返回 [上层, 下层] 交替。
func _wall_pairs(ring: Array, start: int, length: int, reverse: bool) -> Array:
	var pairs: Array = []
	for column in length / 2:
		pairs.append([ring[start + column * 2], ring[start + column * 2 + 1]])
	if reverse: pairs.reverse()
	var out: Array = []
	for pair in pairs:
		out.append(pair[0])
		out.append(pair[1])
	return out

func _short_array(data: Array) -> Array:
	var out: Array = []
	for tile in data: out.append(_tile_short(str(tile)))
	return out

class WallArrayOverlay extends Control:
	var blocks: Array = []
	func _draw() -> void:
		var font := TileView._font()
		for b in blocks:
			var cell: Vector2 = b.cell
			var panel := Rect2(Vector2(b.pos), Vector2(int(b.columns) * cell.x + 8.0,
				2.0 * cell.y + 24.0))
			draw_rect(panel, Color(0, 0, 0, 0.48))
			draw_rect(panel, Color(1, 1, 1, 0.18), false, 1.0)
			draw_string(font, Vector2(b.pos) + Vector2(4, 13), str(b.title),
				HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(b.font) - 2, 8), Color(1, 0.9, 0.65))
			for column in int(b.columns):
				for row in 2:
					var index: int = column * 2 + row
					if index >= b.data.size(): continue
					var at := Vector2(b.pos) + Vector2(4 + column * cell.x, 18 + row * cell.y)
					draw_string(font, at + Vector2(0, cell.y * 0.78), str(b.data[index]),
						HORIZONTAL_ALIGNMENT_CENTER, cell.x, int(b.font),
						Color(0.96, 1, 0.94))

func _refresh_hud() -> void:
	if round == null or _label_layer == null:
		return
	var seats: Array = snapshot.get("seats", [])
	var signature := str([snapshot.get("turn", -1), seats.map(
		func(data): return [data.name, data.score, data.ready, data.is_dealer, data.is_human]),
		round.phase, AudioManager.seat_voice_packs, table != null and table._net_mode() != ""])
	if signature == _label_signature and not _labels.is_empty():
		return
	_label_signature = signature
	_clear(_label_layer)
	_build_labels(seats)

func _seat_display_names(seats: Array) -> Dictionary:
	var names := {}
	var used := {}
	for data in seats:
		var seat := int(data.seat)
		if seat != human_seat and not bool(data.is_human):
			continue
		var name := str(data.name).replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges()
		if seat == human_seat:
			name = "你"
		elif name.is_empty():
			name = "玩家%d" % (seat + 1)
		names[seat] = name
		used[name] = true
	for data in seats:
		var seat := int(data.seat)
		if names.has(seat):
			continue
		var base := VOICE_PACKS.label(AudioManager.get_seat_voice_pack(seat))
		var name := base
		var suffix := 2
		while used.has(name):
			name = "%s %d" % [base, suffix]
			suffix += 1
		names[seat] = name
		used[name] = true
	return names

func _build_labels(seats: Array) -> void:
	_hud_bounds.clear()
	_labels.clear()
	_name_labels.clear()
	_voice_buttons.clear()
	var names := _seat_display_names(seats)
	for data in seats:
		var seat := int(data.seat)
		var bounds := _seat_hud_rect(seat)
		_hud_bounds[seat] = bounds
		var is_dealer := bool(data.is_dealer)
		var has_voice: bool = table != null and table._net_mode() != "" and (seat == human_seat or bool(data.is_human))
		var is_turn: bool = int(snapshot.get("turn", -1)) == seat and round.phase == ROUND_STATE.Phase.PLAYING
		var who: String = names[seat]
		var caption := who
		var name_edge := bounds.end.x - 24.0
		var name_width := minf(name_edge - bounds.position.x - 24.0, ceilf(_hud_text_width(caption, 24)) + 2.0)
		var left := minf(bounds.get_center().x - name_width / 2.0, name_edge - name_width)
		var name_label := _table_text(_label_layer, caption, 24, UI.INK)
		name_label.name = "SeatName%d" % seat
		name_label.position = Vector2(left, bounds.position.y)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size = Vector2(name_width, 32)
		name_label.tooltip_text = who
		_name_labels.append(name_label)
		if is_turn:
			var turn_marker := _table_text(_label_layer, "●", 18, UI.GOLD)
			turn_marker.name = "SeatTurn%d" % seat
			turn_marker.position = Vector2(left - 24.0, bounds.position.y)
			turn_marker.size = Vector2(20, 32)

		var score := _table_text(_label_layer, "", 28, UI.GOLD if is_dealer else UI.INK)
		score.name = "SeatScore%d" % seat
		var score_width := minf(142, bounds.size.x - 8)
		score.position = Vector2(bounds.get_center().x - score_width / 2, bounds.position.y + 38.0)
		score.size = Vector2(score_width, 38)
		if round.phase == ROUND_STATE.Phase.SETTLED:
			var deltas: Array = round.last_result.get("deltas", [])
			var value := float(deltas[seat]) if seat < deltas.size() else 0.0
			var delta := _table_text(_label_layer, _settlement_signed(value), 28, _settlement_net_color(value))
			delta.name = "SeatDelta%d" % seat
			score.set_meta("round_delta", delta)
			delta.clip_text = true
			delta.tooltip_text = "本局结算 " + delta.text
			delta.visible = _settlement_started
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		score.clip_text = true
		score.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var displayed_score := float(data.score)
		if native_settlement_active() and seat < _settlement_display_scores.size():
			displayed_score = float(_settlement_display_scores[seat])
		elif not _settlement_started and round.phase == ROUND_STATE.Phase.SETTLED:
			# Rules have already applied the ledger, but a last draw/meld flight
			# can still be on screen. Keep the old totals until counting starts.
			var deltas: Array = round.last_result.get("deltas", [])
			if seat < deltas.size(): displayed_score -= float(deltas[seat])
		_set_seat_score(score, displayed_score)
		_labels.append(score)

		if has_voice:
			_build_voice_control(seat, bounds)

func _build_voice_control(seat: int, bounds: Rect2) -> void:
	var button := Button.new()
	button.name = "SeatVoice%d" % seat
	button.position = bounds.position
	button.size = bounds.size
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func():
		if seat == human_seat:
			table._toggle_voice_chat()
		else:
			table._toggle_remote_voice(seat)
		refresh_voice_control(seat))
	_label_layer.add_child(button)
	_voice_buttons[seat] = button
	refresh_voice_control(seat)

func refresh_voice_control(seat: int, message: String = "") -> void:
	var button: Button = _voice_buttons.get(seat)
	if button == null: return
	var local := seat == human_seat
	var enabled: bool = table._local_voice_enabled() if local else table._remote_voice_enabled(seat)
	var microphone_on: bool = enabled if local else table._remote_microphone_on(seat)
	var nickname: Label = _label_layer.get_node("SeatName%d" % seat)
	nickname.add_theme_color_override("font_color", UI.GOLD if enabled and microphone_on else UI.INK)
	button.disabled = local and not table._can_toggle_voice_chat()
	var hint := ("关闭麦克风" if enabled else "开启麦克风") if local else ("静音该玩家" if enabled else "播放该玩家语音")
	if not local and not microphone_on: hint = "对方麦克风已关闭\n" + hint
	if not message.is_empty():
		button.set_meta("voice_status", message)
	var status := str(button.get_meta("voice_status", ""))
	button.tooltip_text = hint if status.is_empty() else "%s\n%s" % [hint, status]

func _hud_badge(caption: String, at: Vector2, background: Color, border: Color) -> Label:
	var badge := _table_text(_label_layer, caption, 18, UI.INK)
	badge.position = at
	badge.size = Vector2(26, 26)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	badge.add_theme_stylebox_override("normal", style)
	return badge

func _hud_text_width(caption: String, font_size: int) -> float:
	return TileView._font().get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

func _set_seat_score(label: Label, value: float) -> void:
	var delta: Label = label.get_meta("round_delta") if label.has_meta("round_delta") else null
	if delta != null: delta.visible = _settlement_started
	var caption := "%.0f分" % value
	if label.text == caption:
		return
	label.text = caption
	label.tooltip_text = caption
	var width := _hud_text_width(caption, 28)
	var font_size := clampi(floori(28.0 * (label.size.x - 16.0) / maxf(width, 1.0)), 17, 28)
	label.add_theme_font_size_override("font_size", font_size)
	if delta != null:
		var seat := int(str(label.name).trim_prefix("SeatScore"))
		var edge := _seat_hud_rect(seat).end.x
		var left := label.position.x + (label.size.x + _hud_text_width(caption, font_size)) / 2.0 + 6.0
		var available := maxf(0.0, edge - left)
		var delta_font := clampi(floori(24.0 * (available - 2.0) / maxf(_hud_text_width(delta.text, 24), 1.0)), 17, 24)
		if _hud_text_width(delta.text, delta_font) <= available:
			delta.position = Vector2(left, label.position.y)
			delta.size = Vector2(available, label.size.y)
			delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		else:
			# Narrow side seats keep the round delta inside the same hand-follow panel.
			var bounds := _seat_hud_rect(seat)
			label.add_theme_font_size_override("font_size", mini(font_size, 22))
			label.position.y = bounds.position.y + 32
			label.size.y = 36
			delta.position = Vector2(label.position.x, bounds.position.y + 68)
			delta.size = Vector2(label.size.x, 28)
			delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			delta_font = 18
		delta.add_theme_font_size_override("font_size", delta_font)
		if delta_font == 18: delta.size.y = 28

func _on_hand_tile_input(event: InputEvent, seat: int, slot: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		hand_tile_pressed.emit(seat, slot)

func _on_retained_hand_input(event: InputEvent, tile: TileView) -> void:
	_on_hand_tile_input(event, int(tile.get_meta("v2_seat", -1)), int(tile.get_meta("v2_hand_slot", -1)))

func count_kind(kind: String) -> int:
	if kind in ["hand", "draw"]:
		var n := 0
		for box in (hand_boxes if kind == "hand" else draw_boxes): n += box.get_child_count()
		return n
	var layer: Control
	match kind:
		"wall": layer = _wall_layer
		"ordinary": layer = _discard_layer
		"red": layer = _red_layer
	if layer == null: return 0
	return layer.get_child_count()

func _seat_hud_rect(seat: int) -> Rect2:
	var rel := G.relative_seat(human_seat, seat)
	var along: Vector2 = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN][rel]
	var first := Rect2()
	var first_distance := INF
	if seat < hand_boxes.size():
		for node in hand_boxes[seat].get_children() + draw_boxes[seat].get_children():
			if not node is TileView or node.is_queued_for_deletion(): continue
			if _reconciling and not _render_seen.has(node.get_instance_id()): continue
			var rect := _visual_rect(node)
			var shadow: Vector2 = (Vector2(2, 4) * node.unit * node.scale).rotated(node.rotation)
			rect = rect.merge(Rect2(rect.position + shadow, rect.size))
			var distance := rect.get_center().dot(along)
			if distance < first_distance:
				first_distance = distance
				first = rect
	if first_distance == INF:
		var size := G.hand_tile_size(seat, human_seat)
		if rel in [1, 3]: size = Vector2(size.y, size.x)
		first = Rect2(_hand_center(seat, 0, _current_hand_count(seat)) - size / 2, size)
	var size := Vector2(120 if rel in [1, 3] else 184, 96)
	var at: Vector2 = [
		Vector2(first.position.x - 16 - size.x, first.get_center().y - size.y / 2),
		Vector2(G.DESIGN_SIZE.x - 8 - size.x, first.end.y + 16),
		Vector2(first.end.x + 16, first.get_center().y - size.y / 2),
		Vector2(8, first.position.y - 16 - size.y),
	][rel]
	at.y = clampf(at.y, G.TABLE_BOUNDS.position.y, G.TABLE_BOUNDS.end.y - size.y)
	if rel in [0, 2]: at.x = clampf(at.x, G.TABLE_BOUNDS.position.x, G.TABLE_BOUNDS.end.x - size.x)
	return Rect2(at, size)

func _process(_delta: float) -> void:
	_follow_hand_hud()
	if _arrangement_thread != null and not _arrangement_thread.is_alive():
		var choices: Array = _arrangement_thread.wait_to_finish()
		_arrangement_thread = null
		if _arrangement_job_key == _arrangement_key:
			_arrangement_choices = choices
			_arrangement_done_key = _arrangement_key
			_refresh_hand_arrangement()

func _follow_hand_hud() -> void:
	if _label_layer == null or _labels.size() != 4: return
	for seat in 4:
		if not _hud_bounds.has(seat): continue
		var bounds := _seat_hud_rect(seat)
		var offset: Vector2 = bounds.position - _hud_bounds[seat].position
		if offset.is_zero_approx(): continue
		_hud_bounds[seat] = bounds
		var nodes: Array = [_labels[seat], _name_labels[seat],
			_label_layer.get_node_or_null("SeatTurn%d" % seat), _voice_buttons.get(seat)]
		if _labels[seat].has_meta("round_delta"): nodes.append(_labels[seat].get_meta("round_delta"))
		for node in nodes:
			if is_instance_valid(node): node.position += offset

func _ordinary_count(seat: int) -> int:
	if round == null: return 0
	return round.players[seat].discards.filter(func(card): return not TILES.is_chicken(str(card))).size()

func _take_river_node(seat: int, discard_id: int) -> TileView:
	for tile in _discard_layer.get_children():
		if tile is TileView and int(tile.get_meta("v2_seat",-1))==seat and int(tile.get_meta("discard_id",-1))==discard_id:return tile
	return null
