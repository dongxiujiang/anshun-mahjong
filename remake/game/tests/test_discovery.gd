extends SceneTree

const Discovery = preload("res://src/network/LanDiscovery.gd")
const Client = preload("res://src/network/GameClient.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func _run() -> void:
	check(Discovery.valid_room_number("001234") and not Discovery.valid_room_number("12 x"), "room numbers retain leading zeroes and reject invalid input")
	check(not Discovery._private_ipv4("8.8.8.8") and Discovery._subnet_targets("8.8.8.8").is_empty(), "discovery never scans public addresses")
	check(Discovery._subnet_targets("192.168.2.5").size() == 254, "hotspot fallback bounded to private /24")
	var host := Client.new()
	host.name = "LanOwner"
	root.add_child(host)
	check(host.host_lan({"player_id": "lan-owner", "nickname": "南家"}, "001234", 0, {"room_name": "南家麻将局"}), "local host uses true ENet connection")
	var search := Discovery.new()
	root.add_child(search)
	search.search()
	for frame in 3000:
		await process_frame
		OS.delay_msec(1)
		if search.has_number("001234") and not host.view.is_empty() and search.rooms.values()[0].players == 1: break
	check(search.has_number("001234"), "real UDP search finds advertised room without IP input")
	if search.has_number("001234"):
		var found: Dictionary = search.rooms.values()[0]
		check(found.port == host.local_port and found.name == "南家麻将局" and found.players == 1, "discovery exposes correct public room summary")
		var instance: String = host.view.room.room_instance_id
		var ticket := host.ticket.duplicate(true)
		host._reset() # Unexpected connection loss preserves the seat and LAN authority.
		for frame in 50:
			await process_frame
			OS.delay_msec(1)
		check(host.connect_room(found.host, found.port, {"mode": "lan"}, ticket), "creator can return after unexpected loss")
		for frame in 3000:
			await process_frame
			OS.delay_msec(1)
			if not host.view.is_empty(): break
		check(not host.view.is_empty() and host.view.room.room_instance_id == instance, "unexpected loss preserves independent LAN authority and instance")
	host.queue_free()
	search.queue_free()
	for child in root.get_children():
		if str(child.name).begins_with("HostedRoom_"): child.queue_free()
	await process_frame
	await process_frame
	print("Discovery: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
