extends Node
## Device benchmark: legal recorded actions, real table and animation paths.
var table
var stage := ""
var last_tick := 0
var samples := {}
var events := {}
var slow_frames := []
var action_index := -1
var output := ""
var result := {}

func _ready(): call_deferred("run")
func _process(_delta):
	var now := Time.get_ticks_usec()
	if stage != "" and last_tick > 0:
		var ms := (now-last_tick)/1000.0
		samples[stage].frames.append(ms)
		samples[stage].draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if ms>33.4: slow_frames.append({"stage":stage,"action":action_index,"ms":ms})
	last_tick=now

func change_stage(value: String):
	stage=value
	if value!="" and not samples.has(value): samples[value]={"frames":[],"draws":[]}
	last_tick=Time.get_ticks_usec()

func summary(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0}
	var sorted:=values.duplicate()
	sorted.sort()
	var total:=0.0
	for value in values: total+=value
	return {"count":values.size(),"mean":total/values.size(),"p95":sorted[int(values.size()*.95)],"p99":sorted[int(values.size()*.99)],"max":sorted[-1],"over33":values.filter(func(v):return v>33.4).size(),"over50":values.filter(func(v):return v>50).size()}

func screenshot(label: String):
	var previous:=stage
	change_stage("")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output+"/"+label+".png")
	for i in 4: await get_tree().process_frame
	change_stage(previous)

func wait_visual() -> bool:
	var deadline:=Time.get_ticks_msec()+20000
	await get_tree().process_frame
	while table.round.pause_after_opening or table._table_animation_controller.has_pending():
		if Time.get_ticks_msec()>deadline: return false
		await get_tree().process_frame
	return true

func fail(reason: String):
	change_stage("")
	result.error=reason
	finish()

func finish():
	change_stage("")
	result["stages"]={}
	for key in samples:
		result.stages[key]={"frame_ms":summary(samples[key].frames),"draw_calls":summary(samples[key].draws)}
		result.stages[key]["fps"]=1000.0/result.stages[key].frame_ms.get("mean",1000.0)
	result["slow_frames"]=slow_frames
	result["events"]=events
	result["accepted_actions"]=action_index+1
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("[mobile-perf] ",JSON.stringify(result))
	set_process(false)
	get_tree().quit(1 if result.has("error") else 0)

func run():
	output=str(ProjectSettings.get_setting("performance/output","res://build/performance-sample"))
	DirAccess.make_dir_recursive_absolute(output)
	result={"label":ProjectSettings.get_setting("performance/label","desktop"),"resolution":get_viewport().size,"engine":Engine.get_version_info().string,"mode":"legal recorded offline game"}
	Engine.max_fps=60
	var config=get_node("/root/GameConfig")
	config.set_tile_animation_seconds(0.2,false)
	config.set_settlement_speed("0.7",false)
	config.set_score_details_enabled(false,false)
	table=load("res://scenes/GameTable.tscn").instantiate()
	add_child(table)
	table.round.controllers=[null,null,null,null]
	table.round.cancel_ai()
	var record: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mobile_performance_round.json"))
	table.round.set_rng_seed(int(record.seed))
	table.round.next_dealer_seat=int(record.dealer)
	table.round.visual_event.connect(func(event):
		var kind=str(event.get("type",""))
		events[kind]=int(events.get(kind,0))+1)
	change_stage("opening")
	table.round.start_round(table.human_seat,int(record.red),int(record.white))
	if not await wait_visual(): fail("opening timeout"); return
	change_stage("idle")
	await get_tree().create_timer(5.0).timeout
	await screenshot("01-dealt")
	change_stage("play")
	for i in record.actions.size():
		action_index=i
		var action: Dictionary=record.actions[i]
		var accepted: bool=table.round.submit_turn(int(action.seat),action.decision) if action.kind=="turn" else table.round.submit_response(int(action.seat),str(action.tile),action.decision)
		if not accepted: fail("rejected action %d"%i); return
		if table.round.phase==RoundState.Phase.SETTLED: break
		if not await wait_visual(): fail("animation timeout at %d"%i); return
		await get_tree().create_timer(0.8 if action.kind=="turn" else 0.2).timeout
		if i in [20,50]: await screenshot("%02d-play"%i)
	if table.round.phase!=RoundState.Phase.SETTLED: fail("round did not settle"); return
	change_stage("settlement")
	var deadline:=Time.get_ticks_msec()+45000
	while not table._new_areas.native_settlement_started() or not table._new_areas.native_settlement_complete():
		if Time.get_ticks_msec()>deadline: fail("settlement timeout"); return
		await get_tree().process_frame
	await screenshot("04-settlement")
	change_stage("settled_idle")
	await get_tree().create_timer(5.0).timeout
	result["score_total"]=table.round.last_result.total_delta
	result["settled"]=true
	finish()
