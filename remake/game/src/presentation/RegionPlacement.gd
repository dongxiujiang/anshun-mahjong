extends RefCounted
## Ordered display slots only. Physical tile identities and the wall's head/tail stay in the round.
const Layout = preload("res://src/presentation/TableLayout.gd")
var profile
var _public := [{}, {}, {}, {}]

func _init(layout_profile) -> void:
	profile = layout_profile

func indexed(seat: int, kind: String, index: int, width: float, depth: float, height: float, tilt: float, count: int = -1, reverse: bool = false) -> Dictionary:
	var remaining := index
	for name in profile.region_keys(seat, kind):
		var region: Dictionary = profile.data.regions[name]
		if not region.visible: continue
		var scale: float = region.scale
		var columns := floori((float(region.width) + 0.00001) / (width * scale))
		var rows := floori((float(region.depth) + 0.00001) / (depth * scale))
		var capacity := columns * rows
		if remaining >= capacity:
			remaining -= capacity
			continue
		var row := remaining / columns
		var column := remaining % columns
		var used := columns
		if count >= 0: used = mini(columns, count - (index - remaining) - row * columns)
		var x := (column - (used - 1) * 0.5) * width * scale
		if reverse: x = -x
		var local := Transform3D(Basis(Vector3.RIGHT, tilt).scaled(Vector3.ONE * scale), Vector3(x, height * scale, -(row + 0.5) * depth * scale))
		return {"pose": profile.region_pose(seat, kind, name) * local, "region": name}
	return {}

const GAP := Layout.WIDTH * 0.1
const BADGE_SIDE := Layout.WIDTH

static func badge(kind: String) -> Dictionary:
	return {"width": BADGE_SIDE, "depth": BADGE_SIDE, "far": BADGE_SIDE * 0.5, "marker": kind}

static func footprint(seat: int, meld: Dictionary) -> Dictionary:
	if meld.kind == "pung": return {"width": 3.0, "depth": Layout.LONG, "far": Layout.LONG * 0.5}
	if meld.kind == "add_kong": return {"width": 4.0, "depth": Layout.LONG, "far": Layout.LONG * 0.5}
	return Layout.meld_footprint(seat, meld)

static func chicken(cross: bool) -> Dictionary:
	return {"width": Layout.LONG if cross else Layout.WIDTH, "depth": Layout.WIDTH if cross else Layout.LONG, "far": (Layout.WIDTH if cross else Layout.LONG) * 0.5}

func _right(name: String) -> bool:
	return profile.data.regions[name].get("start_corner", "bottom_left") == "bottom_right"

func _offset(name: String, rect: Rect2) -> float:
	var half: float = profile.data.regions[name].width * 0.5
	return half - rect.end.x if _right(name) else rect.position.x + half

func _item(seat: int, name: String, offset: float, width: float, depth: float, group: Dictionary, rise: float = 0.0) -> Dictionary:
	var region: Dictionary = profile.data.regions[name]
	var x: float = region.width * 0.5 - offset - width if _right(name) else -region.width * 0.5 + offset
	var rect := Rect2(x, rise, width, depth)
	var far: float = group.get("far", Layout.LONG * 0.5)
	var origin := Vector3(rect.get_center().x, 0, -rise - far * region.scale)
	var pose: Transform3D = profile.region_pose(seat, name.split("/")[1], name) * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * region.scale), origin)
	return {"region": name, "rect": rect, "pose": pose, "far": far, "marker": group.get("marker", "")}

func _depth(group: Dictionary) -> float:
	return group.get("depth", Layout.LONG * 0.5 - group.get("reserve_near", -Layout.LONG * 0.5))

func _append(seat: int, name: String, group: Dictionary, saved: Dictionary) -> Dictionary:
	var row: Dictionary = profile.data.regions[name]
	if not row.visible: return {}
	var width: float = group.width * row.scale
	var depth := _depth(group) * float(row.scale)
	if depth > float(row.depth) + 0.00001: return {}
	var end := 0.0; var occupied := false
	for previous in saved.values():
		if previous.region != name: continue
		end = maxf(end, _offset(name, previous.rect) + previous.rect.size.x); occupied = true
	var offset: float = end + GAP * row.scale if occupied else 0.0
	if offset + width > float(row.width) + 0.00001: return {}
	return _item(seat, name, offset, width, depth, group)

func _marker(seat: int, key: String, group: Dictionary, saved: Dictionary) -> Dictionary:
	var names: Array = profile.region_keys(seat, "public_front").filter(func(name): return profile.data.regions[name].visible)
	if names.is_empty(): return {}
	var name: String = names[0]
	var row: Dictionary = profile.data.regions[name]
	var width: float = group.width * row.scale
	var depth := _depth(group) * float(row.scale)
	var rise := 0.0; var column := 0.0
	for item in saved.values():
		if item.region != name or item.get("marker", "").is_empty(): continue
		column = maxf(column, item.rect.size.x)
		if group.marker == "ready": rise = maxf(rise, item.rect.end.y + GAP * row.scale)
	if rise + depth > float(row.depth) + 0.00001 or width > float(row.width) + 0.00001: return {}
	var shift: float = maxf(0, width - column) if column > 0 else width + GAP * row.scale
	for item in saved.values():
		if item.region == name and item.get("marker", "").is_empty() and _offset(name, item.rect) + item.rect.size.x + shift > float(row.width) + 0.00001: return {}
	for id in saved.keys():
		var item: Dictionary = saved[id]
		if item.region == name and item.get("marker", "").is_empty():
			saved[id] = _item(seat, name, _offset(name, item.rect) + shift, item.rect.size.x, item.rect.size.y, {"far": item.get("far", Layout.LONG * 0.5)})
	return _item(seat, name, 0, width, depth, group, rise)

func public_group(seat: int, key: String, group: Dictionary, _order: Array, groups: Dictionary) -> Dictionary:
	var saved: Dictionary = _public[seat]
	for old in saved.keys():
		if not groups.has(old): saved.erase(old)
	if saved.has(key):
		var previous: Dictionary = saved[key]
		var scale: float = profile.data.regions[previous.region].scale
		if is_equal_approx(previous.rect.size.x, group.width * scale) and is_equal_approx(previous.rect.size.y, _depth(group) * scale): return previous
		return _resize(seat, key, group)
	var result := {}
	if not str(group.get("marker", "")).is_empty(): result = _marker(seat, key, group, saved)
	else:
		var names: Array = profile.public_region_keys(seat)
		var first := 0
		for item in saved.values():
			if item.get("marker", "").is_empty(): first = maxi(first, names.find(item.region))
		for name in names.slice(first):
			result = _append(seat, name, group, saved)
			if not result.is_empty(): break
	if not result.is_empty(): saved[key] = result
	return result

func _resize(seat: int, key: String, group: Dictionary) -> Dictionary:
	var saved: Dictionary = _public[seat]
	var previous: Dictionary = saved[key]
	var name: String = previous.region
	var row: Dictionary = profile.data.regions[name]
	var width: float = group.width * row.scale
	var depth := _depth(group) * float(row.scale)
	var start := _offset(name, previous.rect)
	var increase := width - float(previous.rect.size.x)
	var suffix := saved.keys().filter(func(id): return id != key and saved[id].region == name and saved[id].get("marker", "").is_empty() and _offset(name, saved[id].rect) > start + 0.00001)
	var fits: bool = row.visible and depth <= float(row.depth) + 0.00001 and start + width <= float(row.width) + 0.00001
	for id in suffix:
		var item: Dictionary = saved[id]
		if _offset(name, item.rect) + item.rect.size.x + maxf(increase, 0) > float(row.width) + 0.00001: fits = false
	if fits:
		for id in suffix:
			var item: Dictionary = saved[id]
			saved[id] = _item(seat, name, _offset(name, item.rect) + maxf(increase, 0), item.rect.size.x, item.rect.size.y, {"far": item.get("far", Layout.LONG * 0.5)})
		saved[key] = _item(seat, name, start, width, depth, group)
		return saved[key]
	var names: Array = profile.public_region_keys(seat)
	for next in names.slice(names.find(name) + 1):
		var result := _append(seat, next, group, saved)
		if result.is_empty(): continue
		saved[key] = result
		suffix.sort_custom(func(a,b): return _offset(name,saved[a].rect) < _offset(name,saved[b].rect))
		var cursor := 0.0; var prefix := false
		for id in saved:
			var item: Dictionary = saved[id]
			if item.region == name and not suffix.has(id):
				cursor = maxf(cursor, _offset(name, item.rect) + item.rect.size.x); prefix = true
		if prefix: cursor += GAP * row.scale
		for id in suffix:
			var item: Dictionary = saved[id]
			saved[id] = _item(seat, name, cursor, item.rect.size.x, item.rect.size.y, {"far": item.get("far", Layout.LONG * 0.5)})
			cursor += item.rect.size.x + GAP * row.scale
		return result
	return {}

func public_state(seat: int) -> Dictionary:
	var result := {}
	for key in _public[seat]:
		var item: Dictionary = _public[seat][key]
		var rect: Rect2 = item.rect
		result[key] = {"region": item.region, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "far": item.get("far", Layout.LONG * 0.5), "marker": item.get("marker", "")}
	return result

func restore_public(seat: int, state: Dictionary) -> bool:
	var restored := {}
	for key in state:
		var item = state[key]
		if not item is Dictionary or not profile.data.regions.has(item.get("region", "")): return false
		if not str(item.region).begins_with(str(seat) + "/public_"): return false
		var values = item.get("rect")
		if not values is Array or values.size() != 4: return false
		for v in values:
			if not (v is int or v is float) or not is_finite(float(v)) or absf(v) > 100: return false
		var rect := Rect2(values[0], values[1], values[2], values[3])
		var far = item.get("far", Layout.LONG * 0.5)
		if not (far is int or far is float) or not is_finite(float(far)) or absf(far) > 100: return false
		if item.get("marker", "") not in ["", "dealer", "ready"]: return false
		if rect.size.x <= 0 or rect.size.y <= 0: return false
		var result := _item(seat, item.region, _offset(item.region, rect), rect.size.x, rect.size.y, {"far": far, "marker": item.get("marker", "")}, rect.position.y)
		restored[key] = result
	_public[seat] = restored
	return true
