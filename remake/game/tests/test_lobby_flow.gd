extends "res://tests/test_play_controls.gd"
const Packs = preload("res://src/audio/VoicePacks.gd")
var _phone: SubViewport

func _run() -> void:
	var folder := "user://lobby-flow-"+str(Time.get_ticks_usec())
	DirAccess.make_dir_absolute(folder)
	var path := folder.path_join("profile.cfg")
	_phone=SubViewport.new();root.add_child(_phone)
	_phone.size=Vector2i(2670,1200)
	_phone.size_2d_override=Vector2i(1602,720)
	_phone.size_2d_override_stretch=true
	_phone.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	app=Main.instantiate();app.table_play_only=true;app._settings=Settings.new(path)
	app._settings.save_profile("预览玩家",1)
	app._settings.update({"directory_url":"http://127.0.0.1:1"})
	_phone.add_child(app)
	check(app._screen=="connect" and app._mode=="online" and app._client.ticket.is_empty(),"phone boot opens online lobby without creating or joining a room")
	check(app.table_play_only,"lobby boot retains phone table framing mode")
	var authorities := []
	var people := []
	var rows := []
	for index in 2:
		var authority := Client.new();root.add_child(authority);authorities.append(authority)
		authority.start_server(str(1234+index),0,{"room_name":"好友麻将桌"+str(index+1)})
		for person in 2:
			var peer := Client.new();root.add_child(peer);people.append(peer)
			peer.connect_room("127.0.0.1",authority.local_port,{"player_id":"preview-%d-%d"%[index,person],"nickname":"牌友"+str(index*2+person),"room_number":str(1234+index),"avatar":index*4+person+1,"voice_pack":Packs.ORDER[0],"requested_seat":1 if person==0 else 3})
			check(await until(func():return not peer.view.is_empty()),"real lobby occupant joins")
		var room: Dictionary = authority.discovery_info();room.host="127.0.0.1";rows.append(room)
	app._refresh_online(rows)
	for i in 16:await process_frame
	for item in app._online_results._labels:
		check(app._online_results._stage.get_global_rect().grow(2).encloses(item.control.get_global_rect()),"room labels and seat targets remain within their actual stage")
	await _shot("lobby-phone-mode")
	app._open_settings()
	check(is_instance_valid(app._lobby_backdrop) and app._lobby_backdrop.get_child_count()==1,"settings preserves the actual lobby viewport behind its panel")
	app._close_settings()
	app._refresh_online(rows)
	for i in 16:await process_frame
	var room: Dictionary = rows[0]
	app._select_room_seat(room,0)
	check(await until(func():return not app._view.is_empty() and app._transition.active),"selected seat starts actual descending camera")
	var target: Transform3D = app._table.camera.transform
	check(app._choices().is_empty() and not app._table.is_processing_input(),"entry blocks UI actions without blocking authority")
	if not app._entry_origin.is_empty():
		var index := 0
		for x in [-app._table.table_edge(),app._table.table_edge()]:
			for z in [-app._table.table_edge(),app._table.table_edge()]:
				var actual: Vector2 = app._table.camera.unproject_position(Vector3(x,0,z))*app._board.size/Vector2(app._board_world.size)+app._board.global_position
				check(actual.distance_to(app._entry_origin.corners[index])<35,"entry starts at clicked table: actual=%s expected=%s board=%s source=%s"%[actual,app._entry_origin.corners[index],app._board.get_global_rect(),app._entry_origin.rect])
				index+=1
	for i in 32:await process_frame
	await _shot("entering-phone-mode")
	check(await until(func():return not app._transition.active),"full entry completes")
	check(not app._table.camera.transform.is_equal_approx(target),"camera reaches seated framing")
	check(app._screen=="room" and app._frame.visible,"joined preparation controls return after camera")
	app._start_seating()
	app._transition._process(.25)
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	app.propagate_notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not app._transition.active,"background during entry snaps to final camera instead of restarting")
	app._table.apply_quality("smooth")
	check(not app._table._key_light.shadow_enabled and not app._table._reflection_probe.visible,"smooth disables decorative shadows and reflections")
	app._table.apply_quality("detail")
	check(app._table._key_light.shadow_enabled and app._table._reflection_probe.visible,"detail enables shadows and a local reflection probe")
	await app._back_home()
	check(app._view.is_empty() and not app._transition.active,"real intentional leave completes reverse move and releases its seat")
	for peer in people:peer._reset();peer.free()
	for authority in authorities:authority._reset();authority.free()
	await AudioRetirement.release_app(app,self)
	_phone.free()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(folder)
	print("Lobby flow: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _shot(name: String) -> void:
	var output := OS.get_environment("DONGXIU_LOBBY_CAPTURE")
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	if name=="lobby-phone-mode":
		print("LOBBY_VIEWPORT ",app._online_results._viewport.size," stage=",app._online_results._stage.size," camera=",app._online_results._viewport.get_camera_3d()==app._online_results._camera)
	DirAccess.make_dir_recursive_absolute(output)
	var photo:Image = _phone.get_texture().get_image()
	check(photo.get_size()==Vector2i(2670,1200) and app.table_play_only,"capture uses actual phone-mode viewport")
	photo.save_png(output.path_join(name+".png"))
	var manifest := FileAccess.open(output.path_join(name+".json"),FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"kind":"desktop_phone_mode_live_game","viewport":[2670,1200],"logical":[1602,720],"screen":app._screen,"layout_sha256":FileAccess.get_sha256(app._table.LAYOUT_PATH),"real_enet_room_summaries":true,"characters":Packs.ORDER},"\t"))
