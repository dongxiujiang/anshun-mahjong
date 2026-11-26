extends "res://tests/test_presentation_receipts.gd"

const Pace=preload("res://src/presentation/GamePace.gd")
const Deal=preload("res://src/presentation/OpeningDeal.gd")
const Preferences=preload("res://src/app/AppSettings.gd")

func _run()->void:
	for field in ["music_volume","voice_volume","effects_volume","microphone_gain","speaker_gain"]:
		check(Preferences.DEFAULTS[field]==0.8,"fresh %s defaults to 80 percent"%field)
	check(not Preferences.DEFAULTS.music and not Preferences.DEFAULTS.microphone,"volume defaults do not turn music or microphone on")
	for count in [1,4]:
		for style in ["a","b"]:
			var total:float=Deal.CARRY+(Deal.SPREAD if count==4 and style=="a" else 0.0)+(2 if count==4 and style=="b" else 1)*(Deal.FLIP+Deal.RACK)
			check(is_equal_approx(total*Deal.pickup_scale(count,style),0.3),"each physical deal group lasts 0.3 seconds")
	var host:=Host.new();root.add_child(host);raw_ms=1000;host.clock_msec=func():return raw_ms
	check(host.configure("514236","online",1),"configure production defaults")
	check(host._ai_delay==500 and host._durations.turn==300 and host._durations.response==300,"server uses fixed animation and AI delay defaults")
	host.join("human","玩家","human");host.set_ready("human",true);host._prepare_at=-1
	_fixed_dice(host._dice)
	check(host._session.start_round(host._dice,_deck(1,5,{},"wan9"),raw_ms,1),"start real legal round")
	host._refresh();raw_ms+=int(host._durations.dealt)
	check(_ack(host,"human"),"release completed physical deal")
	raw_ms+=299
	_ack(host,"human");await process_frame
	check(host.view_for("human").round.choices.is_empty(),"draw cannot finish at the old 0.2-second boundary")
	raw_ms+=1;await process_frame
	var view:Dictionary=host.view_for("human")
	check(not view.round.choices.is_empty(),"draw becomes actionable at 0.3 seconds")
	host.set_auto_play("human",view.room.room_instance_id,1,true)
	raw_ms+=499
	for frame in 20:await process_frame;OS.delay_msec(1)
	check(host.view_for("human").round.prompt_id==view.round.prompt_id,"AI cannot act before 0.5 seconds after landing")
	raw_ms+=1
	for frame in 2000:
		await process_frame
		if host.view_for("human").round.prompt_id!=view.round.prompt_id:break
		OS.delay_msec(1)
	check(host.view_for("human").round.prompt_id!=view.round.prompt_id,"legal AI action proceeds after full 0.5-second wait")
	await _close(host)
	print("Game pace: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
