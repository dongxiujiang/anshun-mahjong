class_name TileView
extends Control
## 一张麻将牌视图：优先使用 res/tiles 素材，缺图时回退程序化绘制。
## 素材编号：1-9=筒, 11-19=条, 21-29=万。无牌背素材 → 程序化牌背。

var tile := ""       # 牌值 "tong3"/"tiao1"/"wan9"
var face_up := true
var unit := 1.0      # 玩家牌与牌墙/出牌区可分别指定尺寸倍率。
var ready_locked := false  # 报听手牌金边，正面和牌背共用。
var highlight := false   # 金框高亮（用于标记鸡牌、报听等）
var back_depth_top := false  # 牌背白色牌体边朝上（南墙朝桌内）
var latest_highlight := false   # 最新打出的牌，使用高对比橙色
var ai_teach_highlight := false   # AI 教学推荐，独立于鸡牌/报听金框
var score_highlight := false   # 结算预览阶段的记分牌黄色底色
var selected := false
var interactive := false
var _table_position := Vector2.ZERO
var _hovered := false
var touch_padding := 14.0
var _lift_tween: Tween
var _win_tween: Tween
var _win_glow := 0.0:
	set(value):
		_win_glow = value
		queue_redraw()

const BASE_W := 48.0
const BASE_H := 64.0

static var _tex_cache := {}
static var _style_cache := {}

func _ready() -> void:
	_apply_size()
	set_interactive(interactive)
	# Tile identity is already visible on the face; do not show a second text
	# description when the pointer rests over a tile.
	tooltip_text = ""
	mouse_entered.connect(func(): _hovered = true)
	mouse_exited.connect(func(): _hovered = false)

func set_table_position(pos: Vector2) -> void:
	_table_position = pos
	_update_lift()

func set_selected(on: bool) -> void:
	selected = on
	queue_redraw()

func set_interactive(on: bool) -> void:
	interactive = on
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW

func set_winning(on: bool) -> void:
	if _win_tween != null: _win_tween.kill()
	_win_glow = 0.8 if on else 0.0
	if on and is_inside_tree() and DisplayServer.get_name() != "headless":
		# A finite pulse keeps the winning glow visible without repainting the
		# table forever while the settlement screen stays open.
		_win_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_win_tween.tween_property(self, "_win_glow", 0.35, 0.7)
		_win_tween.tween_property(self, "_win_glow", 0.85, 0.7)
		_win_tween.tween_property(self, "_win_glow", 0.8, 0.2)

## 保持绘制尺寸不变，只扩展触控命中区域，避免相邻手牌被视觉放大后互相遮挡。
func _has_point(point: Vector2) -> bool:
	if not interactive:
		return Rect2(Vector2.ZERO, size).has_point(point)
	var padding := touch_padding * unit

	# Expand vertically; horizontal overlap would make the next tile steal taps.
	return Rect2(-2.0, -padding, size.x + 4.0, size.y + padding * 2.0).has_point(point)

func _update_lift(animate: bool = false) -> void:
	# Discarding is a direct tap.  Keep the tile at its layout position so a
	# click or a later draw cannot leave a stale lifted tile behind.
	var destination := _table_position
	if _lift_tween != null: _lift_tween.kill()
	if animate and is_inside_tree() and DisplayServer.get_name() != "headless":
		_lift_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_lift_tween.tween_property(self, "position", destination, 0.16)
	else: position = destination

static func texture_path(t: String) -> String:
	var s := Tiles.suit(t)
	var r := Tiles.rank(t)
	var n := r
	if s == "tiao":
		n = 10 + r
	elif s == "wan":
		n = 20 + r
	return "res://res/tiles/%d.png" % n

static func _get_texture(t: String) -> Texture2D:
	var path := texture_path(t)
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_tex_cache[path] = tex
	return tex

func set_card(t: String, up: bool) -> void:
	tile = t
	face_up = up
	queue_redraw()

func set_highlight(on: bool) -> void:
	highlight = on
	queue_redraw()

func set_ready_locked(on: bool) -> void:
	if ready_locked == on: return
	ready_locked = on
	queue_redraw()

func set_latest_highlight(on: bool) -> void:
	latest_highlight = on
	queue_redraw()

func set_ai_teach_highlight(on: bool) -> void:
	ai_teach_highlight = on
	queue_redraw()

func set_score_highlight(on: bool) -> void:
	score_highlight = on
	queue_redraw()

func set_unit(k: float) -> void:
	unit = k
	_apply_size()
	queue_redraw()

func _apply_size() -> void:
	custom_minimum_size = Vector2(BASE_W, BASE_H) * unit
	size = custom_minimum_size

func _draw() -> void:
	var w := BASE_W * unit
	var h := BASE_H * unit
	var depth := 5.0 * unit
	draw_style_box(_tile_style(Color(0, 0, 0, 0.30), Color.TRANSPARENT), Rect2(2 * unit, 4 * unit, w, h))
	draw_style_box(_tile_style(Color("#becbb9"), Color("#8a9c86")), Rect2(0, 0, w, h))
	if face_up and tile != "":
		var face_color := Color("#f6f7ed") if not score_highlight else Color("#f3d875")
		var face_border := Color("#d9dfd2") if not score_highlight else Color("#c89d32")
		draw_style_box(_tile_style(face_color, face_border), Rect2(0, 0, w, h - depth))
		var tex := _get_texture(tile)
		if tex != null:
			draw_texture_rect(tex, Rect2(3 * unit, 2 * unit, w - 6 * unit, h - depth - 4 * unit), false)
		else:
			_draw_face_proc(w, h - depth)
		if score_highlight:
			draw_rect(Rect2(0, 0, w, h - depth), Color(0.95, 0.78, 0.22, 0.30))
		if Tiles.is_chicken(tile):
			draw_circle(Vector2(w - 4 * unit, 4 * unit), 2 * unit, Color("#c5993e"))
	else:
		var back_y := depth if back_depth_top else 0.0
		_draw_back(w, h - depth, back_y)
		if score_highlight:
			draw_rect(Rect2(0, back_y, w, h - depth), Color(0.95, 0.78, 0.22, 0.40))
	if ready_locked:
		draw_rect(Rect2(1.5 * unit, 1.5 * unit, w - 3 * unit, h - 3 * unit),
			Color("#f1d47f"), false, 2.5 * unit)
	if highlight or ai_teach_highlight or latest_highlight or selected or _win_glow > 0:
		var glow := _tile_style(Color.TRANSPARENT, Color(0.95, 0.80, 0.39, maxf(0.24, _win_glow)))
		glow.set_border_width_all(4)
		draw_style_box(glow, Rect2(-4, -4, w + 8, h + 8))
		var outline := _tile_style(Color.TRANSPARENT, Color("#f1d47f"))
		outline.set_border_width_all(2)
		draw_style_box(outline, Rect2(-1, -1, w + 2, h + 2))
		if highlight:
			draw_circle(Vector2(w / 2, -5 * unit), 2.5 * unit, Color("#f1d47f"))
		if ai_teach_highlight:
			# AI 推荐使用更粗的蓝色边框；多张同牌都会各自显示。
			var ai_outline := _tile_style(Color.TRANSPARENT, Color("#5ad4ff"))
			ai_outline.set_border_width_all(6)
			draw_style_box(ai_outline, Rect2(-5, -5, w + 10, h + 10))
		if latest_highlight:
			# 最新弃牌用亮橙色，和鸡牌/报听的暗金色区分。
			var latest_glow := _tile_style(Color.TRANSPARENT, Color(1.0, 0.38, 0.12, 0.45))
			latest_glow.set_border_width_all(8)
			draw_style_box(latest_glow, Rect2(-7, -7, w + 14, h + 14))
			var latest_outline := _tile_style(Color.TRANSPARENT, Color("#ff7a2f"))
			latest_outline.set_border_width_all(5)
			draw_style_box(latest_outline, Rect2(-3, -3, w + 6, h + 6))
	if bool(get_meta("charge_chicken", false)) and bool(get_meta("gold_chicken", false)):
		_draw_badge(Vector2(w - 12 * unit, 12 * unit), Color("#d5af4e"), "冲金")
	elif bool(get_meta("charge_chicken", false)):
		_draw_badge(Vector2(w - 12 * unit, 12 * unit), Color("#db8246"), "冲")
	elif bool(get_meta("gold_chicken", false)):
		_draw_badge(Vector2(w - 12 * unit, 12 * unit), Color("#d5af4e"), "金")

func _draw_badge(center: Vector2, color: Color, text: String) -> void:
	draw_circle(center, 8.0 * unit, Color(0.08, 0.12, 0.1, 0.78))
	draw_circle(center, 6.5 * unit, color)
	draw_string(_font(), center + Vector2(-4.0 * unit, 3.5 * unit), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8.0 * unit), Color("#fff7dc"))

func _tile_style(color: Color, border: Color) -> StyleBoxFlat:
	# 动画/结算会反复重绘同一批牌；缓存只读 StyleBox，避免每帧分配。
	var radius := maxi(1, int(3 * unit))
	var key := (int(color.to_rgba32()) * 73856093) ^ (int(border.to_rgba32()) * 19349663) ^ radius
	if _style_cache.has(key):
		return _style_cache[key]
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	_style_cache[key] = style
	return style

## ---- 程序化牌背（无素材） ----
func _draw_back(w: float, h: float, offset_y: float = 0.0) -> void:
	draw_style_box(_tile_style(Color("#286c53"), Color("#75a18b")),
		Rect2(0, offset_y, w, h))
	draw_rect(Rect2(4 * unit, offset_y + 4 * unit, w - 8 * unit, h - 8 * unit),
		Color("#5b9177"), false, maxf(0.6, unit))
	for i in 3:
		var x := w * (0.35 + i * 0.15)
		draw_line(Vector2(x, offset_y + h * 0.3), Vector2(x, offset_y + h * 0.7),
			Color("#3a7d60"), maxf(0.6, unit))

## ---- 程序化牌面（素材缺失时的兜底） ----
func _draw_face_proc(w: float, h: float) -> void:
	var suit := Tiles.suit(tile)
	var rank := Tiles.rank(tile)
	var accent: Color = {"wan": Color("#1a4fd0"), "tiao": Color("#0c8a3f"), "tong": Color("#c0392b")}.get(suit, Color("#555555"))
	draw_rect(Rect2(0, 0, w, h), accent)
	draw_rect(Rect2(2, 2, w - 4, h - 4), Color("#fbf8ea"))
	var f := _font()
	if suit == "wan":
		draw_string(f, Vector2(w / 2, h / 2 + 8), "萬", HORIZONTAL_ALIGNMENT_CENTER, -1, int(h * 0.38), Color("#1a4fd0"))
	elif suit == "tong":
		var pips := [[0,0],[2,0],[1,0],[0,2],[2,2],[1,2],[0,1],[2,1],[1,1]]
		for i in rank:
			var p = pips[i]
			draw_circle(Vector2(w * 0.28 + p[0] * w * 0.22, h * 0.34 + p[1] * h * 0.2), w * 0.09, Color("#c0392b"))
	elif suit == "tiao":
		for i in rank:
			draw_rect(Rect2(w / 2 - 3, h * 0.2 + i * (h * 0.07), 6, h * 0.05), Color("#0c8a3f"))
	draw_string(f, Vector2(w - 4, h * 0.16), str(rank), HORIZONTAL_ALIGNMENT_RIGHT, -1, int(h * 0.16), Color("#7a1f2b"))

static var _sysfont: SystemFont
static var _font_resource: Font
static func _font() -> Font:
	if _font_resource == null and ResourceLoader.exists("res://res/fonts/NotoSansSC-Regular.otf"):
		_font_resource = load("res://res/fonts/NotoSansSC-Regular.otf")
	if _font_resource != null:
		return _font_resource
	if _sysfont == null:
		_sysfont = SystemFont.new()
		_sysfont.font_names = PackedStringArray(["Microsoft YaHei", "PingFang SC", "Heiti SC", "Noto Sans CJK SC", "sans-serif"])
	return _sysfont


func reset() -> void:
	"""重置 TileView 为默认状态，用于对象池回收。"""
	set_selected(false)
	set_interactive(false)
	set_winning(false)
	set_highlight(false)
	set_ready_locked(false)
	set_latest_highlight(false)
	set_ai_teach_highlight(false)
	set_score_highlight(false)
	tile = ""
	face_up = false
	set_unit(1.0)
	_table_position = Vector2.ZERO
	modulate = Color.WHITE
	visible = true
	if _lift_tween != null: _lift_tween.kill()
	_lift_tween = null
	_win_tween = null
	_hovered = false
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	pivot_offset = Vector2.ZERO
	self_modulate = Color.WHITE
	z_index = 0
	back_depth_top = false
	tooltip_text = ""
	# Containers may have assigned a larger size to a pooled tile.  Reset both
	# the minimum and the current rectangle so a red tile cannot inherit a hand
	# or draw tile's dimensions when it is reused later in the same refresh.
	reset_size()
	if not gui_input.get_connections().is_empty():
		for conn in gui_input.get_connections():
			if conn.callable.is_valid(): gui_input.disconnect(conn.callable)
	for key in get_meta_list(): remove_meta(key)
