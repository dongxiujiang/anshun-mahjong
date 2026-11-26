extends RefCounted
## Display-only coordinates. The round, wall inventory and scoring never read this file.
const Layout = preload("res://src/presentation/TableLayout.gd")
const Geometry = preload("res://src/presentation/TileGeometry.gd")
const Hud = preload("res://src/presentation/HudLayout.gd")
const Pages = preload("res://src/presentation/PageLayout.gd")
const KINDS := ["hand", "draw", "public_front", "public_left", "discard", "wall"]
const LABELS := ["手牌", "独立摸牌", "碰杠前方（含鸡牌）", "碰杠左侧（含鸡牌）", "弃牌", "牌墙"]
const SEATS := ["东", "南", "西", "北"]
const DEFAULT_TABLE_SIDE := 36.0
const MAX_TABLE_SIDE := 80.0
var data: Dictionary
var error := ""

func _init() -> void:
	data = defaults()

static func key(seat: int, kind: String) -> String:
	return str(seat) + "/" + kind

static func anchor(kind: String) -> Vector2:
	match kind:
		"hand": return Vector2(0, Layout.EDGE)
		"draw": return Vector2(7.125, Layout.EDGE)
		"public_front": return Vector2(0, Layout.PUBLIC_RADIUS)
		"public_left": return Vector2(-8.2, Layout.EDGE - Layout.LONG * 0.5)
		"discard": return Vector2(1.95, 6.22)
		_: return Vector2(0, Layout.WALL_RADIUS)

static func defaults() -> Dictionary:
	var regions := {}
	for seat in 4:
		for kind in KINDS:
			var origin := anchor(kind)
			var width := 14.0
			var depth := default_depth(kind)
			if kind == "hand": width = 13.0
			if kind == "draw": width = 1.0
			if kind == "public_left": width = 6.0
			if kind == "public_front": width = 16.0
			if kind == "discard": width = 7.0
			regions[key(seat, kind)] = {"x": origin.x, "z": origin.y, "width": width, "depth": depth,
				"scale": 1.0, "spacing": 1.0, "rotation": 0.0, "locked": false, "visible": true, "priority": 1, "start_corner": "bottom_left"}
	return {"schema": 2, "product": "dongxiu-table-layout", "table_side": DEFAULT_TABLE_SIDE, "regions": regions, "hud": {}, "pages": {}, "hand_tolerance": 1.5,
		"presentation": {"hand_pitch": 90.0, "self_hand_pitch": 78.0, "self_hand_scale": 1.0, "camera_pitch": 34.92}}

static func default_depth(kind: String, hand_pitch: float = 90.0) -> float:
	return Geometry.prototype_bounds(kind, hand_pitch).size.z

func accept(candidate) -> bool:
	error = "布局文件格式或数值无效，当前方案未改变"
	if not candidate is Dictionary or (candidate.get("schema") != 1 and candidate.get("schema") != 2) or candidate.get("product") != "dongxiu-table-layout": return false
	if not candidate.get("regions") is Dictionary or candidate.regions.size() < 24 or candidate.regions.size() > 768: return false
	var limits := {"x": [-40.0, 40.0], "z": [-40.0, 40.0], "width": [0.25, 30.0], "depth": [0.25, 30.0],
		"scale": [0.4, 1.8], "spacing": [0.5, 2.0], "rotation": [-180.0, 180.0]}
	var normalized: Dictionary = candidate.duplicate(true)
	if not Hud.valid(candidate.get("hud", {})): return false
	normalized.hud = candidate.get("hud", {}).duplicate(true)
	if not Pages.valid(candidate.get("pages",{})):return false
	normalized.pages=candidate.get("pages",{}).duplicate(true)
	if normalized.pages.has("profile_setup"):
		if not normalized.pages.has("profile_edit"):normalized.pages.profile_edit=normalized.pages.profile_setup
		normalized.pages.erase("profile_setup")
	var tolerance: Variant = candidate.get("hand_tolerance", 1.5)
	if not _number(tolerance, 1.0, 2.5): return false
	normalized.hand_tolerance = float(tolerance)
	var side = normalized.get("table_side", Layout.EDGE * 2)
	if not _number(side, 12.0, MAX_TABLE_SIDE): return false
	normalized.table_side = float(side)
	var priorities := {}
	for region in normalized.regions:
		var parts: PackedStringArray = str(region).split("/")
		if parts.size() not in [2, 3] or parts[0] not in ["0", "1", "2", "3"] or parts[1] not in KINDS: return false
		if parts.size() == 3 and (not parts[2].is_valid_int() or int(parts[2]) < 2): return false
		var row = normalized.regions[region]
		if not row is Dictionary: return false
		for field in limits:
			if not _number(row.get(field), limits[field][0], limits[field][1]): return false
		if not row.get("locked") is bool or not row.get("visible") is bool: return false
		if row.get("start_corner", "bottom_left") not in ["bottom_left", "bottom_right"]: return false
		row.start_corner = row.get("start_corner", "bottom_left")
		var priority = row.get("priority", 1)
		if not _number(priority, 1, 32) or int(priority) != priority: return false
		row.priority = int(priority)
		var group := parts[0] + "/" + parts[1]
		if not priorities.has(group): priorities[group] = []
		if priorities[group].has(int(priority)): return false
		priorities[group].append(int(priority))
	for group in defaults().regions:
		if not priorities.has(group): return false
		priorities[group].sort()
		for index in priorities[group].size():
			if priorities[group][index] != index + 1: return false
	var p = candidate.get("presentation")
	if not p is Dictionary: return false
	if not _number(p.get("hand_pitch"), 0, 90) or not _number(p.get("self_hand_scale"), 1, 2.4) or not _number(p.get("camera_pitch"), 25, 75): return false
	if not _number(p.get("self_hand_pitch", p.hand_pitch), 0, 90): return false
	normalized.presentation.self_hand_pitch = p.get("self_hand_pitch", p.hand_pitch)
	data = normalized
	data.schema = 2
	error = ""
	return true

static func _number(value, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= low and value <= high

func load_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		error = "找不到布局文件：" + path
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 512 * 1024:
		error = "布局文件不可读或超过512KB"
		return false
	return accept(JSON.parse_string(file.get_as_text()))

func save_file(path: String) -> Error:
	var check = get_script().new()
	if not check.accept(data): return ERR_INVALID_DATA
	var full := ProjectSettings.globalize_path(path)
	var result := DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	if result != OK: return result
	var file := FileAccess.open(full + ".tmp", FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t", true, true) + "\n")
	file.close()
	return DirAccess.rename_absolute(full + ".tmp", full)

func region_pose(seat: int, kind: String, region_key := "") -> Transform3D:
	var row: Dictionary = data.regions[key(seat, kind) if region_key.is_empty() else region_key]
	return Layout.pose(seat, Vector3(row.x, 0, row.z), 0, deg_to_rad(row.rotation))

func region_keys(seat: int, kind: String) -> Array:
	var prefix := key(seat, kind)
	var result: Array = data.regions.keys().filter(func(k): return k == prefix or str(k).begins_with(prefix + "/"))
	result.sort_custom(func(a, b): return data.regions[a].priority < data.regions[b].priority)
	return result

func public_region_keys(seat: int) -> Array:
	return region_keys(seat, "public_front") + region_keys(seat, "public_left")

func add_region(seat: int, kind: String, template: Dictionary) -> String:
	var prefix := key(seat, kind)
	var keys := region_keys(seat, kind)
	if keys.size() >= 32: return ""
	var serial := 2
	while data.regions.has(prefix + "/" + str(serial)): serial += 1
	var name := prefix + "/" + str(serial)
	data.regions[name] = template.duplicate(true)
	data.regions[name].priority = keys.size() + 1
	data.regions[name].locked = false
	return name

func remove_region(name: String) -> bool:
	var parts := name.split("/")
	var keys := region_keys(int(parts[0]), parts[1])
	if keys.size() == 1 or data.regions[name].locked: return false
	data.regions.erase(name)
	keys.erase(name)
	for i in keys.size(): data.regions[keys[i]].priority = i + 1
	return true
