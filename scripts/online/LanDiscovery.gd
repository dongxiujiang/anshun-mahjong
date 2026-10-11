class_name LanDiscovery
extends Node
## 广播查询从临时端口发出，房主单播回复；IP 只在内部用于连接。
signal rooms_updated
signal discovery_error(message)
const FIRST_PORT := 7499
const PORT_COUNT := 10
const PROTOCOL := "anshun-mahjong-lobby-v1"
const STALE_MS := 5000
var rooms: Dictionary = {}
var searching := false
var _query: PacketPeerUDP
var _responder: PacketPeerUDP
var _net: NetGameNode
var _timer := 0.0
var _room_id := ""

func search() -> void:
	searching = true
	if _query == null:
		_query = PacketPeerUDP.new()
		if _query.bind(0) != OK:
			discovery_error.emit("无法搜索局域网，请检查网络后重试")
			_query = null
			return
		_query.set_broadcast_enabled(true)
	_send_query()

func stop_search() -> void:
	searching = false
	if _query != null: _query.close()
	_query = null

func advertise(net: NetGameNode) -> bool:
	stop_advertise()
	_net = net
	_room_id = Crypto.new().generate_random_bytes(12).hex_encode()
	_responder = PacketPeerUDP.new()
	for port in range(FIRST_PORT, FIRST_PORT + PORT_COUNT):
		if _responder.bind(port) == OK: return true
	_responder = null
	discovery_error.emit("局域网搜索端口已占满，请关闭多余房间后重试")
	return false

func stop_advertise() -> void:
	if _responder != null: _responder.close()
	_responder = null
	_net = null

func _send_query() -> void:
	if _query == null: return
	_timer = 1.5
	var data := JSON.stringify({"protocol": PROTOCOL, "type": "query"}).to_utf8_buffer()
	for port in range(FIRST_PORT, FIRST_PORT + PORT_COUNT):
		for address in ["255.255.255.255", "127.0.0.1"]:
			_query.set_dest_address(address, port)
			_query.put_packet(data)

func _process(delta: float) -> void:
	if _responder != null and is_instance_valid(_net):
		for packet in mini(_responder.get_available_packet_count(), 64):
			var bytes := _responder.get_packet()
			var address := _responder.get_packet_ip()
			var port := _responder.get_packet_port()
			if bytes.size() > 2048: continue
			var query = JSON.parse_string(bytes.get_string_from_utf8())
			if not query is Dictionary or query.get("protocol") != PROTOCOL or query.get("type") != "query": continue
			var response := {"protocol": PROTOCOL, "type": "room", "id": _room_id, "number": _net.room_number, "name": _net.room_name, "port": _net._port, "players": _net._members.size(), "started": _net._started}
			_responder.set_dest_address(address, port)
			_responder.put_packet(JSON.stringify(response).to_utf8_buffer())
	if not searching or _query == null: return
	_timer -= delta
	if _timer <= 0.0: _send_query()
	var changed := false
	for packet in mini(_query.get_available_packet_count(), 128):
		var bytes := _query.get_packet()
		var address := _query.get_packet_ip()
		if bytes.size() > 2048: continue
		var room = JSON.parse_string(bytes.get_string_from_utf8())
		if not room is Dictionary or room.get("protocol") != PROTOCOL or room.get("type") != "room": continue
		if not NetGameNode.valid_room_number(str(room.get("number", ""))) or int(room.get("port", 0)) < 1 or int(room.get("port", 0)) > 65535: continue
		room["host"] = address
		room["seen"] = Time.get_ticks_msec()
		var identity := str(room.get("id", ""))
		if identity == "": continue
		# 同机测试的回环回复比广播更可靠，保留回环地址。
		if rooms.has(identity) and rooms[identity].host == "127.0.0.1": room.host = "127.0.0.1"
		changed = changed or not rooms.has(identity) or rooms[identity].players != room.players or rooms[identity].started != room.started
		rooms[identity] = room
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
