extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

# Simulate a hotspot that drops global, directed and loopback broadcasts.
# Only the real interface-bound unicast scan may discover this room.
class UnicastDiscovery:
	extends LanDiscovery
	func _send_query() -> void:
		_timer = QUERY_INTERVAL

class PassiveDiscovery:
	extends UnicastDiscovery
	func _send_probes(_delta: float) -> void: pass

func _initialize() -> void: call_deferred("_run")

func _wait_until(predicate: Callable, seconds: float = 6.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(predicate.call())

func _run() -> void:
	for address in ["10.223.21.26", "192.168.43.1", "172.16.0.1", "172.31.255.254"]:
		t.expect(LanDiscovery._private_ipv4(address), "accept private hotspot address " + address)
	for address in ["127.0.0.1", "169.254.1.1", "8.8.8.8", "172.32.0.1", "192.169.1.1", "10.0.0.256", "10.0.0.-1", "10.0.0.01", "10.0.0", "fe80::1"]:
		t.expect(not LanDiscovery._private_ipv4(address), "do not scan invalid, public or disconnected interface " + address)
	var interfaces := [
		{"name": "rmnet_data0", "addresses": ["10.55.6.7"]},
		{"name": "wlan0", "addresses": ["10.223.21.26", "fe80::1"]},
		{"name": "ap0", "addresses": ["192.168.43.1"]},
		{"name": "eth0", "addresses": ["169.254.1.1", "10.223.21.26", "8.8.8.8"]},
	]
	var addresses := LanDiscovery._interface_addresses(interfaces)
	t.expect(addresses == PackedStringArray(["10.223.21.26", "192.168.43.1", "10.55.6.7"]), "hotspot/Wi-Fi before mobile data, deduplicate addresses")
	var targets := LanDiscovery._subnet_targets("10.223.21.26")
	t.expect(targets.size() == 254 and targets.has("10.223.21.155"), "phone gateway .26 finds PC .155 without assuming gateway .1")
	t.expect(targets[0] == "10.223.21.26", "same-machine rooms covered without loopback")
	var bounded := true
	for address in targets:
		if not str(address).begins_with("10.223.21."): bounded = false
	t.expect(bounded, "bounded local subnet only")
	t.expect(LanDiscovery._subnet_targets("8.8.8.8").is_empty(), "no public network probing")

	var scanner := UnicastDiscovery.new()
	root.add_child(scanner)
	var network := root.get_node("Network")
	network.reset()
	t.expect(network.start_host(false, true, 7548, "947128", "热点扫描测试"), "host starts on test game port")
	t.expect(network.discovery.advertise(network.net_node), "real UDP discovery responder opens")
	network.discovery._announce_timer = 3600.0
	scanner.search()
	if scanner._probes.is_empty():
		print("[smoke_lan_discovery] No connected private IPv4 interface; real hotspot unicast test skipped")
	else:
		t.expect(await _wait_until(func(): return scanner.has_number("947128")), "unicast alone discovers room when all broadcasts are suppressed")
		for room in scanner.rooms.values():
			if room.number == "947128":
				t.expect(room.host != "127.0.0.1" and LanDiscovery._private_ipv4(room.host), "reply comes over real LAN interface")
				t.expect(room.port == 7548 and room.players == 1 and not room.started, "room response retains real join endpoint and readiness")
		t.expect(network.net_node.game.players.is_empty(), "discovery does not deal tiles")
		var passive := PassiveDiscovery.new()
		root.add_child(passive)
		passive.search()
		# Simulate Android not returning any hotspot interfaces to the app.
		for probe in passive._probes: probe.socket.close()
		passive._probes.clear()
		passive._interface_timer = 3600.0
		network.discovery._announce_timer = 0.0
		t.expect(await _wait_until(func(): return passive.has_number("947128")), "host announcements find phone with no visible hotspot interfaces or outgoing queries")
		t.expect(passive._announcements != null and passive._probes.is_empty(), "passive discovery uses fixed listener, not broadcast or subnet queries")
		passive.stop_search()
		t.expect(passive._announcements == null, "passive listener closes on exit")
		passive.queue_free()

	# Malformed traffic must neither crash the lobby nor create a fake room.
	var sender := PacketPeerUDP.new()
	t.expect(sender.bind(0, "127.0.0.1") == OK, "malformed reply test sender binds")
	sender.set_dest_address("127.0.0.1", scanner._query.get_local_port())
	for bad in [
		{"protocol": LanDiscovery.PROTOCOL, "type": "room", "id": "invalid", "number": "1234", "port": 7500},
		{"protocol": LanDiscovery.PROTOCOL, "type": "room", "id": "invalid", "number": "1234", "port": {}, "name": "bad", "started": false, "players": 1},
		{"protocol": LanDiscovery.PROTOCOL, "type": "room", "id": "invalid", "number": "1234", "port": 7500, "name": "bad", "started": false, "players": 9},
	]:
		sender.put_packet(JSON.stringify(bad).to_utf8_buffer())
	await create_timer(0.06).timeout
	t.expect(not scanner.rooms.has("invalid"), "ignore incomplete or malformed discovery replies")
	sender.close()
	scanner.stop_search()
	t.expect(scanner._query == null and scanner._announcements == null and scanner._probes.is_empty() and scanner.rooms.is_empty(), "leaving search releases all interface sockets and stale rooms")
	network.reset()
	scanner.queue_free()
	await process_frame
	quit(t.finish("smoke_lan_discovery"))
