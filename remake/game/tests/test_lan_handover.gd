extends SceneTree
## Real ENet peers in one SceneTree. Removing nodes simulates service loss.
const Client = preload("res://src/network/GameClient.gd")
var checks := 0
var failures := 0
var raw_ms := 1000
var nodes: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func client(label: String):
	var value := Client.new()
	value.view_changed.connect(func(state):
		if state.has("presentation"):value.finish_presentation.call_deferred(state.presentation))
	value.name = label
	root.add_child(value)
	nodes.append(value)
	return value

func until(predicate: Callable, limit: int = 4000) -> bool:
	for step in limit:
		if predicate.call():
			return true
		await process_frame
		OS.delay_msec(1)
	return false

func service_of(owner: Node):
	for child in root.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion():
			continue
		if str(child.name).begins_with("HostedRoom_") or str(child.name).begins_with("PromotedRoom_"):
			if child._owned_service and child._host != null:
				return child
	return null

func _run() -> void:
	var settings := {"difficulty": "low", "ai_delay_ms": 2,
		"presentation_ms": {"dealt": 10, "turn": 5, "response": 5, "ready_draw": 5}}
	var host = client("HostUI")
	check(host.host_lan({"player_id": "handover-host", "nickname": "房主", "room_number": "123456",
		"draw_style": "a", "avatar": 2, "voice_pack": "luoxiaohei", "mode": "lan"}, "123456", 0, settings),
		"host lan room starts")
	check(host.local_port > 0, "host picks a real LAN port")
	var authority: Node = service_of(host)
	check(authority != null, "hosted LAN service has its own lifetime")
	authority._host.clock_msec = func(): return raw_ms
	var south = client("South")
	var east = client("East")
	var profile_s := {"player_id": "handover-south", "nickname": "南家", "room_number": "123456", "avatar": 5, "voice_pack": "nvyou", "mode": "lan"}
	var profile_e := {"player_id": "handover-east", "nickname": "东家", "room_number": "123456", "avatar": 8, "voice_pack": "wangye", "mode": "lan"}
	check(south.connect_room("127.0.0.1", host.local_port, profile_s), "south joins")
	check(east.connect_room("127.0.0.1", host.local_port, profile_e), "east joins")
	check(await until(func(): return not south.view.is_empty() and not east.view.is_empty()), "both peers authenticated")
	if south.view.is_empty() or east.view.is_empty():
		await finish()
		return
	check(south.view.seat == 0 and east.view.seat == 3, "host took south; next in turn order is the first joiner (east seat)")
	check(await until(func(): return not south._standby_state.is_empty()), "first successor gets backup")
	south.move_to_empty_seat(2)
	check(await until(func(): return south._standby_state.is_empty() and not east._standby_state.is_empty()), "moving behind east revokes the former successor")
	south.move_to_empty_seat(0)
	check(await until(func(): return east._standby_state.is_empty() and not south._standby_state.is_empty()), "moving back transfers standby eligibility")
	var encrypted: Dictionary = south._standby_state.duplicate(true)
	check(not encrypted.has("state") and encrypted.get("payload") is PackedByteArray, "standby holds encrypted bytes")
	encrypted.payload[16] ^= 1
	check(Client.Backup.unseal(encrypted, south._backup_private).is_empty(), "tampered ciphertext rejected")
	host.set_ready(true)
	south.set_ready(true)
	east.set_ready(true)
	host.start_first_round()
	await until(func(): return authority._host._prepare_at >= 0)
	raw_ms += 3001
	check(await until(func(): return south.view.round.phase == "dealt", 12000), "real deal reaches peers before the crash")
	var saved_ticket: Dictionary = host.ticket.duplicate(true)
	var instance: String = saved_ticket.room_instance_id
	var south_hand: Array = south.view.round.players[0].hand.duplicate()
	var remaining: int = south.view.round.wall_remaining
	check(not south_hand.is_empty() and east.view.round.players[3].hand.size() == 13, "private hands stay per-view before takeover")
	check(await until(func(): return not south._standby_state.is_empty()), "next human holds a fresh standby copy")
	check(str(south._standby_state.get("instance", "")) == instance, "standby copy names the same room instance")
	authority.queue_free()
	host.queue_free()
	await process_frame
	check(await until(func(): return service_of(south) != null, 12000), "next human promotes from standby")
	var promoted: Node = service_of(south)
	check(promoted != null and promoted != authority, "promoted room service now lives on the next human's device")
	if promoted == null:
		await finish()
		return
	# 冻结新权威的时钟，避免后续等待期间 AI 继续摸打改变牌墙与手牌。
	promoted._host.clock_msec = func(): return raw_ms
	check(await until(func(): return not south.view.is_empty() and south.view.room.get("room_instance_id", "") == instance, 12000),
		"promoted host re-enters the same instance")
	check(south.view.round.players[0].hand == south_hand, "successor's own concealed hand survives the handover")
	check(await until(func(): return not east.view.is_empty() and east.view.room.get("room_instance_id", "") == instance and promoted._host.public_room().seats[3].connected, 12000),
		"remaining human discovers the promoted room and rejoins with its ticket")
	check(east.view.round.phase in ["dealt", "turn"] and (east.view.round.wall_remaining == remaining if east.view.round.phase == "dealt" else east.view.round.wall_remaining == remaining - 1),
		"phase and wall survive the handover")
	check(east.view.round.players[3].hand.size() == 13, "east concealed hand survives the handover")
	check(east.view.round.players[0].hand.is_empty(), "hidden hand of another seat never appears in east's view")
	var returning = client("HostReturn")
	check(returning.connect_room("127.0.0.1", 1, {"player_id": "handover-host", "nickname": "房主",
		"room_number": "123456", "avatar": 2, "voice_pack": "luoxiaohei", "mode": "lan"}, saved_ticket),
		"killed host restarts and returns with the saved ticket")
	check(await until(func(): return not returning.view.is_empty() and returning.view.seat == 1, 12000),
		"host reclaims seat 1 and its score")
	check(await until(func(): return is_instance_valid(promoted) and not promoted._standby_connection.is_empty()), "promoted authority selects the next human standby")
	check(await until(func(): return not east._standby_state.is_empty()), "second successor gets an encrypted backup")
	promoted.queue_free()
	south.queue_free()
	await process_frame
	check(await until(func(): return service_of(east) != null and service_of(east)._host_player_id == profile_e.player_id, 12000), "east takes over on the second failure")
	check(await until(func(): return not returning._standby_state.is_empty() and returning.ticket.room_instance_id == instance, 12000), "old host rejoins second authority as remaining standby")
	await finish()

func finish() -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.leave()
	for child in root.get_children():
		if str(child.name).begins_with("HostedRoom_") or str(child.name).begins_with("PromotedRoom_"):
			child.queue_free()
	for step in 20:
		await process_frame
		OS.delay_msec(5)
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
