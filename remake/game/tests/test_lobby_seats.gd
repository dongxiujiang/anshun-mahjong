extends "res://tests/test_presentation_receipts.gd"
const Browser = preload("res://src/app/RoomBrowser.gd")
const Art = preload("res://src/app/CharacterArt.gd")
const Packs = preload("res://src/audio/VoicePacks.gd")

func _wait(predicate: Callable) -> bool:
	var until := Time.get_ticks_msec()+5000
	while not predicate.call() and Time.get_ticks_msec()<until:
		await process_frame
		OS.delay_msec(1)
	return predicate.call()

func _run() -> void:
	await _transport()
	await _browser()
	print("Lobby seats: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)

func _transport() -> void:
	var service := Client.new();root.add_child(service)
	check(service.start_server("1234",0,{"owner_token_hash":"creator".sha256_text(),"require_start":true,"start_delay_ms":3000}),"independent service starts")
	var inspector := Client.new();root.add_child(inspector)
	var found := []
	inspector.room_inspected.connect(func(room):found.append(room))
	check(inspector.inspect_room("127.0.0.1",service.local_port),"manual address begins inspection")
	check(await _wait(func():return not found.is_empty()),"manual address returns actual room")
	check(inspector.ticket.is_empty() and inspector.view.is_empty() and service.discovery_info().players==0,"inspection claims no seat")
	check(found[0].number=="1234" and found[0].seats.size()==4,"inspection supplies actual seats")
	check(not JSON.stringify(found[0]).contains("token_hash") and not found[0].has("round"),"public inspection excludes secrets and dark hands")
	var owner := Client.new();root.add_child(owner)
	owner.connect_room("127.0.0.1",service.local_port,{"player_id":"creator","nickname":"房主","room_number":"1234","owner_token":"creator","requested_seat":1})
	check(await _wait(func():return not owner.view.is_empty()),"creator enters south")
	var guest := Client.new();root.add_child(guest)
	guest.connect_room("127.0.0.1",service.local_port,{"player_id":"guest","nickname":"客人","room_number":"1234","requested_seat":3})
	check(await _wait(func():return not guest.view.is_empty()),"clicked north seat joins")
	check(owner.view.seat==1 and guest.view.seat==3,"server honors exact chosen seat")
	check(owner.view.room.requires_start and owner.view.room.seats[1].ready and guest.view.room.seats[3].ready,"first entrants ready automatically but require host start")
	var rival := Client.new();root.add_child(rival)
	var rejected := []
	rival.session_ended.connect(func(reason):rejected.append(reason))
	rival.connect_room("127.0.0.1",service.local_port,{"player_id":"rival","nickname":"另一位","room_number":"1234","requested_seat":3})
	check(await _wait(func():return not rejected.is_empty()),"occupied-seat race rejects")
	check(rival.ticket.is_empty() and service.discovery_info().players==2,"race never silently assigns another seat")
	guest.start_first_round()
	await create_timer(.1).timeout
	check(service._host._prepare_at==-1 and not service._host._roll_valid,"guest cannot start first round")
	owner.start_first_round()
	check(await _wait(func():return service._host._prepare_at>=0),"creator start accepted over real ENet")
	var saved: Dictionary = service._host.export_authority()
	check(saved.require_start and saved.first_start_requested,"LAN checkpoint preserves start gate")
	service._host.disconnect_human("does-not-exist")
	for node in [rival,guest,owner,inspector,service]:
		node._reset();node.free()
	await process_frame

func _browser() -> void:
	for index in range(1, Packs.ORDER.size() + 1):
		check(Art.portrait(index) != null, "runtime 2D portrait exists: " + str(index))
	var browser := Browser.new();root.add_child(browser)
	browser.size = Vector2(1000,390)
	var rooms := []
	for index in 5:
		rooms.append({"number":str(1000+index),"name":"测试桌","players":4 if index==0 else 0,"started":false})
	browser.set_rooms(rooms)
	check(browser.rooms[0].number=="1001" and browser.rooms[-1].number=="1000","available tables precede full tables")
	check(browser._labels.filter(func(item): return not item.get("heading", false)).size() == 8, "only two tables' eight seat cards rendered")
	browser._pressed=true
	browser.set_rooms([])
	check(browser.rooms.size()==5,"publications do not move table targets during a press")
	browser._pressed=false;browser._flush_pending()
	check(browser.rooms.is_empty(),"delayed publication applies after release")
	browser.free()
	await process_frame
