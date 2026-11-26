extends Control
## 胡牌后、弹出结算卡片前的「翻鸡时刻」展示层：
## 让玩家先在无遮挡的 3D 亮牌牌桌上清晰看清翻出的鸡牌及关联计分鸡牌，再平滑进入结算界面。

const UI := preload("res://src/app/AppTheme.gd")
const TileArt := preload("res://src/presentation/TileArt.gd")
const Tiles := preload("res://src/anshun/scoring/Tiles.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")

const REVEAL_SECONDS := 2.6

signal finished(key: String)

var active_key := ""
var flip_tile_value := ""

var _card := PanelContainer.new()
var _title_label: Label
var _sub_label: Label
var _flip_tile_card := PanelContainer.new()
var _flip_tile_box := CenterContainer.new()
var _flip_name_label: Label
var _related_row := HBoxContainer.new()
var _gold_hint_label: Label
var _skip_btn: Button
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 18
	hide()

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.add_theme_stylebox_override("panel", UI.elevated_card(Color("#0d261ef0"), 18, 18, Color("#e4bf68"), 2, 14))
	_card.custom_minimum_size = Vector2(360, 0)
	center.add_child(_card)

	var col := VBoxContainer.new()
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
	main_row.alignment = BoxContainer.ALIGNMENT_CENTER
	main_row.add_theme_constant_override("separation", 18)
	col.add_child(main_row)

	var flip_col := VBoxContainer.new()
	flip_col.alignment = BoxContainer.ALIGNMENT_CENTER
	flip_col.add_theme_constant_override("separation", 4)
	main_row.add_child(flip_col)

	_flip_tile_card.custom_minimum_size = Vector2(64, 86)
	_flip_tile_card.add_theme_stylebox_override("panel", UI.elevated_card(Color("#f6eed9"), 8, 5, Color("#e8be59"), 2, 6))
	_flip_tile_card.add_child(_flip_tile_box)
	flip_col.add_child(_flip_tile_card)

	_flip_name_label = UI.label("", 15, UI.GOLD_BRIGHT)
	_flip_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flip_col.add_child(_flip_name_label)

	var rel_col := VBoxContainer.new()
	rel_col.alignment = BoxContainer.ALIGNMENT_CENTER
	rel_col.add_theme_constant_override("separation", 6)
	main_row.add_child(rel_col)

	var rel_title := UI.label("本局关联鸡牌", 14, Color("#b9ddd0"))
	rel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rel_col.add_child(rel_title)

	_related_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_related_row.add_theme_constant_override("separation", 8)
	rel_col.add_child(_related_row)

	_gold_hint_label = UI.label("", 13, Color("#ffd66b"))
	_gold_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_hint_label.hide()
	rel_col.add_child(_gold_hint_label)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(footer)
	_skip_btn = UI.button("查看结算", finish_now)
	_skip_btn.custom_minimum_size = Vector2(126, 36)
	_skip_btn.add_theme_font_size_override("font_size", 14)
	footer.add_child(_skip_btn)


func is_active_for(key: String) -> bool:
	return visible and not key.is_empty() and active_key == key


func present(key: String, result: Dictionary, members: Array) -> bool:
	var flip_tile := str(result.get("flip_tile", ""))
	if flip_tile.is_empty() or not Catalog.valid_value(flip_tile):
		return false
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
	_flip_name_label.text = "翻出 " + _tile_name(flip_tile)

	_clear(_flip_tile_box)
	_add_tile_visual(_flip_tile_box, flip_tile, Vector2(52, 74))

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
		item_col.alignment = BoxContainer.ALIGNMENT_CENTER
		item_col.add_theme_constant_override("separation", 3)
		var mini := PanelContainer.new()
		mini.custom_minimum_size = Vector2(40, 54)
		mini.add_theme_stylebox_override("panel", UI.card(Color("#f7efd9"), 5, 3, Color("#f2c24e") if is_gold else Color("#b8a885"), 2 if is_gold else 1))
		_add_tile_visual(mini, val, Vector2(32, 46))
		item_col.add_child(mini)
		var tag := UI.label("金鸡×2" if is_gold else _tile_name(val), 12, Color("#ffd966") if is_gold else UI.INK)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_col.add_child(tag)
		_related_row.add_child(item_col)

	if has_gold_chicken:
		_gold_hint_label.text = "命中幺鸡/八筒，金鸡双倍计分！"
		_gold_hint_label.show()
	else:
		_gold_hint_label.hide()

	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate = Color(1, 1, 1, 0)
	_card.pivot_offset = _card.get_combined_minimum_size() * 0.5
	_card.scale = Vector2(0.88, 0.88)
	show()
	_tween = create_tween().set_ignore_time_scale(true)
	_tween.set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_card, "scale", Vector2.ONE, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(REVEAL_SECONDS)
	_tween.tween_property(self, "modulate:a", 0.0, 0.22)
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
	active_key = ""
	flip_tile_value = ""
	hide()


func _complete() -> void:
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
