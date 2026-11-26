extends SceneTree
const Profile = preload("res://src/presentation/TableLayoutProfile.gd")
const Pack = preload("res://src/presentation/RegionPlacement.gd")
const Table = preload("res://src/presentation/TableView.gd")
const Public = preload("res://src/presentation/PublicTablePlacement.gd")
const Layout = preload("res://src/presentation/TableLayout.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL public incremental: " + message)
func _initialize() -> void: _run.call_deferred()
func _profile(seat: int, width: float = 5.3):
	var profile := Profile.new()
	var front: Dictionary = profile.data.regions[str(seat) + "/public_front"]
	front.width = width; front.depth = 3
	var second: String = profile.add_region(seat, "public_front", front)
	profile.data.regions[second].width = 4
	profile.data.regions[second].x = 6
	var third: Dictionary = profile.data.regions[str(seat) + "/public_left"]
	third.start_corner = "bottom_right"; third.width = 6
	return profile
func _run() -> void:
	for seat in 4:
		var profile = _profile(seat)
		var pack := Pack.new(profile)
		var groups := {"first": Pack.chicken(false), "pung": Pack.footprint(seat, {"kind": "pung"}), "tail": Pack.chicken(false)}
		for key in groups: check(not pack.public_group(seat, key, groups[key], groups.keys(), groups).is_empty(), "initial public row fits actual item widths")
		var first: Dictionary = pack.public_state(seat).first.duplicate(true)
		var old_tail: Dictionary = pack._public[seat].tail.duplicate(true)
		groups.pung = Pack.footprint(seat, {"kind": "add_kong"})
		var moved := pack.public_group(seat, "pung", groups.pung, groups.keys(), groups)
		check(moved.region == str(seat) + "/public_front/2", "oversized added kong migrates to next region")
		check(pack.public_state(seat).first == first, "prefix stays fixed during added-kong migration")
		var tail: Dictionary = pack._public[seat].tail
		check(is_equal_approx(pack._offset(tail.region, tail.rect), 1.1), "source suffix closes gap to exactly 0.1 tile width")
		var slide: Vector3 = Layout.facing(seat).inverse() * (tail.pose.origin - old_tail.pose.origin)
		check(slide.x < 0 and is_zero_approx(slide.z), "source compaction moves horizontally left in every owner orientation")
		var fixed: Dictionary = pack.public_state(seat).duplicate(true)
		for key in groups: pack.public_group(seat, key, groups[key], groups.keys(), groups)
		check(pack.public_state(seat) == fixed, "ordinary refresh never reflows migrated layout")
		var restored := Pack.new(profile)
		check(restored.restore_public(seat, fixed) and restored.public_state(seat) == fixed, "saved public facts restore exact migrated positions")
		groups.next = Pack.chicken(false)
		var next := pack.public_group(seat, "next", groups.next, groups.keys(), groups)
		check(next.region == str(seat) + "/public_left", "new content continues forward rather than returning to source holes")
		check(is_equal_approx(next.rect.end.x, 3), "third public region starts at its right-hand edge")
		groups.next2 = Pack.chicken(false)
		var next2 := pack.public_group(seat, "next2", groups.next2, groups.keys(), groups)
		check(is_equal_approx(next.rect.position.x - next2.rect.end.x, 0.1), "third region fills right to left with the same gap")
		var enough := Pack.new(_profile(seat, 7))
		var same := {"first": Pack.chicken(false), "pung": Pack.footprint(seat, {"kind":"pung"}), "tail":Pack.chicken(false)}
		for key in same: enough.public_group(seat,key,same[key],same.keys(),same)
		var before: Dictionary = enough._public[seat].duplicate(true)
		same.pung = Pack.footprint(seat, {"kind":"add_kong"})
		var expanded := enough.public_group(seat,"pung",same.pung,same.keys(),same)
		check(expanded.region == str(seat)+"/public_front", "added kong stays in its region when suffix can shift")
		check(enough._public[seat].first.pose == before.first.pose and is_equal_approx(enough._public[seat].tail.rect.position.x-before.tail.rect.position.x,1), "expansion moves only following items by required width")
		var full_profile = _profile(seat)
		full_profile.data.regions[str(seat)+"/public_front/2"].width=3
		full_profile.data.regions[str(seat)+"/public_left"].width=3
		var full := Pack.new(full_profile)
		var blocked := {"first":Pack.chicken(false),"pung":Pack.footprint(seat,{"kind":"pung"}),"tail":Pack.chicken(false)}
		for key in blocked: full.public_group(seat,key,blocked[key],blocked.keys(),blocked)
		var original: Dictionary = full.public_state(seat).duplicate(true)
		blocked.pung=Pack.footprint(seat,{"kind":"add_kong"})
		check(full.public_group(seat,"pung",blocked.pung,blocked.keys(),blocked).is_empty() and full.public_state(seat)==original, "no-space resize fails atomically without losing or moving old groups")
		var badge_profile = _profile(seat, 10)
		var badges := Pack.new(badge_profile)
		var inputs := {"dealer":Pack.badge("dealer"),"ready":Pack.badge("ready"),"one":Pack.chicken(false),"two":Pack.chicken(false)}
		for key in inputs: badges.public_group(seat,key,inputs[key],inputs.keys(),inputs)
		var state: Dictionary = badges._public[seat]
		check(state.dealer.rect.position.x == state.ready.rect.position.x and is_equal_approx(state.ready.rect.position.y-state.dealer.rect.end.y,0.1), "badges stack in one column with vertical 0.1 gap")
		check(is_equal_approx(state.one.rect.position.x-state.dealer.rect.end.x,0.1) and is_equal_approx(state.two.rect.position.x-state.one.rect.end.x,0.1), "marker column and identical chickens both leave 0.1 gap")
		var authority = Public.new()
		var authority_profile = _profile(seat, 6.4)
		authority._regions=Pack.new(authority_profile);authority.layout_hash=JSON.stringify(authority_profile.data).sha256_text()
		var fake_round := {"round_meta":{"dealer_seat":seat},"players":[]}
		for other in 4: fake_round.players.append({"seat":other,"ready":false,"melds":[]})
		authority.sync_status(fake_round)
		authority._groups[seat].merge({"c10":Pack.chicken(false),"m0":Pack.footprint(seat,{"kind":"pung"}),"c11":Pack.chicken(false)})
		authority._reserve_active(seat)
		fake_round.players[seat].melds=[{"kind":"add_kong","tile_ids":[1,2,3,4]}]
		var facts := JSON.stringify(fake_round)
		authority.consume(fake_round,{"type":"add_kong","seat":seat,"id":4})
		check(JSON.stringify(fake_round)==facts, "authority display processing never changes round facts")
		check(authority.regions_for(seat).m0.region==str(seat)+"/public_front/2", "authority handles real added-kong event and publishes migrated final position")
		var backup: Dictionary = authority.export_authority()
		var replacement = Public.new();replacement._regions=Pack.new(authority_profile);replacement.layout_hash=authority.layout_hash
		check(replacement.restore_authority(backup) and replacement.regions_for(seat)==authority.regions_for(seat), "authority handover preserves badge column and compacted public positions")
		# Exercise the actual renderer's four parallel tile motions plus the source suffix slide.
		var board = Table.new(); root.add_child(board); await process_frame
		board.custom_profile = profile; board.region_placement = Pack.new(profile); board.viewer=seat
		board._retired_backs={0:[],1:[],2:[],3:[]}
		board.view = {"phase":"turn","viewer_seat":seat,"dealer":-1,"charge_chickens":{}}
		var player := {"seat":seat,"ready":false,"discard_count":4,"discards":[{"id":10,"value":"tiao1"},{"id":11,"value":"tong8"}],"melds":[{"kind":"pung","tile":"wan5","from_seat":posmod(seat+1,4),"tile_ids":[1,2,3]}],"public_order":["c10","m0","c11"]}
		board._public(player,false)
		board._place(4,"wan5",Layout.pose(seat,Vector3(0,1,13),PI/2),"hand",false)
		var starts := {}
		for id in [1,2,3,4,11]: starts[id]=board.tiles[id].transform
		player.melds[0].kind="add_kong";player.melds[0].tile_ids.append(4)
		board._adding_kong=[1,2,3,4];board._public(player,true);board._adding_kong=[]
		var motions := []
		for id in [1,2,3,4,11]:
			check(board._motions.has(id), "every kong tile and source suffix begins moving in the same render pass")
			if board._motions.has(id):
				var motion: Tween = board._motions[id]; motion.pause();motions.append(motion)
		for motion in motions: motion.custom_step(0.15)
		for id in [1,2,3,4,11]:
			check(not board.tiles[id].transform.is_equal_approx(starts[id]) and not board.tiles[id].transform.is_equal_approx(board._destinations[id]), "all five pieces are in flight together at the halfway point")
		for motion in motions: motion.custom_step(0.3)
		for id in [1,2,3,4,11]: check(board.tiles[id].transform.is_equal_approx(board._destinations[id]), "all five pieces finish at their planned positions")
		var local_tail: Vector3 = Layout.facing(seat).inverse()*(board.tiles[11].position-starts[11].origin)
		check(local_tail.x < 0 and is_zero_approx(local_tail.z), "renderer source suffix slides only horizontally")
		board.view.dealer=seat;player.ready=true
		board.region_placement=Pack.new(badge_profile);board.custom_profile=badge_profile
		board._public(player,false)
		check(board._badges.is_empty(), "dealer and ready markers are shown beside player names instead of on the 3D table")
		if seat==1:
			var folder := OS.get_environment("DONGXIU_LAYOUT_CAPTURE")
			if not folder.is_empty() and DisplayServer.get_name()!="headless":
				DirAccess.make_dir_recursive_absolute(folder)
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder.path_join("runtime-public-badges.png"))
		board.queue_free();await process_frame
	var path := "user://public-direction.json"
	var directional = _profile(1)
	check(directional.save_file(path) == OK, "directional layout saves")
	var reopened := Profile.new()
	check(reopened.load_file(path) and reopened.data.regions["1/public_left"].start_corner == "bottom_right" and reopened.data.regions.size() == directional.data.regions.size(), "directional layout survives save and reopen")
	DirAccess.remove_absolute(path)
	var applied := Profile.new()
	check(applied.load_file(Table.LAYOUT_PATH), "applied game layout loads with directional regions")
	for seat in 4:
		check(applied.data.regions[applied.public_region_keys(seat)[2]].start_corner == "bottom_right", "all four players' third public region starts at bottom-right")
	print("%d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
