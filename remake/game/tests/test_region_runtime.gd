extends SceneTree
const Profile = preload("res://src/presentation/TableLayoutProfile.gd")
const Placement = preload("res://src/presentation/RegionPlacement.gd")
const Table = preload("res://src/presentation/TableView.gd")
const Layout = preload("res://src/presentation/TableLayout.gd")
const Geometry = preload("res://src/presentation/TileGeometry.gd")
const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Public = preload("res://src/presentation/PublicTablePlacement.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL region runtime: " + message)
func _run() -> void:
	var p := Profile.new()
	var legacy := p.data.duplicate(true); legacy.schema = 1
	for row in legacy.regions.values(): row.erase("priority")
	check(p.accept(legacy) and p.data.schema == 2, "old one-region drafts migrate without lost geometry")
	var invalid := p.data.duplicate(true); invalid.regions["1/hand"].priority = 2
	check(not p.accept(invalid), "non-contiguous placement priority is rejected")
	# A first area fits two flat cards, then the third must move to area two.
	var row: Dictionary = p.data.regions["1/discard"]
	row.width = 2.0; row.depth = Layout.LONG
	var next := p.add_region(1, "discard", row)
	p.data.regions[next].x = -5.0
	var pack := Placement.new(p)
	var first := pack.indexed(1, "discard", 0, 1, Layout.LONG, 0.31, 0)
	var second := pack.indexed(1, "discard", 1, 1, Layout.LONG, 0.31, 0)
	var third := pack.indexed(1, "discard", 2, 1, Layout.LONG, 0.31, 0)
	check(first.region == "1/discard" and second.region == first.region and third.region == next, "indexed cards exhaust area one before using area two")
	check(pack.indexed(1, "discard", 4, 1, Layout.LONG, 0.31, 0).is_empty(), "insufficient space is reported instead of overlapping slots")
	# Public groups preserve event identity; a pung reserves the fourth-tile expansion.
	var front: Dictionary = p.data.regions["1/public_front"]
	front.width = 4; front.depth = 8
	var next_front := p.add_region(1, "public_front", front)
	p.data.regions[next_front].x = -6
	var group := {"width": 4.0, "reserve_near": -1.67}
	var groups := {"m0": group, "m1": group}
	var a := pack.public_group(1, "m0", group, ["m0", "m1"], groups)
	var b := pack.public_group(1, "m1", group, ["m0", "m1"], groups)
	check(a.region == "1/public_front" and b.region == next_front, "public events use the next region instead of a second row even when the first region is deep")
	check(is_zero_approx(a.rect.position.y) and is_zero_approx(b.rect.position.y), "public regions only allocate a single row")
	check(pack.public_group(1, "m0", group, ["m0", "m1"], groups).pose == a.pose, "refreshing snapshots never moves an old public group")
	var round_state := Round.new(); round_state.start(1, 4, 2, Catalog.values(493)); round_state.begin_dealer_turn()
	var snapshot := round_state.snapshot_for(1)
	var facts := JSON.stringify(round_state.export_authority())
	var board := Table.new(); root.add_child(board); await process_frame
	board.custom_profile = p; board.region_placement = pack
	board.apply_view(snapshot); board._render(false)
	check(board.tiles.size() == 108, "configured runtime renderer still conserves 108 identities")
	check(JSON.stringify(round_state.export_authority()) == facts, "rendering never changes game rules or wall facts")
	var draw: int = round_state.players[1].draw_id
	var expected := pack.indexed(1, "hand", 12, 1, Layout.THICK, Layout.LONG * 0.5, PI / 2, 13)
	expected.pose = expected.pose.translated_local(Vector3(Layout.WIDTH * 1.25, 0, 0))
	expected.pose = board._magnify_own_hand(board._tilt_own_hand(expected.pose, false), 1)
	check(board.tiles[draw].transform.is_equal_approx(expected.pose), "actual runtime draw follows the last hand tile with a quarter-width gap")
	var spot := board.camera.unproject_position(board.tiles[draw].position)
	check(board.tile_at(spot) == draw, "ray picking follows the actual configured card")
	var wall_id: int = round_state.wall.peek_head()
	check(board.tiles[wall_id].transform.is_equal_approx(board._wall_pose(wall_id, [])), "wall node uses configured pose without replacing wall identity")
	var wall_seat:int=board.layout.slots.slot_info(wall_id).seat
	var wall_key:String=p.region_keys(wall_seat,"wall")[0]
	var original_z:float=p.data.regions[wall_key].z
	var original_wall:Transform3D=board.tiles[wall_id].transform
	p.data.regions[wall_key].z+=0.3
	board.apply_view(snapshot);board._render(false)
	check(not board.tiles[wall_id].transform.is_equal_approx(original_wall),"editing an existing wall region invalidates cached poses")
	p.data.regions[wall_key].z=original_z
	board.apply_view(snapshot);board._render(false)
	check(board.tiles[wall_id].transform.is_equal_approx(original_wall),"restoring the region restores the exact wall pose")
	var centered:Dictionary=snapshot.duplicate(true)
	centered.wall_offsets=[0.0,0.0,0.0,0.0];centered.wall_offsets[wall_seat]=0.4
	board.apply_view(centered);board._render(false)
	check(not board.tiles[wall_id].transform.is_equal_approx(original_wall),"centering a remaining wall invalidates cached poses")
	board.apply_view(snapshot);board._render(false)
	var owner_discards := []
	for turn in 9:
		var seat: int = round_state.turn
		var chosen := -1
		for id in round_state.choices(seat).discard_ids:
			if round_state.wall.value(id) not in ["tiao1", "tong8"]: chosen = id; break
		check(chosen >= 0 and round_state.submit(seat, round_state.prompt_id, "discard", chosen), "actual authorized gameplay emits an ordinary discard")
		if seat == 1: owner_discards.append(chosen)
		if round_state.phase == "response": round_state.expire_responses(round_state.prompt_id)
		board.apply_view(round_state.snapshot_for(1)); board._render(false)
	check(owner_discards.size() == 3, "owner discards three times through real turn flow")
	if owner_discards.size() == 3:
		check(board.tiles[owner_discards[2]].transform.is_equal_approx(third.pose), "third actual discard lands in area two after area one's two slots fill")
	# Reload the exported source configuration with a fresh real TableView.
	var config_path := "user://runtime-regions-test.json"
	check(p.save_file(config_path) == OK, "source-compatible layout can be serialized")
	var loaded := Profile.new(); check(loaded.load_file(config_path), "runtime layout loader reads multi-area schema")
	# The outer test harness preserves any user's existing source configuration.
	if OS.get_environment("DONGXIU_TEST_APPLY") == "1":
		var live := Table.new(); live.custom_profile = loaded; live.region_placement = Placement.new(loaded); root.add_child(live); await process_frame
		check(live.custom_profile != null, "fresh actual game table loads multi-area profile")
		live.apply_view(snapshot); live._render(false)
		check(live.tiles[draw].transform.is_equal_approx(expected.pose), "exported configuration changes actual game draw geometry")
		var authority := Public.new()
		authority._regions = Placement.new(loaded)
		authority._groups[1] = groups.duplicate(true)
		authority._reserve_active(1)
		var fixed: Dictionary = authority.regions_for(1)
		check(fixed.m0.region == "1/public_front" and fixed.m1.region == next_front, "server display facts use the same ordered multiple regions")
		var replacement := Public.new()
		replacement._regions = Placement.new(loaded)
		replacement.layout_hash = authority.layout_hash
		check(replacement.restore_authority(authority.export_authority()), "layout display facts restore during server handover")
		check(JSON.stringify(replacement.regions_for(1)) == JSON.stringify(fixed), "handover preserves old public group positions")
		var client_pack := Placement.new(loaded)
		check(client_pack.restore_public(1, fixed), "client receives only public layout positions")
		check(client_pack.public_group(1, "m1", group, groups.keys(), groups).pose.is_equal_approx(b.pose), "late client sees exactly the server's existing placement")
		live.free()
	board.free(); await process_frame
	await _draw_spacing()
	print("%d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)

func _draw_spacing() -> void:
	var profile := Profile.new()
	check(profile.load_file(Table.LAYOUT_PATH), "draw regression uses the actual applied game layout")
	var board := Table.new(false)
	board.custom_profile = profile
	root.add_child(board); await process_frame
	for rotation in [0.0, 23.0]:
		for owner in 4:
			var row: Dictionary = profile.data.regions[profile.region_keys(owner, "hand")[0]]
			row.scale = 1.0 if rotation == 0 else 0.8
			row.width = 13 * Layout.WIDTH * row.scale
			row.depth = Geometry.tile_bounds(profile.data.presentation.hand_pitch).size.z * row.scale
			row.rotation = rotation
			for magnification in [1.0, 1.5]:
				profile.data.presentation.self_hand_scale = magnification
				for viewer in 4:
					board.viewer = viewer
					board._frame_camera()
					for flat in [false, true]:
						board.flat_hands = flat
						for phase in ["turn", "self_win", "discard_win"]:
							for count in [13, 10, 7, 4, 1, 0]:
								_draw_fixture(board, owner, count, phase)
								var visible: bool = owner == viewer or phase != "turn"
								var drawn: Transform3D = board.tiles[count if visible else Table._hidden_key(owner, count)].transform
								var note := "owner %d viewer %d count %d %s flat %s scale %s yaw %s" % [owner, viewer, count, phase, flat, magnification, rotation]
								if count == 0:
									if owner == viewer:
										if not flat and phase == "turn": drawn.origin -= Layout.facing(owner) * Vector3(0, 0, 2.8)
										drawn = board._magnify_hand(drawn, owner, 1.0 / magnification)
									elif phase != "turn":
										drawn = board._magnify_hand(drawn, owner, 1.0 / 1.24)
									var center: Transform3D = profile.region_pose(owner, "hand").affine_inverse() * drawn
									check(absf(center.origin.x) < 0.005, "lone draw centers in hand region: " + note)
								else:
									var last: Transform3D = board.tiles[count - 1 if visible else Table._hidden_key(owner, count - 1)].transform
									var axis := last.basis.x.normalized()
									var width := Layout.WIDTH * last.basis.x.length()
									var delta := drawn.origin - last.origin
									check(absf(delta.dot(axis) / width - 1.25) < 0.005, "world edge gap remains a quarter tile: " + note)
									check((delta - axis * width * 1.25).length() < 0.005 and drawn.basis.is_equal_approx(last.basis), "draw follows hand rotation, posture and scale: " + note)
									if viewer == owner and rotation == 0:
										var left := board.camera.unproject_position(last.origin - axis * width * 0.5)
										var right := board.camera.unproject_position(last.origin + axis * width * 0.5)
										var draw_left := board.camera.unproject_position(drawn.origin - axis * width * 0.5)
										check(absf(draw_left.distance_to(right) / left.distance_to(right) - 0.25) < 0.005, "own screen gap remains a quarter tile after magnification: " + note)
								if count == 13:
									for corner in 8:
										var screen := board.camera.unproject_position(drawn * Geometry.BOUNDS.get_endpoint(corner))
										check(root.get_visible_rect().has_point(screen), "13+1 draw remains fully framed: " + note)
						_draw_fixture(board, owner, 13, "turn", true)
						var visible: bool = viewer == owner
						var last: Transform3D = board.tiles[12 if visible else Table._hidden_key(owner, 12)].transform
						var extra: Transform3D = board.tiles[13 if visible else Table._hidden_key(owner, 13)].transform
						check((last.affine_inverse() * extra.origin - Vector3(Layout.WIDTH, 0, 0)).length() < 0.005, "merged fourteenth tile touches the thirteenth for every seat and posture")
	_draw_framing(board)
	board.free(); await process_frame

func _draw_framing(board) -> void:
	var original_size := root.size
	var profile := Profile.new()
	profile.data.presentation.self_hand_scale = 1.5
	for owner in 4:
		# Place the hand at the table edge and the old draw area elsewhere to expose clipping.
		profile.data.regions["%d/hand" % owner].x = profile.data.table_side * 0.5 - 6.5
		profile.data.regions["%d/draw" % owner].x = -4.0
	board.custom_profile = profile
	board.region_placement = Placement.new(profile)
	for resolution in [Vector2i(1280, 720), Vector2i(2670, 1200), Vector2i(2400, 1080)]:
		root.size = resolution
		var safe := Vector4(45, 12, 30, 18)
		var screen_rect := Rect2(safe.x, safe.y, resolution.x - safe.x - safe.z, resolution.y - safe.y - safe.w)
		for owner in 4:
			board.viewer = owner
			board.set_safe_insets(safe)
			for flat in [false, true]:
				board.flat_hands = flat
				_draw_fixture(board, owner, 13, "turn")
				for node in board.tiles.values():
					for corner in 8:
						var screen: Vector2 = board.camera.unproject_position(node.transform * Geometry.BOUNDS.get_endpoint(corner))
						check(screen_rect.has_point(screen), "13+1 magnified hand fits the safe area at %s, seat %d, flat %s" % [resolution, owner, flat])
				var facing := Layout.facing(owner).inverse()
				var first: Vector3 = facing * board.tiles[0].position
				var drawn: Vector3 = facing * board.tiles[13].position
				var expected_center: float = profile.data.regions["%d/hand" % owner].x + 0.625 * Layout.WIDTH
				check(absf((first.x + drawn.x) * 0.5 - expected_center) < 0.005, "magnification anchors the full dynamic hand-plus-draw envelope")
	root.size = original_size

func _draw_fixture(board, owner: int, count: int, phase: String, merged: bool = false) -> void:
	var faces := []
	for id in count + 1:
		if phase != "discard_win" or id < count: faces.append({"id": id, "value": "wan1"})
	var player := {"seat": owner, "hand": faces if owner == board.viewer or phase != "turn" else [],
		"hand_count": count + 1, "draw_id": count if phase != "discard_win" else -1, "has_draw": phase != "discard_win",
		"ready": false, "melds": [], "discards": [], "display": {"draw_merged": merged}}
	board.view = {"phase": "turn" if phase == "turn" else "settled", "viewer_seat": board.viewer, "players": [player],
		"result": {} if phase == "turn" else {"winner": owner, "self_draw": phase == "self_win", "win_tile_id": count, "win_tile": "wan1"}}
	board.hand_order = {"draw_merged": merged}
	board._render(false)
