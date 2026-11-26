extends RefCounted
## All provisional dimensions are in tile widths. These are runtime defaults, not an approved phone layout.

const Wall = preload("res://src/domain/Wall.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Seats = preload("res://src/domain/Seats.gd")
const Geometry = preload("res://src/presentation/TileGeometry.gd")
const WIDTH := Geometry.WIDTH
const THICK := Geometry.THICKNESS
const LONG := Geometry.LENGTH
const EDGE := 12.25
const WALL_RADIUS := 7.55
const PUBLIC_RADIUS := 10.12
const RIVER_COLUMNS := 7 # Q10 is deferred. Use one provisional packing for all four world seats.
const GAP := 0.25
var slots = Wall.new(Catalog.ordered_values()) # Only slot_info is used; carries no shuffled/private faces.
var anchors: Array = [{}, {}, {}, {}]

static func facing(seat: int) -> Basis:
	return Basis(Vector3.UP, (1 - seat) * PI / 2.0)

static func pose(seat: int, point: Vector3, tilt: float = 0.0, yaw: float = 0.0) -> Transform3D:
	var seat_basis := facing(seat)
	return Transform3D(seat_basis * Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt), seat_basis * point)

func wall_pose(id: int, offsets: Array, stack_height: int = -1) -> Transform3D:
	var slot: Dictionary = slots.slot_info(id)
	var columns := 14 if int(slot.seat) % 2 else 13
	var shift := float(offsets[slot.seat]) if offsets.size() == 4 else 0.0
	var x := (columns - 1) * 0.5 - float(slot.column) - shift
	var layer := 1 - int(slot.layer) if stack_height < 0 else stack_height
	return pose(slot.seat, Vector3(x, (layer + 0.5) * THICK, WALL_RADIUS), PI if stack_height < 0 else 0.0)

static func hand_pose(seat: int, index: int, count: int, has_draw: bool, flat: bool, lifted: bool) -> Transform3D:
	var gap := GAP if has_draw else 0.0
	var x := index - (count - 1 + gap) * 0.5 + (gap if index == count - 1 else 0.0)
	var y := (THICK if flat else LONG) * 0.5 + (0.42 if lifted else 0.0)
	var z := EDGE - (LONG if flat else THICK) * 0.5
	return pose(seat, Vector3(x, y, z), 0.0 if flat else PI / 2)

static func discard_pose(seat: int, index: int) -> Transform3D:
	var row := floori(float(index) / RIVER_COLUMNS)
	# Adjacent seats occupy four interlocking rectangles clear of the central dice.
	return pose(seat, Vector3(-1.05 + (index % RIVER_COLUMNS), THICK * 0.5, 6.22 - row * LONG))

# Stay inside this owner's wedge even when the neighboring player has a deep opposite-source kong.
const PUBLIC_LIMIT := PUBLIC_RADIUS - LONG * 0.5 - 1.0 - 0.05
const PUBLIC_GAP := 0.10

static func chicken_footprint(cross: bool) -> Dictionary:
	return {"width": LONG if cross else WIDTH, "reserve_near": -LONG * 0.5}

static func meld_footprint(seat: int, meld: Dictionary) -> Dictionary:
	var near := -LONG * 0.5
	var width := 4.0
	if not meld.get("concealed", false) and int(meld.get("from_seat", -1)) >= 0:
		var opposite := Seats.relative(seat, int(meld.from_seat)) == 2
		width = 3.0 if opposite else 3.0 + LONG
		if opposite:
			near -= WIDTH
		# The current four-straight added kong and the provider-facing kong both fit the original pung reservation.
		if meld.kind in ["pung", "add_kong"]:
			width = maxf(4.0, width)
	return {"width": width, "reserve_near": near}

func reserve(seat: int, key: String, group: Dictionary, hand_count: int, active: Dictionary) -> bool:
	var saved: Dictionary = anchors[seat]
	if saved.has(key):
		return true
	var width := float(group.width)
	var half := width * 0.5
	var occupied := []
	var front := []
	for existing in saved:
		if not active.has(existing):
			continue
		var item: Dictionary = saved[existing]
		occupied.append(item)
		if is_equal_approx(item.center.y, PUBLIC_RADIUS):
			front.append(item)
	var center_x := 0.0
	if not front.is_empty():
		var last: Dictionary = front.back()
		center_x = last.center.x + last.width * 0.5 + PUBLIC_GAP + half
	var candidate := _footprint(center_x, PUBLIC_RADIUS, group)
	if _fits(candidate, occupied):
		saved[key] = candidate
		return true
	var hand_edge := (hand_count + GAP) * 0.5 + GAP
	var side_depth := EDGE - LONG * 0.5
	for side: float in [-1.0, 1.0]:
		var x := side * (hand_edge + half)
		while absf(x) + half <= PUBLIC_LIMIT:
			candidate = _footprint(x, side_depth, group)
			if _fits(candidate, occupied):
				saved[key] = candidate
				return true
			x += side * 0.125
	# Try the smallest shared leftward motion that frees the required front-end space.
	var shift := maxf(0.0, center_x + half - PUBLIC_LIMIT)
	if shift > 0.0 and not front.is_empty():
		var fixed := occupied.filter(func(item): return not is_equal_approx(item.center.y, PUBLIC_RADIUS))
		var safe := true
		for item in front:
			var swept: Dictionary = item.duplicate()
			swept.rect = Rect2(item.rect.position - Vector2(shift, 0), item.rect.size + Vector2(shift, 0))
			if not _fits(swept, fixed):
				safe = false
				break
		candidate = _footprint(center_x - shift, PUBLIC_RADIUS, group)
		if safe and _fits(candidate, fixed):
			for item in front:
				item.center.x -= shift
				item.rect.position.x -= shift
			saved[key] = candidate
			return true
	return false

static func _footprint(x: float, z: float, group: Dictionary) -> Dictionary:
	var half := float(group.width) * 0.5
	var near := minf(-LONG * 0.5, float(group.get("reserve_near", -LONG * 0.5)))
	for piece in group.get("pieces", []):
		near = minf(near, float(piece[3]) - (0.5 if piece[4] else LONG * 0.5))
	var rect := Rect2(Vector2(x - half, z + near), Vector2(half * 2, LONG * 0.5 - near))
	return {"center": Vector2(x, z), "width": half * 2, "rect": rect}

static func _fits(candidate: Dictionary, occupied: Array) -> bool:
	var rect: Rect2 = candidate.rect
	if rect.position.x < -PUBLIC_LIMIT - 0.0001 or rect.end.x > PUBLIC_LIMIT + 0.0001:
		return false
	for other in occupied:
		if rect.grow(PUBLIC_GAP * 0.5).intersects(other.rect):
			return false
	return true
