extends "res://tests/test_round.gd"
const Main=preload("res://scenes/Main.tscn")
const Profile=preload("res://src/presentation/TableLayoutProfile.gd")
const Layout=preload("res://src/presentation/TableLayout.gd")
const Geometry=preload("res://src/presentation/TileGeometry.gd")
var metrics:=[]
func _initialize()->void:run.call_deferred()
func settle()->void:
	for i in 10:await process_frame
func capture(viewport:Viewport,name:String)->void:
	var folder:=OS.get_environment("DONGXIU_CAMERA_CAPTURE")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(folder);await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(folder.path_join(name+".png"))
func face_area(table,node:MeshInstance3D)->float:
	var points:=[]
	for point in [Vector3(-0.5,0.31,-0.67),Vector3(0.5,0.31,-0.67),Vector3(0.5,0.31,0.67),Vector3(-0.5,0.31,0.67)]:points.append(table.camera.unproject_position(node.global_transform*point))
	var area:=0.0
	for i in 4:area+=points[i].cross(points[(i+1)%4])
	return absf(area)*0.5
func screen_bounds(table,node:MeshInstance3D)->Rect2:
	var bounds:=Rect2()
	for corner in 8:
		var point:Vector2=table.camera.unproject_position(node.global_transform*node.get_aabb().get_endpoint(corner))
		bounds=Rect2(point,Vector2.ZERO) if corner==0 else bounds.expand(point)
	return bounds
func old_camera(table)->void:
	var aspect:float=table.get_viewport().get_visible_rect().size.aspect()
	var pitch:float=table.custom_profile.data.presentation.camera_pitch
	pitch=rad_to_deg(asin(clampf(sin(deg_to_rad(pitch))*minf(1.0,(16.0/9.0)/aspect),sin(deg_to_rad(25.0)),sin(deg_to_rad(75.0)))))
	table.camera.position=Layout.facing(table.viewer)*Vector3(0,sin(deg_to_rad(pitch)),cos(deg_to_rad(pitch)))*maxf(60,table.table_edge()*4.8)
	table.camera.look_at(Vector3.ZERO)
	table._frame_saved_table(Layout.facing(table.viewer),table.get_viewport().get_visible_rect().size,aspect)
func kong_game(owner:int,provider:int):
	var probe:=Round.new();probe.start(provider,5,2,Catalog.ordered_values());probe.begin_dealer_turn()
	var copies:Array=probe.players[owner].hand.slice(0,3);copies.append(probe.players[provider].draw_id)
	var pool:=Catalog.values(8427)
	for id in copies:pool.erase("wan6")
	var deck:=[]
	for id in Catalog.COUNT:deck.append("wan6" if copies.has(id) else pool.pop_back())
	var game:=Round.new();game.start(provider,5,2,deck);game.begin_dealer_turn()
	_discard(game,game.players[provider].draw_id);check(game.submit(owner,game.prompt_id,"kong"),"public visibility fixture claims a legal exposed kong");_pass_all(game)
	return game
func _mount_live_table(app, profile, viewer: int, settled: bool) -> void:
	app._table.custom_profile = profile
	app._table.region_placement = load("res://src/presentation/RegionPlacement.gd").new(profile)
	app._table.viewer = viewer
	app.table_play_only = true
	app._mode = "solo"
	var members := []
	for seat in 4:
		members.append({"nickname": ["东秀", "牌友小明", "麻将搭子", "清风"][seat], "score": 200, "ai_id": seat, "connected": true, "player_id": "cam-" + str(seat), "avatar": seat + 1})
	if settled:
		var probe = load("res://src/domain/Wall.gd").new(Catalog.values(697)); probe.open(viewer, 4)
		var cards := ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","tiao1","tiao2","tiao3","tong5"]
		var fixed := {}
		for idx in cards.size():
			var offset: int = 48 if idx == 12 else (idx / 4) * 16 + idx % 4
			fixed[(probe.break_index + offset) % 108] = cards[idx]
		fixed[(probe.break_index + 52) % 108] = "tong5"
		var pool: Array = Catalog.values(285)
		for v in fixed.values(): pool.erase(v)
		var stock := []
		for idx in 108: stock.append(fixed[idx] if fixed.has(idx) else pool.pop_back())
		var rs := Round.new(); rs.start(viewer, 4, 2, stock, 1); rs.begin_dealer_turn()
		rs.submit(viewer, rs.prompt_id, "self_win", -1)
		var snap := rs.snapshot_for(viewer)
		var facts := rs.settlement_facts()
		var ledger: Dictionary = load("res://src/anshun/scoring/ScoringEngine.gd").settle(facts)
		for idx in 4: members[idx].score = 200 + int(ledger.deltas[idx])
		app._round_projection = snap
		app._view = {"seat": viewer, "room": {"room_instance_id": "cam", "round_number": 1, "seats": members, "mode": "solo"}, "round": snap,
			"settlement": {"round_number": 1, "next_dealer_seat": viewer, "viewer_seat": viewer,
				"scores": members.map(func(m): return m.score), "seats": members,
				"players": facts.players, "round_meta": facts.round_meta, "last_discard": facts.last_discard, "ledger": ledger}}
		app._table.apply_view(snap)
		app._show("settlement")
		await settle()
		app._queue_hud_layout()
	else:
		var rs := Round.new(); rs.start(viewer, 4, 2, Catalog.values(541)); rs.begin_dealer_turn()
		var snap := rs.snapshot_for(viewer)
		app._round_projection = snap
		app._view = {"seat": viewer, "room": {"room_instance_id": "cam", "round_number": 1, "seats": members, "mode": "solo"}, "round": snap}
		app._table.apply_view(snap)
		app._show("play")
	await settle()

func run()->void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var cfg := "user://cam-read-%d.cfg" % Time.get_ticks_usec()
	var app=Main.instantiate();app._settings=load("res://src/app/AppSettings.gd").new(cfg);app._settings.save_profile("镜头测",1);app.table_play_only=true;viewport.add_child(app);await settle()
	var profile:=Profile.new();profile.load_file("res://assets/layouts/table-layout.json")
	for resolution in [Vector2i(1280,720),Vector2i(1602,720),Vector2i(2670,1200)]:
		viewport.size=resolution;app.size=Vector2(resolution);await settle()
		for viewer in [1,0,3,2]:
			await _mount_live_table(app, profile, viewer, true)
			var table=app._table;var transforms:={};var current:={}
			for key in table.tiles:
				var node:MeshInstance3D=table.tiles[key];transforms[key]=node.transform
				if node.get_meta("zone","")=="hand" and node.get_meta("seat",-1)!=viewer:
					var seat:int=node.get_meta("seat");current[seat]=current.get(seat,0.0)+face_area(table,node)
					check(is_equal_approx(node.basis.get_scale().x,1.24),"other revealed hands use the settlement scale")
			old_camera(table);var baseline:={}
			for node in table.tiles.values():
				if node.get_meta("zone","")=="hand" and node.get_meta("seat",-1)!=viewer:
					node.basis=Layout.facing(int(node.get_meta("seat")))
					var seat:int=node.get_meta("seat");baseline[seat]=baseline.get(seat,0.0)+face_area(table,node)
			for seat in current:
				var gain:float=current[seat]/baseline[seat]
				metrics.append({"resolution":str(resolution),"viewer":viewer,"seat":seat,"face_area_ratio":gain})
				check(gain>1.20,"settlement improves the visible face area of every other hand: %s gain %s at %s"%[seat,gain,resolution])
			if resolution==Vector2i(1602,720) and viewer==1:await capture(viewport,"old-camera-settlement")
			for key in transforms:table.tiles[key].transform=transforms[key]
			table._frame_camera();app._apply_hud_layout();await settle()
			check(table.tiles.keys().all(func(key):return table.tiles[key].transform==transforms[key]),"lens changes leave all tile identities and world positions unchanged")
			check(table.camera.far>table.camera.position.length()+table.table_edge(),"long-lens view retains far-side geometry within the clipping range")
			var screen:=Rect2(Vector2.ZERO,Vector2(resolution))
			for node in table.tiles.values():
				if node.get_meta("zone","")!="hand" or node.get_meta("seat",-1)==viewer:continue
				var bounds:=Rect2()
				for corner in 8:
					var point:Vector2=app._table_screen_point(node.global_transform*node.get_aabb().get_endpoint(corner))
					bounds=Rect2(point,Vector2.ZERO) if corner==0 else bounds.expand(point)
				check(screen.encloses(bounds),"revealed opponent hand stays on screen at %s viewer %d"%[resolution,viewer])
				check(not app._frame.get_child(0).get_global_rect().intersects(bounds),"settlement panel does not cover revealed hand at %s viewer %d"%[resolution,viewer])
				for badge in app._settlement_names.badges:
					if badge.visible:check(not badge.get_global_rect().intersects(bounds),"settlement name does not cover revealed hand at %s viewer %d"%[resolution,viewer])
			for index in [1,3]:
				var badge=app._settlement_names.badges[index]
				for node in table.tiles.values():
					if node.get_meta("zone","")!="hand" or node.get_meta("seat",-1)!=int(badge.context.seat):continue
					var bounds:=Rect2()
					for corner in 8:
						var point:Vector2=app._table_screen_point(node.global_transform*node.get_aabb().get_endpoint(corner))
						bounds=Rect2(point,Vector2.ZERO) if corner==0 else bounds.expand(point)
					check(not badge.get_global_rect().intersects(bounds),"side names never obscure revealed opponent hand faces after reframing")
			if resolution==Vector2i(1602,720) and viewer==1:await capture(viewport,"new-camera-settlement")
			if resolution in [Vector2i(1602,720),Vector2i(2670,1200)] and viewer==1:await capture(viewport,"settlement-25d-%dx%d"%[resolution.x,resolution.y])
	viewport.size=Vector2i(1602,720);app.size=Vector2(1602,720);await settle()
	for owner in [3,2,0]:
		var game=kong_game(owner,1);var facts:=JSON.stringify(game.export_authority())
		await _mount_live_table(app, profile, 1, false);app._table.apply_view(game.snapshot_for(1));app._table._render(false);await settle()
		var table=app._table;var public_ids:Array=game.players[owner].melds[0].tile_ids
		table._frame_camera()
		var shown:=0.0
		for id in public_ids:shown+=face_area(table,table.tiles[id])
		old_camera(table);var before:=0.0
		for id in public_ids:
			var node:MeshInstance3D=table.tiles[id];var original:=node.basis
			node.basis=node.basis.scaled(Vector3.ONE/1.12);before+=face_area(table,node);node.basis=original
		table._frame_camera();await settle()
		metrics.append({"owner":owner,"public_kong_face_area_ratio":shown/before})
		check(shown/before>1.05,"public kong faces retain their footprint or gain area while far hands become clearer: %s ratio %s"%[owner,shown/before])
		check(table.tiles.values().all(func(node):return node.get_meta("zone","")!="hand" or node.get_meta("seat",-1)==1 or node.get_meta("value","")==""),"more readable camera never reveals private opponent hand faces during play")
		check(JSON.stringify(game.export_authority())==facts,"camera framing never alters the actual kong, stock or rule state")
		await capture(viewport,"public-kong-seat-%s"%owner)
	for resolution in [Vector2i(1280,720),Vector2i(1602,720),Vector2i(2670,1200)]:
		viewport.size=resolution;app.size=Vector2(resolution);await settle()
		for viewer in 4:
			var game=kong_game(viewer,posmod(viewer+2,4))
			var snapshot:Dictionary=game.snapshot_for(viewer)
			snapshot.dealer=viewer;snapshot.players[viewer].ready=true
			snapshot.players[viewer].discards.append({"id":9999,"value":"tiao1"})
			snapshot.charge_chickens={"tiao1":{"discard_id":9999,"location":"discard"}}
			snapshot.players[viewer].public_order=["c9999","m0"]
			snapshot.players[viewer].erase("public_regions")
			await _mount_live_table(app, profile, viewer, false);var table=app._table
			table.apply_view(snapshot);table._render(false);await settle()
			var public_nodes:=[]
			for node in table.tiles.values():
				if node.get_meta("seat",-1)==viewer and node.get_meta("zone","") in ["meld","chicken"]:public_nodes.append(node)
			for key in table._badges:
				if str(key).begins_with(str(viewer)+"/"):public_nodes.append(table._badges[key])
			check(public_nodes.size()>=5 and table._badges.is_empty(),"fixture contains the kong and chicken with no 3D table badges")
			var own_ids:=[]
			for key in table.tiles:
				var node=table.tiles[key]
				if node.get_meta("seat",-1)==viewer and node.get_meta("zone","")=="hand":own_ids.append(key)
			own_ids.sort_custom(func(a,b):return screen_bounds(table,table.tiles[a]).get_center().x < screen_bounds(table,table.tiles[b]).get_center().x)
			for selected_id in [own_ids[0],own_ids[own_ids.size()/2],own_ids[-1]]:
				table.hand_order.selected_id=selected_id;table._render(false);await settle()
				for hand in table.tiles.values():
					if hand.get_meta("seat",-1)!=viewer or hand.get_meta("zone","")!="hand":continue
					check(Rect2(Vector2.ZERO,Vector2(resolution)).encloses(screen_bounds(table,hand)),"selected own hand stays on screen at %s viewer %d"%[resolution,viewer])
					for public_node in public_nodes:
						check(not screen_bounds(table,hand).grow(1).intersects(screen_bounds(table,public_node)),"selected own hand leaves a visible gap from public pieces at %s viewer %d"%[resolution,viewer])
			if resolution in [Vector2i(1602,720),Vector2i(2670,1200)] and viewer==1:await capture(viewport,"in-round-own-public-%dx%d"%[resolution.x,resolution.y])
	await load("res://tests/AudioRetirement.gd").release_app(app, self)
	viewport.free()
	DirAccess.remove_absolute(cfg)
	await settle()
	var path:=OS.get_environment("DONGXIU_CAMERA_CAPTURE")
	if not path.is_empty():
		var file:=FileAccess.open(path.path_join("metrics.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(metrics,"  "))
	print("Camera readability: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
