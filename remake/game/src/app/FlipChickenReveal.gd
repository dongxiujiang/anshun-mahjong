extends Control
## 胡牌后、弹出结算卡片前的「翻鸡时刻」自动翻牌动画展示层：
## 先播放清晰可辨的翻牌动画，展示翻出的鸡牌与关联计分鸡牌并留足全员观看时间，随后自动平滑进入结算界面（无需手动点击）。

const UI := preload("res://src/app/AppTheme.gd")
const TileArt := preload("res://src/presentation/TileArt.gd")
const TableTheme := preload("res://src/presentation/TableTheme.gd")
const Tiles := preload("res://src/anshun/scoring/Tiles.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")

const MotionConfig = preload("res://src/presentation/MotionConfig.gd")
const MotionFX = preload("res://src/presentation/MotionFX.gd")

const REVEAL_SECONDS := 2.4

signal finished(key: String)

var active_key := ""
var flip_tile_value := ""

var _quality := MotionConfig.current_quality
var _particles := MotionFX.ParticlePool.new()
var _fx_overlay: Control
var _card := PanelContainer.new()
var _title_label: Label
var _sub_label: Label
var _flip_tile_card := PanelContainer.new()
var _flip_tile_box := CenterContainer.new()
var _flip_back_mark: Label
var _flip_name_label: Label
var _related_row := HBoxContainer.new()
var _gold_hint_label: Label
var _auto_hint_label: Label
var _progress_track := PanelContainer.new()
var _progress_fill := ColorRect.new()
var _tween: Tween
var _face_box: StyleBoxFlat
var _back_box: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 18
	hide()

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", UI.elevated_card(Color("#0d261ef0"), 18, 18, Color("#e4bf68"), 2, 14))
	_card.custom_minimum_size = Vector2(368, 0)
	center.add_child(_card)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	_card.add_child(col)

	_title_label = UI.label("翻鸡时刻", 24, UI.GOLD_BRIGHT)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title_label)

	_sub_label = UI.label("", 14, UI.MUTED)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_sub_label)

	var main_row := HBoxContainer.new()
	main_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_row.alignment = BoxContainer.ALIGNMENT_CENTER
	main_row.add_theme_constant_override("separation", 18)
	col.add_child(main_row)

	var flip_col := VBoxContainer.new()
	flip_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flip_col.alignment = BoxContainer.ALIGNMENT_CENTER
	flip_col.add_theme_constant_override("separation", 5)
	main_row.add_child(flip_col)

	_face_box = UI.elevated_card(Color("#f6eed9"), 8, 5, Color("#e8be59"), 2, 6)
	_back_box = UI.elevated_card(Color("#1e5b3a"), 8, 5, Color("#d4af5e"), 2, 6)
	_flip_tile_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flip_tile_card.custom_minimum_size = Vector2(64, 86)
	_flip_tile_card.add_theme_stylebox_override("panel", _back_box)
	_flip_tile_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flip_tile_card.add_child(_flip_tile_box)
	_flip_back_mark = UI.label("鸡", 24, Color("#f2d488"))
	_flip_back_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flip_back_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_flip_tile_card.add_child(_flip_back_mark)
	flip_col.add_child(_flip_tile_card)

	_flip_name_label = UI.label("", 15, UI.GOLD_BRIGHT)
	_flip_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flip_col.add_child(_flip_name_label)

	var rel_col := VBoxContainer.new()
	rel_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rel_col.alignment = BoxContainer.ALIGNMENT_CENTER
	rel_col.add_theme_constant_override("separation", 6)
	main_row.add_child(rel_col)

	var rel_title := UI.label("本局关联鸡牌", 14, Color("#b9ddd0"))
	rel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rel_col.add_child(rel_title)

	_related_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_related_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_related_row.add_theme_constant_override("separation", 8)
	rel_col.add_child(_related_row)

	_gold_hint_label = UI.label("", 13, Color("#ffd66b"))
	_gold_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_hint_label.hide()
	rel_col.add_child(_gold_hint_label)

	var footer := VBoxContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 5)
	col.add_child(footer)

	_progress_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_track.custom_minimum_size = Vector2(220, 4)
	_progress_track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_progress_track.add_theme_stylebox_override("panel", UI.card(Color(0.04, 0.12, 0.09, 0.85), 2, 0, Color(0.78, 0.64, 0.35, 0.25), 1))
	footer.add_child(_progress_track)

	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_fill.color = Color("#e8c167")
	_progress_fill.custom_minimum_size = Vector2(218, 2)
	_progress_fill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_progress_track.add_child(_progress_fill)

	_auto_hint_label = UI.label("即将自动进入结算…", 12, Color("#9db8ae"))
	_auto_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_child(_auto_hint_label)

	_fx_overlay = Control.new()
	_fx_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx_overlay)
	_fx_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx_overlay.draw.connect(_particles.draw.bind(_fx_overlay))
	apply_quality(_quality)
	set_process(false)


func apply_quality(value: String) -> void:
	_quality = MotionConfig.normalize_quality(value)
	var shadow := 14 if MotionConfig.value("panel", "shadow_enabled", false, _quality) else 0
	if _card.has_theme_stylebox_override("panel"):
		var box: StyleBoxFlat = _card.get_theme_stylebox("panel")
		box.shadow_size = shadow
	if _face_box:
		_face_box.shadow_size = 6 if shadow > 0 else 0
	if _back_box:
		_back_box.shadow_size = 6 if shadow > 0 else 0
	if not MotionConfig.is_detail(_quality):
		_clear_particles()


func _clear_particles() -> void:
	_particles.clear()
	set_process(false)
	if _fx_overlay:
		_fx_overlay.queue_redraw()


func _process(delta: float) -> void:
	set_process(_particles.step(delta))
	_fx_overlay.queue_redraw()


func is_active_for(key: String) -> bool:
	return visible and not key.is_empty() and active_key == key


func _sync_back_color() -> void:
	if _back_box == null:
		return
	var spec: Dictionary = TableTheme.tile_back_data(TileArt._tile_back_id)
	var c: Color = spec.get("back", Color(0.18, 0.58, 0.32, 1.0))
	_back_box.bg_color = c.darkened(0.12)


func _set_tile_revealed(revealed: bool, flip_tile: String) -> void:
	_flip_tile_card.add_theme_stylebox_override("panel", _face_box if revealed else _back_box)
	_flip_tile_box.visible = revealed
	_flip_back_mark.visible = not revealed
	_flip_name_label.text = ("翻出 " + _tile_name(flip_tile)) if revealed else "正在翻鸡…"


func _set_progress(ratio: float) -> void:
	_progress_fill.custom_minimum_size.x = maxf(0.0, 218.0 * clampf(ratio, 0.0, 1.0))


func _burst_reveal_particles(has_gold_chicken: bool, fx: Dictionary) -> void:
	var count := int(fx.flip_particles) if has_gold_chicken else mini(8, int(fx.flip_particles))
	if count <= 0:
		return
	var colors := [Color("#ffe394"), Color("#eeb84b"), Color("#fff2bf")] if has_gold_chicken else [Color("#f0d388"), Color("#9fe0c2"), Color("#fff2d6")]
	_particles.emit_burst(size * 0.5, count, colors, 220.0, 420.0, 0.38, 0.62, 110.0)
	set_process(_particles.active_count > 0)
	if _fx_overlay:
		_fx_overlay.queue_redraw()


func present(key: String, result: Dictionary, members: Array) -> bool:
	var flip_tile := str(result.get("flip_tile", ""))
	if flip_tile.is_empty() or not Catalog.valid_value(flip_tile):
		return false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_clear_particles()
	var fx := MotionConfig.section("fx", _quality)
	var detailed := MotionConfig.is_detail(_quality)
	active_key = key
	flip_tile_value = flip_tile

	var winners: Array = result.get("winners", [])
	var winner_names := PackedStringArray()
	for s in winners:
		var idx := int(s)
		if idx in range(members.size()):
			winner_names.append(str(members[idx].get("nickname", "牌友")))
	var action_word := "自摸" if bool(result.get("self_draw", false)) else "胡牌"
	_sub_label.text = ("%s %s · 牌墙翻开鸡牌" % ["、".join(winner_names), action_word]) if not winner_names.is_empty() else "牌墙翻开本局鸡牌"

	_sync_back_color()
	_clear(_flip_tile_box)
	_add_tile_visual(_flip_tile_box, flip_tile, Vector2(52, 74))
	_set_tile_revealed(false, flip_tile)

	_clear(_related_row)
	var related: Array = Tiles.flip_related(flip_tile)
	if related.size() == 3:
		related = [related[1], related[0], related[2]]
	var has_gold_chicken := false
	for tile_val in related:
		var val := str(tile_val)
		var is_gold := Tiles.is_chicken(val)
		if is_gold:
			has_gold_chicken = true
		var item_col := VBoxContainer.new()
		item_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_col.alignment = BoxContainer.ALIGNMENT_CENTER
		item_col.add_theme_constant_override("separation", 3)
		var mini := PanelContainer.new()
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mini.custom_minimum_size = Vector2(40, 54)
		mini.add_theme_stylebox_override("panel", UI.card(Color("#f7efd9"), 5, 3, Color("#f2c24e") if is_gold else Color("#b8a885"), 2 if is_gold else 1))
		_add_tile_visual(mini, val, Vector2(32, 46))
		item_col.add_child(mini)
		var tag := UI.label("金鸡×2" if is_gold else _tile_name(val), 12, Color("#ffd966") if is_gold else UI.INK)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_col.add_child(tag)
		item_col.modulate.a = 0.0
		item_col.scale = Vector2.ONE * (0.86 if detailed else 0.94)
		_related_row.add_child(item_col)

	if has_gold_chicken:
		_gold_hint_label.text = "命中幺鸡/八筒，金鸡双倍计分！"
		_gold_hint_label.modulate.a = 0.0
		_gold_hint_label.show()
	else:
		_gold_hint_label.hide()

	var duration := float(fx.flip_in_duration)
	var from_scale := Vector2.ONE * float(fx.flip_from_scale)
	var stagger := float(fx.flip_related_stagger)
	var half_flip_in := 0.20 if detailed else 0.15
	var half_flip_out := 0.26 if detailed else 0.17
	var lift_y := 1.07 if detailed else 1.0

	modulate = Color(1, 1, 1, 0)
	_card.pivot_offset = _card.get_combined_minimum_size() * 0.5
	_card.scale = from_scale
	_flip_tile_card.pivot_offset = _flip_tile_card.custom_minimum_size * 0.5
	_flip_tile_card.scale = Vector2.ONE
	_set_progress(1.0)
	show()

	_tween = create_tween().set_ignore_time_scale(true)
	# 1. Card entrance
	_tween.set_trans(fx.flip_trans).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_card, "scale", Vector2.ONE, duration).from(from_scale)
	_tween.parallel().tween_property(self, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_QUAD)
	# 2. Brief anticipation beat on face-down tile back, then flip 180° horizontally to reveal face
	_tween.tween_interval(0.14 if detailed else 0.08)
	_tween.tween_property(_flip_tile_card, "scale", Vector2(0.0, lift_y), half_flip_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func():
		_set_tile_revealed(true, flip_tile)
		_burst_reveal_particles(has_gold_chicken, fx))
	_tween.tween_property(_flip_tile_card, "scale", Vector2.ONE, half_flip_out).set_trans(fx.flip_trans).set_ease(Tween.EASE_OUT)
	# 3. Reveal the 3 related chicken tiles right as the flip opens
	for i in _related_row.get_child_count():
		var item: Control = _related_row.get_child(i)
		item.pivot_offset = item.get_combined_minimum_size() * 0.5
		var delay := i * stagger
		_tween.parallel().tween_property(item, "modulate:a", 1.0, duration).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_property(item, "scale", Vector2.ONE, duration).set_delay(delay).set_trans(fx.flip_trans).set_ease(Tween.EASE_OUT)
	if has_gold_chicken:
		_tween.parallel().tween_property(_gold_hint_label, "modulate:a", 1.0, duration).set_delay(stagger * 2.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 4. Hold cleanly with visible auto-progress bar so all players can read, then auto-enter settlement
	_tween.tween_method(_set_progress, 1.0, 0.0, REVEAL_SECONDS).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_property(self, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_complete)
	return true


func finish_now() -> void:
	if not visible:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_complete()


func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_clear_particles()
	active_key = ""
	flip_tile_value = ""
	hide()


func _complete() -> void:
	_clear_particles()
	var key := active_key
	active_key = ""
	hide()
	if not key.is_empty():
		finished.emit(key)


static func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func _add_tile_visual(parent: Control, value: String, sz: Vector2) -> void:
	var tex := TileArt.face(value)
	if tex != null:
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = tex
		icon.custom_minimum_size = sz
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		parent.add_child(icon)
	else:
		var lbl := UI.label(_tile_name(value), 14, Color("#1f2e26"))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		parent.add_child(lbl)


static func _tile_name(value: String) -> String:
	if not Catalog.valid_value(value):
		return ""
	return value.right(1) + str({"wan": "万", "tiao": "条", "tong": "筒"}[value.left(-1)])
