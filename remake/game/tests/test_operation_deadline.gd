extends "res://tests/test_presentation_receipts.gd"
## Reuse legal walls and authenticated animation gates; only the operation cutoff changes.

func _run()->void:
	await _discard_boundary()
	await _response_boundary()
	await _delegated_boundary()
	print("Operation deadline: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _playing(hands:Dictionary={},draw:String="wan9"):
	var host=_fixture(hands,draw)
	raw_ms+=20;check(_ack(host,"south"),"dealer opening finished")
	raw_ms+=20;check(_ack(host,"south"),"dealer draw finished")
	return host

func _inputs(host,prompt:int,seat:int)->Array:
	var record:Dictionary=host._session._record.export_authority() if host._session._record!=null else host.last_completed_record()
	return record.inputs.filter(func(event):return event.get("prompt_id")==prompt and event.get("seat")==seat)

func _discard_boundary()->void:
	var host=_playing()
	var view:Dictionary=host.view_for("south")
	var prompt:int=view.round.prompt_id
	var tile:int=view.round.choices.discard_ids[0]
	raw_ms=view.clock.deadline_ms
	host._process(0)
	check(not host.view_for("south").round.choices.is_empty(),"timer intent does not hide valid options at the exact cutoff")
	check(not host.submit("south",view.room.room_instance_id,1,prompt,"discard",999),"invalid exact-deadline tile is still rejected")
	check(host.submit("south",view.room.room_instance_id,1,prompt,"discard",tile),"legal request at the exact deadline remains valid after the timer tick")
	check(not host.submit("south",view.room.room_instance_id,1,prompt,"discard",tile),"duplicate exact-deadline request cannot execute twice")
	check(_inputs(host,prompt,1).size()==1,"one accepted action cancels its pending timeout")
	await _close(host)

	host=_playing();view=host.view_for("south");prompt=view.round.prompt_id;tile=view.round.choices.discard_ids[0]
	raw_ms=view.clock.deadline_ms+1
	check(not host.submit("south",view.room.room_instance_id,1,prompt,"discard",tile),"one millisecond late is rejected")
	for tick in 3000:
		await process_frame
		if host.view_for("south").round.prompt_id!=prompt:break
		OS.delay_msec(1)
	var actions:=_inputs(host,prompt,1)
	check(actions.size()==1 and actions[0].type=="timeout" and actions[0].action=="discard","late request still allows exactly one ordinary timeout discard")
	await _close(host)

func _response_boundary()->void:
	var host=_playing({0:"w1122334455667"},"wan7")
	var view:Dictionary=host.view_for("south")
	check(host.submit("south",view.room.room_instance_id,1,view.round.prompt_id,"discard",view.round.players[1].draw_id),"legal discard opens response")
	raw_ms+=20;check(_ack(host,"east"),"responder sees landed discard")
	view=host.view_for("east")
	check(view.round.choices.actions.has("win"),"responder has a genuine legal win")
	var prompt:int=view.round.prompt_id
	var tile:int=view.round.choices.tile_id
	raw_ms=view.clock.deadline_ms
	host._process(0)
	check(host.submit("east",view.room.room_instance_id,1,prompt,"win",tile),"winning response at deadline is not replaced by automatic pass")
	check(_inputs(host,prompt,0).any(func(event):return event.action=="win"),"accepted deadline win is recorded")
	await _close(host)

func _delegated_boundary()->void:
	var host=_playing()
	var view:Dictionary=host.view_for("south")
	var prompt:int=view.round.prompt_id
	host._ai_delay=15000
	check(host.set_auto_play("south",view.room.room_instance_id,1,true),"explicitly authorize continuous AI in fixture")
	for tick in 3000:
		await process_frame
		if host._decisions.has(1):break
		OS.delay_msec(1)
	check(host._decisions.has(1),"authorized worker is ready before cutoff")
	raw_ms=view.clock.deadline_ms
	await process_frame
	check(host.view_for("south").round.prompt_id!=prompt,"already-authorized AI decision at exact deadline never waits for a ruling")
	check(_inputs(host,prompt,1).size()==1,"AI deadline decision is accepted once")
	await _close(host)
