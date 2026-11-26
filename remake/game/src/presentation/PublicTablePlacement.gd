extends RefCounted
## Only public group centers are projected. Seats keep their original world positions across reconnects.
const Layout = preload("res://src/presentation/TableLayout.gd")
const Profile = preload("res://src/presentation/TableLayoutProfile.gd")
const Regions = preload("res://src/presentation/RegionPlacement.gd")
var _regions
var layout_hash := ""
var _layout := Layout.new()
var _groups: Array = [{}, {}, {}, {}]
var _meld_counts: Array[int] = [0, 0, 0, 0]
var _first_chickens := {}

func _init(use_saved_layout: bool=true) -> void:
	if not use_saved_layout: return
	var path := "res://assets/layouts/table-layout.json"
	if not FileAccess.file_exists(path): return
	var profile := Profile.new()
	if profile.load_file(path):
		_regions = Regions.new(profile)
		layout_hash = JSON.stringify(profile.data).sha256_text()

func consume(round_state, event: Dictionary) -> void:
	match event.type:
		"discard":
			var value: String = round_state.wall.value(event.id)
			if value not in ["tiao1", "tong8"]:
				return
			var cross := not _first_chickens.has(value)
			_first_chickens[value] = true
			_groups[event.seat]["c" + str(event.id)] = Regions.chicken(cross) if _regions else Layout.chicken_footprint(cross)
			_reserve_active(event.seat)
		"meld":
			var meld: Dictionary = event.meld
			_remove_chicken(meld.from_seat, meld.source_id)
			var seat: int = event.seat
			var key := "m" + str(_meld_counts[seat])
			_meld_counts[seat] += 1
			_groups[seat][key] = Regions.footprint(seat, meld) if _regions else Layout.meld_footprint(seat, meld)
			_reserve_active(seat)
		"add_kong":
			var seat: int = event.seat
			for index in round_state.players[seat].melds.size():
				var meld: Dictionary = round_state.players[seat].melds[index]
				if meld.kind == "add_kong" and meld.tile_ids.has(event.id):
					_groups[seat]["m" + str(index)] = Regions.footprint(seat, meld) if _regions else Layout.meld_footprint(seat, meld)
					_reserve_active(seat); break
		"finish":
			# An ordinary discard win claims a visible tile. A self-drawn or robbed tile has no discard entry.
			_remove_chicken(event.source, event.id)

func _remove_chicken(seat: int, tile_id: int) -> void:
	if seat >= 0 and _groups[seat].erase("c" + str(tile_id)):
		_reserve_active(seat)

func sync_status(round_state) -> void:
	if not _regions: return
	for player in round_state.players:
		var active: Dictionary = _groups[player.seat]
		if player.seat == int(round_state.round_meta.dealer_seat): active["badge_dealer"] = Regions.badge("dealer")
		if player.ready: active["badge_ready"] = Regions.badge("ready")
		_reserve_active(player.seat)

func _reserve_active(seat: int) -> void:
	var hand_count := 14
	var active: Dictionary = _groups[seat]
	for key: String in active:
		if key.begins_with("badge_"):
			if _regions: _regions.public_group(seat, key, active[key], active.keys(), active)
			continue
		if key.begins_with("m"):
			hand_count -= 3
		_layout.reserve(seat, key, active[key], hand_count, active)
		if _regions: _regions.public_group(seat, key, active[key], active.keys(), active)
	if _regions and active.is_empty(): _regions.restore_public(seat, {})

func regions_for(seat: int) -> Dictionary:
	return _regions.public_state(seat) if _regions else {}

func centers_for(seat: int) -> Dictionary:
	var result := {}
	for key in _groups[seat]:
		if _layout.anchors[seat].has(key):
			var center: Vector2 = _layout.anchors[seat][key].center
			result[key] = [center.x, center.y]
	return result


func export_authority() -> Dictionary:
	return {"groups": _groups.duplicate(true), "meld_counts": _meld_counts.duplicate(),
		"first_chickens": _first_chickens.duplicate(true), "layout_hash": layout_hash,
		"public_regions": [regions_for(0), regions_for(1), regions_for(2), regions_for(3)]}


func restore_authority(state: Dictionary) -> bool:
	if not state.get("groups") is Array or state.groups.size() != 4:
		return false
	if not state.get("meld_counts") is Array or state.meld_counts.size() != 4:
		return false
	_groups = state.groups.duplicate(true)
	var counts: Array = state.meld_counts
	_meld_counts = []
	for value in counts:
		_meld_counts.append(int(value))
	_first_chickens = state.get("first_chickens", {}).duplicate(true)
	var saved = state.get("public_regions", [])
	if _regions and state.get("layout_hash") == layout_hash and saved is Array and saved.size() == 4:
		for seat in 4:
			if not saved[seat] is Dictionary or not _regions.restore_public(seat, saved[seat]): return false
	for seat in 4:
		_reserve_active(seat)
	return true

func table_edge() -> float:
	return float(_regions.profile.data.table_side) * 0.5 if _regions else Layout.EDGE
