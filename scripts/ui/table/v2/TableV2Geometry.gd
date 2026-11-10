class_name TableV2Geometry
extends RefCounted
## 新牌桌唯一布局标准：只做数学，不创建节点、不读实时手牌宽度。
## 所有坐标都是 2280×1280 设计画布坐标。

const DESIGN_SIZE := Vector2(2280, 1280)
const TABLE_BOUNDS := Rect2(24, 80, 2232, 1120)
const CENTER := Vector2(1140, 640)
const CENTRAL_SIZE := Vector2(1320, 520)

const TILE_BASE := Vector2(48, 64)
const TILE_GAP := 4.0
const OWN_UNIT := 2.4          # 115.2 × 153.6
const OPPONENT_UNIT := 1.35    # 64.8 × 86.4
const WALL_UNIT := 1.0         # 48 × 64
const WALL_EDGE_GAP := 8.0
const WALL_LAYER_SHIFT := 8.0
const WALL_BLOCK_GAP := 0.0

const HAND_TOP := 100.0
const HAND_BOTTOM := 1180.0
const HAND_LEFT := 44.0
const HAND_RIGHT := 2236.0
const DRAW_GAP_TILES := 0.5

const ORDINARY_UNIT := 1.25    # 60 × 80
const ORDINARY_STEP_X := 64.0
const ORDINARY_STEP_Y := 84.0
const ORDINARY_ROW_WIDTH := 768.0
## 东/西弃牌旋转后视觉尺寸 80×60，槽位必须按旋转后的步进。
const ORDINARY_SIDE_STEP_X := 84.0
const ORDINARY_SIDE_STEP_Y := 64.0

const RED_WIDTH := 44.0
const RED_HEIGHT := 56.0
const RED_LINE_GAP := 4.0
const RED_HAND_GAP := 8.0
const RED_GROUP_GAP := 8.0
const RED_CATEGORY_GAP := 12.0
const SIDE_RED_GAP := 8.0
## 东/西两行红牌最宽占位：56 + 4 + 56。
const SIDE_RED_RESERVE := 116.0
## 东/西牌墙中心对齐牌墙内框中心 y=606.4。
const SIDE_WALL_Y_SHIFT := -33.6
## A 方案：北/南牌墙为“墙—红8、红—手8”整体移动。
const NORTH_WALL_SHIFT := -49.6
const SOUTH_WALL_SHIFT := -17.6

static func relative_seat(human_seat: int, seat: int) -> int:
	return posmod(human_seat - seat, 4)

## Slots follow the meld owner's left-to-right order in every seat rotation.
static func exposed_kong_source_slot(seat: int, source: int) -> int:
	if source not in range(4) or source == seat:
		return -1
	return 0 if posmod(source - seat, 4) == 1 else 3

## Corner areas outside the full hand and draw envelopes. The bottom center
## is reserved for post-settlement controls.
static func seat_hud_rect(relative: int) -> Rect2:
	var position: Vector2 = [
		Vector2(150, 1062), Vector2(2068, 1108),
		Vector2(1768, 100), Vector2(150, 100),
	][relative]
	return Rect2(position, Vector2(184, 120))

static func hand_unit(seat: int, human_seat: int) -> float:
	return OWN_UNIT if seat == human_seat else OPPONENT_UNIT

static func hand_tile_size(seat: int, human_seat: int) -> Vector2:
	return TILE_BASE * hand_unit(seat, human_seat)

static func hand_span(count: int, unit: float) -> float:
	return maxf(0.0, count * (TILE_BASE.x * unit + TILE_GAP) - TILE_GAP)

## 13张手牌的固定屏幕 AABB。红色区、名字、分数、庄家标记共用。
static func hand13_rect(seat: int, human_seat: int) -> Rect2:
	var rel := relative_seat(human_seat, seat)
	var unit := hand_unit(seat, human_seat)
	var size := hand_tile_size(seat, human_seat)
	var span := hand_span(13, unit)
	var left := CENTER.x - span / 2.0
	var top := CENTER.y - span / 2.0
	if rel == 0:
		return Rect2(left, HAND_BOTTOM - size.y, span, size.y)
	if rel == 2:
		return Rect2(left, HAND_TOP, span, size.y)
	if rel == 1:
		return Rect2(HAND_RIGHT - size.y, top, size.y, span)
	return Rect2(HAND_LEFT, top, size.y, span)

## 当前手牌槽中心。count 由调用方决定：开局固定用 13，普通手牌用实际张数。
## 手牌+摸牌整体中心固定在牌桌中心线。
static func hand_slot_center(seat: int, slot: int, human_seat: int, count: int = 13,
		_reserve_draw: bool = false) -> Vector2:
	var rel := relative_seat(human_seat, seat)
	var unit := hand_unit(seat, human_seat)
	var size := TILE_BASE * unit
	var step := size.x + TILE_GAP
	var hs := hand_span(count, unit)
	var left := CENTER.x - hs / 2.0
	var top := CENTER.y - hs / 2.0
	if rel == 0:
		return Vector2(left + size.x / 2.0 + slot * step, HAND_BOTTOM - size.y / 2.0)
	if rel == 2:
		return Vector2(left + hs - size.x / 2.0 - slot * step, HAND_TOP + size.y / 2.0)
	if rel == 1:
		return Vector2(HAND_RIGHT - size.y / 2.0, top + hs - size.x / 2.0 - slot * step)
	# 西家：上方手牌 + 下端摸牌
	return Vector2(HAND_LEFT + size.y / 2.0, top + size.x / 2.0 + slot * step)

static func draw_slot_center(seat: int, human_seat: int, count: int = 13) -> Vector2:
	var rel := relative_seat(human_seat, seat)
	var unit := hand_unit(seat, human_seat)
	var size := TILE_BASE * unit
	var hs := hand_span(count, unit)
	const DRAW_GAP := 20.0
	if rel == 0:
		return Vector2(CENTER.x + hs / 2.0 + DRAW_GAP + size.x / 2.0,
			HAND_BOTTOM - size.y / 2.0)
	if rel == 2:
		return Vector2(CENTER.x - hs / 2.0 - DRAW_GAP - size.x / 2.0,
			HAND_TOP + size.y / 2.0)
	if rel == 1:
		# 东家：摸牌在手牌上端。
		return Vector2(HAND_RIGHT - size.y / 2.0,
			CENTER.y - hs / 2.0 - DRAW_GAP - size.x / 2.0)
	# 西家：摸牌在手牌下端。
	return Vector2(HAND_LEFT + size.y / 2.0,
		CENTER.y + hs / 2.0 + DRAW_GAP + size.x / 2.0)

static func wall_upper_offset(seat: int) -> Vector2:
	# 上层相对下层：玩家本地左12 + 朝手牌12。
	if seat == 3: return Vector2(WALL_LAYER_SHIFT, -WALL_LAYER_SHIFT)   # 北：左=+x，手=-y
	if seat == 1: return Vector2(-WALL_LAYER_SHIFT, WALL_LAYER_SHIFT)   # 南：左=-x，手=+y
	if seat == 0: return Vector2(WALL_LAYER_SHIFT, WALL_LAYER_SHIFT)    # 东：左=+y，手=+x
	return Vector2(-WALL_LAYER_SHIFT, -WALL_LAYER_SHIFT)                # 西：左=-y，手=-x

## 东/西牌墙外移量：让墙—红—手都留 8。
static func side_wall_shift() -> float:
	var hand_edge := HAND_RIGHT - TILE_BASE.y * OPPONENT_UNIT
	var wall_outer := CENTER.x + CENTRAL_SIZE.x / 2.0 + WALL_EDGE_GAP + TILE_BASE.y * WALL_UNIT
	return hand_edge - (SIDE_RED_RESERVE + SIDE_RED_GAP * 2.0) - wall_outer

## 东/西牌墙外沿 x 坐标。
static func wall_outer_x(seat: int) -> float:
	var half := CENTRAL_SIZE.x / 2.0
	var wall_w := TILE_BASE.y * WALL_UNIT
	var shift := side_wall_shift()
	if seat == 0:
		return CENTER.x + half + WALL_EDGE_GAP + wall_w + shift
	return CENTER.x - half - WALL_EDGE_GAP - wall_w - shift

static func wall_angle(seat: int) -> float:
	if seat == 3: return 0.0
	if seat == 1: return 0.0
	if seat == 0: return PI / 2.0
	return -PI / 2.0

## row=0 上层，row=1 下层。
static func wall_block_center(seat: int, slot: int, row: int, columns: int = 0) -> Vector2:
	var size := TILE_BASE * WALL_UNIT
	var half := CENTRAL_SIZE / 2.0
	var step := size.x + WALL_BLOCK_GAP
	if columns == 0: columns = 14 if seat in [1, 3] else 13
	var span := columns * step - WALL_BLOCK_GAP
	var center := Vector2.ZERO
	if seat == 3:
		center = Vector2(CENTER.x - span / 2.0 + size.x / 2.0 + slot * step,
			CENTER.y - half.y - WALL_EDGE_GAP - size.y / 2.0 + NORTH_WALL_SHIFT)
	elif seat == 1:
		center = Vector2(CENTER.x - span / 2.0 + size.x / 2.0 + slot * step,
			CENTER.y + half.y + WALL_EDGE_GAP + size.y / 2.0 + SOUTH_WALL_SHIFT)
	elif seat == 0:
		center = Vector2(CENTER.x + half.x + WALL_EDGE_GAP + size.y / 2.0 + side_wall_shift(),
			CENTER.y - span / 2.0 + size.x / 2.0 + slot * step + SIDE_WALL_Y_SHIFT)
	else:
		center = Vector2(CENTER.x - half.x - WALL_EDGE_GAP - size.y / 2.0 - side_wall_shift(),
			CENTER.y - span / 2.0 + size.x / 2.0 + slot * step + SIDE_WALL_Y_SHIFT)
	if row == 0:
		center += wall_upper_offset(seat)
	return center

## 普通弃牌先按中央四块互不重叠的槽位区分配：
## 北/南横条 768×164，东/西竖条 244×500，四区之间留 20 边距。
## 牌墙围出的内框。
static func wall_inner_rect() -> Rect2:
	var top: float = wall_block_center(3, 0, 1).y + TILE_BASE.y * WALL_UNIT / 2.0
	var bottom: float = wall_block_center(1, 0, 1).y - TILE_BASE.y * WALL_UNIT / 2.0
	var left: float = wall_block_center(2, 6, 1).x + TILE_BASE.y * WALL_UNIT / 2.0
	var right: float = wall_block_center(0, 6, 1).x - TILE_BASE.y * WALL_UNIT / 2.0
	return Rect2(left, top, right - left, bottom - top)

## 北/南：12张×3行=36；东/西：8张×5行=40。
## 四家最外一行到牌墙内框统一 8。
static func ordinary_slot_center(seat: int, index: int, human_seat: int) -> Vector2:
	var rel := relative_seat(human_seat, seat)
	var inner := wall_inner_rect()
	var half := TILE_BASE * ORDINARY_UNIT / 2.0
	var gap := 8.0
	if rel == 0:
		var left := CENTER.x - ORDINARY_ROW_WIDTH / 2.0
		var first_y: float = inner.end.y - gap - half.y - 2.0 * ORDINARY_STEP_Y
		return Vector2(left + 30.0 + (index % 12) * ORDINARY_STEP_X,
			first_y + (index / 12) * ORDINARY_STEP_Y)
	if rel == 2:
		# 北家与南家镜像：从右向左。
		var right := CENTER.x + ORDINARY_ROW_WIDTH / 2.0
		var first_y_n: float = inner.position.y + gap + half.y + 2.0 * ORDINARY_STEP_Y
		return Vector2(right - 30.0 - (index % 12) * ORDINARY_STEP_X,
			first_y_n - (index / 12) * ORDINARY_STEP_Y)
	var center_y := (inner.position.y + inner.end.y) / 2.0
	if rel == 1:
		# 东家本地视角：8张一行×5行；从下向上，和西家镜像。
		# 第一行在桌内，逐行向右侧牌墙外递进。
		var outer_x: float = inner.end.x - gap - half.y
		var first_x: float = outer_x - 4.0 * ORDINARY_SIDE_STEP_X
		return Vector2(first_x + (index / 8) * ORDINARY_SIDE_STEP_X,
			center_y + 254.0 - half.x - (index % 8) * ORDINARY_SIDE_STEP_Y)
	# 西家本地视角：8张一行×5行；从上向下，和东家镜像。
	var outer_x_w: float = inner.position.x + gap + half.y
	var first_x_w: float = outer_x_w + 4.0 * ORDINARY_SIDE_STEP_X
	return Vector2(first_x_w - (index / 8) * ORDINARY_SIDE_STEP_X,
		center_y - 254.0 + half.x + (index % 8) * ORDINARY_SIDE_STEP_Y)

static func red_anchor(seat: int, human_seat: int, line: int) -> Vector2:
	var rel := relative_seat(human_seat, seat)
	var ref := hand13_rect(seat, human_seat)
	var step := RED_HEIGHT + RED_LINE_GAP
	if rel == 0:
		return Vector2(ref.position.x, ref.position.y - RED_HAND_GAP - RED_HEIGHT - line * step)
	if rel == 2:
		return Vector2(ref.end.x, ref.end.y + RED_HAND_GAP + line * step)
	if rel == 1:
		return Vector2(ref.position.x - RED_HAND_GAP - RED_HEIGHT - line * step, ref.end.y)
	return Vector2(ref.end.x + RED_HAND_GAP + line * step, ref.position.y)

## 普通碰杠固定锚点。锚点只读 13 张手牌参考线，不随当前手牌长度漂移。
static func meld_anchor(seat: int, human_seat: int) -> Vector2:
	var rel := relative_seat(human_seat, seat)
	var ref := hand13_rect(seat, human_seat)
	match rel:
		0:
			return Vector2(CENTER.x, ref.position.y - RED_HAND_GAP - RED_HEIGHT * 0.5)
		2:
			return Vector2(CENTER.x, ref.end.y + RED_HAND_GAP + RED_HEIGHT * 0.5)
		1:
			return Vector2(ref.position.x - RED_HAND_GAP - RED_HEIGHT * 0.5, CENTER.y)
		_:
			return Vector2(ref.end.x + RED_HAND_GAP + RED_HEIGHT * 0.5, CENTER.y)
