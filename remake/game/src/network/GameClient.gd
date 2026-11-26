extends Node
## 同一客户端入口使用本机权威或真正的 ENet 连接；不在客户端重新裁决牌局。

const Protocol = preload("res://src/domain/Protocol.gd")
const Discovery = preload("res://src/network/LanDiscovery.gd")
const Seats = preload("res://src/domain/Seats.gd")
const Host = preload("res://src/runtime/GameHost.gd")
const Backup = preload("res://src/network/AuthorityBackup.gd")
const STANDBY_INTERVAL_MS := 250
const RECOVERY_WINDOW_MS := 5 * 60 * 1000
const TABLE_COMMANDS := ["action", "hand_display", "auto_play", "center_wall", "ready", "move", "presentation_finished", "start_first"]
const CONNECT_TIMEOUT_MS := 10000
signal view_changed(view: Dictionary)
signal status_changed(text: String)
signal dice_updated(snapshot: Dictionary)
signal presentation_required(cue: Dictionary)
signal session_ended(reason: String)
signal ticket_changed(ticket: Dictionary)
signal voice_packet_received(packet: PackedByteArray)
signal voice_stream_reset(seat: int)
signal voice_connection_ended()
signal record_submission_status(state: Dictionary)
signal room_inspected(room: Dictionary)

var view := {}
var ticket := {}
var mode := ""
var local_port := 0
var _host: Node
var _api: SceneMultiplayer
var _peer: ENetMultiplayerPeer
var _profile := {}
var _address := ""
var _port := 0
var _connection := ""
var _peer_connections := {}
var _last_requests := {}
var _request_id := 0
var _finished_cue := ""
var _connect_started := -1
var _server := false
var _silent_restore := false
var _latest_dice := {}
var _room_number := ""
var _room_instance := ""
var _owned_service := false
var _discovery: Node
var _room_name := ""
var _voice_limits := {}
var _voice_epochs := {}
var _record_status := {}
var _hand_display_limits := {}
var _application_away := false
var _presence_revision := 0
var _sent_presence_revision := -1
var _acknowledged_view := -1
var _host_player_id := ""
var _host_seat := 1
var _leave_started := -1
var _standby_connection := ""
var _standby_next_send := 0
var _standby_state := {}
var _backup_key_job := Thread.new()
var _backup_private: CryptoKey
var _backup_public := {}
var _backup_keys := PackedByteArray()
var _wrapped_keys := PackedByteArray()
var _backup_sequence := 0
var _backup_scheduled := false
var _received_sequence := 0
var _pending_publications: Array[Dictionary] = []
var _lan_recovering := false
var _recovery_started := -1
var _promoting := false
var _inspecting := false

func _ready() -> void:
	_api = SceneMultiplayer.new()
	_api.root_path = get_path()
	_api.server_relay = false
	_api.allow_object_decoding = false
	get_tree().set_multiplayer(_api, get_path())
	_api.peer_connected.connect(_on_peer_connected)
	_api.peer_disconnected.connect(_on_peer_disconnected)
	_api.connected_to_server.connect(_on_connected)
	_api.connection_failed.connect(_connection_failed)
	_api.server_disconnected.connect(_server_disconnected)
	process_mode = Node.PROCESS_MODE_ALWAYS

func _new_id() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()

func start_solo(profile: Dictionary, settings: Dictionary = {}) -> bool:
	_reset()
	mode = "solo"
	_profile = profile.duplicate(true)
	_connection = "local-" + _new_id()
	_create_host("solo", "单机", settings)
	var nickname: Variant = _profile.get("nickname", "牌友")
	var joined: Dictionary = _host.join(_player_id(), nickname, _connection, _player_profile(_profile)) if nickname is String else {}
	if joined.is_empty():
		status_changed.emit("昵称需要1至6个汉字、字母或数字")
		return false
	_host.set_draw_style(_connection, str(profile.get("draw_style", "a")))
	_take_ticket(joined.ticket)
	_take_view(joined.view)
	_host.set_ready(_connection, true)
	return true

func host_lan(profile: Dictionary, room_number: String, port: int = 0, settings: Dictionary = {}) -> bool:
	_reset()
	# LAN authority outlives its creator leaving the seat or returning to the lobby.
	var service = get_script().new()
	service.name = "HostedRoom_" + _new_id()
	get_tree().root.add_child(service)
	service._owned_service = true
	var owner_token := _new_id()
	var host_settings := settings.duplicate()
	host_settings.owner_token_hash = owner_token.sha256_text()
	if not service.start_server(room_number, port, host_settings, "lan"):
		service.queue_free()
		status_changed.emit("房间未能启动，请检查网络后重试")
		return false
	var assigned_port: int = service.local_port
	var identity := profile.duplicate(true)
	identity.mode = "lan"
	identity.room_number = room_number
	if str(identity.get("player_id", "")).is_empty(): identity.player_id = _new_id()
	service._host_player_id = identity.player_id
	identity.owner_token = owner_token
	var connected := connect_room("127.0.0.1", assigned_port, identity)
	local_port = assigned_port
	if not connected: service.queue_free()
	return connected

func start_server(room_number: String, port: int, settings: Dictionary = {}, host_mode: String = "online") -> bool:
	_reset()
	mode = host_mode
	_room_number = room_number
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_server(port, 8, 3) != OK:
		return false
	_api.multiplayer_peer = _peer
	_server = true
	local_port = _peer.get_host().get_local_port()
	var options := settings.duplicate()
	if not options.has("require_start"):
		options.require_start = false
	_create_host(host_mode, room_number, options)
	_room_instance = str(_host.public_room().get("room_instance_id", ""))
	_room_name = str(settings.get("room_name", "麻将局")).left(24)
	if host_mode == "lan":
		_discovery = Discovery.new()
		add_child(_discovery)
		if not _discovery.advertise(self):
			_reset()
			return false
	return true

func discovery_info() -> Dictionary:
	if _host == null or not _server: return {}
	var room: Dictionary = _host.public_room()
	if room.is_empty(): return {}
	return {"number": _room_number, "name": _room_name, "port": local_port,
		"players": room.seats.filter(func(seat): return not seat.player_id.is_empty()).size(),
		"started": room.phase == 1, "instance": str(room.get("room_instance_id", "")),
		"seats": room.seats, "owner_player_id": room.owner_player_id}

func inspect_room(address: String, port: int) -> bool:
	if not connect_room(address, port, {"mode":"lan"}): return false
	_inspecting = true
	return true

func connect_room(address: String, port: int, profile: Dictionary, saved_ticket: Dictionary = {}) -> bool:
	_reset()
	if address.strip_edges().is_empty() or port < 1 or port > 65535:
		status_changed.emit("请填写有效的房间地址和端口")
		return false
	mode = "lan" if profile.get("mode", "online") == "lan" else "online"
	_profile = profile.duplicate(true)
	_address = address.strip_edges()
	_port = port
	ticket = saved_ticket.duplicate(true)
	_silent_restore = not ticket.is_empty()
	_peer = ENetMultiplayerPeer.new()
	if _peer.create_client(_address, port, 3) != OK:
		status_changed.emit("暂时无法连接房间")
		return false
	_api.multiplayer_peer = _peer
	_connect_started = Time.get_ticks_msec()
	status_changed.emit("正在恢复房间" if _silent_restore else "正在连接房间")
	return true

func _create_host(host_mode: String, room_number: String, settings: Dictionary) -> void:
	var script = load("res://src/runtime/GameHost.gd")
	_host = script.new()
	_host.name = "Authority"
	add_child(_host)
	_host.configure(room_number, host_mode, 1, settings)
	_host.view_changed.connect(_on_host_view)
	_host.dice_updated.connect(_on_host_dice)
	_host.presentation_required.connect(_on_host_cue)
	_host.room_closed.connect(_on_room_closed)

func _player_id() -> String:
	if str(_profile.get("player_id", "")).is_empty():
		_profile.player_id = _new_id()
	return str(_profile.player_id)

static func _player_profile(profile: Dictionary) -> Dictionary:
	var fields := {}
	for key in ["nickname", "avatar", "voice_pack", "suit_order", "hand_priority", "novice"]:
		if profile.has(key):
			fields[key] = profile[key]
	return fields

func set_player_profile(profile: Dictionary) -> bool:
	return _command({"kind": "player_profile", "profile": _player_profile(profile)})

func set_difficulty(level: String) -> bool:
	if view.get("room", {}).is_empty(): return false
	return _command({"kind":"difficulty", "instance":view.room.room_instance_id, "level":level})

func set_ready(ready: bool) -> bool:
	return _command({"kind": "ready", "ready": ready})

func start_first_round() -> bool:
	return _command({"kind":"start_first"})

func move_to_empty_seat(seat: int) -> bool:
	return _command({"kind": "move", "seat": seat})

func submit(prompt: int, action: String, tile_id: int = -1) -> bool:
	if view.get("room", {}).is_empty():
		return false
	return _command({"kind": "action", "instance": view.room.room_instance_id,
		"round": view.room.round_number, "prompt": prompt, "action": action, "tile_id": tile_id})

func set_auto_play(enabled: bool) -> bool:
	if view.get("round", {}).get("phase", "") not in ["dealt", "turn", "response", "ready_draw"]:
		return false
	return _command({"kind": "auto_play", "instance": view.room.room_instance_id,
		"round": view.room.round_number, "enabled": enabled})

func center_wall(seat: int) -> bool:
	return _command({"kind": "center_wall", "seat": seat})

func set_draw_style(style: String) -> bool:
	return _command({"kind": "draw_style", "style": style})

func set_hand_display(display: Dictionary) -> bool:
	if view.get("round", {}).is_empty() or var_to_bytes(display).size() > 4096: return false
	return _command({"kind": "hand_display", "instance": view.room.room_instance_id,
		"round": view.room.round_number, "prompt": view.round.prompt_id, "display": display.duplicate(true)})

func request_record_submission() -> bool:
	if view.get("room", {}).is_empty(): return false
	return _command({"kind": "submit_record", "instance": view.room.room_instance_id, "round": view.room.round_number})

func voice_chat_allowed() -> bool:
	return mode == "lan" and not waiting_for_foreground_view() and _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func set_application_away(away: bool) -> void:
	if _application_away == away: return
	_application_away = away
	_presence_revision += 1
	if mode in ["lan", "online"] and not view.is_empty():
		_send_presence()

func _send_presence() -> void:
	if _command({"kind": "presence", "instance": view.room.room_instance_id, "revision": _presence_revision, "away": _application_away}):
		_sent_presence_revision = _presence_revision

func waiting_for_foreground_view() -> bool:
	if mode not in ["lan", "online"]: return false
	var own: Dictionary = view.get("presence", {})
	return _application_away or own.get("revision", -1) != _presence_revision or own.get("away", true)

func report_mic_active(instance: String, seat: int, active: bool) -> bool:
	if mode not in ["lan", "online"] or view.get("room", {}).get("room_instance_id") != instance or view.get("seat") != seat:
		return false
	return _command({"kind": "mic_active", "instance": instance, "seat": seat, "active": active})

func send_local_voice(packet: PackedByteArray) -> void:
	if voice_chat_allowed() and _valid_voice(packet):
		client_voice.rpc_id(1, packet)

static func _valid_voice(packet: PackedByteArray) -> bool:
	return packet.size() == 966 and packet[0] == 1

@rpc("any_peer", "call_remote", "unreliable", 2)
func client_voice(packet: PackedByteArray) -> void:
	if not _server or mode != "lan" or _host == null or not _valid_voice(packet): return
	var sender := _api.get_remote_sender_id()
	if not _can_send_to(sender): return
	var connection: String = _peer_connections[sender]
	if _host.connection_away(connection): return
	var seat: int = _host.authenticated_seat(connection)
	if seat < 0: return
	var now := Time.get_ticks_msec()
	var state: Dictionary = _voice_limits.get(connection, {"start": now, "count": 0, "last": -1})
	if now - state.start >= 1000:
		state.start = now
		state.count = 0
	if state.count >= 75: return
	var sequence := int(packet.decode_u32(2))
	# Allow real u32 wrap; a restarted sender has a new authenticated connection.
	var distance := (sequence - int(state.last) + 4294967296) % 4294967296
	if state.last >= 0 and (distance < 1 or distance >= 2147483648): return
	state.last = sequence
	state.count += 1
	_voice_limits[connection] = state
	var outgoing := packet.duplicate()
	outgoing[1] = seat
	for peer_id in _peer_connections:
		if peer_id != sender and _can_send_to(peer_id) and _host.authenticated_seat(_peer_connections[peer_id]) >= 0 and not _host.connection_away(_peer_connections[peer_id]):
			server_voice.rpc_id(peer_id, connection, outgoing)

@rpc("authority", "call_remote", "unreliable", 2)
func server_voice(epoch: String, packet: PackedByteArray) -> void:
	if _server or _api.get_remote_sender_id() != 1 or not voice_chat_allowed() or not _valid_voice(packet) or packet[1] > 3: return
	var seat := int(packet[1])
	if seat == int(view.seat): return
	if _voice_epochs.get(seat, "") != epoch:
		_voice_epochs[seat] = epoch
		voice_stream_reset.emit(seat)
	voice_packet_received.emit(packet)

func finish_presentation(cue: Dictionary) -> void:
	if _host != null and mode == "solo":
		_host.finish_presentation(cue.get("room_instance_id", ""), int(cue.get("round_number", -1)),
			int(cue.get("prompt_id", -1)), int(cue.get("seat", -1)))
	elif mode in ["lan","online"] and not view.is_empty() and cue.get("seat",-1)==view.seat:
		if not view.has("presentation") or cue.get("room_instance_id")!=view.room.room_instance_id or cue.get("round_number")!=view.room.round_number or cue.get("prompt_id")!=view.round.prompt_id:return
		var key:="%s/%s/%s" % [cue.get("room_instance_id",""),cue.get("round_number",-1),cue.get("prompt_id",-1)]
		if key==_finished_cue:return
		if _command({"kind":"presentation_finished","instance":cue.get("room_instance_id",""),
			"round":cue.get("round_number",-1),"prompt":cue.get("prompt_id",-1)}):_finished_cue=key

func set_paused(paused: bool) -> void:
	if _host != null and mode == "solo":
		_host.set_solo_paused(paused)

func _command(packet: Dictionary) -> bool:
	if _leave_started >= 0: return false
	if packet.kind in TABLE_COMMANDS and waiting_for_foreground_view(): return false
	if _host != null and not _connection.is_empty():
		return _dispatch(_connection, packet)
	if _peer == null or _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED or view.is_empty():
		return false
	var remote := _peer.get_peer(1)
	if remote == null or remote.get_state()!=ENetPacketPeer.STATE_CONNECTED:return false
	_request_id += 1
	packet.request_id = _request_id
	client_request.rpc_id(1, packet)
	return true

func _dispatch(connection_id: String, packet: Dictionary) -> bool:
	if packet.get("kind") in TABLE_COMMANDS and _host.connection_away(connection_id): return false
	match packet.get("kind", ""):
		"leave":
			return _host.disconnect_human(connection_id, true)
		"difficulty":
			return packet.get("instance") is String and packet.get("level") is String and _host.set_difficulty(connection_id, packet.instance, packet.level)
		"presentation_finished":
			if packet.has("seat") or not packet.get("instance") is String or not _integer(packet.get("round"),1,2147483647) or not _integer(packet.get("prompt"),0,2147483647):return false
			return _host.acknowledge_presentation(connection_id,packet.instance,packet.round,packet.prompt)
		"presence", "foreground_received":
			if not packet.get("instance") is String or packet.has("seat") or not _integer(packet.get("revision"), 0, 2147483647): return false
			if packet.kind == "foreground_received":
				return _host.acknowledge_foreground_view(connection_id, packet.instance, packet.revision)
			return packet.get("away") is bool and _host.set_application_away(connection_id, packet.instance, packet.revision, packet.away)
		"mic_active":
			if not packet.get("instance") is String or not _integer(packet.get("seat"), 0, 3) or not packet.get("active") is bool: return false
			return _host.set_mic_active(connection_id, packet.instance, packet.seat, packet.active)
		"auto_play":
			if not packet.get("instance") is String or not packet.get("enabled") is bool or not _integer(packet.get("round"), 1, 2147483647): return false
			return _host.set_auto_play(connection_id, packet.instance, packet.round, packet.enabled)
		"player_profile":
			return packet.get("profile") is Dictionary and _host.set_player_profile(connection_id, packet.profile)
		"hand_display":
			if not packet.get("instance") is String or not packet.get("display") is Dictionary: return false
			if not _integer(packet.get("round"), 1, 2147483647) or not _integer(packet.get("prompt"), 0, 2147483647) or var_to_bytes(packet.display).size() > 4096: return false
			var now := Time.get_ticks_msec()
			var limit: Dictionary = _hand_display_limits.get(connection_id, {"start": now, "count": 0})
			if now - limit.start >= 1000:
				limit = {"start": now, "count": 0}
			if limit.count >= 60: return false
			limit.count += 1
			_hand_display_limits[connection_id] = limit
			return _host.set_hand_display(connection_id, packet.instance, packet.round, packet.prompt, packet.display)
		"submit_record":
			if not packet.get("instance") is String or not _integer(packet.get("round"), 1, 2147483647): return false
			return _host.request_record_submission(connection_id, packet.instance, packet.round)
		"draw_style":
			return packet.get("style") is String and _host.set_draw_style(connection_id, packet.style)
		"ready":
			return packet.get("ready") is bool and _host.set_ready(connection_id, packet.ready)
		"start_first":
			return _host.start_first_round(connection_id)
		"move", "center_wall":
			if not _integer(packet.get("seat"), 0, 3): return false
			if packet.kind == "center_wall": return _host.center_wall(connection_id, packet.seat)
			var moved: bool = _host.move_to_empty_seat(connection_id, packet.seat)
			if moved: _refresh_standby()
			return moved
		"action":
			if not packet.get("instance") is String or not packet.get("action") is String: return false
			if not _integer(packet.get("round"), 1, 2147483647) or not _integer(packet.get("prompt"), 0, 2147483647) or not _integer(packet.get("tile_id"), -1, 107): return false
			return _host.submit(connection_id, packet.instance, packet.round, packet.prompt, packet.action, packet.tile_id)
	return false

func _on_peer_connected(peer_id: int) -> void:
	if _server:
		_peer_connections[peer_id] = "net-" + _new_id()

func _can_send_to(peer_id: int) -> bool:
	# ENet can drop several links before the room receives their individual callbacks.
	return _peer_connections.has(peer_id) and _peer.get_peer(peer_id).get_state() == ENetPacketPeer.STATE_CONNECTED

func _on_peer_disconnected(peer_id: int) -> void:
	if _server and _peer_connections.has(peer_id):
		var connection_id: String = _peer_connections[peer_id]
		_peer_connections.erase(peer_id)
		_backup_public.erase(connection_id)
		_last_requests.erase(connection_id)
		_voice_limits.erase(connection_id)
		_hand_display_limits.erase(connection_id)
		_host.disconnect_human(connection_id)
		_refresh_standby()

func _on_connected() -> void:
	_request_id = 1
	if _peer != null:
		var remote: ENetPacketPeer = _peer.get_peer(1)
		if remote != null:
			remote.ping_interval(1500)
			remote.ping()
	if _inspecting:
		client_request.rpc_id(1, {"kind":"inspect", "request_id":1, "protocol":Protocol.PROTOCOL_VERSION,
			"variant":Protocol.VARIANT_ID, "rules":Protocol.RULES_VERSION})
		return
	_finished_cue = ""
	_sent_presence_revision = _presence_revision
	var profile := _player_profile(_profile)
	for key in ["player_id", "room_number", "draw_style", "owner_token", "requested_seat"]:
		if _profile.has(key):
			profile[key] = _profile[key]
	client_request.rpc_id(1, {"kind": "hello", "request_id": 1, "protocol": Protocol.PROTOCOL_VERSION,
		"variant": Protocol.VARIANT_ID, "rules": Protocol.RULES_VERSION, "profile": profile, "ticket": ticket,
		"away": _application_away, "presence_revision": _presence_revision})

@rpc("any_peer", "call_remote", "reliable", 0)
func client_request(packet: Dictionary) -> void:
	if not _server or _host == null:
		return
	var sender := _api.get_remote_sender_id()
	if not _can_send_to(sender) or not _integer(packet.get("request_id"), 1, 2147483647):
		return
	var connection_id: String = _peer_connections[sender]
	if packet.request_id <= int(_last_requests.get(connection_id, 0)):
		return
	_last_requests[connection_id] = packet.request_id
	if packet.get("kind") == "inspect":
		if packet.get("protocol") != Protocol.PROTOCOL_VERSION or packet.get("variant") != Protocol.VARIANT_ID or packet.get("rules") != Protocol.RULES_VERSION:
			server_packet.rpc_id(sender, {"kind":"rejected", "reason":"version_mismatch"})
		elif packet.request_id == 1:
			server_packet.rpc_id(sender, {"kind":"inspected", "room":discovery_info()})
		return
	if packet.get("kind") == "hello":
		if packet.get("protocol") != Protocol.PROTOCOL_VERSION or packet.get("variant") != Protocol.VARIANT_ID or packet.get("rules") != Protocol.RULES_VERSION:
			server_packet.rpc_id(sender, {"kind": "rejected", "reason": "version_mismatch"})
			return
		if not packet.get("profile") is Dictionary or not packet.get("ticket") is Dictionary:
			return
		var away: Variant = packet.get("away", false)
		var revision: Variant = packet.get("presence_revision", 0)
		if not away is bool or not _integer(revision, 0, 2147483647): return
		var profile: Dictionary = packet.profile
		if profile.has("requested_seat") and not _integer(profile.requested_seat, 0, 3): return
		var saved: Dictionary = packet.ticket
		if saved.is_empty() and str(profile.get("room_number", "")) != _room_number:
			server_packet.rpc_id(sender, {"kind": "rejected", "reason": "room_expired"})
			return
		var result := {}
		if not saved.is_empty():
			result = _host.resume(str(saved.get("room_instance_id", "")), str(saved.get("player_id", "")), str(saved.get("member_token", "")), connection_id, _player_profile(profile), away, revision)
			if result.is_empty():
				server_packet.rpc_id(sender, {"kind": "rejected", "reason": "room_expired",
					"instance": _room_instance})
				return
			server_packet.rpc_id(sender, {"kind": "joined", "ticket": saved, "view": result})
		else:
			if profile.get("nickname") is String:
				result = _host.join(str(profile.get("player_id", "")), profile.nickname, connection_id, _player_profile(profile), away, revision, str(profile.get("owner_token", "")), int(profile.get("requested_seat", -1)))
			if result.is_empty():
				server_packet.rpc_id(sender, {"kind": "rejected", "reason": "join_failed"})
				return
			server_packet.rpc_id(sender, {"kind": "joined", "ticket": result.ticket, "view": result.view})
		_host.set_draw_style(connection_id, str(profile.get("draw_style", "a")))
		if _server and mode == "lan":
			if not _host_player_id.is_empty() and profile.get("player_id") != _host_player_id:
				request_backup_key.rpc_id(sender)
			_refresh_standby()
		if not _latest_dice.is_empty(): server_packet.rpc_id(sender, {"kind": "dice", "state": _latest_dice})
	else:
		var accepted := _dispatch(connection_id, packet)
		if accepted and packet.get("kind") == "leave":
			server_packet.rpc_id(sender, {"kind":"left"})
			_refresh_standby()
		elif not accepted and packet.get("kind") not in ["hand_display", "presence", "foreground_received"]:
			server_packet.rpc_id(sender, {"kind": "invalid_action"})

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func server_dice_pose(state: Dictionary) -> void:
	if not _server and _api.get_remote_sender_id() == 1 and _connect_started < 0:
		dice_updated.emit(state)

@rpc("authority", "call_remote", "reliable", 0)
func server_packet(packet: Dictionary) -> void:
	if _server or _api.get_remote_sender_id() != 1:
		return
	if _leave_started >= 0:
		if packet.get("kind") in ["left", "closed", "rejected"]: _complete_leave()
		return
	match packet.get("kind"):
		"inspected":
			if not _inspecting or not packet.get("room") is Dictionary: return
			var summary: Dictionary = packet.room.duplicate(true)
			summary.host = _address
			summary.port = _port
			_reset()
			room_inspected.emit(summary)
		"joined":
			if _connect_started < 0:
				return
			_connect_started = -1
			_profile.erase("owner_token")
			_recovery_started = -1
			_take_ticket(packet.ticket)
			_take_view(packet.view)
			status_changed.emit("已进入房间")
		"view":
			if _connect_started < 0:
				_take_view(packet.view)
		"dice":
			if _connect_started < 0:
				dice_updated.emit(packet.state)
		"cue":
			if _connect_started < 0:
				presentation_required.emit(packet.cue)
		"invalid_action": status_changed.emit("该操作已过期，请按当前提示操作")
		"closed":
			_reset()
			session_ended.emit("room_expired")
		"rejected":
			var reason: String = packet.get("reason", "join_failed")
			if reason == "room_expired" and mode == "lan" and not ticket.is_empty() and packet.get("instance", "") != ticket.get("room_instance_id", "") and _recovery_started < 0:
				_begin_lan_recovery()
				return
			_reset()
			status_changed.emit("需要相同版本的游戏" if reason == "version_mismatch" else ("" if reason == "room_expired" else "暂时无法加入该房间"))
			session_ended.emit(reason)

func _take_ticket(raw: Dictionary) -> void:
	ticket = raw.duplicate(true)
	ticket.merge({"address": _address, "port": _port, "mode": mode}, true)
	ticket_changed.emit(ticket.duplicate(true))

func _take_view(state: Dictionary) -> void:
	if mode in ["lan", "online"] and state.get("room", {}).get("room_instance_id") != ticket.get("room_instance_id"): return
	view = state.duplicate(true)
	var submission: Dictionary = view.get("record_submission", {})
	if submission != _record_status:
		_record_status = submission.duplicate(true)
		record_submission_status.emit(_record_status.duplicate(true))
	view_changed.emit(view)
	if mode not in ["lan", "online"] or view.is_empty(): return
	if _sent_presence_revision != _presence_revision:
		_send_presence()
	elif not _application_away and view.presence.revision == _presence_revision and view.presence.needs_ack and _acknowledged_view != _presence_revision:
		if _command({"kind": "foreground_received", "instance": view.room.room_instance_id, "revision": _presence_revision}):
			_acknowledged_view = _presence_revision

func _on_host_view(connection_id: String, state: Dictionary) -> void:
	if not _standby_connection.is_empty():
		_queue_publication({"connection": connection_id, "view": state})
		return
	_deliver_host_view(connection_id, state)

func _queue_publication(item: Dictionary) -> void:
	item.sequence = _backup_sequence + 1
	_pending_publications.append(item)
	if not _backup_scheduled:
		_backup_scheduled = true
		_flush_publications.call_deferred()

func _flush_publications() -> void:
	_backup_scheduled = false
	if not _pending_publications.is_empty() and _pending_publications.back().sequence > _backup_sequence:
		_send_standby_now()

func _deliver_host_view(connection_id: String, state: Dictionary) -> void:
	if connection_id == _connection:
		_take_view(state)
	else:
		for peer_id in _peer_connections:
			if _peer_connections[peer_id] == connection_id and _can_send_to(peer_id):
				server_packet.rpc_id(peer_id, {"kind": "view", "view": state})
				break

func _on_host_dice(state: Dictionary) -> void:
	_latest_dice = state.duplicate(true)
	dice_updated.emit(state)
	if _server:
		for peer_id in _peer_connections:
			if _can_send_to(peer_id) and not _host.view_for(_peer_connections[peer_id]).is_empty():
				if state.get("phase") == "settled":
					server_packet.rpc_id(peer_id, {"kind": "dice", "state": state})
				else:
					server_dice_pose.rpc_id(peer_id, state)

func _on_host_cue(cue: Dictionary) -> void:
	if not _standby_connection.is_empty():
		_queue_publication({"cue": cue})
		return
	_deliver_host_cue(cue)

func _deliver_host_cue(cue: Dictionary) -> void:
	presentation_required.emit(cue)
	if _server:
		for peer_id in _peer_connections:
			if _can_send_to(peer_id) and _host.authenticated_seat(_peer_connections[peer_id]) == cue.seat:
				server_packet.rpc_id(peer_id, {"kind": "cue", "cue": cue})

func _on_room_closed() -> void:
	if _server:
		for peer_id in _peer_connections:
			if _can_send_to(peer_id): server_packet.rpc_id(peer_id, {"kind": "closed"})
	view = {}
	session_ended.emit("room_expired")
	# Let the reliable close notification leave the socket before destroying an owned LAN service.
	if _owned_service:
		await get_tree().create_timer(0.2).timeout
		queue_free()

func _refresh_standby() -> void:
	if not _server or mode != "lan" or _host == null or _host_player_id.is_empty():
		return
	var room: Dictionary = _host.public_room()
	if room.is_empty():
		return
	var host_seat := -1
	for seat in 4:
		if str(room.seats[seat].player_id) == _host_player_id:
			host_seat = seat
			break
	if host_seat < 0:
		host_seat = _host_seat
	else:
		_host_seat = host_seat
	var candidate: int = host_seat
	for _step in 4:
		candidate = Seats.next(candidate)
		if candidate == host_seat:
			break
		var occupant: Dictionary = room.seats[candidate]
		if str(occupant.player_id) == "" or str(occupant.player_id) == _host_player_id or not occupant.connected:
			continue
		for connection_id in _peer_connections.values():
			if _backup_public.has(connection_id) and _host.authenticated_seat(str(connection_id)) == candidate:
				_select_standby(str(connection_id))
				return
	_select_standby("")

@rpc("authority", "call_remote", "reliable", 0)
func request_backup_key() -> void:
	if _server or mode != "lan" or ticket.is_empty() or _api.get_remote_sender_id() != 1: return
	if _backup_private != null:
		offer_backup_key.rpc_id(1, _backup_private.save_to_string(true))
	elif not _backup_key_job.is_started():
		# RSA generation must not stall ENet polling or the microphone stream.
		_backup_key_job.start(_generate_backup_key)

static func _generate_backup_key() -> CryptoKey:
	return Crypto.new().generate_rsa(2048)

@rpc("any_peer", "call_remote", "reliable", 0)
func offer_backup_key(public_text: String) -> void:
	var connection: String = _peer_connections.get(_api.get_remote_sender_id(), "")
	if not _server or mode != "lan" or _host_player_id.is_empty() or connection.is_empty() or _backup_public.has(connection): return
	if _host.authenticated_seat(connection) < 0 or public_text.length() not in range(1, 1025): return
	var key := CryptoKey.new()
	if key.load_from_string(public_text, true) == OK:
		_backup_public[connection] = key
		_refresh_standby()

func _select_standby(connection_id: String) -> void:
	if connection_id == _standby_connection: return
	for peer_id in _peer_connections:
		if _peer_connections[peer_id] == _standby_connection and _can_send_to(peer_id):
			standby_state.rpc_id(peer_id, {})
	_standby_connection = connection_id
	_backup_keys.clear()
	_wrapped_keys.clear()
	if not connection_id.is_empty():
		var crypto := Crypto.new()
		_backup_keys = crypto.generate_random_bytes(64)
		_wrapped_keys = crypto.encrypt(_backup_public[connection_id], _backup_keys)
		_send_standby_now()
	else:
		_release_publications(_backup_sequence + 1)

func _release_publications(sequence: int) -> void:
	while not _pending_publications.is_empty() and int(_pending_publications.front().sequence) <= sequence:
		var item: Dictionary = _pending_publications.pop_front()
		if item.has("cue"): _deliver_host_cue(item.cue)
		else: _deliver_host_view(item.connection, item.view)

@rpc("any_peer", "call_remote", "reliable", 0)
func backup_received(sequence: int) -> void:
	if _server and mode == "lan" and sequence <= _backup_sequence and _peer_connections.get(_api.get_remote_sender_id(), "") == _standby_connection and not _standby_connection.is_empty():
		_release_publications(sequence)

func _send_standby() -> void:
	if not _server or mode != "lan" or _standby_connection.is_empty() or _host == null:
		return
	if Time.get_ticks_msec() - _standby_next_send < STANDBY_INTERVAL_MS:
		return
	_send_standby_now()


func _send_standby_now() -> int:
	if not _server or mode != "lan" or _standby_connection.is_empty() or _host == null:
		return 0
	_standby_next_send = Time.get_ticks_msec()
	for peer_id in _peer_connections:
		if _peer_connections[peer_id] == _standby_connection and _can_send_to(peer_id):
			var state: Dictionary = _host.export_authority()
			if state.is_empty() or _wrapped_keys.is_empty(): return 0
			var packet := Backup.seal({"state": state, "port": local_port, "number": _room_number,
				"instance": state.instance}, _backup_keys)
			if packet.is_empty(): return 0
			_backup_sequence += 1
			packet.sequence = _backup_sequence
			packet.wrapped = _wrapped_keys
			packet.instance = state.instance
			standby_state.rpc_id(peer_id, packet)
			return _backup_sequence
	return 0

@rpc("authority", "call_remote", "reliable", 0)
func standby_state(packet: Dictionary) -> void:
	if _server or mode != "lan" or _api.get_remote_sender_id() != 1: return
	if packet.is_empty():
		_standby_state.clear()
	elif packet.get("instance", "") == ticket.get("room_instance_id", "") and packet.get("sequence") is int and packet.sequence > _received_sequence:
		_standby_state = packet.duplicate(true)
		_received_sequence = packet.sequence
		backup_received.rpc_id(1, _received_sequence)

## 备用副本所在的真人升级为新服务器。旧房主本人重启后仍凭原票据回来。
func promote_lan_from_standby(packet: Dictionary, saved_ticket: Dictionary) -> bool:
	if mode not in ["", "lan"] or saved_ticket.get("mode") != "lan" or packet.get("state", {}).get("mode") != "lan": return false
	_reset()
	mode = "lan"
	_host_player_id = str(saved_ticket.get("player_id", ""))
	_host_seat = int(saved_ticket.get("seat", 1))
	if _host_player_id.is_empty() or packet.get("instance") != saved_ticket.get("room_instance_id"): return false
	_room_number = str(packet.get("number", ""))
	if _room_number.is_empty():
		return false
	_peer = ENetMultiplayerPeer.new()
	var opened := _peer.create_server(int(packet.get("port", 0)), 8, 3)
	if opened != OK:
		_peer.close()
		_peer = ENetMultiplayerPeer.new()
		opened = _peer.create_server(0, 8, 3)
	if opened != OK:
		_peer = null
		return false
	_api.multiplayer_peer = _peer
	_server = true
	local_port = _peer.get_host().get_local_port()
	_host = Host.new()
	_host.name = "Authority"
	add_child(_host)
	_host.view_changed.connect(_on_host_view)
	_host.dice_updated.connect(_on_host_dice)
	_host.presentation_required.connect(_on_host_cue)
	_host.room_closed.connect(_on_room_closed)
	if not _host.restore_authority(packet.get("state", {}), {}):
		_reset()
		return false
	_room_instance = str(packet.instance)
	_room_name = _room_number
	_owned_service = true
	_discovery = Discovery.new()
	add_child(_discovery)
	if not _discovery.advertise(self):
		_reset()
		return false
	status_changed.emit("已接替房主")
	return true


func _promote_from_standby() -> void:
	if mode != "lan" or _promoting: return
	_promoting = true
	var packet := Backup.unseal(_standby_state, _backup_private)
	var profile := _profile.duplicate(true)
	var saved := ticket.duplicate(true)
	_reset()
	if not packet.is_empty():
		for attempt in 40:
			if not is_inside_tree() or not _promoting: return
			var service = get_script().new()
			service.name = "PromotedRoom_" + _new_id()
			get_tree().root.add_child(service)
			if service.promote_lan_from_standby(packet, saved):
				_promoting = false
				connect_room("127.0.0.1", service.local_port, profile, saved)
				return
			service.queue_free()
			await get_tree().create_timer(0.1).timeout
	_promoting = false
	status_changed.emit("接管房主失败，正在寻找房间")
	ticket = saved
	_begin_lan_recovery()

func _begin_lan_recovery() -> void:
	_lan_recovering = true
	if _recovery_started < 0: _recovery_started = Time.get_ticks_msec()
	_connect_started = -1
	if _peer != null:
		_peer.close()
	_peer = null
	if _api != null:
		_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	if is_instance_valid(_discovery):
		_discovery.queue_free()
	_discovery = Discovery.new()
	add_child(_discovery)
	_discovery.rooms_updated.connect(_on_recovery_rooms)
	_discovery.search()
	status_changed.emit("房主已断开，正在等待新服务器接替")


func _on_recovery_rooms() -> void:
	if not _lan_recovering or not is_instance_valid(_discovery):
		return
	var want := str(ticket.get("room_instance_id", ""))
	for room in _discovery.rooms.values():
		if str(room.get("instance", "")) != want or str(room.get("host", "")) == "":
			continue
		var profile: Dictionary = _profile.duplicate(true)
		var saved: Dictionary = ticket.duplicate(true)
		_lan_recovering = false
		_discovery.rooms_updated.disconnect(_on_recovery_rooms)
		_discovery.stop_search()
		_discovery.queue_free()
		_discovery = null
		status_changed.emit("已找到接替的房主，正在重新进入")
		var started := _recovery_started
		connect_room(str(room.host), int(room.port), profile, saved)
		_recovery_started = started
		return
	# A link loss alone does not establish authority loss. Query the room first.
	if not _standby_state.is_empty() and Time.get_ticks_msec() - _recovery_started >= 2000:
		_promote_from_standby()
		return
	if Time.get_ticks_msec() - _recovery_started >= RECOVERY_WINDOW_MS:
		_lan_recovering = false
		_discovery.stop_search()
		_discovery.queue_free()
		_discovery = null
		_reset()
		status_changed.emit("暂时无法连接原房间")
		session_ended.emit("connection_failed")


func _process(_delta: float) -> void:
	if _backup_key_job.is_started() and not _backup_key_job.is_alive():
		_backup_private = _backup_key_job.wait_to_finish()
		if mode == "lan" and _backup_private != null and _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			offer_backup_key.rpc_id(1, _backup_private.save_to_string(true))
	if _connect_started >= 0 and Time.get_ticks_msec() - _connect_started > CONNECT_TIMEOUT_MS:
		_connection_failed()
	_send_standby()
	if _lan_recovering:
		_on_recovery_rooms()

func _connection_failed() -> void:
	if mode == "lan" and not ticket.is_empty():
		if not _lan_recovering: _begin_lan_recovery()
		return
	_reset()
	status_changed.emit("连接暂时不可用，请检查网络后重试")
	session_ended.emit("connection_failed")

func _server_disconnected() -> void:
	if _leave_started >= 0:
		_complete_leave()
		return
	if _lan_recovering or _promoting:
		return
	if mode == "lan" and not ticket.is_empty():
		_begin_lan_recovery()
		var room: Dictionary = view.get("room", {})
		if room.get("phase") == 1 or room.get("rolling", false): session_ended.emit("disconnected")
		return
	_reset()
	status_changed.emit("与房间的连接已断开")
	session_ended.emit("disconnected")

func leave() -> void:
	if _leave_started >= 0: return
	_promoting = false
	if _host != null and not _connection.is_empty():
		_host.disconnect_human(_connection, true)
	elif _command({"kind":"leave"}):
		# Keep the socket alive until the authority acknowledges the departure.
		_leave_started = Time.get_ticks_msec()
		while is_inside_tree() and _leave_started >= 0:
			await get_tree().process_frame
			if _leave_started >= 0 and Time.get_ticks_msec() - _leave_started > CONNECT_TIMEOUT_MS:
				_complete_leave()
		return
	_complete_leave()

func _complete_leave() -> void:
	_reset()
	session_ended.emit("left")

func resume_standby_search() -> bool:
	if mode != "lan" or _standby_state.is_empty() or _peer != null or not is_instance_valid(_discovery): return false
	_begin_lan_recovery()
	return true

func searching_for_lan_authority() -> bool:
	return _lan_recovering or _promoting

func cancel_recovery_connection() -> void:
	if _lan_recovering:
		_lan_recovering = false
		_discovery.stop_search()
		return
	if _silent_restore and not _server:
		_reset()

func _reset() -> void:
	_inspecting = false
	_leave_started = -1
	_connect_started = -1
	_server = false
	if is_instance_valid(_discovery):
		if _discovery.rooms_updated.is_connected(_on_recovery_rooms):
			_discovery.rooms_updated.disconnect(_on_recovery_rooms)
		_discovery.stop_search()
		_discovery.stop_advertise()
		_discovery.queue_free()
	_discovery = null
	_lan_recovering = false
	_recovery_started = -1
	_standby_state = {}
	_received_sequence = 0
	_backup_sequence = 0
	_pending_publications.clear()
	if _backup_key_job.is_started(): _backup_key_job.wait_to_finish()
	_backup_private = null
	_backup_public.clear()
	_backup_keys.clear()
	_wrapped_keys.clear()
	_standby_connection = ""
	_standby_next_send = 0
	_host_player_id = ""
	_host_seat = 1
	if _peer != null: _peer.close()
	_peer = null
	if not view.is_empty() and mode in ["lan", "online"]:
		voice_connection_ended.emit()
	if _api != null: _api.multiplayer_peer = OfflineMultiplayerPeer.new()
	if is_instance_valid(_host):
		if _host.has_method("shutdown"): _host.shutdown()
		_host.queue_free()
	_host = null
	_peer_connections.clear()
	_last_requests.clear()
	_voice_limits.clear()
	_voice_epochs.clear()
	_record_status.clear()
	_hand_display_limits.clear()
	for seat in 4: voice_stream_reset.emit(seat)
	_connection = ""
	_request_id = 0
	_finished_cue = ""
	_sent_presence_revision = -1
	_acknowledged_view = -1
	view = {}
	ticket = {}
	_latest_dice = {}
	local_port = 0
	_address = ""
	_port = 0
	_room_number = ""

func _exit_tree() -> void:
	_reset()

static func _integer(value: Variant, low: int, high: int) -> bool:
	return value is int and value >= low and value <= high

## Never sent via RPC or discovery_info(). A headless room writes it to its private heartbeat.
func directory_auth_state() -> Dictionary:
	return _host.directory_auth_state() if _server and mode == "online" and _host != null else {}


## 返回当前网络连接的真实状态与 ENet 往返延迟（毫秒）；单机模式返回 active=false。
func connection_metrics() -> Dictionary:
	if mode not in ["lan", "online"]:
		return {"active": false, "mode": mode, "state": "local", "rtt_ms": -1, "local_host": false}
	var is_local_host := mode == "lan" and _address in ["127.0.0.1", "localhost", "::1"]
	if _lan_recovering or _promoting:
		return {"active": true, "mode": mode, "state": "reconnecting", "rtt_ms": -1, "local_host": is_local_host}
	if _peer == null:
		return {"active": true, "mode": mode, "state": "disconnected", "rtt_ms": -1, "local_host": is_local_host}
	var status := _peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTING:
		return {"active": true, "mode": mode, "state": "connecting", "rtt_ms": -1, "local_host": is_local_host}
	if status != MultiplayerPeer.CONNECTION_CONNECTED:
		return {"active": true, "mode": mode, "state": "disconnected", "rtt_ms": -1, "local_host": is_local_host}
	var remote: ENetPacketPeer = _peer.get_peer(1)
	if remote == null or remote.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return {"active": true, "mode": mode, "state": "connecting", "rtt_ms": -1, "local_host": is_local_host}
	var last_rtt := remote.get_statistic(ENetPacketPeer.PEER_LAST_ROUND_TRIP_TIME)
	var mean_rtt := remote.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)
	var rtt_ms := -1
	if last_rtt > 0.0:
		rtt_ms = int(round(last_rtt))
	elif mean_rtt > 0.0 and mean_rtt < 500.0:
		rtt_ms = int(round(mean_rtt))
	elif is_local_host:
		rtt_ms = 1
	return {"active": true, "mode": mode, "state": "connected", "rtt_ms": rtt_ms, "local_host": is_local_host}
