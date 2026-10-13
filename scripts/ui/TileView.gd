class_name TileView
extends Control
## 一张麻将牌视图：优先使用 res/tiles 素材，缺图时回退程序化绘制。
## 素材编号：1-9=筒, 11-19=条, 21-29=万。无牌背素材 → 程序化牌背。

var tile := ""       # 牌值 "tong3"/"tiao1"/"wan9"
var face_up := true
var unit := 1.0      # 玩家牌与牌墙/出牌区可分别指定尺寸倍率。
var highlight := false   # 金框高亮（用于标记鸡牌）
var selected := false
var interactive := false
var _table_position := Vector2.ZERO
var _hovered := false
var touch_padding := 14.0

const BASE_W := 48.0
const BASE_H := 64.0

static var _tex_cache := {}

func _ready() -> void:
	_apply_size()
	set_interactive(interactive)
	tooltip_text = "%d%s" % [Tiles.rank(tile), {"wan": "万", "tiao": "条", "tong": "筒"}.get(Tiles.suit(tile), "")] if face_up and tile != "" else ""
	mouse_entered.connect(func(): _hovered = true; _update_lift())
	mouse_exited.connect(func(): _hovered = false; _update_lift())

func set_table_position(pos: Vector2) -> void:
	_table_position = pos
	_update_lift()

func set_selected(on: bool) -> void:
	selected = on
	_update_lift()
	queue_redraw()

func set_interactive(on: bool) -> void:
	interactive = on
	mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	_update_lift()

## 保持绘制尺寸不变，只扩展触控命中区域，避免相邻手牌被视觉放大后互相遮挡。
func _has_point(point: Vector2) -> bool:
	if not interactive:
		return Rect2(Vector2.ZERO, size).has_point(point)
	var padding := touch_padding * unit
	return Rect2(-padding, -padding, size.x + padding * 2.0, size.y + padding * 2.0).has_point(point)

func _update_lift() -> void:
	position = _table_position + Vector2(0, -14.0 if selected else (-6.0 if _hovered and interactive else 0.0))

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
	draw_style_box(_tile_style(Color(0, 0, 0, 0.23), Color.TRANSPARENT), Rect2(2 * unit, 4 * unit, w, h))
	draw_style_box(_tile_style(Color("#becbb9"), Color("#8a9c86")), Rect2(0, 0, w, h))
	if face_up and tile != "":
		draw_style_box(_tile_style(Color("#f6f7ed"), Color("#d9dfd2")), Rect2(0, 0, w, h - depth))
		var tex := _get_texture(tile)
		if tex != null:
			draw_texture_rect(tex, Rect2(3 * unit, 2 * unit, w - 6 * unit, h - depth - 4 * unit), false)
		else:
			_draw_face_proc(w, h - depth)
		if Tiles.is_chicken(tile):
			draw_circle(Vector2(w - 4 * unit, 4 * unit), 2 * unit, Color("#c5993e"))
	else:
		_draw_back(w, h - depth)
	if highlight or selected:
		var outline := _tile_style(Color.TRANSPARENT, Color("#f1d47f"))
		outline.set_border_width_all(2)
		draw_style_box(outline, Rect2(-1, -1, w + 2, h + 2))
		if highlight:
			draw_circle(Vector2(w / 2, -5 * unit), 2.5 * unit, Color("#f1d47f"))
	if bool(get_meta("charge_chicken", false)):
		_draw_badge(Vector2(w - 12 * unit, 12 * unit), Color("#db8246"), "冲")
	elif bool(get_meta("gold_chicken", false)):
		_draw_badge(Vector2(w - 12 * unit, 12 * unit), Color("#d5af4e"), "金")

func _draw_badge(center: Vector2, color: Color, text: String) -> void:
	draw_circle(center, 8.0 * unit, Color(0.08, 0.12, 0.1, 0.78))
	draw_circle(center, 6.5 * unit, color)
	draw_string(_font(), center + Vector2(-4.0 * unit, 3.5 * unit), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(8.0 * unit), Color("#fff7dc"))

func _tile_style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_corner_radius_all(maxi(1, int(3 * unit)))
	style.set_border_width_all(1)
	return style

## ---- 程序化牌背（无素材） ----
func _draw_back(w: float, h: float) -> void:
	draw_style_box(_tile_style(Color("#286c53"), Color("#75a18b")), Rect2(0, 0, w, h))
	draw_rect(Rect2(4 * unit, 4 * unit, w - 8 * unit, h - 8 * unit), Color("#5b9177"), false, maxf(0.6, unit))
	for i in 3:
		var x := w * (0.35 + i * 0.15)
		draw_line(Vector2(x, h * 0.3), Vector2(x, h * 0.7), Color("#3a7d60"), maxf(0.6, unit))

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
