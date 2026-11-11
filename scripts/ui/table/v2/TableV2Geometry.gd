class_name TableV2Geometry
extends RefCounted
## 新牌桌唯一布局标准：只做数学，不创建节点、不读实时手牌宽度。
## 所有坐标都是 2280×1280 设计画布坐标。

const DESIGN_SIZE := Vector2(2280, 1280)
const TABLE_BOUNDS := Rect2(24, 80, 2232, 1120)
const CENTER := Vector2(1140, 640)

const TILE_BASE := Vector2(48, 64)
const TILE_GAP := 4.0
const OWN_UNIT := 2.4          # 115.2 × 153.6
const OPPONENT_UNIT := 1.35    # 64.8 × 86.4
const WALL_UNIT := OPPONENT_UNIT
const WALL_LAYER_SHIFT := 8.0
const MELD_SIZE := TILE_BASE * OPPONENT_UNIT
const MELD_SPAN := MELD_SIZE.x * 3.0 + MELD_SIZE.y + TILE_GAP * 3.0
const STACK_SPAN := MELD_SIZE.x * 3.0 + TILE_GAP * 2.0
const ACTION_TOP := 816.8
const SETTLEMENT_AREA := Rect2(690, 389, 900, 420)
const WALL_BOUNDS := [
	Rect2(2047.2, 106.8, 94.4, 915.2), Rect2(682.4, 830, 915.2, 94.4),
	Rect2(350, 106.8, 94.4, 915.2), Rect2(682.4, 284.8, 915.2, 94.4),
]
const MELD_BADGES := [Vector2(1080, 954), Vector2(1628.4, 580), Vector2(1080, 210), Vector2(627.2, 580)]

const HAND_TOP := 100.0
const HAND_BOTTOM := 1180.0
const HAND_LEFT := 44.0
const HAND_RIGHT := 2236.0
const DRAW_GAP_TILES := 0.5

const ORDINARY_UNIT := 1.1     # 52.8 × 70.4
const RED_WIDTH := 44.0       # 单张出牌鸡；为横放的冲锋鸡预留56×56。
const RED_HEIGHT := 56.0

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

static func wall_angle(seat: int) -> float:
	if seat == 0: return PI / 2.0
	if seat == 2: return -PI / 2.0
	return 0.0

## 保留逻辑墙的蹲数与固定槽位。两层偏移后的包围盒也不占用手牌或牌河。
static func wall_block_center(seat: int, slot: int, row: int, columns: int = 0) -> Vector2:
	if columns == 0: columns = 14 if seat in [1, 3] else 13
	var bounds: Rect2 = WALL_BOUNDS[seat]
	var offset := wall_upper_offset(seat)
	var side := seat in [0, 2]
	var axis := Vector2.DOWN if side else Vector2.RIGHT
	var depth := Vector2.RIGHT if side else Vector2.DOWN
	var center := bounds.get_center() + axis * ((slot + 0.5 - columns * 0.5) * MELD_SIZE.x)
	center -= axis * offset.dot(axis) / 2.0 + depth * offset.dot(depth) / 2.0
	return center + (offset if row == 0 else Vector2.ZERO)

static func river_capacity(relative: int) -> int:
	return 21 if relative in [1, 3] else 20

static func meld_badge_rect(relative: int) -> Rect2:
	return Rect2(MELD_BADGES[relative], Vector2(56, 120) if relative in [1, 3] else Vector2(120, 56))

## 普通弃牌独立使用牌河，出牌鸡留在各自碰杠区。
static func ordinary_slot_center(seat: int, index: int, human_seat: int) -> Vector2:
	var rel := relative_seat(human_seat, seat)
	if rel in [1, 3]:
		var column := index / 7
		var row := index % 7
		if rel == 1: return Vector2(1448.0 + column * 72.0, 782.2 - row * 61.5)
		return Vector2(864.0 - column * 72.0, 413.2 + row * 61.5)
	if index >= 16:
		var extra := index - 16
		return Vector2(1187.8 + extra * 64.0 if rel == 0 else 1123.8 - extra * 64.0, 603.0)
	var y := 687.0 + (index / 8) * 84.0 if rel == 0 else 507.2 - (index / 8) * 84.0
	var x := 931.8 + (index % 8) * 64.0 if rel == 0 else 1379.8 - (index % 8) * 64.0
	return Vector2(x, y)

static func chicken_slot_centers(seat: int, human_seat: int, meld_tiles: Array) -> Array[Vector2]:
	var rel := relative_seat(human_seat, seat)
	var bands: Array[Rect2] = []
	if rel in [0, 2]:
		bands.append(Rect2(138.4, 952.4 if rel == 0 else 202.4, 1904.8, 64))
		bands.append(Rect2(228.8, 816.8, 117.2, 64) if rel == 0 else Rect2(448.4, 284.8, 178, 64))
	elif rel == 3:
		bands.assign([Rect2(138.4, 354, 207.6, 458), Rect2(448.4, 354, 178, 458)])
	else:
		bands.append(Rect2(1684, 354, 359.2, 458))
	var obstacles: Array[Rect2] = []
	for wall: Rect2 in WALL_BOUNDS: obstacles.append(wall.grow(4))
	for spec in meld_tiles:
		var extent := MELD_SIZE
		if bool(spec.sideways) != (rel in [1, 3]): extent = Vector2(extent.y, extent.x)
		obstacles.append(Rect2(Vector2(spec.center) - extent / 2, extent).grow(1))
	for relative in 4: obstacles.append(meld_badge_rect(relative).grow(1))
	var out: Array[Vector2] = []
	for slot in 8:
		var found := false
		for band in bands:
			var xs: Array[float] = [band.position.x]
			var ys: Array[float] = [band.position.y]
			for obstacle in obstacles:
				if obstacle.end.x >= band.position.x and obstacle.end.x + 56 <= band.end.x: xs.append(obstacle.end.x)
				if obstacle.end.y >= band.position.y and obstacle.end.y + 56 <= band.end.y: ys.append(obstacle.end.y)
			xs.sort()
			ys.sort()
			for y in ys:
				for x in xs:
					var rect := Rect2(x, y, 56, 56)
					if not band.encloses(rect) or obstacles.any(func(other): return rect.intersects(other)): continue
					out.append(rect.get_center())
					obstacles.append(rect.grow(4))
					found = true
					break
				if found: break
			if found: break
		if not found: break
	return out

## 槽位原点沿玩家视角从左到右，纵深朝桌内。
static func meld_origins(relative: int, inline_count: int, stack_count: int) -> Array[Vector2]:
	var inline_origins: Array[Vector2] = []
	var stack_origins: Array[Vector2] = []
	if relative in [0, 2]:
		var y := 1018.4 if relative == 0 else 194.4
		var direction := 1.0 if relative == 0 else -1.0
		var left_count := ceili(inline_count / 2.0)
		for i in inline_count:
			# Keep a 128px opening on the hand centerline for the dealer/ready badges.
			var x := -64.0 - (left_count - i) * (MELD_SPAN + TILE_GAP) if i < left_count \
				else 64.0 + (i - left_count) * (MELD_SPAN + TILE_GAP)
			inline_origins.append(Vector2(CENTER.x + direction * x, y))
		for i in stack_count:
			var x: float = [138.4, 448.4, 1605.6, 1839.0][i]
			stack_origins.append(Vector2(x + (STACK_SPAN if relative == 2 else 0.0), y))
	else:
		# 成组贴边排列。混合列最靠下的一组是平放组，给本家的按钮让位。
		var templates: Array = [
			[[false, false], [false, false]], [[true, false], [false, false]],
			[[true, true], [false, false]], [[true, false], [true, true]], [[true, true], [true, true]],
		][stack_count]
		var edges := Vector2(2043.2, 1862.4) if relative == 1 else Vector2(138.4, 448.4)
		for column in 2:
			var depth := edges[column]
			var y := 354.0
			var serial: bool = templates[column].has(true)
			for stacked in templates[column]:
				if stacked and stack_origins.size() == stack_count: continue
				if not stacked and inline_origins.size() == inline_count: continue
				var span := STACK_SPAN if stacked else MELD_SPAN
				var origin := Vector2(depth, y + (span if relative == 1 else 0.0))
				if stacked: stack_origins.append(origin)
				else: inline_origins.append(origin)
				if serial: y += span + TILE_GAP
				else: depth += (MELD_SIZE.y + TILE_GAP) * (-1.0 if relative == 1 else 1.0)
	return inline_origins + stack_origins
