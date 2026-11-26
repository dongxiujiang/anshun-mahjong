extends SceneTree
const Main=preload("res://scenes/Main.tscn")
const Settings=preload("res://src/app/AppSettings.gd")
const Retire=preload("res://tests/AudioRetirement.gd")
const Geometry=preload("res://src/presentation/TileGeometry.gd")
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL max table: "+message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	root.size=Vector2i(1280,720)
	var app=Main.instantiate();app.table_layout_review=true;app._settings=Settings.new("user://max-table-profile.cfg");app._settings.save_profile("取景检查",1)
	root.add_child(app);await process_frame;app._choose_mode("solo")
	var limit:=Time.get_ticks_msec()+25000
	while not (app._choices().get("actions",[]).has("discard") and app._table.own_hand_stable()) and Time.get_ticks_msec()<limit:
		await process_frame;OS.delay_msec(1)
	check(app._choices().get("actions",[]).has("discard"),"real game reaches an actual play turn")
	if not app._choices().get("actions",[]).has("discard"):
		await Retire.release_app(app,self);quit(1);return
	app._client._host.set_process(false);app._table._render(false)
	var game=app._client._host._session._round
	for seat in 4:game.snapshot_for(seat)
	var facts:=JSON.stringify(game.export_authority())
	check(not app._hud.visible and app._screen=="play","layout review hides all overlay buttons, names, scores and timer without replacing the game scene")
	var table=app._table
	var own:int=app._view.seat
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2670,1200)]:
		root.size=resolution;await process_frame;await process_frame;app._fit_safe_area();await process_frame
		var size:=Vector2(app._board_world.size)
		var screen:=Rect2(Vector2.ZERO,size)
		var left:=INF;var right:=-INF;var top:=INF;var bottom:=-INF
		table.set_safe_insets(Vector4(size.x*0.045,4,4,4))
		var edge:float=table.table_edge()+0.52
		for x in [-edge,edge]:
			for z in [-edge,edge]:
				for y in [-0.37,0.062]:
					var point:Vector2=table.camera.unproject_position(Vector3(x,y,z))
					check(screen.has_point(point),"complete tabletop remains in the viewport")
					left=minf(left,point.x);right=maxf(right,point.x);top=minf(top,point.y);bottom=maxf(bottom,point.y)
		check((right-left)/size.x>(0.75 if size.aspect()>2.0 else 0.80),"wooden frame fills a reasonable width: %s at %s"%[(right-left)/size.x,resolution])
		var safe:=Rect2(Vector2(size.x*0.045,4),Vector2(size.x*0.955-4,size.y-8))
		for id in table.tiles:
			var tile:MeshInstance3D=table.tiles[id]
			if tile.get_meta("zone")=="hand" and tile.get_meta("seat")==own:
				var box:=Geometry.transformed_bounds(tile.transform)
				check(absf(box.position.y)<0.002,"tilted own cards remain on the table rather than floating")
				for corner in 8:
					var point:Vector2=table.camera.unproject_position(tile.transform*Geometry.BOUNDS.get_endpoint(corner))
					check(safe.has_point(point),"own hand and independent draw stay within the phone safe area")
					top=minf(top,point.y);bottom=maxf(bottom,point.y)
		check((bottom-top)/size.y>(0.91 if size.aspect()>2.0 else 0.92),"frame and foreground hand fill the landscape height: %s at %s"%[(bottom-top)/size.y,resolution])
		var folder:=OS.get_environment("DONGXIU_REFERENCE_SCREENS")
		if not folder.is_empty() and DisplayServer.get_name()!="headless":
			DirAccess.make_dir_recursive_absolute(folder);await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join("table-only-%dx%d.png"%[resolution.x,resolution.y]))
	var base:=Transform3D(Basis(Vector3.RIGHT,PI/2),Vector3(0,Geometry.LENGTH/2,0))
	var tilted:Transform3D=table._tilt_own_hand(base,false)
	var angle:float=table.custom_profile.data.presentation.self_hand_pitch
	check(angle>=50 and angle<90,"own cards use the 2.5D inclination while remaining short of fully upright")
	check(tilted.basis.is_equal_approx(Basis(Vector3.RIGHT,deg_to_rad(angle))),"own visual inclination comes from the saved presentation setting")
	check(table._tilt_own_hand(base,true)==base,"flat-hand mode is not changed by own standing-card inclination")
	check(JSON.stringify(game.export_authority())==facts,"camera framing and inclination never change the round")
	app._back_home();check(await Retire.release_app(app,self),"review scene and audio retire after capture")
	print("%d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
