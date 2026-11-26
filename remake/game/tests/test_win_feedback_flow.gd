extends SceneTree
const Main=preload("res://scenes/Main.tscn")
const Settings=preload("res://src/app/AppSettings.gd")
const Round=preload("res://src/domain/Round.gd")
const Catalog=preload("res://src/domain/TileCatalog.gd")
const Retire=preload("res://tests/AudioRetirement.gd")
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL win flow: "+message)
func _initialize()->void:_run.call_deferred()
func _until(predicate:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+18000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame;OS.delay_msec(1)
	return predicate.call()
func _deck(red:int,owner:int)->Array:
	var probe:=Round.new();probe.start(1,red,2,Catalog.ordered_values())
	var values:=["wan1","wan1","wan1","wan2","wan2","wan2","wan3","wan3","wan3","wan4","wan4","wan4","wan5"]
	var fixed:={}
	for i in values.size():fixed[probe.players[owner].hand[i]]=values[i]
	fixed[probe.wall.peek_head()]="wan5"
	var remaining:=Catalog.ordered_values()
	for value in fixed.values():remaining.erase(value)
	var result:=[]
	for id in 108:result.append(fixed[id] if fixed.has(id) else remaining.pop_back())
	return result
func _case(self_draw:bool)->void:
	var folder:="user://feedback-flow-"+str(Time.get_ticks_usec());DirAccess.make_dir_absolute(folder)
	var app=Main.instantiate();app._settings=Settings.new(folder.path_join("profile.cfg"));app._settings.save_profile("反馈检查",1)
	root.add_child(app);await process_frame
	app._choose_mode("solo")
	var host=app._client._host
	host._dice.result_ready.disconnect(host._dice_settled)
	host._dice.result_ready.connect(func(red:int,_white:int):
		host._roll_valid=false;host._last_locked_dice=host._dice.snapshot()
		check(host._session.start_round(host._dice,_deck(red,1 if self_draw else 0),host._now(),1),"real dice and legal wall start feedback scenario")
		host._refresh(),CONNECT_ONE_SHOT)
	check(await _until(func():return app._choices().get("actions",[]).has("discard") and app._table.own_hand_stable()),"real opening and hand animation complete")
	if not app._choices().get("actions",[]).has("discard"):
		await Retire.release_app(app,self);return
	var game=host._session._round
	if self_draw:
		check(app._choices().actions.has("self_win"),"authority genuinely offers self-draw")
		app._pick_action("self_win")
	else:
		# Keep the real AI jobs from racing the deterministic response chosen below.
		host.set_process(false)
		app._submit_action("discard",int(game.players[1].draw_id))
		check(game.phase=="response" and game.choices(0).actions.has("win"),"real discarded tile opens a legal opponent win")
		for seat in [2,3]:
			var job:Dictionary=host._session.ai_job(seat,host._now())
			if not job.is_empty():host._session.submit_ai(job,"pass",-1,host._now())
		var job:Dictionary=host._session.ai_job(0,host._now())
		check(host._session.submit_ai(job,"win",-1,host._now()),"ordinary win is accepted through the normal session AI entry")
		host._refresh()
	await process_frame;await process_frame
	var flip_tile := str(app._round_projection.get("result", {}).get("flip_tile", ""))
	if not flip_tile.is_empty():
		check(app._round_projection.phase=="settled" and app._flip_reveal.visible and app._flip_reveal.flip_tile_value==flip_tile and app._screen=="play","flip chicken reveal appears clearly before settlement panel covers the board")
		check(app._win_feedback.visible and app._win_feedback._title.text==("自摸" if self_draw else "胡"),"real finish event triggers the matching reference-style presentation")
		app._flip_reveal.finish_now()
		await process_frame
	check(app._round_projection.phase=="settled" and app._screen=="settlement" and not app._flip_reveal.visible,"settlement screen appears cleanly right after flip chicken reveal completes")
	if flip_tile.is_empty():
		check(app._win_feedback.visible and app._win_feedback._title.text==("自摸" if self_draw else "胡"),"real finish event triggers the matching reference-style presentation")
	var facts:=JSON.stringify(game.export_authority())
	var tween:Tween=app._win_feedback._motion
	app._show_win_feedback(app._round_projection.result,app._win_feedback.last_key)
	check(app._win_feedback._motion==tween,"repeat finish snapshot does not restart the feedback")
	tween.pause();app._win_feedback._advance(0.35)
	var folder_out:=OS.get_environment("DONGXIU_REFERENCE_SCREENS")
	if not folder_out.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(folder_out);await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder_out.path_join("actual-self-draw.png" if self_draw else "actual-win.png"))
	check(JSON.stringify(game.export_authority())==facts,"feedback leaves the completed game and scoring facts untouched")
	tween.custom_step(2)
	check(not app._win_feedback.visible,"real game feedback retires completely")
	app._back_home();check(await Retire.release_app(app,self),"game and audio processes retire after the scenario")
func _run()->void:
	root.size=Vector2i(1280,720)
	await _case(true);await _case(false)
	print("%d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
