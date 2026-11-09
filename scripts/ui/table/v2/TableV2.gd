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
const SCORE_INSPECTION := preload("res://scripts/ui/table/v2/TableV2ScoreInspection.gd")
const VOICE_PACKS := preload("res://scripts/core/VoicePackRegistry.gd")

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
var _animation_layer: Control
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
var _latest_discard_seat := -1
var _latest_discard_id := -1
var _labels: Array = []
var _name_labels: Array = []
var _badges: Array = []
var _voice_buttons: Array = []

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
	_action_layer = _layer("ActionLayer")
	_action_layer.z_index = 90
	_animation_layer = _layer("AnimationLayer")
	_deal_layer = _layer("DealLayer")
	_deal_layer.z_index = 10
	_debug_layer = _layer("WallDebugLayer")
	_settlement_layer = _layer("SettlementLayer")
	# 牌墙/手牌使用 z_index，结算卡必须压过它们，否则庄家卡会被南墙和手牌遮住。
	_settlement_layer.z_index = 100

func clear_dice_visual() -> void:
	if _dice_tween != null and _dice_tween.is_valid(): _dice_tween.kill()
	_dice_tween = null
	if _dice_layer != null:
		for node in _dice_layer.get_children():
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
	var titles: Array[String] = []
	for winner in winners:
		var title: String = relative[posmod(int(winner) - human_seat, 4)]
		if round.players[winner].ready: title += "报听"
		if bool(meta.get("self_draw", false)):
			if int(meta.get("kong_draw_seat", -1)) == winner: title += "杠开"
			if int(meta.get("last_four_self_draw_seat", -1)) == winner: title += "海底"
			title += "自摸"
		elif bool(meta.get("robbed_kong", false)):
			title += "抢" + source_name + "的杠胡牌" if source_name != "" else "抢杠胡"
		else:
			title += "胡" + source_name if source_name != "" else "胡牌"
		var patterns: Array[String] = []
		var items: Array = round.last_result.get("items", [])
		for item in items[winner] if winner < items.size() else []:
			if str(item.get("kind", "")) != "pattern": continue
			var caption := str(item.get("label", ""))
			if caption == "清龙对": caption = "清龙七对"
			if caption != "" and caption not in patterns: patterns.append(caption)
		if not patterns.is_empty(): title += "-" + "·".join(patterns)
		titles.append(title)
	return "、".join(titles)

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
	panel.size = Vector2(1020, 386)
	panel.position = G.CENTER - panel.size / 2.0
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
	title.position = Vector2(28, 8)
	title.size = Vector2(964, 44)
	title.add_theme_font_size_override("font_size", clampi(floori(30.0 * title.size.x / maxf(_hud_text_width(title.text, 30), title.size.x)), 18, 30))
	title.clip_text = true
	title.tooltip_text = title.text
	var multiplier := _table_text(panel, _settlement_multiplier_title(), 24, UI.GOLD)
	multiplier.name = "MultiplierTitle"
	multiplier.position = Vector2(28, 50)
	multiplier.size = Vector2(964, 34)
	var header_y := 90.0
	var column_start := 188.0
	var column_width := 184.0
	var row_height := 70.0
	for index in 4:
		var seat := posmod(human_seat + index, 4)
		var center := 102.0 if index == 0 else column_start + (index - 1) * column_width + column_width / 2.0
		var direction := _table_text(panel, ["我", "上", "对", "下"][index], 36, UI.GOLD)
		direction.name = "SettlementSeat%d" % seat
		direction.position = Vector2(center - 35.0, header_y)
		direction.size = Vector2(36, 58)
		direction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var called := bool(_settlement_plan.called[seat])
		if not called: continue
		var background := Color("#30784e")
		var border := Color("#a2d3ac")
		var badge := _hud_badge("叫", Vector2(center + 9.0, header_y + 16.0), background, border)
		badge.name = "CalledStatus%d" % seat
		badge.tooltip_text = "叫牌"
		badge.reparent(panel, false)

	for row in 3:
		var top := 152.0 + row * row_height
		var divider := ColorRect.new()
		divider.color = Color(UI.GOLD, 0.28 if row == 2 else 0.13)
		divider.position = Vector2(24, top)
		divider.size = Vector2(panel.size.x - 48, 1)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(divider)
		var caption := _table_text(panel, ["我的分数", "对方分数", "结算"][row], 28, UI.INK)
		caption.position = Vector2(28, top + 4)
		caption.size = Vector2(148, row_height - 4)
		var labels: Array[Label] = []
		for index in 3:
			var value := _table_text(panel, "0", 42 if row == 2 else 38, UI.MUTED)
			value.position = Vector2(column_start + index * column_width, top + 4)
			value.size = Vector2(column_width, row_height - 4)
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			labels.append(value)
		_settlement_score_rows.append(labels)

	var total_bg := ColorRect.new()
	total_bg.color = Color(UI.GOLD, 0.10)
	total_bg.position = Vector2(762, 296)
	total_bg.size = Vector2(232, 66)
	total_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(total_bg)
	var total_title := _table_text(total_bg, "合计", 28, UI.GOLD)
	total_title.position = Vector2(14, 0)
	total_title.size = Vector2(70, total_bg.size.y)
	total_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settlement_total_label = _table_text(total_bg, "0", 48, UI.MUTED)
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
		tile.position = _wall_center_for_ring_index(_settlement_flip_index) - tile.size / 2.0
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
	var top := G.hand13_rect(human_seat, human_seat).position.y - 12.0 - row_size.y
	var placement := Rect2(Vector2(right - row_size.x, top), row_size)
	var obstacles: Array[Rect2] = []
	var rows: Array[float] = [top]
	for layer in _render_layers():
		if layer == _wall_layer: continue
		for tile in layer.get_children():
			if not (tile is TileView) or not tile.is_visible_in_tree(): continue
			var bounds := _visual_rect(tile).grow(6.0)
			if bounds.end.x <= placement.position.x or bounds.position.x >= placement.end.x: continue
			obstacles.append(bounds)
			var above := bounds.position.y - 12.0 - row_size.y
			if above >= G.CENTER.y and above < top: rows.append(above)
	rows.sort()
	rows.reverse()
	for y in rows:
		placement.position.y = y
		if obstacles.all(func(bounds: Rect2): return not placement.intersects(bounds)):
			return placement
	placement.position.y = top
	return placement

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
	var card := str(p.discards[idx])
	var local := Vector2.ZERO
	if TILES.is_chicken(card):
		# 红色牌按当前红色时间轴中鸡牌出现顺序定位（必须用实时数据，不能用旧 snapshot）。
		var live: Dictionary = MODEL.build(table.round, human_seat)
		var data: Dictionary = {}
		for s in live.get("seats", []):
			if int(s.seat) == seat: data = s
		var specs: Array = red_layout(data.get("exposed_timeline", data.get("red_timeline", [])), seat, G.relative_seat(human_seat, seat), true)
		var seen := 0
		for spec in specs:
			if str(spec.kind) in ["charge", "ordinary"]:
				if seen == _chicken_index(p, idx): local = Vector2(spec.center)
				seen += 1
	else:
		var ordinary_index := 0
		for i in idx:
			if not TILES.is_chicken(str(p.discards[i])): ordinary_index += 1
		local = G.ordinary_slot_center(seat, ordinary_index, human_seat)
	return get_global_transform() * local

func _chicken_index(p, idx: int) -> int:
	var n := 0
	for i in idx:
		if TILES.is_chicken(str(p.discards[i])): n += 1
	return n

## WallRing 单张下标 -> 牌墙牌背中心。
func wall_center_for_index(index: int) -> Vector2:
	if index < 0 or index >= 108: return G.CENTER
	var seat := 3
	var slot := 0
	var row := index % 2
	if index < 28:
		seat = 3
		slot = int(index / 2)
	elif index < 54:
		seat = 0
		slot = int((index - 28) / 2)
	elif index < 82:
		seat = 1
		slot = 13 - int((index - 54) / 2)
	else:
		seat = 2
		slot = 12 - int((index - 82) / 2)
	return G.wall_block_center(seat, slot, row)

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
	if not test_frozen:
		_build_discards()
		_build_red()
		_build_melds()
	_build_hands()
	_end_tile_reconcile()
	_refresh_hud()
	if is_instance_valid(_score_inspection):
		_score_inspection.refresh()
	if all_dealt_now and not _sort_started:
		_begin_hand_sort()
	_build_wall_debug()
	if table != null and table._table_animation_controller != null and table.round != null:
		var dealer := int(table.round.dealer_seat)
		if table._table_animation_controller.dealt_count(dealer) >= 8:
			table._table_animation_controller.clear_dice()
			if keep_removed_wall_gray:
				# 旧动画层只保留骰子；不能整层隐藏，否则骰子动画不可见。
				if _animation_layer != null: _animation_layer.hide()
	queue_redraw()

## 同一牌桌实例会跨局复用；RoundState 变化时必须清掉上一局的瞬时视觉状态。
func _reset_round_visual_state() -> void:
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
		if tween.is_valid(): tween.kill()
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
	var settled_reveal: bool = round != null and round.phase == ROUND_STATE.Phase.SETTLED \
		and not bool(round.round_meta.get("all_called_draw", false))
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
	if not key.begins_with("hand:") and not key.begins_with("draw:"): node.set_ready_locked(false)
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
		var seat := int(data.get("seat", 0))
		var rel := G.relative_seat(human_seat, seat)
		var discards: Array = data.get("discards", [])
		var index := 0
		for i in discards.size():
			var card := str(discards[i])
			if TILES.is_chicken(card):
				continue
			var capacity := 40 if rel in [1, 3] else 36
			if index >= capacity: break
			var discard_id := int(data.discard_ids[i]) if i < data.discard_ids.size() else i
			var d := _sync_tile(_discard_layer, "discard:%d:%d" % [seat, discard_id], card, true, G.ordinary_slot_center(seat, index, human_seat),
				G.ORDINARY_UNIT, UI.ROTATIONS[rel])
			d.set_meta("new_kind", "ordinary")
			d.set_meta("v2_seat", seat)
			d.set_meta("discard_id", int(data.discard_ids[i]) if i < data.discard_ids.size() else i)
			d.set_latest_highlight(seat == _latest_discard_seat and discard_id == _latest_discard_id)
			index += 1

func _advance_red(cursor: Vector2, rel: int, amount: float) -> Vector2:
	if rel == 0: return cursor + Vector2(amount, 0)
	if rel == 2: return cursor - Vector2(amount, 0)
	if rel == 1: return cursor - Vector2(0, amount)
	return cursor + Vector2(0, amount)

func _red_tile(card: String, cursor: Vector2, rel: int, charge: bool, seat: int,
		kind: String = "", group: int = -1) -> void:
	var tile := _tile(_red_layer, card, true, _red_center(cursor, rel, charge), 1.0,
		UI.ROTATIONS[rel] + (PI / 2.0 if charge else 0.0))
	tile.scale = Vector2(G.RED_WIDTH / TileView.BASE_W, G.RED_HEIGHT / TileView.BASE_H)
	tile.set_meta("new_kind", "red")
	tile.set_meta("v2_seat", seat)
	tile.set_meta("v2_charge", charge)
	if kind != "": tile.set_meta("v2_red_kind", kind)
	if group >= 0: tile.set_meta("v2_red_group", group)

func _red_center(cursor: Vector2, rel: int, charge: bool = false) -> Vector2:
	var hw: float = G.RED_WIDTH * 0.5
	var hh: float = G.RED_HEIGHT * 0.5
	if charge:
		# 横放后视觉 56×44；在不同座位分别对齐竖放牌的屏幕下边缘。
		if rel == 0: return cursor + Vector2(G.RED_HEIGHT * 0.5, G.RED_HEIGHT - G.RED_WIDTH * 0.5)
		# 北家视角旋转180度，横放牌对齐上边缘。
		if rel == 2: return cursor + Vector2(-G.RED_HEIGHT * 0.5, G.RED_WIDTH * 0.5)
		if rel == 1:
			# 东家：横放牌右边缘与竖放牌右边缘对齐。
			return cursor + Vector2(G.RED_HEIGHT - G.RED_WIDTH * 0.5, -G.RED_WIDTH * 0.5)
		# 西家：横放牌左边缘与竖放牌左边缘对齐。
		return cursor + Vector2(G.RED_WIDTH * 0.5, G.RED_WIDTH * 0.5 - G.RED_HEIGHT * 0.5 + G.RED_WIDTH * 0.5)
	if rel == 0: return cursor + Vector2(hw, hh)
	if rel == 2: return cursor + Vector2(-hw, hh)
	if rel == 1: return cursor + Vector2(hh, -hw)
	return cursor + Vector2(hh, hw)

func _build_red() -> void:
	for data in snapshot.get("seats", []):
		var seat := int(data.get("seat", 0))
		var rel := G.relative_seat(human_seat, seat)
		var discards: Array = data.get("discards", [])
		var charges: Array = data.get("discard_charge", [])
		var singles: Array = []
		for i in discards.size():
			if TILES.is_chicken(str(discards[i])):
				singles.append({"tile": str(discards[i]),
					"charge": bool(charges[i]) if i < charges.size() else false})
		var pongs: Array = []
		var kongs: Array = []
		for meld in data.get("melds", []):
			if not TILES.is_chicken(str(meld.get("tile", ""))): continue
			if str(meld.get("kind", "")) == "pung": pongs.append(str(meld.get("tile", "")))
			elif str(meld.get("kind", "")) in ["kong", "add_kong"]: kongs.append(str(meld.get("tile", "")))
		var first_child := _red_layer.get_child_count()
		var timeline: Array = data.get("exposed_timeline", data.get("red_timeline", []))
		if not timeline.is_empty():
			_build_red_timeline(timeline, seat, rel)
			continue
		var line := 0
		var cursor := G.red_anchor(seat, human_seat, line)
		var line_tiles := 0
		var line_capacity := 12 if rel in [1, 3] else 24
		var placed := 0
		var first := true
		for category in 3:
			var items: Array = singles if category == 0 else (pongs if category == 1 else kongs)
			if items.is_empty(): continue
			if not first: cursor = _advance_red(cursor, rel, G.RED_CATEGORY_GAP)
			first = false
			if category == 0:
				var single_no := 0
				for item in items:
					if placed >= 24: break
					if rel in [1, 3] and line_tiles >= line_capacity:
						if line >= 1: break
						line = 1
						cursor = G.red_anchor(seat, human_seat, line)
						line_tiles = 0
					var charge: bool = bool(item.charge)
					_red_tile(str(item.tile), cursor, rel, charge, seat)
					var step: float = G.RED_HEIGHT + G.RED_LINE_GAP if charge else G.RED_WIDTH + G.RED_LINE_GAP
					cursor = _advance_red(cursor, rel, step)
					single_no += 1
					line_tiles += 1
					placed += 1
			else:
				var count := 3 if category == 1 else 4
				for card in items:
					if placed + count > 24: break
					if rel in [1, 3] and line_tiles + count > line_capacity:
						if line >= 1: break
						line = 1
						cursor = G.red_anchor(seat, human_seat, line)
						line_tiles = 0
					for _i in count:
						_red_tile(str(card), cursor, rel, false, seat)
						cursor = _advance_red(cursor, rel, G.RED_WIDTH + G.RED_LINE_GAP)
						line_tiles += 1
						placed += 1
					cursor = _advance_red(cursor, rel, G.RED_GROUP_GAP)
		_center_red_group(first_child, rel)
		_offset_red_to_wall(first_child, rel)

func _build_red_timeline(timeline: Array, seat: int, rel: int) -> void:
	for spec in red_layout(timeline, seat, rel, true):
		if not TILES.is_chicken(str(spec.tile)): continue
		var key := "red-meld:%d:%d:%d" % [seat, int(spec.meld_index), int(spec.meld_slot)] \
			if int(spec.meld_index) >= 0 else "red-discard:%d:%d" % [seat, int(spec.discard_id)]
		var tile := _red_tile_at(str(spec.tile), Vector2(spec.center), rel, bool(spec.charge), seat,
			str(spec.kind), int(spec.group), key)
		if tile != null:
			tile.rotation = UI.ROTATIONS[rel] + (PI / 2.0 if bool(spec.get("sideways", spec.charge)) else 0.0)
			var concealed := bool(spec.get("concealed", false))
			var revealed := bool(spec.get("revealed", false)) or seat == human_seat
			var face := not concealed or revealed
			tile.set_card(str(spec.tile) if face else "", face)
			tile.set_meta("meld_concealed", concealed)
			tile.set_meta("meld_revealed", revealed)
			tile.set_meta("meld_index", int(spec.get("meld_index", -1)))
			tile.set_meta("meld_slot", int(spec.get("meld_slot", -1)))
			tile.set_meta("discard_id", int(spec.get("discard_id", -1)))
			tile.set_latest_highlight(int(spec.meld_index) < 0 and seat == _latest_discard_seat \
				and int(spec.discard_id) == _latest_discard_id)

func red_layout(timeline: Array, seat: int, rel: int, include_ordinary: bool = false) -> Array:
	var side := rel in [1, 3]
	var groups: Array = []
	var stacked: Array = []
	var placed := 0
	for item in timeline:
		if placed >= 24: break
		var kind := str(item.get("kind", ""))
		var tile := str(item.get("tile", ""))
		if not include_ordinary and not TILES.is_chicken(tile): continue
		if kind in ["pung", "kong", "add_kong"] and tile == "": continue
		var count := 1
		if kind == "pung": count = 4 if bool(item.get("add_kong", false)) else 3
		elif kind == "kong": count = 4
		if placed + count > 24: break
		var source := int(item.get("from_seat", -1))
		var source_slot := G.exposed_kong_source_slot(seat, source) \
			if kind == "kong" and not bool(item.get("concealed", false)) else -1
		var opposite := source_slot >= 0 and posmod(source - seat, 4) == 2
		var group := {"kind": kind, "tile": tile, "count": count, "source_slot": source_slot, "stacked": opposite,
			"meld_index": int(item.get("meld_index", -1)),
			"discard_id": int(item.get("order", -1)),
			"concealed": bool(item.get("concealed", false)),
			"revealed": bool(item.get("revealed", false)),
			"add_kong": bool(item.get("add_kong", false))}
		if opposite:
			stacked.append(group)
		else:
			groups.append(group)
		placed += count

	var lines := _red_belt_lines(groups, side, not stacked.is_empty())
	var hand := G.hand13_rect(seat, human_seat)
	var along: Vector2 = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN][rel]
	var inward: Vector2 = [Vector2.UP, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT][rel]
	var origin: Vector2 = [
		Vector2(G.CENTER.x, hand.position.y - G.RED_HAND_GAP),
		Vector2(hand.position.x - G.RED_HAND_GAP, G.CENTER.y),
		Vector2(G.CENTER.x, hand.end.y + G.RED_HAND_GAP),
		Vector2(hand.end.x + G.RED_HAND_GAP, G.CENTER.y),
	][rel]
	var regular_span := 0.0
	for line in lines:
		regular_span = maxf(regular_span, _red_line_span(line))
	var stack_span := _red_line_span(stacked)
	var between := G.RED_GROUP_GAP if regular_span > 0.0 and stack_span > 0.0 else 0.0
	var regular_center := origin
	if side:
		regular_center -= along * (stack_span + between) / 2.0

	var out: Array = []
	for li in lines.size():
		var line: Array = lines[li]
		var start := regular_center - along * _red_line_span(line) / 2.0
		start += inward * (G.RED_HEIGHT + G.RED_LINE_GAP) * li
		for gi in line.size():
			if gi > 0:
				start += along * _red_gap(line[gi - 1].kind, line[gi].kind)
			_append_red_group(out, line[gi], start, along, inward, li * 100 + gi)
			start += along * _red_group_span(line[gi])
	if stacked.is_empty():
		return out
	if side:
		# A stacked kong uses both columns; place it after the longer column.
		var start := origin + along * ((regular_span + between - stack_span) / 2.0)
		for i in stacked.size():
			_append_red_group(out, stacked[i], start, along, inward, 300 + i)
			start += along * (_red_group_span(stacked[i]) + G.RED_GROUP_GAP)
	else:
		# North and south walls fill the space directly behind the central belt.
		# Use the open ends for two-tier groups so the top tile clears the wall.
		var half_wall := 7.0 * G.TILE_BASE.x * G.WALL_UNIT + G.WALL_LAYER_SHIFT
		var clearance := G.RED_GROUP_GAP
		var left := origin.x - maxf(half_wall, regular_span / 2.0) - clearance
		var right := origin.x + maxf(half_wall, regular_span / 2.0) + clearance
		var side_wall_width := G.TILE_BASE.y * G.WALL_UNIT + G.WALL_LAYER_SHIFT + clearance
		var min_x := G.wall_outer_x(2) + side_wall_width
		var max_x := G.wall_outer_x(0) - side_wall_width
		var cross := origin.y + (28.0 if rel == 2 else 0.0)
		for i in stacked.size():
			var span := _red_group_span(stacked[i])
			var on_left := (i % 2 == 0 and left - span >= min_x) or right + span > max_x
			var x := left - span if on_left else right
			var start := Vector2(x if rel == 0 else x + span, cross)
			_append_red_group(out, stacked[i], start, along, inward, 300 + i)
			if on_left:
				left -= span + clearance
			else:
				right += span + clearance
	return out

func _red_belt_lines(groups: Array, side: bool, balance: bool) -> Array:
	if not side:
		return [groups]
	if not balance:
		var lines: Array = []
		var line: Array = []
		var count := 0
		for group in groups:
			var group_count := int(group.count)
			if count + group_count > 12:
				lines.append(line)
				line = []
				count = 0
			line.append(group)
			count += group_count
		if not line.is_empty():
			lines.append(line)
		return lines
	var split := groups.size()
	var used := 0
	var best_span := INF
	for i in range(groups.size() + 1):
		if used > 12:
			break
		var first := groups.slice(0, i)
		var second := groups.slice(i)
		var remaining := 0
		for group in second:
			remaining += int(group.count)
		if remaining <= 12:
			var span := maxf(_red_line_span(first), _red_line_span(second))
			if span < best_span:
				best_span = span
				split = i
		if i < groups.size():
			used += int(groups[i].count)
	return [groups.slice(0, split), groups.slice(split)]

func _red_line_span(line: Array) -> float:
	var span := 0.0
	for i in line.size():
		if i > 0:
			span += _red_gap(line[i - 1].kind, line[i].kind)
		span += _red_group_span(line[i])
	return span

func _red_group_span(group: Dictionary) -> float:
	var n := 3 if group.stacked else int(group.count)
	var tile_width := G.RED_HEIGHT if group.kind == "charge" else G.RED_WIDTH
	var extra := G.RED_HEIGHT - G.RED_WIDTH if group.source_slot >= 0 and not group.stacked else 0.0
	return n * tile_width + (n - 1) * G.RED_LINE_GAP + extra

func _append_red_group(out: Array, group: Dictionary, origin: Vector2, along: Vector2,
		inward: Vector2, group_id: int) -> void:
	var charge: bool = group.kind == "charge"
	var cursor := 0.0
	for slot in int(group.count):
		var sideways: bool = charge or slot == int(group.source_slot)
		var extent := G.RED_HEIGHT if sideways else G.RED_WIDTH
		var depth := G.RED_WIDTH if sideways else G.RED_HEIGHT
		var center := origin + along * (cursor + extent / 2.0) + inward * depth / 2.0
		if group.stacked and sideways:
			center = origin + along * (_red_group_span(group) / 2.0) \
				+ inward * (G.RED_HEIGHT + G.RED_LINE_GAP + depth / 2.0)
		out.append({"center": center, "charge": charge, "tile": group.tile,
			"kind": "add_kong" if group.add_kong else group.kind, "group": group_id,
			"sideways": sideways, "concealed": group.concealed, "revealed": group.revealed,
			"discard_id": group.discard_id, "meld_index": int(group.meld_index), "meld_slot": slot})
		cursor += extent + G.RED_LINE_GAP

func _red_gap(a: String, b: String) -> float:
	if a == b:
		return 4.0 if a in ["charge", "ordinary"] else 8.0
	return 12.0

func _red_tile_at(card: String, center: Vector2, rel: int, charge: bool, seat: int,
		kind: String = "", group: int = -1, key: String = "") -> TileView:
	var tile := _sync_tile(_red_layer, key, card, true, center, 1.0,
		UI.ROTATIONS[rel] + (PI / 2.0 if charge else 0.0)) if key != "" \
		else _tile(_red_layer, card, true, center, 1.0, UI.ROTATIONS[rel] + (PI / 2.0 if charge else 0.0))
	if _reconciling: _render_seen[tile.get_instance_id()] = true
	tile.scale = Vector2(G.RED_WIDTH / TileView.BASE_W, G.RED_HEIGHT / TileView.BASE_H)
	tile.set_meta("new_kind", "red")
	tile.set_meta("v2_seat", seat)
	tile.set_meta("v2_charge", charge)
	if kind != "": tile.set_meta("v2_red_kind", kind)
	if group >= 0: tile.set_meta("v2_red_group", group)
	return tile

## 东/西红色区与牌墙外沿保持 8 的间距。
func _offset_red_to_wall(first_child: int, rel: int) -> void:
	if rel not in [1, 3]: return
	var children := _red_layer.get_children()
	var lo := INF
	var hi := -INF
	for i in range(first_child, children.size()):
		var tile = children[i]
		if not (tile is Control): continue
		var rect := _visual_rect(tile)
		lo = minf(lo, rect.position.x)
		hi = maxf(hi, rect.end.x)
	if lo == INF: return
	var delta := 0.0
	if rel == 1:
		# 东家：红色区在牌墙外侧，靠墙边缘离墙 8。
		delta = (G.wall_outer_x(0) + G.SIDE_RED_GAP) - lo
	else:
		# 西家：红色区在牌墙外侧，靠墙边缘离墙 8。
		delta = (G.wall_outer_x(2) - G.SIDE_RED_GAP) - hi
	for i in range(first_child, children.size()):
		var tile = children[i]
		if tile is Control:
			tile.position.x += delta

## 红色区整体（冲锋鸡 + 碰 + 杠）沿牌桌方向居中。
func _center_red_group(first_child: int, rel: int) -> void:
	var children := _red_layer.get_children()
	var lo := INF
	var hi := -INF
	for i in range(first_child, children.size()):
		var tile = children[i]
		if not (tile is Control): continue
		var center: Vector2 = _visual_rect(tile).get_center()
		var axis: float = center.x if rel in [0, 2] else center.y
		lo = minf(lo, axis)
		hi = maxf(hi, axis)
	if lo == INF or hi == -INF: return
	var delta := 0.0
	if rel in [0, 2]:
		delta = G.CENTER.x - (lo + hi) / 2.0
	else:
		delta = G.CENTER.y - (lo + hi) / 2.0
	for i in range(first_child, children.size()):
		var tile = children[i]
		if tile is Control:
			tile.position += Vector2(delta, 0) if rel in [0, 2] else Vector2(0, delta)

## Control.size 是旋转前的局部矩形；布局必须使用 RedLayer 坐标系中的实际
## AABB。 不能用全局坐标与 G 的设计坐标混算，否则 Android 拉伸缩放时红区
## 会按 surface.scale 漂移。
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
	var tile := _sync_tile(_wall_layer, "wall:%d" % index, _native_flip_tile() if revealed else card,
		revealed or face, G.wall_block_center(seat, slot, row), G.WALL_UNIT, G.wall_angle(seat))
	tile.back_depth_top = seat == 1
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
	var sum := Vector2.ZERO
	for i in cards.size():
		var idx := int(indices[i])
		var center := _wall_center_for_ring_index(idx)
		entries.append({"card": str(cards[i]), "index": idx, "center": center,
			"row": idx % 2, "pos": i})
		sum += center
	# 下层(index奇数)在左，上层(index偶数)在右；同层保持摸牌先后。
	entries.sort_custom(func(a, b):
		if a.row == b.row: return a.pos < b.pos
		return a.row > b.row)
	var mid: Vector2 = sum / float(entries.size())
	var final_count := existing + cards.size()
	# 四家统一用实际手牌槽位推导“右方向”和步进，不写死座位方向。
	var slot0 := G.hand_slot_center(seat, 0, human_seat, final_count, false)
	var slot1 := G.hand_slot_center(seat, 1, human_seat, final_count, false)
	var dir: Vector2 = (slot1 - slot0).normalized()
	var hand_step: float = slot0.distance_to(slot1)

	if dir == Vector2.ZERO: dir = Vector2(1, 0)
	var wall_step: float = TileView.BASE_W * G.WALL_UNIT + 4.0
	var starts: Array = []
	for k in entries.size():
		var off := (k - (entries.size() - 1) * 0.5) * wall_step
		starts.append(mid + dir * off)
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
	for k in entries.size():
		var tile := _tile(_deal_layer, entries[k].card, _face_visible(seat), starts[k], hand_unit, G.wall_angle(seat))
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

func _wall_center_for_ring_index(index: int) -> Vector2:
	if index < 0 or index >= 108: return G.CENTER
	var starts := {3: 0, 0: 28, 1: 54, 2: 82}
	var counts := {3: 14, 0: 13, 1: 14, 2: 13}
	var seat := 0
	for s in starts:
		if index >= int(starts[s]) and index < int(starts[s]) + int(counts[s]) * 2:
			seat = s
			break
	var logical := int((index - int(starts[seat])) / 2)
	var row := index % 2
	var physical := logical
	if seat in [1, 2]: physical = int(counts[seat]) - 1 - logical
	return G.wall_block_center(seat, physical, row)

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
	var start := _wall_center_for_ring_index(wall_index) if has_wall_source else target
	var tile := _tile(_deal_layer, card, _face_visible(seat),
		start, hand_unit, G.wall_angle(seat))
	tile.set_ready_locked(round != null and bool(round.players[seat].ready))
	tile.scale = Vector2.ONE * (G.WALL_UNIT / hand_unit)
	for node in _wall_layer.get_children():
		if int(node.get_meta("wall_ring_index", -2)) == wall_index:
			node.visible = false
	var complete := func():
		_draw_flights.erase(seat)
		_release_visual_node(tile)
		var drawn := _tile(draw_boxes[seat], card, _face_visible(seat),
			target, hand_unit, UI.ROTATIONS[rel])
		drawn.set_ready_locked(round != null and bool(round.players[seat].ready))
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
	var ordinary_index := 0
	if player != null and not player.discards.is_empty():
		for i in maxi(0, player.discards.size() - 1):
			if not TILES.is_chicken(str(player.discards[i])): ordinary_index += 1
	var chicken := TILES.is_chicken(card)
	var charge := false
	var target := G.ordinary_slot_center(seat, ordinary_index, human_seat)
	if chicken:
		# 幺鸡进红牌/碰杠区，不进普通弃牌区。
		var global_target := Vector2.ZERO
		if discard_id >= 0: global_target = discard_target_global(seat, discard_id)
		if player != null and not player.discards.is_empty():
			charge = table.round.is_charge_discard(seat, player.discards.size() - 1)
		if global_target != Vector2.ZERO:
			target = get_global_transform().affine_inverse() * global_target
		else:
			var hand := G.hand13_rect(seat, human_seat)
			match rel:
				0: target = Vector2(G.CENTER.x, hand.position.y - 60.0)
				1: target = Vector2(hand.end.x + 60.0, G.CENTER.y)
				2: target = Vector2(G.CENTER.x, hand.end.y + 60.0)
				_: target = Vector2(hand.position.x - 60.0, G.CENTER.y)
	var target_size: Vector2 = Vector2(G.RED_WIDTH, G.RED_HEIGHT) if chicken \
		else Vector2(TileView.BASE_W, TileView.BASE_H) * G.ORDINARY_UNIT
	var target_angle: float = UI.ROTATIONS[rel] + (PI / 2.0 if charge else 0.0)
	if missing_source:
		node = _tile(_deal_layer, card, true, target, 1.0, target_angle)
	if node.get_parent() != _deal_layer: node.reparent(_deal_layer)
	node.set_ready_locked(false)
	var target_scale := target_size / node.size
	var duration := 0.0 if missing_source else GameConfig.tile_motion_seconds()
	_latest_discard_seat = seat
	_latest_discard_id = discard_id
	for layer in [_discard_layer, _red_layer]:
		for previous in layer.get_children():
			if previous is TileView: previous.set_latest_highlight(false)
	_discard_flight_id += 1
	var flight_id := _discard_flight_id
	_discard_flights[flight_id] = {"node_id": node.get_instance_id(), "card": card, "seat": seat,
		"chicken": chicken, "charge": charge, "target": target, "rel": rel, "angle": target_angle,
		"discard_id": discard_id,
		"tween": null, "finish": on_finish}
	if duration <= 0.0:
		_finish_discard_flight(flight_id)
		return
	var tw := _motion_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_discard_flights[flight_id].tween = tw
	tw.tween_property(node, "position", target - node.size / 2.0, duration)
	tw.tween_property(node, "scale", target_scale, duration)
	tw.tween_property(node, "rotation", target_angle, duration)
	tw.chain().tween_callback(Callable(self, "_finish_discard_flight").bind(flight_id))

func _finish_discard_flight(flight_id: int) -> void:
	var data: Dictionary = _discard_flights.get(flight_id, {})
	if data.is_empty(): return
	_discard_flights.erase(flight_id)
	var node = instance_from_id(int(data.get("node_id", 0)))
	var card := str(data.get("card", ""))
	var seat := int(data.get("seat", 0))
	var chicken := bool(data.get("chicken", false))
	var target: Vector2 = data.get("target", Vector2.ZERO)
	var rel := int(data.get("rel", 0))
	var angle := float(data.get("angle", 0.0))
	if node is TileView:
		if chicken:
			_place_exposed_tiles(seat)
		var destination: Control = _red_layer if chicken else _discard_layer
		if node.get_parent() != destination: node.reparent(destination, false)
		node.set_interactive(false)
		node.set_card(card, true)
		node.set_unit(1.0 if chicken else G.ORDINARY_UNIT)
		node.pivot_offset = node.size / 2.0
		node.position = target - node.size / 2.0
		node.rotation = angle
		node.scale = Vector2(G.RED_WIDTH / TileView.BASE_W, G.RED_HEIGHT / TileView.BASE_H) if chicken else Vector2.ONE
		node.rotation = angle
		node.set_meta("new_kind", "red" if chicken else "ordinary")
		node.set_meta("v2_seat", seat)
		node.set_meta("discard_id", int(data.get("discard_id", -1)))
		node.set_meta("meld_index", -1)
		node.set_meta("v2_charge", bool(data.get("charge", false)))
		node.set_latest_highlight(seat == _latest_discard_seat and int(data.get("discard_id", -1)) == _latest_discard_id)
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
		if tween.is_valid(): tween.kill()
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
	var used: Dictionary = {}
	var moves: Array = []
	if not hand_slot_map.is_empty():
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

func _meld_targets(seat: int, meld_index: int, count: int, tile: String) -> Array:
	var positions: Dictionary = _meld_positions(seat)
	if positions.has(meld_index):
		return positions[meld_index]
	var rel := G.relative_seat(human_seat, seat)
	var anchor := G.meld_anchor(seat, human_seat)
	var dir: Vector2
	match rel:
		0: dir = Vector2.RIGHT
		2: dir = Vector2.LEFT
		1: dir = Vector2.UP
		_: dir = Vector2.DOWN
	var unit := G.ORDINARY_UNIT
	var step := G.TILE_BASE.x * unit + 8.0
	var out: Array = []
	for slot in count:
		out.append(anchor + dir * (-40.0 + slot * step))
	return out

## 某家全部非鸡牌碰/杠的最终落点（含换行与整体居中），供静态重建和动画目标共用。
func _meld_positions(seat: int) -> Dictionary:
	var out := {}
	if round == null: return out
	var live: Dictionary = MODEL.build(round, human_seat)
	for data in live.get("seats", []):
		if int(data.seat) != seat: continue
		for spec in red_layout(data.get("exposed_timeline", []), seat, G.relative_seat(human_seat, seat), true):
			if TILES.is_chicken(str(spec.tile)): continue
			var mi := int(spec.meld_index)
			if not out.has(mi): out[mi] = []
			out[mi].append(Vector2(spec.center))
	return out

func _place_exposed_tiles(seat: int, excluded_meld: int = -1) -> void:
	if round == null: return
	var rel := G.relative_seat(human_seat, seat)
	var layout: Array = []
	for data in MODEL.build(round, human_seat).get("seats", []):
		if int(data.seat) == seat: layout = red_layout(data.get("exposed_timeline", []), seat, rel, true)
	for node in _red_layer.get_children() + _meld_layer.get_children():
		if not (node is TileView) or int(node.get_meta("v2_seat", -1)) != seat: continue
		var mi := int(node.get_meta("meld_index", -1))
		if mi >= 0 and mi == excluded_meld: continue
		for spec in layout:
			var matches := int(spec.meld_index) == mi and int(spec.meld_slot) == int(node.get_meta("meld_slot", -2)) if mi >= 0 \
				else int(spec.meld_index) < 0 and int(spec.discard_id) == int(node.get_meta("discard_id", -2))
			if not matches: continue
			node.position = Vector2(spec.center) - node.size / 2.0
			break

## 碰/杠：手牌和来源弃牌飞到碰杠区。
func animate_meld(event: Dictionary, done: Callable) -> void:
	var action_id := _begin_visual_action()
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
	var target_sizes: Array = []
	var target_angles: Array = []
	var meld_index := int(event.get("index", 0))
	var rel := G.relative_seat(human_seat, seat)
	var source_slot := G.exposed_kong_source_slot(seat, int(event.get("source", -1))) if kind == "kong" else -1
	if chicken and table != null and table.round != null:
		# 鸡牌碰杠落红牌区，目标从当前红牌时间轴计算。
		var live: Dictionary = MODEL.build(table.round, human_seat)
		var data: Dictionary = {}
		for s in live.get("seats", []):
			if int(s.seat) == seat: data = s
		for spec in red_layout(data.get("exposed_timeline", data.get("red_timeline", [])), seat, rel, true):
			if int(spec.get("meld_index", -1)) != meld_index: continue
			targets.append(Vector2(spec.center))
			target_sizes.append(Vector2(G.RED_WIDTH, G.RED_HEIGHT))
			target_angles.append(UI.ROTATIONS[rel] + (PI / 2.0 if bool(spec.get("sideways", spec.charge)) else 0.0))
	if targets.is_empty():
		targets = _meld_targets(seat, meld_index, count, tile)
		for i in count:
			target_sizes.append(Vector2(G.RED_WIDTH, G.RED_HEIGHT))
			target_angles.append(UI.ROTATIONS[rel] + (PI / 2.0 if i == source_slot else 0.0))
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
	var land := func():
		_place_exposed_tiles(seat, meld_index)
		for i in nodes.size():
			var node: TileView = nodes[i]
			var destination: Control = _red_layer if chicken else _meld_layer
			if node.get_parent() != destination: node.reparent(destination, false)
			node.set_card(tile if visible_face else "", visible_face)
			node.set_interactive(false)
			node.set_latest_highlight(false)
			node.set_ready_locked(false)
			node.set_unit(1.0)
			node.pivot_offset = node.size / 2.0
			node.scale = Vector2(G.RED_WIDTH / TileView.BASE_W, G.RED_HEIGHT / TileView.BASE_H)
			node.position = Vector2(targets[i]) - node.size / 2.0
			node.rotation = float(target_angles[i])
			node.set_meta("new_kind", "red" if chicken else "meld")
			node.set_meta("v2_seat", seat)
			node.set_meta("meld_index", meld_index)
			node.set_meta("meld_slot", i)
			node.set_meta("meld_sideways", i if i == source_slot else -1)
			node.set_meta("meld_concealed", concealed)
			node.set_meta("meld_revealed", visible_face)
		var held: Array = []
		for slot in remaining_sources.size():
			var kept: TileView = remaining_sources[slot].node
			if kept.get_parent() != hand_boxes[seat]: kept.reparent(hand_boxes[seat], false)
			held.append(kept.position + kept.size / 2.0)
			kept.set_meta("new_kind", "hand")
			kept.set_meta("drawn", false)
			kept.set_meta("concealed_index", int(remaining_sources[slot].index))
			kept.set_meta("v2_hand_slot", slot)
			hand_boxes[seat].move_child(kept, slot)
		_held_hand_centers[seat] = held
	var duration := GameConfig.tile_motion_seconds()
	if duration <= 0.0:
		land.call()
		_complete_visual_action(action_id, done)
		return
	var flight := _motion_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in nodes.size():
		var node: TileView = nodes[i]
		# 飞行实体置于动画层，经过牌墙和弃牌时保持可见。
		node.reparent(_deal_layer)
		node.set_card(tile if visible_face else "", visible_face)
		node.set_interactive(false)
		node.set_latest_highlight(false)
		node.set_ready_locked(false)
		var target: Vector2 = targets[i]
		var tile_size: Vector2 = target_sizes[i]
		flight.tween_property(node, "position", target - node.size / 2.0, duration)
		flight.tween_property(node, "scale", tile_size / node.size, duration)
		flight.tween_property(node, "rotation", target_angles[i], duration)
	flight.chain().tween_callback(func():
		land.call()
		_complete_visual_action(action_id, done))

func _build_melds() -> void:
	if _meld_layer == null: return
	for data in snapshot.get("seats", []):
		var seat := int(data.get("seat", 0))
		var rel := G.relative_seat(human_seat, seat)
		var positions: Dictionary = _meld_positions(seat)
		var unit := 1.0
		for mi in data.get("melds", []).size():
			var meld: Dictionary = data.melds[mi]
			var kind := str(meld.get("kind", ""))
			var tile := str(meld.get("tile", ""))
			if tile == "" or TILES.is_chicken(tile): continue
			var count := 3
			if kind in ["kong", "add_kong"] or bool(meld.get("concealed", false)): count = 4
			var centers: Array = positions.get(mi, [])
			if centers.size() < count: continue
			var concealed := bool(meld.get("concealed", false))
			var revealed := bool(meld.get("revealed", false))
			var face := not concealed or revealed or seat == human_seat
			var source_slot := G.exposed_kong_source_slot(seat, int(meld.get("from_seat", -1))) \
				if kind == "kong" and not concealed else -1
			for slot in count:
				var center: Vector2 = centers[slot]
				var sideways := slot == source_slot
				var angle: float = UI.ROTATIONS[rel] + (PI / 2.0 if sideways else 0.0)
				var shown := _sync_tile(_meld_layer, "meld:%d:%d:%d" % [seat, mi, slot], tile if face else "", face, center, unit, angle,
					Vector2(G.RED_WIDTH / TileView.BASE_W, G.RED_HEIGHT / TileView.BASE_H))
				shown.set_meta("new_kind", "meld")
				shown.set_meta("v2_seat", seat)
				shown.set_meta("meld_index", mi)
				shown.set_meta("meld_slot", slot)
				shown.set_meta("meld_sideways", slot if sideways else -1)
				shown.set_meta("meld_concealed", concealed)
				shown.set_meta("meld_revealed", revealed or seat == human_seat)


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
			tile.set_ready_locked(bool(data.get("ready", false)))
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
			drawn_tile.set_ready_locked(bool(data.get("ready", false)))
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
		round.phase, AudioManager.seat_voice_packs])
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
	_labels.clear()
	_name_labels.clear()
	_badges.clear()
	_voice_buttons.clear()
	var names := _seat_display_names(seats)
	for data in seats:
		var seat := int(data.seat)
		var bounds := G.seat_hud_rect(G.relative_seat(human_seat, seat))
		var is_ready := bool(data.ready)
		var is_dealer := bool(data.is_dealer)
		var is_turn: bool = int(snapshot.get("turn", -1)) == seat and round.phase == ROUND_STATE.Phase.PLAYING
		var who: String = names[seat]
		var caption := ("● " if is_turn else "") + who
		var badge_space := 32.0 * (int(is_dealer) + int(is_ready))
		var name_width := minf(bounds.size.x - 8.0 - badge_space, ceilf(_hud_text_width(caption, 24)) + 2.0)
		var left := bounds.get_center().x - (name_width + badge_space) / 2.0
		var name_label := _table_text(_label_layer, caption, 24, UI.GOLD if is_turn else UI.INK)
		name_label.name = "SeatName%d" % seat
		name_label.position = Vector2(left, bounds.position.y)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.clip_text = true
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.size = Vector2(name_width, 32)
		name_label.tooltip_text = who
		_name_labels.append(name_label)

		var badge_position := name_label.position + Vector2(name_width + 4.0, 3)
		var dealer_badge: Label = null
		if is_dealer:
			dealer_badge = _hud_badge("庄", badge_position, UI.DEALER_BACKGROUND, UI.DEALER_BORDER)
			badge_position.x += 32.0
		_badges.append(dealer_badge)
		if is_ready:
			_hud_badge("听", badge_position, Color("#504221"), UI.GOLD)

		var score := _table_text(_label_layer, "", 28, UI.GOLD if is_dealer else UI.INK)
		score.name = "SeatScore%d" % seat
		score.position = Vector2(bounds.get_center().x - 71.0, bounds.position.y + 38.0)
		score.size = Vector2(142, 38)
		var remote_voice_layout: bool = table != null and table._net_mode() != "" and seat != human_seat and bool(data.is_human)
		var has_voice: bool = remote_voice_layout and round.phase != ROUND_STATE.Phase.SETTLED
		if remote_voice_layout and G.relative_seat(human_seat, seat) == 1:
			score.position.x = bounds.position.x
			score.size.x = 92
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
		var pill := StyleBoxFlat.new()
		pill.bg_color = Color(0.05, 0.13, 0.10, 0.78)
		pill.border_color = Color(UI.GOLD, 0.48) if is_turn else Color(UI.FELT_BORDER, 0.45)
		pill.set_border_width_all(1)
		pill.set_corner_radius_all(11)
		score.add_theme_stylebox_override("normal", pill)
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

		var voice_button: Button = null
		if has_voice:
			voice_button = Button.new()
			voice_button.name = "VoiceSpeaker%d" % seat
			voice_button.position = Vector2(bounds.get_center().x - 46.0, bounds.position.y + 82.0)
			voice_button.size = Vector2(92, 34)
			if G.relative_seat(human_seat, seat) == 1:
				voice_button.position = bounds.position + Vector2(96, 38)
				voice_button.size = Vector2(88, 38)
			voice_button.focus_mode = Control.FOCUS_NONE
			voice_button.add_theme_font_size_override("font_size", 20)
			voice_button.tooltip_text = "开关该玩家语音"
			_set_voice_button_state(voice_button, seat)
			voice_button.pressed.connect(func():
				table._toggle_remote_voice(seat)
				_set_voice_button_state(voice_button, seat))
			_label_layer.add_child(voice_button)
		_voice_buttons.append(voice_button)

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
		var edge := G.seat_hud_rect(G.relative_seat(human_seat, seat)).end.x
		var left := label.position.x + (label.size.x + _hud_text_width(caption, font_size)) / 2.0 + 6.0
		var available := maxf(0.0, edge - left)
		var delta_font := clampi(floori(24.0 * (available - 2.0) / maxf(_hud_text_width(delta.text, 24), 1.0)), 17, 24)
		if _hud_text_width(delta.text, delta_font) <= available:
			delta.position = Vector2(left, label.position.y)
			delta.size = Vector2(available, label.size.y)
			delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		else:
			# 极长总分不挪动原分数，净变化使用该座位预留的下方空间。
			delta.position = label.position + Vector2(0, label.size.y + 6)
			delta.size = Vector2(label.size.x, 30)
			delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			delta_font = 24
		delta.add_theme_font_size_override("font_size", delta_font)

func _set_voice_button_state(button: Button, seat: int) -> void:
	var enabled: bool = table._remote_voice_enabled(seat)
	button.text = "喇叭" if enabled else "静音"
	button.modulate = Color.WHITE if enabled else Color(0.62, 0.62, 0.62)

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
