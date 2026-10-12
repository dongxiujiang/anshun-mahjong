class_name NetGameNode
extends Node
## 房间与游戏由服务器权威处理，两端 RPC 节点路径固定。
signal room_ready(seat)
signal lobby_updated
signal lobby_notice(message)
signal state_updated
signal prompted(seat)
signal host_game_started
signal game_started
signal connection_error(message)
signal reconnecting(attempt, maximum)

const AUTO := "auto"
const START_DELAY := 3.0
const NEXT_ROUND_DELAY := 1.0
var host_mode := false
var dedicated := false
var my_seat := -1
var game: RoundState
var round_number := 0
var room_number := "0000"
var room_name := "麻将房间"
var lobby: Dictionary = {}
var _seat_peer: Dictionary = {}
var _peer_seat: Dictionary = {}
var _ctrl_hint: Dictionary = {}
var _members: Dictionary = {}
var _pending_peers: Dictionary = {}
var _owner_peer := 1
var _owner_token := ""
var _port := 7500
var _host_ai_fill := true
var _started := false
var _countdown := -1.0
var _ready_round := -1
var _swap: Dictionary = {}
var _swap_deadline := 0
var _join_number := ""
var _join_name := "玩家"
var _join_token := ""
var _resume_token := ""
var _server_ip := ""
var _server_port := 7500
var _reconnect_attempt := 0
var _reconnect_wait := -1.0
var _reconnecting := false
var _resume_sync_pending := false
var _client_joined := false
var _orphaned: Dictionary = {}
var _state_queued := false
var _state_revision := 0
var _received_revision := -1
var ai_speed := "fast"
var _sent_audio := {}
var state_metrics := {"sent": 0, "coalesced": 0, "bytes": 0, "full_bytes": 0}
var measure_state_traffic := false
var ack_flag := false
var ack_text := ""

static func valid_room_number(value: String) -> bool:
	if value.length() < 4 or value.length() > 8:
		return false
	for code in value.to_utf8_buffer():
		if code < 48 or code > 57:
			return false
	return true

func host(host_auto: bool, ai_fill: bool, port: int = 0, number: String = "0000", title: String = "麻将房间", server_only: bool = false, owner_token: String = "") -> bool:
	if not valid_room_number(number): return false
	var peer := ENetMultiplayerPeer.new()
	_port = port if port > 0 else 7500
	if peer.create_server(_port, 8) != OK: return false
	# 玩家只与服务器通信，禁止引擎向其他客户端转发连接/断线通知。
	# 同时断线时，转发可能向已关闭的 ENet 通道发包。
	var scene_multiplayer := multiplayer as SceneMultiplayer
	if scene_multiplayer != null: scene_multiplayer.server_relay = false
	multiplayer.multiplayer_peer = peer
	host_mode = true
	dedicated = server_only
	ai_speed = "fast" if dedicated else get_node("/root/GameConfig").ai_speed
	_host_ai_fill = ai_fill
	room_number = number
	room_name = title.strip_edges().left(24)
	if room_name == "": room_name = "麻将房间"
	_owner_token = owner_token
	_owner_peer = 0 if dedicated else 1
	game = RoundState.new()
	for seat in 4:
		_seat_peer[seat] = -1
		_ctrl_hint[seat] = AUTO
	if not dedicated:
		_seat_peer[0] = 1
		_peer_seat[1] = 0
		_ctrl_hint[0] = AUTO if host_auto else "human"
		_members[1] = {"name": get_node("/root/GameConfig").player_name, "ready": host_auto, "wants_dealer": false}
		my_seat = 0
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_publish_lobby()
	if not dedicated: room_ready.emit(my_seat)
	return true

func _process(delta: float) -> void:
	if not host_mode:
		if _reconnecting:
			_reconnect_wait -= delta
			if _reconnect_wait <= 0.0: _reconnect_step()
		return
	for seat in _orphaned.keys():
		if Time.get_ticks_msec() >= int(_orphaned[seat].get("until", 0)):
			_orphaned.erase(seat)
			_check_start()
			_publish_lobby()
	for peer in _pending_peers.keys():
		if Time.get_ticks_msec() - int(_pending_peers[peer]) > 10000:
			_pending_peers.erase(peer)
			multiplayer.multiplayer_peer.disconnect_peer(peer)
	if not _swap.is_empty() and Time.get_ticks_msec() > _swap_deadline:
		_swap.clear()
		_check_start()
		_publish_lobby()
	if _countdown >= 0.0:
		var previous := ceili(_countdown)
		_countdown -= delta
		if _countdown <= 0.0:
			if _started: _start_next_round()
			else: start_net_game()
		elif ceili(_countdown) != previous:
			_publish_lobby()

func _on_peer_connected(peer: int) -> void:
	_pending_peers[peer] = Time.get_ticks_msec()

@rpc("any_peer", "call_remote", "reliable")
func request_join(number: String, player_name: String, token: String = "", resume_token: String = "") -> void:
	if not host_mode: return
	var peer := multiplayer.get_remote_sender_id()
	if not _pending_peers.has(peer): return
	if number != "" and number != room_number:
		_reject(peer, "房间号不匹配，请重新搜索")
		return
	if dedicated and _owner_peer == 0 and _owner_token != "" and token != _owner_token:
		_reject(peer, "房主尚未进入，请稍后加入")
		return
	var seat := -1
	var resumed := false
	for orphan_seat in _orphaned:
		var orphan: Dictionary = _orphaned[orphan_seat]
		if resume_token != "" and resume_token == str(orphan.get("token", "")):
			seat = int(orphan_seat)
			resumed = true
			break
	if _started and not resumed:
		_reject(peer, "该房间已开局，或重连座位已过期")
		return
	if not resumed:
		for candidate in 4:
			if int(_seat_peer.get(candidate, -1)) < 1 and not _orphaned.has(candidate):
				seat = candidate
				break
	if seat < 0:
		_reject(peer, "房间已满")
		return
	_pending_peers.erase(peer)
	var saved: Dictionary = _orphaned.get(seat, {}).get("member", {}).duplicate(true)
	_orphaned.erase(seat)
	_seat_peer[seat] = peer
	_peer_seat[peer] = seat
	_ctrl_hint[seat] = "remote"
	var member_name := player_name.strip_edges().left(16) if player_name.strip_edges() != "" else "玩家"
	_members[peer] = saved if resumed else {"name": member_name, "ready": false, "wants_dealer": false, "resume_token": resume_token.left(128)}
	_members[peer]["resume_token"] = resume_token.left(128)
	if _owner_peer == 0:
		_owner_peer = peer
		_owner_token = ""
	if not resumed: _invalidate_ready()
	if _started: game.restore_human_control(seat)
	rpc_id(peer, "seat_assign", seat)
	_check_start()
	_publish_lobby()
	if _started: _host_broadcast()

func _reject(peer: int, message: String) -> void:
	_pending_peers.erase(peer)
	rpc_id(peer, "join_rejected", message)
	await get_tree().create_timer(0.25).timeout
	if is_inside_tree() and multiplayer.multiplayer_peer != null and peer in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer)

func _on_peer_disconnected(peer: int) -> void:
	_pending_peers.erase(peer)
	if not host_mode or not _peer_seat.has(peer): return
	var seat: int = _peer_seat[peer]
	var member: Dictionary = _members.get(peer, {}).duplicate(true)
	if str(member.get("resume_token", "")) != "":
		_orphaned[seat] = {"token": member.resume_token, "until": Time.get_ticks_msec() + 30000, "member": member}
	_peer_seat.erase(peer)
	_sent_audio.erase(peer)
	_members.erase(peer)
	_seat_peer[seat] = -1
	_ctrl_hint[seat] = AUTO
	if _owner_peer == peer:
		_owner_peer = int(_peer_seat.keys()[0]) if not _peer_seat.is_empty() else 0
	if not _started:
		_countdown = -1.0
		_swap.clear()
		_publish_lobby()
		return
	var actor := AiPlayer.new("AI%d" % seat)
	game.controllers[seat] = actor
	if game.awaiting:
		if game._awaiting_response.get("seat", -1) == seat:
			var request: Dictionary = game._awaiting_response
			game.submit_response(seat, request.tile, actor.decide_response(game, seat, request.disc_seat, request.tile, request.options))
		elif game._awaiting_response.is_empty() and game.current_turn == seat:
			game.submit_turn(seat, actor.decide_turn(game, seat))
	_check_start()
	_publish_lobby()
	_host_broadcast()

func _invalidate_ready() -> void:
	_countdown = -1.0
	_swap.clear()
	for peer in _members:
		_members[peer].ready = _ctrl_hint.get(_peer_seat[peer]) == AUTO

func all_ready() -> bool:
	if _members.is_empty() or not _swap.is_empty() or not _orphaned.is_empty(): return false
	for seat in 4:
		var peer := int(_seat_peer.get(seat, -1))
		if peer < 1:
			if not _host_ai_fill and not _started: return false
		elif not bool(_members[peer].ready): return false
	return true

func _check_start() -> void:
	var can_start := not _started or (game != null and game.phase == "settled" and _ready_round == round_number)
	if not can_start or not all_ready():
		_countdown = -1.0
	elif _countdown < 0.0:
		# 重复准备消息不能重置已经开始的倒计时。
		_countdown = NEXT_ROUND_DELAY if _started else START_DELAY

func _publish_lobby() -> void:
	var seats: Array = []
	for seat in 4:
		var peer := int(_seat_peer.get(seat, -1))
		var member: Dictionary = _members.get(peer, {})
		var ai := peer < 1 and (_host_ai_fill or _started)
		var disconnected := _orphaned.has(seat)
		if disconnected: member = _orphaned[seat].member
		seats.append({"seat": seat, "peer": peer, "ai": ai, "disconnected": disconnected, "name": member.get("name", "人机" if ai else "空位"), "ready": false if disconnected else member.get("ready", ai), "wants_dealer": member.get("wants_dealer", false)})
	lobby = {"number": room_number, "name": room_name, "owner": _owner_peer, "started": _started, "ai_speed": ai_speed, "ready_round": _ready_round, "countdown": ceili(_countdown) if _countdown >= 0.0 else -1, "seats": seats, "swap": _swap.duplicate()}
	for peer in _peer_seat:
		if peer > 1 and _peer_connected(peer): rpc_id(peer, "lobby_sync", lobby)
	lobby_updated.emit()

func _peer_connected(peer: int) -> bool:
	if peer not in multiplayer.get_peers(): return false
	var transport := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if transport == null: return false
	var connection := transport.get_peer(peer)
	return connection != null and connection.get_state() == ENetPacketPeer.STATE_CONNECTED

func _local_peer() -> int:
	return 1 if host_mode else multiplayer.get_unique_id()

func _exit_tree() -> void:
	# Cancel delayed AI decisions belonging to a room that has been closed.
	if host_mode and game != null:
		game.phase = "idle"

func _submit_lobby(action: String, data: Dictionary) -> void:
	if _reconnecting or _resume_sync_pending: return
	if host_mode:
		_apply_lobby_action(1, action, data)
	elif my_seat >= 0:
		rpc_id(1, "lobby_action", action, data)

func set_ready(value: bool) -> void:
	_submit_lobby("ready", {"value": value, "round_number": round_number})

func set_ai_speed(speed_key: String) -> void:
	_submit_lobby("ai_speed", {"value": speed_key})

func set_wants_dealer(value: bool) -> void:
	_submit_lobby("dealer", {"value": value})

func select_seat(seat: int) -> void:
	_submit_lobby("seat", {"seat": seat})

func respond_swap(accept: bool) -> void:
	_submit_lobby("swap", {"accept": accept})

@rpc("any_peer", "call_remote", "reliable")
func lobby_action(action: String, data: Dictionary) -> void:
	if host_mode: _apply_lobby_action(multiplayer.get_remote_sender_id(), action, data)

func _apply_lobby_action(peer: int, action: String, data: Dictionary) -> void:
	if not _members.has(peer): return
	if action == "ai_speed":
		var speed_key := str(data.get("value", ""))
		if peer != _owner_peer or speed_key not in ["fast", "medium", "slow"]: return
		ai_speed = speed_key
		game.ai_delay_seconds = float({"fast": 1, "medium": 2, "slow": 3}[speed_key]) if dedicated else get_node("/root/GameConfig").ai_delay_seconds()
		_publish_lobby()
		return
	if _started:
		if action == "ready": _apply_round_ready(peer, data)
		return
	match action:
		"ready":
			_members[peer].ready = bool(data.get("value", false))
		"dealer":
			_members[peer].wants_dealer = bool(data.get("value", false))
			_members[peer].ready = false
		"seat":
			var target := int(data.get("seat", -1))
			if target < 0 or target > 3 or target == int(_peer_seat[peer]): return
			if _orphaned.has(target):
				_notice(peer, "该座位正在等待断线玩家重连")
				return
			if not _swap.is_empty():
				_notice(peer, "已有换座请求，请先处理或等待")
				return
			var other := int(_seat_peer[target])
			if other > 0:
				_swap = {"from": peer, "to": other, "target": target}
				_swap_deadline = Time.get_ticks_msec() + 20000
				_countdown = -1.0
			else:
				_exchange(peer, target)
		"swap":
			if _swap.is_empty() or int(_swap.to) != peer: return
			if bool(data.get("accept", false)):
				_exchange(int(_swap.from), int(_swap.target))
			else:
				_notice(int(_swap.from), "对方暂时不想换座")
				_swap.clear()
		_:
			return
	_check_start()
	_publish_lobby()

func _exchange(peer: int, target: int) -> void:
	var source := int(_peer_seat[peer])
	var other := int(_seat_peer[target])
	var old_hint: String = _ctrl_hint[source]
	_seat_peer[source] = other
	_seat_peer[target] = peer
	_ctrl_hint[source] = _ctrl_hint[target]
	_ctrl_hint[target] = old_hint
	_peer_seat[peer] = target
	if other > 0:
		_peer_seat[other] = source
		_assign(other, source)
	_assign(peer, target)
	_invalidate_ready()

func _assign(peer: int, seat: int) -> void:
	if peer == 1:
		my_seat = seat
		room_ready.emit(seat)
	else:
		rpc_id(peer, "seat_assign", seat)

func _notice(peer: int, message: String) -> void:
	if peer == 1: lobby_notice.emit(message)
	else: rpc_id(peer, "notice", message)

func choose_first_dealer(rng: RandomNumberGenerator) -> int:
	var candidates: Array[int] = []
	for peer in _members:
		if bool(_members[peer].wants_dealer): candidates.append(int(_peer_seat[peer]))
	if candidates.is_empty(): candidates.assign([0, 1, 2, 3])
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func start_net_game(seed_value: int = -1) -> bool:
	if not host_mode or _started or not all_ready(): return false
	_started = true
	_countdown = -1.0
	var ctrls: Array = []
	for seat in 4:
		ctrls.append(AiPlayer.new("AI%d" % seat) if _ctrl_hint[seat] == AUTO else null)
	game.controllers = ctrls
	game.ai_delay_seconds = float({"fast": 1, "medium": 2, "slow": 3}[ai_speed]) if dedicated else get_node("/root/GameConfig").ai_delay_seconds()
	game.require_turn.connect(_on_host_require_turn)
	game.require_response.connect(_on_host_require_response)
	game.state_update.connect(_host_broadcast)
	if seed_value >= 0: game.set_rng_seed(seed_value)
	else: game.randomize_seed()
	var dealer_rng := RandomNumberGenerator.new()
	if seed_value >= 0: dealer_rng.seed = seed_value
	else: dealer_rng.randomize()
	game.next_dealer_seat = choose_first_dealer(dealer_rng)
	round_number = 1
	_publish_lobby()
	game.start_round(my_seat)
	_host_broadcast()
	host_game_started.emit()
	game_started.emit()
	return true

func _on_host_require_turn(_seat: int) -> void:
	# 提示随最新快照一起到达，避免先显示按钮却仍拿着旧 prompt_id。
	_host_broadcast()

func _on_host_require_response(_seat: int, _disc_seat: int, _tile: String, _opts: Dictionary) -> void:
	_host_broadcast()

func _host_broadcast() -> void:
	if not host_mode or game == null or game.phase == "idle": return
	_prepare_round_ready()
	if _state_queued:
		state_metrics.coalesced += 1
		return
	_state_queued = true
	call_deferred("_flush_host_state")

func _flush_host_state() -> void:
	_state_queued = false
	if not host_mode or game == null or game.phase == "idle": return
	_state_revision += 1
	for peer in _peer_seat:
		if peer > 1 and _peer_connected(peer):
			var state := game.serialize_for_seat(int(_peer_seat[peer]))
			state["round_number"] = round_number
			state["revision"] = _state_revision
			if measure_state_traffic: state_metrics.full_bytes += var_to_bytes(state).size()
			var sent: Dictionary = _sent_audio.get(peer, {})
			var last_id := int(sent.get("id", 0)) if sent.get("session", "") == game.audio_session else 0
			state.audio_events = state.audio_events.filter(func(event): return int(event.id) > last_id)
			_sent_audio[peer] = {"session": game.audio_session, "id": game.audio_event_id}
			state_metrics.sent += 1
			if measure_state_traffic: state_metrics.bytes += var_to_bytes(state).size()
			rpc_id(peer, "sync", state)

func is_room_owner() -> bool:
	return int(lobby.get("owner", -1)) == _local_peer()

func next_round() -> void:
	# 每个玩家仅提交自己的准备，开局始终由服务器倒计时控制。
	set_ready(true)

func _prepare_round_ready() -> void:
	if game.phase != "settled" or _ready_round == round_number: return
	_ready_round = round_number
	_invalidate_ready()
	_check_start()
	_publish_lobby()

func _apply_round_ready(peer: int, data: Dictionary) -> void:
	if game == null or game.phase != "settled" or int(data.get("round_number", -1)) != round_number: return
	_prepare_round_ready()
	_members[peer].ready = bool(data.get("value", false))
	_check_start()
	_publish_lobby()

func _start_next_round() -> void:
	if not host_mode or game == null or game.phase != "settled" or _ready_round != round_number or not all_ready() or _countdown > 0.0: return
	_ready_round = -1
	_invalidate_ready()
	round_number += 1
	_publish_lobby()
	game.start_round(my_seat)

func client(ip: String, port: int = 0, number: String = "", player_name: String = "", owner_token: String = "") -> bool:
	_server_ip = ip
	_server_port = port if port > 0 else 7500
	if _resume_token == "": _resume_token = Crypto.new().generate_random_bytes(32).hex_encode()
	host_mode = false
	_join_number = number
	_join_name = player_name if player_name != "" else get_node("/root/GameConfig").player_name
	_join_token = owner_token
	game = game if game != null else RoundState.new()
	return _open_client_peer()

func _open_client_peer() -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(_server_ip, _server_port) != OK: return false
	multiplayer.multiplayer_peer = peer
	if not multiplayer.connected_to_server.is_connected(_on_client_connected): multiplayer.connected_to_server.connect(_on_client_connected)
	if not multiplayer.connection_failed.is_connected(_on_client_failed): multiplayer.connection_failed.connect(_on_client_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected): multiplayer.server_disconnected.connect(_on_server_disconnected)
	return true

func _on_client_connected() -> void:
	rpc_id(1, "request_join", _join_number, _join_name, _join_token, _resume_token)

func _on_client_failed() -> void:
	_begin_reconnect("连接失败")

func _on_server_disconnected() -> void:
	_begin_reconnect("房间连接已断开")

func _begin_reconnect(_reason: String) -> void:
	if host_mode or _server_ip == "" or _reconnecting: return
	if not _client_joined:
		connection_error.emit("连接失败，房间可能已关闭或网络不可达")
		return
	_reconnecting = true
	_resume_sync_pending = game != null and game.phase != "idle"
	_reconnect_attempt = 0
	_reconnect_wait = 0.2
	reconnecting.emit(0, 5)

func _reconnect_step() -> void:
	if host_mode or not _reconnecting: return
	if _reconnect_attempt >= 5:
		_reconnecting = false
		multiplayer.multiplayer_peer = null
		connection_error.emit("重连失败，请返回房间列表重新加入")
		return
	_reconnect_attempt += 1
	reconnecting.emit(_reconnect_attempt, 5)
	_reconnect_wait = 5.0
	multiplayer.multiplayer_peer = null
	_open_client_peer()

func _on_client_sync(state: Dictionary) -> void:
	var revision := int(state.get("revision", _received_revision + 1))
	if revision <= _received_revision: return
	_received_revision = revision
	var first := game.phase == "idle"
	round_number = int(state.get("round_number", 1))
	game.apply_sync(state)
	_resume_sync_pending = false
	state_updated.emit()
	if first: game_started.emit()
	if game.awaiting and (game.current_turn == my_seat or game._awaiting_response.get("seat", -1) == my_seat): prompted.emit(my_seat)

@rpc("authority", "call_remote", "reliable")
func seat_assign(seat: int) -> void:
	_client_joined = true
	_reconnecting = false
	_reconnect_attempt = 0
	my_seat = seat
	room_ready.emit(seat)

@rpc("authority", "call_remote", "reliable")
func lobby_sync(state: Dictionary) -> void:
	lobby = state
	room_number = str(state.number)
	room_name = str(state.name)
	lobby_updated.emit()

@rpc("authority", "call_remote", "reliable")
func join_rejected(message: String) -> void:
	_reconnecting = false
	_server_ip = ""
	connection_error.emit(message)

@rpc("authority", "call_remote", "reliable")
func notice(message: String) -> void:
	lobby_notice.emit(message)

@rpc("any_peer", "call_remote", "reliable")
func send_turn(seat: int, dict: Dictionary) -> void:
	if host_mode and _started and _seat_peer.get(seat, -1) == multiplayer.get_remote_sender_id() and int(dict.get("prompt_id", -1)) == game.prompt_id: game.submit_turn(seat, dict)

@rpc("any_peer", "call_remote", "reliable")
func send_response(seat: int, tile: String, dict: Dictionary) -> void:
	if host_mode and _started and _seat_peer.get(seat, -1) == multiplayer.get_remote_sender_id() and int(dict.get("prompt_id", -1)) == game.prompt_id: game.submit_response(seat, tile, dict)

@rpc("authority", "call_remote", "reliable")
func your_turn(seat: int) -> void:
	game.current_turn = seat
	game.awaiting = true
	game._awaiting_response = {}
	prompted.emit(seat)

@rpc("authority", "call_remote", "reliable")
func your_response(seat: int, disc_seat: int, tile: String, opts: Dictionary) -> void:
	game.awaiting = true
	game._awaiting_response = {"seat": seat, "disc_seat": disc_seat, "tile": tile, "options": opts}
	prompted.emit(seat)

@rpc("authority", "call_remote", "reliable", 1)
func sync(state: Dictionary) -> void:
	_on_client_sync(state)

func submit_client_turn(dict: Dictionary) -> void:
	if _reconnecting or _resume_sync_pending or not _client_joined or multiplayer.multiplayer_peer == null: return
	dict["prompt_id"] = game.prompt_id
	rpc_id(1, "send_turn", my_seat, dict)

func submit_client_response(tile: String, dict: Dictionary) -> void:
	if _reconnecting or _resume_sync_pending or not _client_joined or multiplayer.multiplayer_peer == null: return
	dict["prompt_id"] = game.prompt_id
	rpc_id(1, "send_response", my_seat, tile, dict)

@rpc("any_peer", "call_remote", "reliable")
func ack(text: String) -> void:
	if host_mode and _peer_seat.has(multiplayer.get_remote_sender_id()):
		ack_flag = true
		ack_text = text
