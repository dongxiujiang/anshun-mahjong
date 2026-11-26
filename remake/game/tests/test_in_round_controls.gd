extends SceneTree
const Table=preload("res://src/presentation/TableView.gd")
const Order=preload("res://src/presentation/HandOrder.gd")
const Round=preload("res://src/domain/Round.gd")
const Catalog=preload("res://src/domain/TileCatalog.gd")
const Clock=preload("res://src/app/TurnClockView.gd")
const Main=preload("res://scenes/Main.tscn")
const Settings=preload("res://src/app/AppSettings.gd")
const Match=preload("res://src/session/MatchSession.gd")
const Dice=preload("res://src/runtime/DiceRoll.gd")
const Wall=preload("res://src/domain/Wall.gd")
const Retire=preload("res://tests/AudioRetirement.gd")
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL in-round: "+message)
func _initialize()->void:run.call_deferred()
func capture(name:String)->void:
	var folder:=OS.get_environment("DONGXIU_IN_ROUND_SCREENS")
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(folder);await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func run()->void:
	root.size=Vector2i(1280,720)
	var table=Table.new();root.add_child(table);await process_frame
	for seat in 4:table.custom_profile.data.regions[str(seat)+"/wall"].z=11.0
	var game=Round.new();game.start(1,4,2,Catalog.values(418));game.begin_dealer_turn()
	var view:Dictionary=game.snapshot_for(1);table.apply_view(view);table._render(false)
	var facts:=JSON.stringify(game.export_authority())
	for viewer in 4:
		table.set_viewer(viewer)
		check(table.is_discard_point(Vector3(0,0,8.5)),"new wall coordinates expand the shared discard gesture area for every observer")
		check(not table.is_discard_point(Vector3(0,0,10.2)),"a physical wall is not a discard release target")
		check(not table.is_discard_point(Vector3(12,0,0)),"outside the enclosing walls returns the held card")
	table.set_viewer(1);table.apply_view(view);table._render(false)
	var ids:=[];table.swipe_discard.connect(func(id):ids.append(id))
	var id:int=game.players[1].draw_id
	var source:Vector2=table.camera.unproject_position(table.tiles[id].position)
	var destination:Vector2=table.camera.unproject_position(Vector3(0,0,8.5))
	check(table.is_discard_point(table._world_point(destination,0)),"current lens maps the release back inside the authored walls even if hand-drop tolerance overlaps")
	check(table._press(source,0,false),"real independent draw accepts its physical touch")
	if table._press_id==id:
		table._motion(destination);table._release(destination)
		check(ids==[id],"swipe from independent draw emits that exact ID inside the newly configured walls")
	else:check(false,"new-area swipe fixture must pick the independent draw")
	table._render(false)
	source=table.camera.unproject_position(table.tiles[id].global_position)
	var held_before: Vector3=table.tiles[id].position
	check(table._press(source,0,false),"quick swipe starts on draw")
	var bounds: Rect2=table._screen_bounds(table._hand_slots[0])
	var quick:=Vector2(source.x,bounds.position.y-bounds.size.y*0.7)
	table._motion(quick)
	check(table._discard_dragging and not table.tiles[id].position.is_equal_approx(held_before),"upward gesture follows immediately without a hold")
	table._motion(source);table._release(source)
	check(ids==[id],"pulling back cancels the discard")
	table._render(false)
	source=table.camera.unproject_position(table.tiles[id].global_position)
	table._press(source,0,false);table._motion(quick);table._release(quick)
	check(ids==[id,id],"short upward swipe beyond hand line discards")
	table._render(false)
	var slots_seen:=[]
	table.drag_slot_changed.connect(func(slot):slots_seen.append(slot))
	var row_id:int=view.players[1].hand[0].id
	source=table.camera.unproject_position(table.tiles[row_id].global_position)
	table._press(source,0,false)
	var held_point=table._held_point(source)
	var local_held:Vector3=Table.Layout.facing(1).inverse()*Vector3(held_point)
	check(local_held.z>13.8 and local_held.z<=table.table_edge(),"held plane reaches the foreground hand inside the enlarged table")
	var right:=source+Vector2(table._tap_slop()*2,0)
	table._motion(right)
	check(table._dragging,"horizontal movement starts sorting immediately")
	var edge:Rect2=table._screen_bounds(table._hand_slots[table._hand_slots.size()-1])
	var edge_point:=Vector2(edge.end.x+edge.size.x*0.5,edge.get_center().y)
	table._motion(edge_point)
	check(not slots_seen.is_empty() and slots_seen.back()==table._hand_slots.size()-1,"near right edge clamps to last slot")
	table._release(edge_point)
	table._render(false)
	source=table.camera.unproject_position(table.tiles[row_id].global_position)
	table._press(source,0,false);table._motion(source-Vector2(table._tap_slop()*2,0))
	edge=table._screen_bounds(table._hand_slots[0])
	edge_point=Vector2(edge.position.x-edge.size.x*0.5,edge.get_center().y)
	table._motion(edge_point)
	check(slots_seen.back()==0,"near left edge clamps to first slot")
	table._release(edge_point)
	table._render(false)
	var waiting:=view.duplicate(true);waiting.choices.discard_ids=[]
	table.apply_view(waiting);table._render(false)
	var clicks:=[];table.tile_clicked.connect(func(tile):clicks.append(tile))
	source=table.camera.unproject_position(table.tiles[row_id].global_position)
	table._press(source,0,false);table._release(source)
	table._press(source,0,false);table._motion(quick);table._release(quick)
	check(clicks.is_empty() and ids==[id,id],"off turn tap and upward motion cannot select or discard")
	table.apply_view(view)
	var order:=Order.new();order.sync_hand("gesture",1,view.prompt_id,view.players[1].hand,id)
	table.set_hand_order(order.view());table._render(false)
	table.drag_started.connect(func(tile):order.begin_drag(tile);table.set_hand_order(order.view()))
	table.drag_slot_changed.connect(func(slot):order.move_gap(slot);table.set_hand_order(order.view()))
	table.drag_finished.connect(func(slot):order.commit_drag(slot);table.set_hand_order(order.view()))
	var separate_pose:Transform3D=table.tiles[id].transform
	source=table.camera.unproject_position(table.tiles[id].global_position)
	var middle:Vector2=table.camera.unproject_position(table._hand_slots[3].origin)
	table._press(source,0,false);table._motion(middle)
	check(order.view().dragged_id==id and order.view().draw_merged,"direct draw drag enters merged preview")
	table._release(source);table._render(false)
	check(not order.view().draw_merged and table.tiles[id].transform.is_equal_approx(separate_pose),"cancel restores the separate draw and original spacing")
	source=table.camera.unproject_position(table.tiles[id].global_position)
	table._press(source,0,false);table._motion(middle);table._release(middle)
	check(order.view().draw_merged and order.view().slots[3]==id,"direct draw drag inserts at the chosen slot")
	check(JSON.stringify(game.export_authority())==facts,"display gestures do not execute an unvalidated rule action")
	table.free()
	var clock:=Clock.new();root.add_child(clock);clock.size=Vector2(104,122)
	var timing:={"phase":"countdown","remaining_ms":5000,"duration_ms":5000,"reminder":false,"kind":"response"}
	var unchanged:=timing.duplicate(true)
	clock.show_clock(timing,{"phase":"response"},1)
	check(clock._number.text=="5" and clock._caption.text=="请选择" and is_equal_approx(clock._fraction,1),"response clock shows the server's configured full duration")
	clock.show_clock(timing,{"phase":"turn","turn":1},1)
	check(clock._caption.text=="自摸选择","self-draw response is not presented as a discard turn")
	clock.show_clock(timing,{"phase":"turn","turn":1},2)
	check(clock._caption.text=="等待自摸选择","other observers see the self-draw decision as waiting")
	clock.show_clock({"phase":"waiting_animation","remaining_ms":-1},{"phase":"turn","turn":1},1)
	check(clock._caption.text=="等待动画" and clock._number.text=="·","animation barrier never tells the player to discard or starts a countdown")
	clock.show_clock({}, {"phase":"response"},1)
	check(clock._caption.text=="等待响应","players without a response timer see a waiting caption")
	clock.show_clock({"phase":"countdown","remaining_ms":10000,"kind":"discard"},{"phase":"turn","turn":1},1)
	check(clock._caption.text=="请出牌" and clock._number.text=="10","a discard clock still displays the actual discard turn")
	clock.show_clock({"phase":"grace","remaining_ms":4000,"duration_ms":5000,"reminder":true},{"phase":"turn","turn":1},1)
	check(clock._caption.text=="额外等待" and clock._number.text=="4" and clock._reminder,"extra waiting has its own readable state without resetting authority timing")
	check(timing==unchanged,"clock presentation preserves its input")
	clock.show_clock({}, {"phase":"settled"},1);check(not clock.visible,"ended rounds retire the clock")
	clock.free()
	var configured_url=ProjectSettings.get_setting("dongxiu/online_directory_url","")
	ProjectSettings.set_setting("dongxiu/online_directory_url","")
	var app=Main.instantiate();app.table_play_only=true;app._settings=Settings.new("user://in-round-controls.cfg");app._settings.save_profile("牌桌测试",1)
	root.add_child(app);await process_frame;await process_frame
	check(app._screen=="connect" and not app._board.visible and app._mode=="online" and app._client._host==null,"phone startup opens the new lobby without a fake local authority")
	check(app._online_results!=null and app._client.ticket.is_empty(),"startup offers real room selection rather than automatically joining")
	var match_game:=Match.new("in-round-result")
	var joined:Dictionary=match_game.join("winner","牌桌测试","host",100)
	match_game.set_ready("host",true,100)
	var dice:=Dice.new();root.add_child(dice);dice.roll(31605)
	for tick in 1800:
		await physics_frame
		if dice.phase=="settled":break
	check(dice.phase=="settled","settlement fixture uses an actual settled dice result")
	if dice.phase=="settled" and match_game.start_round(dice,winning_deck(int(dice.snapshot().result[0])),100,1):
		var state:Dictionary=match_game.view_for("host",100)
		match_game.begin_dealer_turn(joined.ticket.room_instance_id,1,state.round.prompt_id,100)
		state=match_game.view_for("host",100)
		check(match_game.submit("host",joined.ticket.room_instance_id,1,state.round.prompt_id,"self_win",-1,100),"real scoring authority accepts the fixture's legal self draw")
		var final:Dictionary=match_game.view_for("host",100)
		var original:=JSON.stringify(final.settlement)
		app._view_changed(final);await process_frame;await process_frame
		check(app._screen=="settlement" and app._board.anchor_left==0 and app._frame.anchor_right==1,"settlement keeps the full table behind its center overlay")
		var panel=app._frame.get_child(0)
		check(panel._table_overlay and panel.find_children("*","ScrollContainer",true,false).is_empty(),"all four result rows display together without a details switch or scrolling")
		check(panel.find_children("*","Button",true,false).all(func(button):return button.text!="返回座位"),"result controls do not expose the hidden seat page")
		for resolution in [Vector2i(1280,720),Vector2i(2400,1080),Vector2i(2670,1200)]:
			root.size=resolution;await process_frame;await process_frame;app._fit_safe_area();await process_frame
			check(app._safe.get_global_rect().grow(1).encloses(panel.get_global_rect()),"center result panel fits the landscape safe area")
			check(panel.size.y<app._safe.size.y*0.58,"compact result rows preserve space for the opposite and own hand")
			for badge in app._settlement_names.badges:
				check(not badge.get_global_rect().intersects(panel.get_global_rect()),"fixed result names stay outside the score panel")
			for node in app._table.tiles.values():
				if node.get_meta("zone","")!="hand":continue
				var hand_bounds:=Rect2()
				for corner in 8:
					var point:Vector2=app._table.camera.unproject_position(node.global_transform*node.get_aabb().get_endpoint(corner))*app._board.size/Vector2(app._board_world.size)
					hand_bounds=Rect2(point,Vector2.ZERO) if corner==0 else hand_bounds.expand(point)
				check(not panel.get_global_rect().intersects(hand_bounds),"score panel leaves rendered hand tiles clear")
			await capture("settlement-%dx%d"%[resolution.x,resolution.y])
		check(JSON.stringify(final.settlement)==original,"the reference-style result view never changes amounts or immutable result membership")
	else:check(false,"legal result fixture starts")
	dice.queue_free();check(await Retire.release_app(app,self),"in-round UI and audio resources retire")
	ProjectSettings.set_setting("dongxiu/online_directory_url",configured_url)
	print("%d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func winning_deck(red:int)->Array:
	var probe:=Wall.new(Catalog.values(697));probe.open(1,red)
	var cards:=["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","tiao1","tiao2","tiao3","tong5"]
	var fixed:={}
	for index in cards.size():
		var offset:=48 if index==12 else (index/4)*16+index%4
		fixed[(probe.break_index+offset)%108]=cards[index]
	fixed[(probe.break_index+52)%108]="tong5"
	var pool:=Catalog.values(285)
	for value in fixed.values():pool.erase(value)
	var stock:=[]
	for index in 108:stock.append(fixed[index] if fixed.has(index) else pool.pop_back())
	return stock
