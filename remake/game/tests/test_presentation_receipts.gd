extends "res://tests/test_match_session.gd"
## 固定骰子结果仅作合法牌局夹具；本专项验证回执、起钟及一次性代打。
const Host = preload("res://src/runtime/GameHost.gd")
const Client = preload("res://src/network/GameClient.gd")
const Ai = preload("res://src/ai/AiPlayer.gd")
const Record = preload("res://src/session/RoundRecord.gd")
var raw_ms := 1000

func _run() -> void:
	var probe := Host.new()
	check(probe.has_method("acknowledge_presentation"), "authority must accept authenticated animation receipts")
	root.add_child(probe);probe.shutdown();probe.free()
	if failures:
		print("Presentation receipts: %d checks, %d failures" % [checks, failures]);quit(1);return
	await _receipts()
	await _fallback()
	await _multiple_responses()
	await _restore_wait()
	await _job_scope()
	await _ready_choice()
	await _transport()
	print("Presentation receipts: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _fixture(hands:Dictionary={},draw:String="wan9"):
	raw_ms=1000
	var host:=Host.new();root.add_child(host)
	check(host.configure("734256","online",1,{"difficulty":"low","external_presentation":true,"ai_delay_ms":0,
		"presentation_ms":{"dealt":20,"turn":20,"response":20,"ready_draw":20}}),"configure receipt authority")
	host.clock_msec=func():return raw_ms
	var joined:Dictionary=host.join("south-member","南","south")
	host.set_meta("south_ticket",joined.ticket)
	host.join("east-member","东","east")
	if hands.has(3):host.join("north-member","北","north");host.set_ready("north",true)
	host.set_ready("south",true);host.set_ready("east",true)
	host._prepare_at=-1
	_fixed_dice(host._dice)
	check(host._session.start_round(host._dice,_deck(1,5,hands,draw),raw_ms,1),"start legal fixed wall")
	host._refresh()
	return host

func _fixed_dice(value)->void:
	value.phase="settled";value.roll_id=1;value._frame=1;value._result.assign([5,2])
	for index in 2:
		value.dice[index].freeze=true
		value.dice[index].position=Vector3(-0.4+index*0.8,Dice.SIDE*0.5,0)
		value.dice[index].quaternion=Quaternion(Dice.FACE_NORMALS[value._result[index]-1],Vector3.UP)

func _ack(host,connection:String)->bool:
	var view:Dictionary=host.view_for(connection)
	return host.acknowledge_presentation(connection,view.room.room_instance_id,view.room.round_number,view.round.prompt_id)

func _close(host)->void:
	host.shutdown();host.queue_free();await process_frame

func _receipts()->void:
	var host=_fixture()
	var initial:Dictionary=host.view_for("south")
	var instance_id:String=initial.room.room_instance_id
	raw_ms+=500
	await process_frame
	check(host.view_for("south").round.phase=="dealt","online opening does not advance on estimated duration")
	check(not host.acknowledge_presentation("east",instance_id,1,initial.round.prompt_id),"other seat cannot acknowledge dealer animation")
	check(not host.acknowledge_presentation("unknown",instance_id,1,initial.round.prompt_id),"unknown connection rejected")
	check(_ack(host,"south"),"dealer reports actual finished opening")
	var turn:Dictionary=host.view_for("south")
	check(turn.clock.phase=="waiting_animation" and turn.round.choices.is_empty(),"draw choices and timer wait for actual draw")
	raw_ms+=700
	await process_frame
	check(host.view_for("south").clock.phase=="waiting_animation","estimated draw end cannot consume choice time")
	check(_ack(host,"south"),"draw receipt starts full operation timer")
	var opened:Dictionary=host.view_for("south")
	var deadline:int=opened.clock.deadline_ms
	check(deadline==raw_ms+15000,"normal discard retains full ten plus five seconds")
	check(not _ack(host,"south") and host.view_for("south").clock.deadline_ms==deadline,"duplicate receipt never restarts timer")
	check(not host.acknowledge_presentation("south",instance_id,1,initial.round.prompt_id),"old cue cannot release new prompt")
	await _close(host)

func _fallback()->void:
	var host=_fixture({1:"w123456789 t123 b5"},"tong5")
	raw_ms+=20;check(_ack(host,"south"),"open winning fixture")
	var waiting:Dictionary=host.view_for("south")
	var prompt:int=waiting.round.prompt_id
	check(host._session.view_for("south",raw_ms).round.choices.actions.has("self_win"),"human really has a legal self win")
	raw_ms+=9999;await process_frame
	check(host.view_for("south").round.prompt_id==prompt and not host.view_for("south").has("settlement"),"no early takeover before ten seconds")
	raw_ms+=1
	for tick in 3000:
		await process_frame
		if host.view_for("south").has("settlement"):break
		OS.delay_msec(1)
	var ended:Dictionary=host.view_for("south")
	check(ended.has("settlement") and ended.settlement.ledger.winners.has(1),"animation timeout AI can win instead of being restricted to discard")
	check(not ended.room.seats[1].auto_play,"one animation timeout does not enable continuous delegation")
	check(Record.replay(host.last_completed_record()).get("ok",false),"fallback action replays with same scoring and conservation")
	check(not host.acknowledge_presentation("south",waiting.room.room_instance_id,1,prompt),"late receipt cannot resurrect ended operation")
	await _close(host)

	# Expired opening advances to its dealer action without a second ten-second wait.
	host=_fixture({1:"w123456789 t123 b5"},"tong5")
	raw_ms+=10000
	for tick in 3000:
		await process_frame
		if host.view_for("south").has("settlement"):break
		OS.delay_msec(1)
	check(host.view_for("south").has("settlement"),"opening timeout takes just the next real dealer decision")
	await _close(host)

func _transport()->void:
	var server:=Client.new();server.name="ReceiptServer";root.add_child(server)
	check(server.start_server("734257",0,{"difficulty":"low","start_delay_ms":3000,"presentation_ms":{"dealt":20,"turn":20,"response":20,"ready_draw":20}},"online"),"real ENet server")
	server._host.clock_msec=func():return raw_ms
	var south:=Client.new();south.name="ReceiptSouth";root.add_child(south)
	check(south.connect_room("127.0.0.1",server.local_port,{"player_id":"receipt-member","nickname":"南","room_number":"734257"}),"real ENet client")
	for tick in 3000:
		await process_frame
		if not south.view.is_empty():break
		OS.delay_msec(1)
	check(not south.view.is_empty(),"authenticated view arrives")
	if not south.view.is_empty():
		south.set_ready(true)
		for tick in 30:await process_frame;OS.delay_msec(1)
		var host=server._host
		host._prepare_at=-1
		_fixed_dice(host._dice)
		check(host._session.start_round(host._dice,_deck(1,5,{},"wan9"),raw_ms,1),"network legal opening")
		host._refresh()
		for tick in 100:await process_frame;OS.delay_msec(1)
		raw_ms+=5000
		for tick in 20:await process_frame;OS.delay_msec(1)
		check(south.view.round.phase=="dealt","server really waits for remote receipt")
		south.finish_presentation(south.view.presentation)
		for tick in 3000:
			await process_frame
			if south.view.round.phase=="turn":break
			OS.delay_msec(1)
		check(south.view.round.phase=="turn","actual client RPC releases dealer opening")
		raw_ms+=500
		var pending_cue:Dictionary=south.view.presentation.duplicate(true)
		south.finish_presentation(south.view.presentation)
		for tick in 3000:
			await process_frame
			if not south.view.round.choices.is_empty():break
			OS.delay_msec(1)
		check(not south.view.round.choices.is_empty() and south.view.clock.phase=="countdown","actual remote draw receipt opens full timer")
		# The high-level connection may still look connected after ENet closes its channels.
		south.view.presentation=pending_cue;south._finished_cue=""
		var previous_requests:int=south._request_id
		south._peer.get_peer(1).reset()
		south.finish_presentation(pending_cue)
		check(south._request_id==previous_requests,"late receipt never calls RPC on closed ENet channels")
	south.leave();server.leave();south.queue_free();server.queue_free();await process_frame

func _multiple_responses()->void:
	var host=_fixture({0:"w1122334455667",3:"w1122334455667"},"wan7")
	raw_ms+=20;check(_ack(host,"south"),"open multi-human response fixture")
	raw_ms+=20;check(_ack(host,"south"),"finish dealer draw before legal discard")
	var view:Dictionary=host.view_for("south")
	check(host.submit("south",view.room.room_instance_id,1,view.round.prompt_id,"discard",view.round.players[1].draw_id),"discard actual winning tile")
	check(host._session.view_for("east",raw_ms).round.choices.actions.has("win") and host._session.view_for("north",raw_ms).round.choices.actions.has("win"),"two distinct human seats can legally win this discard")
	raw_ms+=9999;await process_frame
	check(not host.view_for("south").has("settlement"),"neither pending human response expires early")
	raw_ms+=1
	for tick in 3000:
		await process_frame
		if host.view_for("south").has("settlement"):break
		OS.delay_msec(1)
	var final_view:Dictionary=host.view_for("south")
	check(final_view.has("settlement") and final_view.settlement.ledger.winners.has(0) and final_view.settlement.ledger.winners.has(3),"same-window fallback jobs do not overwrite each other's authority")
	check(Record.replay(host.last_completed_record()).get("ok",false),"multiple timeout decisions preserve replay and ledger")
	await _close(host)

func _restore_wait()->void:
	var host=_fixture({1:"w123456789 t123 b5"},"tong5")
	raw_ms+=20;check(_ack(host,"south"),"open handover wait fixture")
	raw_ms+=7000
	var backup:Dictionary=host.export_authority()
	var ticket:Dictionary=host.get_meta("south_ticket")
	await _close(host)
	var restored:=Host.new();root.add_child(restored)
	var clock_box:=[200000]
	restored.clock_msec=func():return clock_box[0]
	check(restored.restore_authority(backup),"restore authority and rebase pending animation deadline")
	check(not restored.resume(ticket.room_instance_id,ticket.player_id,ticket.member_token,"resumed").is_empty(),"same member binds restored authority")
	check(restored.acknowledge_foreground_view("resumed",ticket.room_instance_id,0),"fresh synchronized foreground on new authority")
	clock_box[0]+=2999;await process_frame
	check(restored.view_for("resumed").clock.phase=="waiting_animation","handover retains remaining time instead of immediately taking over")
	clock_box[0]+=1
	for tick in 3000:
		await process_frame
		if restored.view_for("resumed").has("settlement"):break
		OS.delay_msec(1)
	check(restored.view_for("resumed").has("settlement"),"handover does not reset ten-second waiting allowance")
	await _close(restored)

func _job_scope()->void:
	var host=_fixture({1:"w123456789 t123 b5"},"tong5")
	raw_ms+=20;check(_ack(host,"south"),"open scoped job fixture")
	var view:Dictionary=host.view_for("south")
	var intent:={"room_instance_id":view.room.room_instance_id,"round_number":1,"prompt_id":view.round.prompt_id,"seat":1,"deadline_ms":raw_ms+10000}
	check(host._session.animation_timeout_job(intent,raw_ms).is_empty(),"cannot issue one-shot work before its animation deadline")
	raw_ms+=10000
	var job:Dictionary=host._session.animation_timeout_job(intent,raw_ms)
	check(not job.is_empty() and job.view.players[0].hand.is_empty(),"worker receives only its seat's visible information")
	var edited:Dictionary=job.duplicate(true);edited.animation_nonce="forged"
	check(not host._session.submit_animation_timeout(edited,"self_win",-1,raw_ms),"unissued work is rejected")
	var ticket:Dictionary=host.get_meta("south_ticket")
	check(not host.resume(ticket.room_instance_id,ticket.player_id,ticket.member_token,"new-south").is_empty(),"new connection replaces old connection during computation")
	check(not host._session.submit_animation_timeout(job,"self_win",-1,raw_ms),"old worker cannot act after connection ownership changes")
	job=host._session.animation_timeout_job(intent,raw_ms)
	check(not job.is_empty() and host._session.submit_animation_timeout(job,"self_win",-1,raw_ms),"fresh authority can commit one still-legal action")
	check(not host._session.submit_animation_timeout(job,"self_win",-1,raw_ms),"same capability cannot be used twice")
	await _close(host)

func _ready_choice()->void:
	var host=_fixture({1:"w123456789 t123 b5"},"tong4")
	raw_ms+=20;check(_ack(host,"south"),"open legal ready-hand fixture")
	var view:Dictionary=host.view_for("south")
	raw_ms+=10000
	host._animation_timeout(view.presentation)
	var job:Dictionary=host._session.animation_timeout_job(host._animation_expired[1],raw_ms)
	check(job.view.choices.actions.has("ready") and not job.view.choices.ready_ids.is_empty(),"one-shot AI may consider the approved legal ready action")
	var ready_id:int=job.view.choices.ready_ids[0]
	check(host._session.submit_animation_timeout(job,"ready",ready_id,raw_ms),"authorized ready declaration follows normal game rules")
	host._accepted(job.round_number,job.prompt_id,1)
	var after:Dictionary=host.view_for("south")
	check(after.round.players[1].ready and not after.room.seats[1].auto_play,"ready lock persists without enabling continuous AI control")
	check(not host._session.submit_animation_timeout(job,"ready",ready_id,raw_ms),"ready declaration cannot execute twice")
	await _close(host)
