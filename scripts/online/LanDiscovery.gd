class_name LanDiscovery
extends Node
## Broadcast plus interface-bound unicast discovery, including Android hotspots.
## Addresses stay internal; players select a room number instead of entering IPs.
signal rooms_updated
signal discovery_error(message)
const FIRST_PORT := 7499
const PORT_COUNT := 10
const PROTOCOL := "anshun-mahjong-lobby-v1"
const STALE_MS := 5000
const QUERY_INTERVAL := 1.5
const INTERFACE_INTERVAL := 6.0
const PROBE_INTERVAL := 0.05
const PROBE_BUDGET := 8
const PROBE_FRAME_BUDGET_US := 1500
const OCCUPIED_ANNOUNCEMENT_INTERVAL := 0.25
const MAX_INTERFACES := 8
const ANNOUNCEMENT_PORT := 7509
const ANNOUNCEMENT_PORT_COUNT := 10
var rooms: Dictionary = {}
var searching := false
var _query: PacketPeerUDP
var _responder: PacketPeerUDP
var _net: NetGameNode
var _timer := 0.0
var _room_id := ""
var _probes: Array[Dictionary] = []
var _probe_index := 0
var _probe_port := 0
var _probe_timer := 0.0
var _interface_timer := 0.0
var _announcements: PacketPeerUDP
var _advertise_probes: Array[Dictionary] = []
var _announce_index := 0
var _announce_host := 0
var _announce_port := 0
var _announce_timer := 0.0
var _advertise_interface_timer := 0.0

static func _private_ipv4(value: String) -> bool:
	var parts := value.split(".")
	if parts.size() != 4: return false
	for part in parts:
		if not part.is_valid_int() or str(part.to_int()) != part or part.to_int() < 0 or part.to_int() > 255: return false
	var first := parts[0].to_int()
	var second := parts[1].to_int()
	return first == 10 or first == 192 and second == 168 or first == 172 and second >= 16 and second <= 31

static func _interface_addresses(interfaces: Array) -> PackedStringArray:
	var preferred := PackedStringArray()
	var others := PackedStringArray()
	for interface in interfaces:
		var interface_name := str(interface.get("name", "")).to_lower() + " " + str(interface.get("friendly", "")).to_lower()
		var wifi := interface_name.contains("wlan") or interface_name.contains("wifi") or interface_name.contains("wi-fi") or interface_name.contains("wlp") or interface_name.contains("ap") or interface_name.contains("bridge")
		for address in interface.get("addresses", []):
			var value := str(address)
			if not _private_ipv4(value) or value in preferred or value in others: continue
			if wifi: preferred.append(value)
			else: others.append(value)
	preferred.append_array(others)
	return preferred.slice(0, MAX_INTERFACES)

static func _subnet_targets(address: String) -> PackedStringArray:
	if not _private_ipv4(address): return PackedStringArray()
	var prefix := address.get_slice(".", 0) + "." + address.get_slice(".", 1) + "." + address.get_slice(".", 2) + "."
	# A bounded /24 scan is a fallback for hotspot systems that drop broadcasts.
	# The local address also covers two games running on one PC without loopback.
	var targets := PackedStringArray([address])
	for host in range(1, 255):
		var candidate := prefix + str(host)
		if candidate != address: targets.append(candidate)
	return targets

func search() -> void:
	searching = true
	if _query == null:
		_query = PacketPeerUDP.new()
		if _query.bind(0) != OK:
			discovery_error.emit("无法搜索局域网，请检查网络后重试")
			_query = null
			return
		_query.set_broadcast_enabled(true)
	if _announcements == null:
		var listener := PacketPeerUDP.new()
		for port in range(ANNOUNCEMENT_PORT, ANNOUNCEMENT_PORT + ANNOUNCEMENT_PORT_COUNT):
			if listener.bind(port) == OK:
				_announcements = listener
				break
	_refresh_interfaces()
	_send_query()

func stop_search() -> void:
	searching = false
	if _query != null: _query.close()
	_query = null
	if _announcements != null: _announcements.close()
	_announcements = null
	for probe in _probes: probe.socket.close()
	_probes.clear()
	_probe_index = 0
	_probe_port = 0
	_probe_timer = 0.0
	_interface_timer = 0.0
	if not rooms.is_empty():
		rooms.clear()
		rooms_updated.emit()

func advertise(net: NetGameNode) -> bool:
	stop_advertise()
	_net = net
	_room_id = Crypto.new().generate_random_bytes(12).hex_encode()
	_responder = PacketPeerUDP.new()
	for port in range(FIRST_PORT, FIRST_PORT + PORT_COUNT):
		if _responder.bind(port) == OK:
			_refresh_advertise_interfaces()
			return true
	_responder = null
	discovery_error.emit("局域网搜索端口已占满，请关闭多余房间后重试")
	return false

func stop_advertise() -> void:
	if _responder != null: _responder.close()
	_responder = null
	_net = null
	for probe in _advertise_probes: probe.socket.close()
	_advertise_probes.clear()
	_announce_index = 0
	_announce_host = 0
	_announce_port = 0
	_announce_timer = 0.0
	_advertise_interface_timer = 0.0

func _refresh_advertise_interfaces() -> void:
	_advertise_interface_timer = INTERFACE_INTERVAL
	var addresses := _interface_addresses(IP.get_local_interfaces())
	var existing := PackedStringArray()
	for probe in _advertise_probes: existing.append(str(probe.address))
	if addresses == existing: return
	for probe in _advertise_probes: probe.socket.close()
	_advertise_probes.clear()
	for address in addresses:
		var socket := PacketPeerUDP.new()
		if socket.bind(0, address) != OK: continue
		_advertise_probes.append({"socket": socket, "address": address, "targets": _subnet_targets(address)})
	_announce_index = 0
	_announce_host = 0
	_announce_port = 0
	_announce_timer = 0.0

func _room_packet() -> PackedByteArray:
	return JSON.stringify({"protocol": PROTOCOL, "type": "room", "id": _room_id, "number": _net.room_number, "name": _net.room_name, "port": _net._port, "players": _net._members.size(), "started": _net._started}).to_utf8_buffer()

func _send_announcements(delta: float) -> void:
	# The PC can reach the hotspot's phone even when Android hides its AP
	# interface or sends default-route broadcasts over mobile data instead.
	if _net._started: return
	_advertise_interface_timer -= delta
	if _advertise_interface_timer <= 0.0: _refresh_advertise_interfaces()
	if _advertise_probes.is_empty(): return
	_announce_timer -= delta
	if _announce_timer > 0.0: return
	# 有真人加入后降低网段通知频率；仍可发现房间并继续加入剩余座位。
	_announce_timer = OCCUPIED_ANNOUNCEMENT_INTERVAL if _net._members.size() > 1 else PROBE_INTERVAL
	var bytes := _room_packet()
	var started_at := Time.get_ticks_usec()
	for packet in PROBE_BUDGET:
		if packet > 0 and Time.get_ticks_usec() - started_at >= PROBE_FRAME_BUDGET_US: break
		var probe: Dictionary = _advertise_probes[_announce_index]
		_send_to(probe.socket, str(probe.targets[_announce_host % probe.targets.size()]), ANNOUNCEMENT_PORT + _announce_port, bytes)
		_announce_port += 1
		if _announce_port >= ANNOUNCEMENT_PORT_COUNT:
			_announce_port = 0
			_announce_index = (_announce_index + 1) % _advertise_probes.size()
			if _announce_index == 0: _announce_host = (_announce_host + 1) % 255

func _refresh_interfaces() -> void:
	_interface_timer = INTERFACE_INTERVAL
	var addresses := _interface_addresses(IP.get_local_interfaces())
	var existing := PackedStringArray()
	for probe in _probes: existing.append(str(probe.address))
	if addresses == existing: return
	for probe in _probes: probe.socket.close()
	_probes.clear()
	for address in addresses:
		var socket := PacketPeerUDP.new()
		if socket.bind(0, address) != OK: continue
		socket.set_broadcast_enabled(true)
		_probes.append({"socket": socket, "address": address, "targets": _subnet_targets(address), "cursor": 0})
	_probe_index = 0
	_probe_port = 0
	_probe_timer = 0.0

func _send_to(socket: PacketPeerUDP, address: String, port: int, bytes: PackedByteArray) -> void:
	if socket.set_dest_address(address, port) == OK: socket.put_packet(bytes)

func _send_query() -> void:
	if _query == null: return
	_timer = QUERY_INTERVAL
	var data := JSON.stringify({"protocol": PROTOCOL, "type": "query"}).to_utf8_buffer()
	for port in range(FIRST_PORT, FIRST_PORT + PORT_COUNT):
		for address in ["255.255.255.255", "127.0.0.1"]:
			_send_to(_query, address, port, data)
		for probe in _probes:
			var address := str(probe.address)
			var broadcast := address.substr(0, address.rfind(".") + 1) + "255"
			_send_to(probe.socket, broadcast, port, data)
		# Keep discovered rooms alive without relying on another complete subnet sweep.
		for room in rooms.values():
			# Normal routing can reach an announced room even if Android's
			# interface list omits the AP adapter; directed unicast still works.
			_send_to(_query, room.host, port, data)
			if room.host != "127.0.0.1":
				for probe in _probes:
					var prefix := str(probe.address).substr(0, str(probe.address).rfind(".") + 1)
					if str(room.host).begins_with(prefix): _send_to(probe.socket, room.host, port, data)

func _send_probes(delta: float) -> void:
	if _probes.is_empty(): return
	_probe_timer -= delta
	if _probe_timer > 0.0: return
	_probe_timer = PROBE_INTERVAL if rooms.is_empty() else PROBE_INTERVAL * 4.0
	var bytes := JSON.stringify({"protocol": PROTOCOL, "type": "query"}).to_utf8_buffer()
	var started_at := Time.get_ticks_usec()
	for packet in PROBE_BUDGET:
		if packet > 0 and Time.get_ticks_usec() - started_at >= PROBE_FRAME_BUDGET_US: break
		var probe: Dictionary = _probes[_probe_index]
		_send_to(probe.socket, str(probe.targets[int(probe.cursor)]), FIRST_PORT + _probe_port, bytes)
		_probe_port += 1
		if _probe_port >= PORT_COUNT:
			_probe_port = 0
			probe.cursor = (int(probe.cursor) + 1) % probe.targets.size()
			# Interleave interfaces so a mobile-data adapter cannot delay the hotspot.
			_probe_index += 1
			if _probe_index >= _probes.size():
				_probe_index = 0

func _read_rooms(socket: PacketPeerUDP) -> bool:
	var changed := false
	for packet in mini(socket.get_available_packet_count(), 128):
		var bytes := socket.get_packet()
		var address := socket.get_packet_ip()
		if bytes.size() > 2048: continue
		var room = JSON.parse_string(bytes.get_string_from_utf8())
		if not room is Dictionary or room.get("protocol") != PROTOCOL or room.get("type") != "room": continue
		if not room.get("number") is String or not NetGameNode.valid_room_number(room.number): continue
		if not room.get("port") is float and not room.get("port") is int: continue
		if int(room.port) < 1 or int(room.port) > 65535: continue
		if not room.get("name") is String or not room.get("started") is bool: continue
		if not room.get("players") is float and not room.get("players") is int: continue
		if int(room.players) < 0 or int(room.players) > 4: continue
		var identity := str(room.get("id", ""))
		if identity == "" or identity.length() > 64: continue
		room["host"] = address
		room["seen"] = Time.get_ticks_msec()
		room["name"] = str(room.name).left(24)
		room["port"] = int(room.port)
		room["players"] = int(room.players)
		# Prefer loopback for another game on this machine, never advertise it to peers.
		if rooms.has(identity) and rooms[identity].host == "127.0.0.1": room.host = "127.0.0.1"
		changed = changed or not rooms.has(identity) or rooms[identity].players != room.players or rooms[identity].started != room.started or rooms[identity].name != room.name or rooms[identity].host != room.host
		rooms[identity] = room
	return changed

func _process(delta: float) -> void:
	if _responder != null and is_instance_valid(_net) and not _net._started:
		for packet in mini(_responder.get_available_packet_count(), 64):
			var bytes := _responder.get_packet()
			var address := _responder.get_packet_ip()
			var port := _responder.get_packet_port()
			if bytes.size() > 2048: continue
			var query = JSON.parse_string(bytes.get_string_from_utf8())
			if not query is Dictionary or query.get("protocol") != PROTOCOL or query.get("type") != "query": continue
			_responder.set_dest_address(address, port)
			_responder.put_packet(_room_packet())
		_send_announcements(delta)
	if not searching or _query == null: return
	_interface_timer -= delta
	if _interface_timer <= 0.0: _refresh_interfaces()
	_timer -= delta
	if _timer <= 0.0: _send_query()
	_send_probes(delta)
	var changed := _read_rooms(_query)
	if _announcements != null:
		var updated := _read_rooms(_announcements)
		changed = changed or updated
	for probe in _probes:
		# Read every socket even if another socket already changed the room list.
		var updated := _read_rooms(probe.socket)
		changed = changed or updated
	for identity in rooms.keys():
		if Time.get_ticks_msec() - int(rooms[identity].seen) > STALE_MS:
			rooms.erase(identity)
			changed = true
	if changed: rooms_updated.emit()

func has_number(number: String) -> bool:
	for room in rooms.values():
		if room.number == number: return true
	return false

func _exit_tree() -> void:
	stop_search()
	stop_advertise()
