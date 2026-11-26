extends "res://tests/test_presentation_receipts.gd"

const Room = preload("res://src/session/RoomSession.gd")
const Settings = preload("res://src/app/SettingsPanel.gd")
const Preferences = preload("res://src/app/AppSettings.gd")

func _run() -> void:
	var probe := Host.new();root.add_child(probe)
	check(probe.has_method("set_difficulty"), "authority validates room difficulty changes")
	probe.shutdown();probe.free()
	if failures == 0:
		_ownership()
		await _difficulty()
		await _settings_transport()
	print("Room settings: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _ownership() -> void:
	var room := Room.new("1234")
	var south:Dictionary=room.join("s","南","south",0)
	room.join("e","东","east",0);room.join("n","北","north",0)
	check(room.snapshot(0).owner_player_id=="s", "initial member owns unreserved local room")
	check(room.disconnect_human("east",1), "east unexpectedly disconnects")
	check(room.disconnect_human("south",2), "owner unexpectedly disconnects")
	check(room.snapshot(2).owner_player_id=="n", "succession follows seats and skips disconnected humans")
	check(not room.resume(south.room_instance_id,"s",south.member_token,"south2",3).is_empty(), "old owner can return")
	check(room.snapshot(3).owner_player_id=="n", "return does not reclaim ownership")
	check(room.leave_human("north",4), "explicit leave releases a seat")
	check(room.snapshot(4).owner_player_id=="s" and room.snapshot(4).seats[3].player_id.is_empty(), "owner moves forward to remaining online human")
	check(room.disconnect_human("south2",5), "last connected member disconnects")
	check(room.snapshot(5).owner_player_id.is_empty(), "no connected human means no acting owner")
	check(not room.resume(south.room_instance_id,"e",room.get_meta("unused", "invalid"),"bad",6).size(), "untrusted credentials cannot take ownership")
	check(not room.resume(south.room_instance_id,"s",south.member_token,"first-back",6).is_empty(), "first member returns during grace")
	check(room.snapshot(6).owner_player_id=="s", "first authenticated return becomes owner")
	check(room.leave_human("first-back",7) and room.is_open(7), "offline non-departed human retains grace")
	var empty:=Room.new("2345")
	empty.join("only","独","only",0)
	check(empty.leave_human("only",1) and not empty.is_open(1), "all explicit departures close immediately")
	var grace:=Room.new("3456")
	grace.join("only","独","only",0);grace.disconnect_human("only",10)
	check(grace.is_open(300009) and not grace.is_open(300010), "all unexpected disconnects keep exactly five minutes")
	var returning:=Room.new("3512")
	var a:Dictionary=returning.join("a","甲","a",0)
	var b:Dictionary=returning.join("b","乙","b",0)
	returning.disconnect_human("a",1);returning.disconnect_human("b",2)
	check(not returning.resume(a.room_instance_id,"a",a.member_token,"a2",3).is_empty(), "first authenticated return can differ from last owner")
	returning.resume(b.room_instance_id,"b",b.member_token,"b2",4)
	check(returning.snapshot(4).owner_player_id=="a", "last owner returning later cannot reclaim management")
	check(returning.move_to_empty_seat("a2",2,5) and returning.snapshot(5).owner_player_id=="a", "ownership follows a human's seat change")
	check(returning.leave_human("a2",6) and returning.recoverable_seat(a.room_instance_id,"a",a.member_token,7)==-1, "explicit departure revokes its old recovery credential")
	check(returning.snapshot(7).owner_player_id=="b", "succession starts from owner's moved seat")
	var reserved:=Room.new("4567")
	reserved.reserve_owner("secret".sha256_buffer())
	check(reserved.join("guest","客","guest",0).seat==0, "guest cannot occupy creator's reserved south seat")
	check(reserved.snapshot(0).owner_player_id.is_empty(), "guest arriving first cannot become owner")
	check(reserved.join("fake","伪","fake",0,{},"wrong").is_empty(), "wrong creator token is rejected")
	check(reserved.join("creator","主","creator",0,{},"secret").seat==1, "creator claims ownership with private token")
	check(reserved.snapshot(0).owner_player_id=="creator", "creator identity is authoritative")
	check(reserved.join("replay","重","replay",0,{},"secret").is_empty(), "creator token cannot be replayed")
	check(not reserved.snapshot(0).has("owner_token_hash"), "public snapshot never exposes creator credential")

func _difficulty() -> void:
	var host=_fixture()
	var view:Dictionary=host.view_for("south")
	check(not host.set_difficulty("east",view.room.room_instance_id,"high"), "guest difficulty change rejected by server")
	check(not host.set_difficulty("south","old-room","high"), "old room request rejected")
	check(not host.set_difficulty("south",view.room.room_instance_id,"impossible"), "unknown difficulty rejected")
	check(host.set_difficulty("south",view.room.room_instance_id,"high"), "owner queues next round difficulty")
	check(host.view_for("east").room.difficulty=="low" and host.view_for("east").room.next_difficulty=="high", "everyone sees current and pending levels")
	var state:Dictionary=host.export_authority()
	var restored:=Host.new();root.add_child(restored)
	check(restored.restore_authority(state), "authority restore keeps room settings")
	check(restored._level=="low" and restored._next_level=="high", "handover cannot apply difficulty early")
	await _close(restored)
	var deltas:Array[int]=[0,0,0,0]
	host._session._room.finish_round(1,deltas,1,raw_ms)
	host._refresh()
	host._prepare_at=-1
	check(host._session.set_ready("south",true,raw_ms) and host._session.set_ready("east",true,raw_ms), "next round members ready")
	host._dice.roll_id+=1
	check(host._session.start_round(host._dice,_deck(1,5,{},"wan9"),raw_ms,1), "start actual second round")
	host._refresh()
	check(host._level=="high" and host.view_for("east").room.difficulty=="high", "pending level takes effect on next round")
	await _close(host)
	var panel:=Settings.new();root.add_child(panel)
	panel.build(Preferences.new().profile(),false)
	panel.apply_room({"difficulty":"low","next_difficulty":"high"},false)
	check(panel._fields.difficulty.disabled and panel.values().difficulty=="high", "guest reads server's pending value and cannot edit")
	panel.apply_room({"difficulty":"low","next_difficulty":"high"},true)
	panel._fields.difficulty.select(0)
	panel.apply_room({"difficulty":"low","next_difficulty":"high"},true)
	check(panel.values().difficulty=="low", "clock publications do not overwrite unsaved owner selection")
	await process_frame
	panel.free()

func _settings_transport() -> void:
	var service:=Client.new();service.name="SettingsService";root.add_child(service)
	check(service.start_server("1234",0,{"owner_token_hash":"secret".sha256_text()}), "real independent server starts")
	var members:=[null,null]
	for index in [1,0]:
		var member:=Client.new();member.name="SettingsMember"+str(index);root.add_child(member);members[index]=member
		var profile:={"player_id":"net-"+str(index),"nickname":"玩家"+str(index),"room_number":"1234"}
		if index==0:profile.owner_token="secret"
		check(member.connect_room("127.0.0.1",service.local_port,profile), "real member connects")
		check(await _wait(func():return not member.view.is_empty()), "real member joins")
	var owner=members[0];var guest=members[1]
	check(owner.view.seat==1 and guest.view.seat==0 and owner.view.room.owner_player_id=="net-0", "creator keeps south and ownership even when guest connects first")
	owner.set_difficulty("high")
	check(await _wait(func():return guest.view.room.get("next_difficulty")=="high"), "difficulty synchronizes through ENet")
	guest.set_difficulty("low")
	for tick in 20:await process_frame;OS.delay_msec(1)
	check(owner.view.room.next_difficulty=="high", "forged guest edit cannot overwrite setting")
	owner.leave()
	check(await _wait(func():return guest.view.room.owner_player_id=="net-1"), "explicit network leave transfers ownership")
	check(guest.view.room.seats[1].player_id.is_empty(), "network leave releases old seat")
	guest.leave()
	check(await _wait(func():return service._host==null or service._host._closed), "last explicit departure closes authority")
	for member in members:member.free()
	service.free()

func _wait(predicate:Callable) -> bool:
	var end:=Time.get_ticks_msec()+5000
	while not predicate.call() and Time.get_ticks_msec()<end:
		await process_frame
		OS.delay_msec(1)
	return predicate.call()
