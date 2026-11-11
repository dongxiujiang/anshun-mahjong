extends SceneTree
## Graphical end-to-end acceptance. Run with -- --case=win or --case=draw.
const H=preload("res://tests/test_harness.gd")
var t=H.new()
var events={}
var capture_case := ""

class DrawOnly extends RefCounted:
	func decide_turn(round,seat): return {"discard":round.players[seat].just_drew}
	func decide_response(_round,_seat,_source,_tile,_options): return {"action":"pass"}

func _initialize():call_deferred("_run")
func _observe(event):
	var kind=str(event.get("type",""))
	events[kind]=int(events.get(kind,0))+1
	_capture_event.call_deferred("%03d-%s" % [int(event.get("id",0)),kind])

func _capture_event(label: String):
	await create_timer(0.05).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/change-20261112/full-" + capture_case + "/" + label + ".png")

func _run():
	if DisplayServer.get_name()=="headless":
		push_error("table_v2_full_round requires a graphical display")
		quit(1)
		return
	var kind="win"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):kind=arg.substr(7)
	capture_case = kind
	DirAccess.make_dir_recursive_absolute("res://build/change-20261112/full-"+kind)
	var config=root.get_node("GameConfig")
	config.set_tile_animation_seconds(0.15 if kind=="draw" else 0.54,false)
	config.set_settlement_speed("fast",false)
	var table=load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	if kind=="draw":table.round.set_ai_service(null)
	var actor=load("res://scripts/ai/AiPlayer.gd")
	for seat in 4:table.round.controllers[seat]=DrawOnly.new() if kind=="draw" else actor.new("accept%d" % seat,"low")
	table.round.ai_delay_seconds=0.35 if kind=="draw" else 0.8
	table.round.ai_response_delay_seconds=0.35 if kind=="draw" else 0.8
	table.round.set_rng_seed(42)
	table.round.visual_event.connect(_observe)
	table.round.start_round(table.human_seat,3,2)
	var deadline=Time.get_ticks_msec()+100000
	var progress_at=Time.get_ticks_msec()+10000
	while table.round.phase!=RoundState.Phase.SETTLED and Time.get_ticks_msec()<deadline:
		await process_frame
		if Time.get_ticks_msec()>=progress_at:
			print("[full-round] kind=",kind," wall=",table.round.wall.remaining," events=",events)
			progress_at+=10000
	t.expect(table.round.phase==RoundState.Phase.SETTLED,"real graphical round reaches settlement")
	if table.round.phase==RoundState.Phase.SETTLED:
		t.expect(int(table.round.round_meta.winner)<0 if kind=="draw" else int(table.round.round_meta.winner)>=0,"expected exhaustion or winning finish")
		t.expect(is_zero_approx(float(table.round.last_result.total_delta)),"settlement preserves total score")
		deadline=Time.get_ticks_msec()+30000
		var premature_controls=false
		while (not table._new_areas.native_settlement_started() or not table._new_areas.native_settlement_complete()) and Time.get_ticks_msec()<deadline:
			if table._settlement_card._post_controls.visible:premature_controls=true
			await process_frame
		t.expect(not premature_controls,"next-round controls never flash before settlement starts or finishes")
		t.expect(table._new_areas.native_settlement_started() and table._new_areas.native_settlement_complete(),"native staged settlement completes")
		t.expect(table._settlement_card._post_controls.visible,"next-round controls unlock after animation")
		if not bool(table.round.round_meta.get("all_called_draw",false)):
			var all_public=true
			for seat in 4:
				for node in table._new_areas.hand_boxes[seat].get_children():
					if not node.face_up or node.tile=="":all_public=false
			t.expect(all_public,"settlement hand values are public at all four seats")
		t.expect(not table._table_animation_controller.has_pending(),"no native flight remains at settlement completion")
		await _capture_event("settlement")
		var scores=table.round.players.map(func(player):return player.score)
		var dealer=table.round.next_dealer_seat
		table._next_round()
		table.round.controllers=[null,null,null,null]
		deadline=Time.get_ticks_msec()+20000
		while (table.round.pause_after_opening or table._table_animation_controller.input_locked()) and Time.get_ticks_msec()<deadline:await process_frame
		t.expect(table._round_number==2 and table.round.phase==RoundState.Phase.PLAYING,"next round completes opening and reaches playable turn")
		t.expect(table.round.dealer_seat==dealer and table.round.players.map(func(player):return player.score)==scores,"next round preserves dealer and cumulative scores")
		t.expect(not table._new_areas.native_settlement_started() and not table._settlement_card._post_controls.visible,"next round clears previous settlement and controls")
		t.expect(table._new_areas.hand_boxes[dealer].get_child_count()==13 and table._new_areas.draw_boxes[dealer].get_child_count()==1,"next dealer finishes opening with 13 plus one drawn tile")
	print("[full-round] completed kind=",kind," events=",events)
	if table._ai_service!=null:table._ai_service.stop()
	table.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	await H.quit_cleanly(self,t.finish("table_v2_full_round"))
