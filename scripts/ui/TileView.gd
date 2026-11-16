class_name TileView
extends Control
## Shared offline-rendered tile artwork; logical sizes and hit areas stay unchanged.

var tile := ""       # 牌值 "tong3"/"tiao1"/"wan9"
var face_up := true
var flight_pitch := -1.0
var flight_progress := -1.0
var face_depth_top := true:
	set(value):
		if face_depth_top == value: return
		face_depth_top = value
		queue_redraw()
var standing_back_view := -1:
	set(value):
		if standing_back_view == value: return
		standing_back_view = value
		queue_redraw()
var unit := 1.0      # 玩家牌与牌墙/出牌区可分别指定尺寸倍率。
var highlight := false   # 金框高亮（用于标记鸡牌、报听等）
var back_depth_top := false:  # 牌背白色牌体边朝上（南墙朝桌内）
	set(value):
		if back_depth_top == value: return
		back_depth_top = value
		queue_redraw()
var latest_highlight := false   # 最新打出的牌，使用高对比橙色
var ai_teach_highlight := false   # AI 教学推荐，独立于鸡牌/报听金框
var score_highlight := false   # 结算预览阶段的记分牌黄色底色
var selected := false
var interactive := false
var presentation_3d := false:
	set(value):
		if presentation_3d == value: return
		presentation_3d = value
		set_interactive(interactive)
		queue_redraw()
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
const FACE_ROWS := {"wan": 0, "tiao": 1, "tong": 2}
const BACK_ATLAS := preload("res://res/tiles/backs-atlas.png")
const HAND_FACES := preload("res://res/tiles/materials3d/hand-faces.png")
const FLAT_FACES := preload("res://res/tiles/materials3d/flat-faces.png")
const STANDING_BACKS := [null,
	preload("res://res/tiles/materials3d/standing-right.png"),
	preload("res://res/tiles/materials3d/standing-north.png"),
	preload("res://res/tiles/materials3d/standing-left.png")]
const BACK_TOP := preload("res://res/tiles/materials3d/back-top.png")
const BACK_BOTTOM := preload("res://res/tiles/materials3d/back-bottom.png")
const SOFT_SHADOW := preload("res://res/tiles/tile-shadow.svg")

static var _style_cache := {}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
	if selected == on: return
	selected = on
	queue_redraw()

func set_interactive(on: bool) -> void:
	interactive = on
	mouse_filter = Control.MOUSE_FILTER_STOP if on and not presentation_3d else Control.MOUSE_FILTER_IGNORE
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

func set_card(t: String, up: bool) -> void:
	if tile == t and face_up == up: return
	tile = t
	face_up = up
	queue_redraw()

func set_highlight(on: bool) -> void:
	if highlight == on: return
	highlight = on
	queue_redraw()

func set_latest_highlight(on: bool) -> void:
	if latest_highlight == on: return
	latest_highlight = on
	queue_redraw()

func set_ai_teach_highlight(on: bool) -> void:
	if ai_teach_highlight == on: return
	ai_teach_highlight = on
	queue_redraw()

func set_score_highlight(on: bool) -> void:
	if score_highlight == on: return
	score_highlight = on
	queue_redraw()

func set_unit(k: float) -> void:
	unit = k
	_apply_size()
	queue_redraw()

func _apply_size() -> void:
	custom_minimum_size = Vector2(BASE_W, BASE_H) * unit
	size = custom_minimum_size

## Source drawing for tools/render/bake_tile_backs.gd. The atlas preserves
## both depth directions and the shadow-free river variant at 4x resolution.
func _draw_procedural_back(river: bool) -> void:
	var w := BASE_W * unit
	var h := BASE_H * unit
	if not river:
		draw_texture_rect(SOFT_SHADOW, Rect2(2 * unit, 4 * unit, w, h), false)
	draw_texture_rect(BACK_TOP if back_depth_top else BACK_BOTTOM, Rect2(0, 0, w, h), false)

func artwork_rect(reserve_standing: bool = false) -> Rect2:
	if (reserve_standing or not face_up) and standing_back_view in [1, 3]:
		# The 1:2 side render extends past its slot so nearer tiles cover the ends.
		return Rect2((size.x - 2.0 * size.y) / 2.0, 0, 2.0 * size.y, size.y)
	return Rect2(Vector2.ZERO, size)

func _draw() -> void:
	if presentation_3d: return
	var w := BASE_W * unit
	var h := BASE_H * unit
	var depth := 5.0 * unit
	var river := has_meta("discard_id") and int(get_meta("meld_index", -1)) < 0 \
		and str(get_meta("new_kind", "")) in ["ordinary", "red"]
	if face_up and tile != "":
		if not river:
			draw_texture_rect(SOFT_SHADOW, Rect2(2 * unit, 4 * unit, w, h), false)
		# The recessed print and body share one offline-rendered atlas quad.
		var face_y := depth if face_depth_top else 0.0
		var row: int = FACE_ROWS.get(Tiles.suit(tile), 0)
		var region := Rect2((Tiles.rank(tile) - 1) * 256, row * 344, 256, 344)
		draw_texture_rect_region(HAND_FACES if face_depth_top else FLAT_FACES, Rect2(0, 0, w, h), region)
		if score_highlight:
			draw_rect(Rect2(0, face_y, w, h - depth), Color(0.95, 0.78, 0.22, 0.30))
		if Tiles.is_chicken(tile):
			draw_circle(Vector2(w - 4 * unit, 4 * unit), 2 * unit, Color("#c5993e"))
	else:
		var back_y := depth if back_depth_top else 0.0
		if standing_back_view >= 1 and standing_back_view <= 3:
			draw_texture_rect(STANDING_BACKS[standing_back_view], artwork_rect(), false)
		elif is_equal_approx(unit, 1.0) or is_equal_approx(unit, 1.35):
			# Bake each used unit separately: StyleBox borders stay one pixel wide
			# rather than scaling with tile size. Other sizes retain vector drawing.
			var variant := int(back_depth_top) + 2 * int(river)
			var region := Rect2(variant * (292 if unit > 1 else 216),
				288 if unit > 1 else 0, 216 * unit, 288 * unit)
			draw_texture_rect_region(BACK_ATLAS, Rect2(-2 * unit, -2 * unit, 54 * unit, 72 * unit), region)
		else:
			_draw_procedural_back(river)
		if score_highlight:
			draw_rect(Rect2(0, back_y, w, h - depth), Color(0.95, 0.78, 0.22, 0.40))
	if highlight or ai_teach_highlight or latest_highlight or selected or _win_glow > 0:
		var glow := _tile_style(Color.TRANSPARENT, Color(0.95, 0.80, 0.39, maxf(0.24, _win_glow)))
		glow.set_border_width_all(4)
		draw_style_box(glow, Rect2(0, 0, w, h) if river else Rect2(-4, -4, w + 8, h + 8))
		var outline := _tile_style(Color.TRANSPARENT, Color("#f1d47f"))
		outline.set_border_width_all(2)
		draw_style_box(outline, Rect2(0, 0, w, h) if river else Rect2(-1, -1, w + 2, h + 2))
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
			draw_style_box(latest_glow, Rect2(0, 0, w, h) if river else Rect2(-7, -7, w + 14, h + 14))
			var latest_outline := _tile_style(Color.TRANSPARENT, Color("#ff7a2f"))
			latest_outline.set_border_width_all(5)
			draw_style_box(latest_outline, Rect2(0, 0, w, h) if river else Rect2(-3, -3, w + 6, h + 6))
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
	presentation_3d = false
	flight_pitch = -1.0
	flight_progress = -1.0
	set_selected(false)
	set_interactive(false)
	set_winning(false)
	set_highlight(false)
	set_latest_highlight(false)
	set_ai_teach_highlight(false)
	set_score_highlight(false)
	tile = ""
	face_up = false
	face_depth_top = true
	standing_back_view = -1
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
