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

const AUTO := "auto"
const START_DELAY := 3.0
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
var _swap: Dictionary = {}
var _swap_deadline := 0
var _join_number := ""
var _join_name := "玩家"
var _join_token := ""
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
	multiplayer.multiplayer_peer = peer
	host_mode = true
	dedicated = server_only
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
	if not host_mode: return
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
			start_net_game()
		elif ceili(_countdown) != previous:
			_publish_lobby()

func _on_peer_connected(peer: int) -> void:
	_pending_peers[peer] = Time.get_ticks_msec()

@rpc("any_peer", "call_remote", "reliable")
func request_join(number: String, player_name: String, token: String = "") -> void:
	if not host_mode: return
	var peer := multiplayer.get_remote_sender_id()
	if not _pending_peers.has(peer): return
	if _started:
		_reject(peer, "该房间已开局，请选择等待中的房间")
		return
	if number != "" and number != room_number:
		_reject(peer, "房间号不匹配，请重新搜索")
		return
	if dedicated and _owner_peer == 0 and _owner_token != "" and token != _owner_token:
		_reject(peer, "房主尚未进入，请稍后加入")
		return
	var seat := -1
	for candidate in 4:
		if int(_seat_peer.get(candidate, -1)) < 1:
			seat = candidate
			break
	if seat < 0:
		_reject(peer, "房间已满")
		return
	_pending_peers.erase(peer)
	_seat_peer[seat] = peer
	_peer_seat[peer] = seat
	_ctrl_hint[seat] = "remote"
	_members[peer] = {"name": player_name.strip_edges().left(16) if player_name.strip_edges() != "" else "玩家", "ready": false, "wants_dealer": false}
	if _owner_peer == 0:
		_owner_peer = peer
		_owner_token = ""
	_invalidate_ready()
	rpc_id(peer, "seat_assign", seat)
	_publish_lobby()

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
	_peer_seat.erase(peer)
	_members.erase(peer)
	_seat_peer[seat] = -1
	_ctrl_hint[seat] = AUTO
	if _owner_peer == peer:
		_owner_peer = int(_peer_seat.keys()[0]) if not _peer_seat.is_empty() else 0
	if not _started:
		_invalidate_ready()
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
	_publish_lobby()
	_host_broadcast()

func _invalidate_ready() -> void:
	_countdown = -1.0
	_swap.clear()
	for peer in _members:
		_members[peer].ready = _ctrl_hint.get(_peer_seat[peer]) == AUTO

func all_ready() -> bool:
	if _members.is_empty() or not _swap.is_empty(): return false
	for seat in 4:
		var peer := int(_seat_peer.get(seat, -1))
		if peer < 1:
			if not _host_ai_fill: return false
		elif not bool(_members[peer].ready): return false
	return true

func _check_start() -> void:
	if not _started:
		_countdown = START_DELAY if all_ready() else -1.0

func _publish_lobby() -> void:
	var seats: Array = []
	for seat in 4:
		var peer := int(_seat_peer.get(seat, -1))
		var member: Dictionary = _members.get(peer, {})
		seats.append({"seat": seat, "peer": peer, "ai": peer < 1 and _host_ai_fill, "name": member.get("name", "人机" if _host_ai_fill else "空位"), "ready": member.get("ready", _host_ai_fill), "wants_dealer": member.get("wants_dealer", false)})
	lobby = {"number": room_number, "name": room_name, "owner": _owner_peer, "started": _started, "countdown": ceili(_countdown) if _countdown >= 0.0 else -1, "seats": seats, "swap": _swap.duplicate()}
	for peer in _peer_seat:
		if peer > 1: rpc_id(peer, "lobby_sync", lobby)
	lobby_updated.emit()

func _local_peer() -> int:
	return 1 if host_mode else multiplayer.get_unique_id()

func _exit_tree() -> void:
	# Cancel delayed AI decisions belonging to a room that has been closed.
	if host_mode and game != null:
		game.phase = "idle"

func _submit_lobby(action: String, data: Dictionary) -> void:
	if host_mode:
		_apply_lobby_action(1, action, data)
	elif my_seat >= 0:
		rpc_id(1, "lobby_action", action, data)

func set_ready(value: bool) -> void:
	_submit_lobby("ready", {"value": value})

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
	if _started or not _members.has(peer): return
	match action:
		"ready":
			_members[peer].ready = bool(data.get("value", false))
		"dealer":
			_members[peer].wants_dealer = bool(data.get("value", false))
			_members[peer].ready = false
		"seat":
			var target := int(data.get("seat", -1))
			if target < 0 or target > 3 or target == int(_peer_seat[peer]): return
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
	game.ai_delay_seconds = 1.0 if dedicated else get_node("/root/GameConfig").ai_delay_seconds()
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

func _on_host_require_turn(seat: int) -> void:
	if int(_seat_peer.get(seat, -1)) > 1: rpc_id(_seat_peer[seat], "your_turn", seat)

func _on_host_require_response(seat: int, disc_seat: int, tile: String, opts: Dictionary) -> void:
	if int(_seat_peer.get(seat, -1)) > 1: rpc_id(_seat_peer[seat], "your_response", seat, disc_seat, tile, opts)

func _host_broadcast() -> void:
	if not host_mode or game == null or game.phase == "idle": return
	for peer in _peer_seat:
		if peer > 1:
			var state := game.serialize_for_seat(int(_peer_seat[peer]))
			state["round_number"] = round_number
			rpc_id(peer, "sync", state)

func is_room_owner() -> bool:
	return int(lobby.get("owner", -1)) == _local_peer()

func next_round() -> void:
	if host_mode: _start_next_round(1)
	elif is_room_owner(): rpc_id(1, "request_next_round")

@rpc("any_peer", "call_remote", "reliable")
func request_next_round() -> void:
	if host_mode: _start_next_round(multiplayer.get_remote_sender_id())

func _start_next_round(peer: int) -> void:
	if peer == _owner_peer and _members.has(peer) and game != null and game.phase == "settled":
		round_number += 1
		game.start_round(my_seat)

func client(ip: String, port: int = 0, number: String = "", player_name: String = "", owner_token: String = "") -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port if port > 0 else 7500) != OK: return false
	multiplayer.multiplayer_peer = peer
	host_mode = false
	_join_number = number
	_join_name = player_name if player_name != "" else get_node("/root/GameConfig").player_name
	_join_token = owner_token
	game = RoundState.new()
	multiplayer.connected_to_server.connect(func(): rpc_id(1, "request_join", _join_number, _join_name, _join_token))
	multiplayer.connection_failed.connect(func(): connection_error.emit("连接失败，房间可能已关闭或网络不可达"))
	multiplayer.server_disconnected.connect(func(): connection_error.emit("房间已断开连接"))
	return true

func _on_client_sync(state: Dictionary) -> void:
	var first := game.phase == "idle"
	round_number = int(state.get("round_number", 1))
	game.apply_sync(state)
	state_updated.emit()
	if first: game_started.emit()
	if game.awaiting and (game.current_turn == my_seat or game._awaiting_response.get("seat", -1) == my_seat): prompted.emit(my_seat)

@rpc("authority", "call_remote", "reliable")
func seat_assign(seat: int) -> void:
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

@rpc("authority", "call_remote", "reliable")
func sync(state: Dictionary) -> void:
	_on_client_sync(state)

func submit_client_turn(dict: Dictionary) -> void:
	dict["prompt_id"] = game.prompt_id
	rpc_id(1, "send_turn", my_seat, dict)

func submit_client_response(tile: String, dict: Dictionary) -> void:
	dict["prompt_id"] = game.prompt_id
	rpc_id(1, "send_response", my_seat, tile, dict)

@rpc("any_peer", "call_remote", "reliable")
func ack(text: String) -> void:
	if host_mode and _peer_seat.has(multiplayer.get_remote_sender_id()):
		ack_flag = true
		ack_text = text
