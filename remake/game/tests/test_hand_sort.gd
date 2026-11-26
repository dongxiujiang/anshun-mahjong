extends SceneTree
const Sort = preload("res://src/presentation/HandSort.gd")
const Order = preload("res://src/presentation/HandOrder.gd")
const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Wall = preload("res://src/domain/Wall.gd")
const Shared = preload("res://src/presentation/SharedHandDisplay.gd")
const Arrange = preload("res://src/presentation/HandArrangement.gd")
const Table = preload("res://src/presentation/TableView.gd")
const Main = preload("res://scenes/Main.tscn")
const Host = preload("res://src/runtime/GameHost.gd")
var checks := 0
var failures := 0
var raw_ms := 1000
func _initialize() -> void: run.call_deferred()
func check(ok: bool, note: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL hand sort: "+note)
func fixture(spec: String, draw: int = -1) -> Dictionary:
	var rows := []
	for seat in 4: rows.append({"seat":seat,"hand":[],"draw_id":-1,"ready":false,"discard_count":0,"melds":[],"discards":[]})
	for part in spec.split(" ",false):
		for digit in part.substr(1): rows[1].hand.append({"id":rows[1].hand.size(),"value":{"w":"wan","t":"tiao","b":"tong"}[part.left(1)]+digit})
	rows[1].draw_id=draw
	return {"viewer_seat":1,"players":rows,"phase":"turn","turn":1,"prompt_id":1,"choices":{"prompt_id":1,"actions":["discard"],"discard_ids":rows[1].hand.map(func(f):return f.id)},"last_discard":{}}
func winning_deck() -> Array:
	var probe := Wall.new(Catalog.values(697));probe.open(1,4)
	var cards := ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","tiao1","tiao2","tiao3","tong5"]
	var fixed := {}
	for index in cards.size():
		var offset: int=48 if index==12 else (index/4)*16+index%4
		fixed[(probe.break_index+offset)%108]=cards[index]
	fixed[(probe.break_index+52)%108]="tong5"
	var pool := Catalog.values(285)
	for value in fixed.values():pool.erase(value)
	var stock := []
	for index in 108:stock.append(fixed[index] if fixed.has(index) else pool.pop_back())
	return stock
func run() -> void:
	var view := fixture("w1122334455667")
	var safe := Sort.safe_view(view,["wan","tiao","tong"],"multiple")
	var before := view.duplicate(true)
	var plans: Array = Sort.calculate(safe).plans
	check(plans.size()>1 and plans[0].tier==0 and view==before,"all useful called decompositions precede hypothetical plans without mutating facts")
	var unique := {}
	for plan in plans:
		var ids: Array=plan.slots.duplicate();ids.sort()
		check(ids==range(13),"every sort plan contains exactly the owned physical entities")
		var signature: String=str(plan.slots)+plan.message+plan.structure
		check(not unique.has(signature),"cycling never duplicates an identical scheme")
		unique[signature]=true
		if plan.tier==2:
			var words:PackedStringArray=plan.message.trim_prefix("若摸到").split("，")
			check(words[0]!=words[1].trim_prefix("再打"),"a hypothetical replacement must change the value instead of inventing another identical scheme")
	view.players[0].hand=[{"id":100,"value":"wan9"}];view.wall_values=["wan9"]
	check(Sort.safe_view(view,["wan","tiao","tong"],"multiple")==safe,"hidden opponents and hidden wall cannot enter worker inputs")
	var full:=fixture("w123456789 t123 b55",13)
	full.choices.discard_ids=[0,13]
	var options: Array=Sort.calculate(Sort.safe_view(full,["wan","tiao","tong"],"pattern")).plans
	check(not options.is_empty() and options.all(func(p):return p.merge_draw and p.slots.back() in [0,13]),"post-draw schemes propose only server-legal discards")
	var pair_waits:Array=options.filter(func(p):return p.slots.back()==13 and p.tier==0)
	check(not pair_waits.is_empty() and pair_waits[0].remaining_total==2,"proposed discarded five-dot stays known: its matching wait has two remaining copies, not three")
	check(options[0].distance==options.map(func(p):return p.distance).min(),"when no direct call improves the hand, nearer-to-ready discard schemes are prioritized")
	var order:=Order.new();order.sync_hand("sort",1,1,full.players[1].hand,13)
	check(order.apply_sort_plan(options[0].slots,true) and order.view().draw_merged,"explicit sorting merges the drawn entity into the real display row")
	order.restore_order()
	check(order.view().slots.size()==14 and order.view().draw_merged and not order.view().manual,"restore keeps an already merged draw in the hand")
	var ready:=fixture("w123456789 t123 b55",13);ready.players[1].ready=true
	var locked: Array=Sort.calculate(Sort.safe_view(ready,["wan","tiao","tong"],"multiple")).plans
	check(locked.all(func(p):return not p.merge_draw and not p.slots.has(13) and p.tier!=2),"ready players only inspect the exact locked thirteen and never hypothetical replacement")
	var game:=Round.new();game.start(1,4,2,winning_deck());game.begin_dealer_turn()
	var prompt:int=game.prompt_id;var hand:Array=game.players[1].hand.duplicate();var wall: Dictionary=game.wall.snapshot()
	check(game.choices(1).actions.has("self_win") and game.submit(1,prompt,"sort"),"authority accepts sorting as an explicit self-draw decline")
	check(game.phase=="turn" and game.prompt_id==prompt and game.players[1].hand==hand and game.wall.snapshot()==wall,"decline does not discard, draw, or open a new timer prompt")
	check(not game.choices(1).actions.has("self_win") and not game.players[1].pass_win and not game.submit(1,prompt,"sort"),"one-shot self-win decline does not add an unready discard-win lock")
	var restored:=Round.new();check(restored.restore_authority(game.export_authority()) and not restored.choices(1).actions.has("self_win"),"authority recovery cannot restore the declined self win")
	game.players[1].ready=true;game.players[1].self_win_declined=false;game._turn_options={}
	check(game.submit(1,prompt,"sort") and game.players[1].draw_id<0 and game.players[1].pass_win,"ready sorting follows the existing pass/self-draw-only rule and discards the actual draw")
	await shared_motion()
	shared_merged()
	await host_clock()
	await live_controls()
	print("Hand sort: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
func shared_motion() -> void:
	var game:=Round.new();game.start(1,4,2,Catalog.values(541));game.begin_dealer_turn()
	var shared:=Shared.new(false);shared.sync(game)
	var owner:=Order.new();var own:Dictionary=game.snapshot_for(1).players[1]
	owner.sync_hand("motion",1,game.prompt_id,own.hand,own.draw_id)
	owner.begin_drag(owner.view().slots.back());owner.commit_drag(0);shared.accept(1,owner.view())
	var observers:=[]
	for seat in 4:
		var vp:=SubViewport.new();vp.own_world_3d=true;vp.size=Vector2i(1280,720);root.add_child(vp)
		var table:=Table.new(false);vp.add_child(table);observers.append(table)
		var initial:=game.snapshot_for(seat);shared.project(game,initial)
		table.apply_view(initial,owner.view() if seat==1 else {})
	var draw:int=game.players[1].draw_id
	game.submit(1,game.prompt_id,"discard",owner.view().slots[4]);shared.sync(game)
	var view:=game.snapshot_for(1);shared.project(game,view)
	owner.sync_hand("motion",1,game.prompt_id,view.players[1].hand,-1)
	var plan:=Arrange.new().arrange(view,owner.view())
	check(owner.apply_manual_insertion(plan.slots) and shared.accept(1,owner.view())==1,"client smart insertion is validated as a physical permutation by authority")
	for seat in 4:
		var current:=game.snapshot_for(seat);shared.project(game,current)
		var motion:Dictionary=current.players[1].display.motion
		check(motion.tile is String and motion.tile.length()==32 and not motion.has("value") and not motion.has("tile_id"),"shared animation contains opaque identities and no concealed values")
		var local_order:=owner.view();local_order.insertion=plan.insertion
		observers[seat].apply_view(current,local_order if seat==1 else {})
		var key:Variant=draw if seat==1 else motion.tile
		check(observers[seat]._motions.has(key),"each viewpoint animates the same retained physical draw")
		check(observers[seat].tiles.size()==108,"insertion never duplicates or drops a physical mesh")
		check(seat==1 or observers[seat].tiles[key].get_meta("value")=="","observers still see a concealed back throughout insertion")
		var tween: Tween=observers[seat]._motions[key]
		observers[seat].apply_view(current,local_order if seat==1 else {})
		check(observers[seat]._motions[key]==tween,"duplicate snapshots do not restart an insertion animation")
		observers[seat].get_parent().queue_free()
	await process_frame
func shared_merged() -> void:
	var game:=Round.new();game.start(1,4,2,Catalog.values(541));game.begin_dealer_turn()
	var shared:=Shared.new(false);shared.sync(game)
	var view:=game.snapshot_for(1);var own:Dictionary=view.players[1]
	var hand:=Order.new();hand.sync_hand("merged",1,game.prompt_id,own.hand,own.draw_id)
	var ids:Array=hand.view().slots+[own.draw_id]
	check(hand.apply_sort_plan(ids,true) and shared.accept(1,hand.view())==1,"authority accepts a merged draw as display state while retaining the real draw identity")
	for seat in 4:
		var snapshot:=game.snapshot_for(seat);shared.project(game,snapshot)
		check(snapshot.players[1].display.slots.size()==14 and snapshot.players[1].display.draw=="" and snapshot.players[1].display.motion.tile is String,"all views share a single merged row and an opaque insertion motion")
	shared.project(game,view)
	var recovered:=Order.new();recovered.sync_hand("merged",1,game.prompt_id,own.hand,own.draw_id)
	check(recovered.restore_shared(view.players[1].display) and recovered.view().draw_merged and recovered.view().slots.size()==14,"reconnect restores merged display without changing the authoritative draw")
func host_clock() -> void:
	var host:=Host.new();host.clock_msec=func():return raw_ms
	host.configure("sort-clock","solo",1,{"ai_delay_ms":300000,"presentation_ms":{"dealt":0,"turn":0,"response":0,"ready_draw":0}})
	root.add_child(host);host.join("sort-owner","排序测试","sort-client");host.set_ready("sort-client",true)
	var active:={}
	for step in 1800:
		await process_frame;raw_ms+=10
		active=host.view_for("sort-client")
		if active.get("round",{}).get("phase","")=="turn" and host._released.has(1):break
	check(active.get("round",{}).get("turn",-1)==1 and host._released.has(1),"real host starts a released human discard timer")
	# The surrounding host/clock are production objects; only the legal winning wall is deterministic.
	var winning:=Round.new();winning.start(1,4,2,winning_deck());winning.begin_dealer_turn()
	var prompt:int=active.round.prompt_id;winning.prompt_id=prompt
	host._session._round=winning;host._session._sync_display();host._refresh()
	var before:Dictionary=host.view_for("sort-client").clock.duplicate(true)
	check(host.submit("sort-client",active.room.room_instance_id,1,prompt,"sort"),"host authorizes an explicit sort through the normal command path")
	var after:Dictionary=host.view_for("sort-client").clock
	check(after.deadline_ms==before.deadline_ms and host._released.has(1) and winning.phase=="turn","sort neither resets the deadline nor consumes the discard permission")
	check(not host.submit("sort-client",active.room.room_instance_id,1,prompt,"sort"),"repeated packets cannot decline twice")
	host.shutdown();host.queue_free();await process_frame
func live_controls() -> void:
	var cfg := "user://hand-sort-live-%d.cfg" % Time.get_ticks_usec()
	var app = Main.instantiate()
	app._settings = load("res://src/app/AppSettings.gd").new(cfg)
	app._settings.save_profile("排序测", 1)
	root.add_child(app)
	await process_frame
	var profile = load("res://src/presentation/TableLayoutProfile.gd").new()
	profile.load_file("res://assets/layouts/table-layout.json")
	var rs = Round.new()
	rs.start(1, 4, 2, Catalog.values(541))
	rs.begin_dealer_turn()
	var snap: Dictionary = rs.snapshot_for(1)
	var members := []
	for seat in 4:
		members.append({"nickname": ["东秀", "牌友小明", "麻将搭子", "清风"][seat], "score": 200, "ai_id": seat, "connected": true, "player_id": "p-" + str(seat), "avatar": 1})
	app._screen = "play"; app.table_play_only = true; app._mode = "solo"
	app._table.custom_profile = profile
	app._table.region_placement = load("res://src/presentation/RegionPlacement.gd").new(profile)
	app._round_projection = snap
	app._view = {"seat": 1, "room": {"room_instance_id": "sort-live", "round_number": 1, "seats": members, "mode": "solo"}, "round": snap}
	app._order.sync_hand("sort-live", 1, int(snap.prompt_id), snap.players[1].hand, snap.players[1].draw_id)
	app._table.apply_view(snap, app._order.view())
	app._backdrop.hide(); app._hud.show(); app._frame.hide()
	app._refresh_hud()
	check(app._table.region_placement.profile == profile, "game uses the loaded layout profile")
	for i in 6:await process_frame
	app._sort_hand()
	var end:=Time.get_ticks_msec()+10000
	while app._sort_busy and Time.get_ticks_msec()<end:await process_frame;OS.delay_msec(1)
	check(not app._sort_plans.is_empty() and app._order.view().draw_merged and app._sort_status.text.begins_with("排法"),"live button receives asynchronous plans and renders both order and hint")
	for i in 25:await process_frame
	var limit:=Time.get_ticks_msec()+5000
	while not app._table.own_hand_stable() and Time.get_ticks_msec()<limit:await process_frame;OS.delay_msec(1)
	check(app._table._hand_slots.size()==14 and app._layout_warning=="","merged fourteen fit the authored hand-plus-draw space without a legacy fallback")
	var capture:=OS.get_environment("DONGXIU_SORT_CAPTURE")
	if not capture.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(capture)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.path_join("sort-game.png"))
	var count:int=app._sort_plans.size();var old_index:int=app._sort_index
	app._sort_hand()
	check(app._sort_index==posmod(old_index+1,count),"the visible sort button cycles the next real plan")
	limit=Time.get_ticks_msec()+5000
	while not app._table.own_hand_stable() and Time.get_ticks_msec()<limit:await process_frame;OS.delay_msec(1)
	var original:Array=app._order.view().slots.duplicate()
	app._restore_hand_order()
	check(app._sort_status.text=="" and app._order.view().slots.size()==original.size() and app._order.view().draw_merged,"live restore clears hints while retaining the merged draw")
	var old_scope:Dictionary=app._sort_scope()
	app._sort_scope_cache=old_scope;app._sort_busy=true
	var stable:Array=app._order.view().slots.duplicate()
	app._round_projection.prompt_id+=1
	app._sort_completed({"scope":old_scope,"plans":[{"slots":stable.duplicate(),"merge_draw":true,"message":"旧结果","structure":""}]})
	check(not app._sort_busy and app._sort_status.text=="" and app._order.view().slots==stable,"late results from an old prompt cannot overwrite the hand or leave sorting disabled")
	await load("res://tests/AudioRetirement.gd").release_app(app, self)
	DirAccess.remove_absolute(cfg)
