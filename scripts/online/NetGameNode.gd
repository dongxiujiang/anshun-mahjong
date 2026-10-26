class_name NetGameNode
extends Node
## 房间与游戏由服务器权威处理，两端 RPC 节点路径固定。
signal room_ready(seat)
signal lobby_updated
signal room_empty
signal lobby_notice(message)
signal state_updated
signal prompted(seat)
signal host_game_started
signal game_started
signal returned_to_lobby
signal return_vote_updated(data)
signal connection_error(message)
signal reconnecting(attempt, maximum)
signal session_invalidated
signal voice_status(enabled, message)

const VOICE_CHAT := preload("res://scripts/online/GMEVoiceChat.gd")
const PCM_VOICE := preload("res://scripts/online/OnlineVoiceChat.gd")
const TEST_PATTERNS := preload("res://scripts/core/TestPatterns.gd")
const CONFIG := preload("res://scripts/autoload/GameConfig.gd")
const AUTO := "auto"
const START_DELAY := 3.0
const NEXT_ROUND_DELAY := 1.0
# Phase one keeps the table paused for a short background check. When it
# expires the AI plays on the player's behalf, but the authenticated seat
# reservation survives until the room closes, so the player can always
# reclaim it with the resume token (see request_join).
const RESUME_GRACE_MS := 30000
const RESUME_RETENTION_MS := 30 * 60 * 1000
const HEARTBEAT_INTERVAL_MS := 5000
const HEARTBEAT_TIMEOUT_MS := 15000
# 3: server-issued resume token + compressed state frames.
const PROTOCOL_VERSION := 3
const READY_GRACE_MS := 30000
const BACKGROUND_AI_DELAY_MS := 30000
const BACKGROUND_VOTE_DELAY_MS := 5000
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
var _resume_requested := false
var _pending_snapshot: Dictionary = {}
var _client_joined := false
var _orphaned: Dictionary = {}
var _background_until: Dictionary = {}
var _background_vote_pending: Dictionary = {}
var _test_vote: Dictionary = {}
var _test_pending: Dictionary = {}
var _return_vote_active := false
var _return_vote_yes: Dictionary = {}
var _return_vote_initiator := -1
var _return_vote_rejecter := -1
var _state_queued := false
var _state_revision := 0
var _received_revision := -1
var ai_speed := "fast"
var opening_speed := "standard"
var voice_chat = null
var _ai_service = null
var _voice_last_ms := {}
var _peer_last_seen := {}
var _sent_audio := {}
var _heartbeat_seq := 0
var _last_ping_ms := 0
var _last_pong_ms := 0
var _peer_protocol := {}
var _last_sent_state := {}
var _client_sync_cache := {}
var _last_resync_request := {}
var _last_state_request := {}
var _lobby_action_times := {}
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

func _ai_turn_delay() -> float:
	if not dedicated and DisplayServer.get_name() == "headless": return 0.0
	return float(preload("res://scripts/autoload/GameConfig.gd").AI_SPEED_DELAYS.get(ai_speed, 0.8))

func _ai_response_delay() -> float:
	return _ai_turn_delay()

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
	ai_speed = "medium" if dedicated else get_node("/root/GameConfig").ai_speed
	_host_ai_fill = ai_fill
	room_number = number
	room_name = title.strip_edges().left(24)
	if room_name == "": room_name = "麻将房间"
	_owner_token = owner_token
	_owner_peer = 0 if dedicated else 1
	game = RoundState.new()
	if dedicated or DisplayServer.get_name() != "headless":
		_ai_service = load("res://scripts/ai/AiDecisionService.gd").new()
		game.ai_service = _ai_service
	game._recorder.auto_save = true
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

func _notification(what: int) -> void:
	if not is_inside_tree():
		return
	if what == NOTIFICATION_APPLICATION_RESUMED and host_mode and _started and game != null:
		# Paused processes do not run AI timers. Nudge the host state machine
		# immediately so a backgrounded host resumes instead of looking stuck.
		game.poll_ai()
		_host_broadcast()
	if host_mode:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		# Tell the authority immediately so its reconnect window can start
		# before ENet itself times out.
		if _client_joined and multiplayer.multiplayer_peer != null:
			rpc_id(1, "lobby_action", "background", {"value": true})
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if _resume_requested and not _client_joined and not _reconnecting:
			# The five-attempt retry budget may have elapsed while Android
			# kept the process frozen. Resume the same token flow on return
			# instead of leaving the player stuck on the error dialog.
			_reconnecting = true
			_reconnect_attempt = 0
			_reconnect_wait = 0.0
			_last_pong_ms = Time.get_ticks_msec()
			reconnecting.emit(0, 5)
			return
		if not _client_joined or multiplayer.multiplayer_peer == null:
			return
		# A long Android/desktop pause stops _process; do not count the paused
		# interval as heartbeat loss. The next ping verifies the server again.
		_last_pong_ms = Time.get_ticks_msec()
		_last_ping_ms = 0
		rpc_id(1, "lobby_action", "background", {"value": false})
		if _reconnecting:
			_reconnect_wait = 0.0

func _apply_background(peer: int, backgrounded: bool) -> void:
	if not host_mode: return
	var seat := int(_peer_seat.get(peer, -1))
	if seat < 0: return
	if backgrounded:
		_background_until[seat] = Time.get_ticks_msec() + BACKGROUND_AI_DELAY_MS
		_ctrl_hint[seat] = "wait"
		if _return_vote_active and not bool(_return_vote_yes.get(seat, false)):
			_background_vote_pending[seat] = Time.get_ticks_msec() + BACKGROUND_VOTE_DELAY_MS
	else:
		_background_until.erase(seat)
		_background_vote_pending.erase(seat)
		if not _orphaned.has(seat):
			_ctrl_hint[seat] = "remote"
			for member_peer in _peer_seat.keys():
				if int(_peer_seat[member_peer]) == seat and _members.has(member_peer):
					_members[member_peer].ready = false
			if _started and game != null:
				game.restore_human_control(seat)
	_publish_lobby()
	if _started: _host_broadcast()
	if _return_vote_active: _publish_return_vote()

func _ready() -> void:
	voice_chat = VOICE_CHAT.new()
	voice_chat.name = "VoiceChat"
	add_child(voice_chat)
	voice_chat.setup(self, DisplayServer.get_name() != "headless")
	voice_chat.status_changed.connect(func(enabled: bool, message: String): voice_status.emit(enabled, message))

func _process(delta: float) -> void:
	if voice_chat != null:
		voice_chat.poll_permission()
	if game != null:
		game.poll_ai()
	if not host_mode:
		if _reconnecting:
			_reconnect_wait -= delta
			if _reconnect_wait <= 0.0: _reconnect_step()
		else:
			_poll_heartbeat()
		return
	for seat in _orphaned.keys():
		var orphan: Dictionary = _orphaned[seat]
		if Time.get_ticks_msec() >= int(orphan.get("until", 0)) and not bool(orphan.get("replaced", false)):
			var was_owner := bool(orphan.get("owner", false))
			if _started:
				# After the pause the AI plays on the player's behalf, but the
				# reservation (and the resume token inside it) survives until
				# the settlement screen closes: the player can reclaim the seat
				# via request_join at any point in this round.
				orphan["replaced"] = true
				orphan["retain_until"] = Time.get_ticks_msec() + RESUME_RETENTION_MS
				if was_owner:
					_transfer_owner_from(_owner_peer)
				_install_ai_for_seat(int(seat))
				_check_start()
				_publish_lobby()
				_host_broadcast()
			else:
				# A lobby seat must free up at expiry; a reserved-but-unfilled
				# seat would block both joining and the start countdown.
				_orphaned.erase(seat)
				if was_owner:
					_transfer_owner_from(_owner_peer)
				_check_start()
				_publish_lobby()
		elif bool(orphan.get("replaced", false)) and Time.get_ticks_msec() >= int(orphan.get("retain_until", 0)):
			# Bound abandoned reservations so an empty room can eventually
			# close instead of retaining a seat forever.
			_orphaned.erase(seat)
			_check_start()
			_publish_lobby()
		elif int(_orphaned[seat].get("ready_until", 0)) > 0 and Time.get_ticks_msec() >= int(_orphaned[seat].ready_until):
			_orphaned[seat].ready_until = 0
			_check_start()
			_publish_lobby()
	for seat in _background_until.keys():
		if Time.get_ticks_msec() >= int(_background_until[seat]):
			_background_until.erase(seat)
			# A backgrounded player who has not returned is an AI seat. Do not
			# leave a "wait" hint with no peer/controller: that seat would start
			# the round and then wait forever for a human action.
			_ctrl_hint[int(seat)] = AUTO
			for peer in _peer_seat.keys():
				if int(_peer_seat[peer]) == int(seat) and _members.has(peer):
					_members[peer].ready = true
			if _started:
				_install_ai_for_seat(int(seat))
			else:
				_check_start()
			if _return_vote_active:
				_check_return_vote()
				_publish_return_vote()
			_publish_lobby()
			if _started: _host_broadcast()
	for seat in _background_vote_pending.keys():
		if Time.get_ticks_msec() >= int(_background_vote_pending[seat]):
			_background_vote_pending.erase(seat)
			if not _return_vote_active:
				continue
			_return_vote_yes[int(seat)] = true
			_check_return_vote()
			_publish_return_vote()
	for peer in _peer_last_seen.keys():
		# Only protocol-3+ clients send application heartbeats; the host-side
		# check turns a frozen Android process into a normal disconnect flow
		# (grace -> AI substitute -> reclaimable reservation) deterministically.
		if int(_peer_protocol.get(peer, 0)) < PROTOCOL_VERSION or int(peer) <= 1: continue
		if not _peer_connected(int(peer)):
			_peer_last_seen.erase(peer)
			continue
		if Time.get_ticks_msec() - int(_peer_last_seen[peer]) > HEARTBEAT_TIMEOUT_MS:
			_peer_last_seen.erase(peer)
			multiplayer.multiplayer_peer.disconnect_peer(int(peer))
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

static func new_resume_token() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()

@rpc("any_peer", "call_remote", "reliable")
func request_join(number: String, player_name: String, token: String = "", resume_token: String = "", resume_only: bool = false, client_protocol: int = 0) -> void:
	if not host_mode: return
	var peer := multiplayer.get_remote_sender_id()
	if not _pending_peers.has(peer): return
	if number != "" and number != room_number:
		_reject(peer, "房间号不匹配，请重新搜索")
		return
	var seat := -1
	var resumed := false
	var saved: Dictionary = {}
	var was_owner := false
	for orphan_seat in _orphaned:
		var orphan: Dictionary = _orphaned[orphan_seat]
		# Within the pause window the token resumes the paused seat; after the
		# AI took over (replaced) the same token reclaims the seat at any time.
		var reclaimable := bool(orphan.get("replaced", false)) or Time.get_ticks_msec() < int(orphan.get("until", 0))
		if reclaimable and resume_token != "" and resume_token == str(orphan.get("token", "")):
			seat = int(orphan_seat)
			resumed = true
			was_owner = bool(orphan.get("owner", false))
			saved = orphan.get("member", {}).duplicate(true)
			break
	# A restarted process can arrive before ENet detects the old process's death.
	# Rebind that authenticated seat without running an intermediate AI action.
	if not resumed and resume_only and resume_token != "":
		for previous in _members.keys():
			if previous == peer or resume_token != str(_members[previous].get("resume_token", "")): continue
			seat = int(_peer_seat[previous])
			saved = _members[previous].duplicate(true)
			_peer_seat.erase(previous)
			_members.erase(previous)
			_sent_audio.erase(previous)
			_peer_protocol.erase(previous)
			_last_sent_state.erase(previous)
			if _owner_peer == previous: _owner_peer = peer
			multiplayer.multiplayer_peer.disconnect_peer(previous)
			resumed = true
			break
	if resume_only and not resumed:
		_reject(peer, "原房间已关闭或重连座位已过期，请重新加入房间")
		return
	if dedicated and _owner_peer == 0 and _owner_token != "" and token != _owner_token:
		_reject(peer, "房主尚未进入，请稍后加入")
		return
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
	_orphaned.erase(seat)
	_background_until.erase(seat)
	_background_vote_pending.erase(seat)
	_peer_last_seen[peer] = Time.get_ticks_msec()
	_peer_protocol[peer] = client_protocol
	_last_sent_state.erase(peer)
	if voice_chat != null and voice_chat.has_method("reset_seat"):
		voice_chat.reset_seat(seat)
	_seat_peer[seat] = peer
	_peer_seat[peer] = seat
	_ctrl_hint[seat] = "remote"
	var member_name := player_name.strip_edges().left(16) if player_name.strip_edges() != "" else "玩家"
	# Modern clients get an authority-issued token. Old clients keep the token
	# they generated, so a rolling server update does not break existing users.
	var modern := client_protocol >= PROTOCOL_VERSION
	var assigned_token := str(saved.get("resume_token", "")) if resumed else ""
	if assigned_token == "":
		assigned_token = resume_token.left(128) if not modern else ""
	if assigned_token == "":
		assigned_token = new_resume_token()
	_members[peer] = saved if resumed else {"name": member_name, "ready": false, "wants_dealer": false}
	_members[peer]["resume_token"] = assigned_token
	if was_owner:
		# A reconnecting owner gets a new ENet peer id; bind ownership to it.
		_owner_peer = peer
	if _owner_peer == 0:
		_owner_peer = peer
		_owner_token = ""
	if not resumed: _invalidate_ready()
	if _started:
		# Do not inherit readiness from an older round played by the substitute.
		if resumed and int(saved.get("round_number", round_number)) != round_number: _members[peer].ready = false
		_apply_member_names()
		game.restore_human_control(seat)
	if modern:
		rpc_id(peer, "seat_assign", seat, assigned_token)
	else:
		rpc_id(peer, "seat_assign", seat)
	if resumed:
		# The returning client has no cached frame after a disconnect, so push
		# one full snapshot (or the lobby) right after seat_assign.
		if _started: _host_broadcast()
		else: _publish_lobby()
	_check_start()
	_publish_lobby()
	if _return_vote_active: _publish_return_vote()
	if _started: _host_broadcast()

func _reject(peer: int, message: String) -> void:
	_pending_peers.erase(peer)
	rpc_id(peer, "join_rejected", message)
	await get_tree().create_timer(0.25).timeout
	if is_inside_tree() and multiplayer.multiplayer_peer != null and peer in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(peer)

func _transfer_owner_from(peer: int) -> void:
	if _owner_peer != peer:
		return
	var remaining := _peer_seat.keys()
	remaining.sort()
	_owner_peer = int(remaining[0]) if not remaining.is_empty() else 0

func _on_peer_disconnected(peer: int) -> void:
	_pending_peers.erase(peer)
	if not host_mode or not _peer_seat.has(peer): return
	var seat: int = _peer_seat[peer]
	if voice_chat != null and voice_chat.has_method("reset_seat"):
		voice_chat.reset_seat(seat)
	var member: Dictionary = _members.get(peer, {}).duplicate(true)
	member["round_number"] = round_number
	var retained: bool = str(member.get("resume_token", "")) != ""
	if retained:
		_orphaned[seat] = {"token": member.resume_token, "until": Time.get_ticks_msec() + RESUME_GRACE_MS,
			"ready_until": Time.get_ticks_msec() + READY_GRACE_MS, "owner": _owner_peer == peer,
			"member": member}
	else:
		# Explicit leave: no reconnect reservation and no controller-less seat.
		_orphaned.erase(seat)
	# Common departure cleanup for both reconnectable and explicit leave.
	_peer_seat.erase(peer)
	_sent_audio.erase(peer)
	_peer_protocol.erase(peer)
	_last_sent_state.erase(peer)
	_last_state_request.erase(peer)
	_lobby_action_times.erase(peer)
	_voice_last_ms.erase(peer)
	_peer_last_seen.erase(peer)
	_members.erase(peer)
	_seat_peer[seat] = -1
	if not _test_vote.is_empty():
		var alive := _human_seats()
		var valid := true
		for human in _test_vote.get("humans", []):
			if int(human) not in alive:
				valid = false
				break
		if not valid:
			_test_vote.clear()
			_publish_lobby()
	_background_until.erase(seat)
	_background_vote_pending.erase(seat)
	if retained:
		# Keep the seat human-controlled while the reconnect reservation is alive.
		# No AI action is scheduled until the 30s grace expires.
		_ctrl_hint[seat] = "wait"
	else:
		# Explicit leave in the lobby must hand the seat to the AI controller;
		# otherwise all_ready() allows a round to start with a null controller.
		_ctrl_hint[seat] = AUTO
		if _started: _install_ai_for_seat(seat)
	if _return_vote_active and _return_vote_yes.has(seat) and not bool(_return_vote_yes.get(seat, false)):
		_background_vote_pending[seat] = Time.get_ticks_msec() + BACKGROUND_VOTE_DELAY_MS
		_publish_return_vote()
	# Explicit owner departure must transfer ownership. A reconnectable owner
	# keeps the seat reservation and may reclaim its room.
	if not retained and _owner_peer == peer:
		_transfer_owner_from(peer)
	# An explicit leave is final. If no connected human remains, the dedicated
	# room server must close immediately instead of keeping an AI-only room.
	if not retained and not has_connected_humans():
		room_empty.emit()
	if not _started:
		_countdown = -1.0
		_swap.clear()
		_check_start()
		_publish_lobby()
		return
	_check_start()
	_publish_lobby()
	_host_broadcast()

func _install_ai_for_seat(seat: int) -> void:
	if game == null or seat < 0 or seat > 3:
		return
	_ctrl_hint[seat] = AUTO
	if _background_until.has(seat) or _seat_peer.get(seat, -1) > 0:
		for peer in _peer_seat.keys():
			if int(_peer_seat[peer]) == seat and _members.has(peer):
				_members[peer].ready = true
	var actor := AiPlayer.new("AI%d" % seat)
	game.controllers[seat] = actor
	if game.awaiting:
		if int(game._awaiting_response.get("seat", -1)) == seat:
			var request: Dictionary = game._awaiting_response
			var response: Dictionary = actor.decide_response(game, seat, int(request.get("disc_seat", -1)), str(request.get("tile", "")), request.get("options", {}))
			if not game.submit_response(seat, str(request.get("tile", "")), response):
				# The AI model must never leave a human seat stuck; an empty
				# legal response is always a pass.
				game.submit_response(seat, str(request.get("tile", "")), {"action": "pass"})
		elif game._awaiting_response.is_empty() and game.current_turn == seat:
			var decision: Dictionary = actor.decide_turn(game, seat)
			if not game.submit_turn(seat, decision):
				var legal: Array = game.legal_turn_options(seat).discards
				if not legal.is_empty():
					game.submit_turn(seat, {"discard": str(legal[0])})

@rpc("any_peer", "call_remote", "reliable")
func request_leave() -> void:
	if not host_mode: return
	var peer := multiplayer.get_remote_sender_id()
	if not _members.has(peer): return
	_members[peer]["resume_token"] = ""
	_on_peer_disconnected(peer)
	multiplayer.multiplayer_peer.disconnect_peer(peer)

func has_reconnect_reservations() -> bool:
	for orphan in _orphaned.values():
		if bool(orphan.get("replaced", false)):
			if Time.get_ticks_msec() < int(orphan.get("retain_until", 0)): return true
		elif Time.get_ticks_msec() < int(orphan.get("until", 0)):
			return true
	return false

func _waiting_for_reconnect(seat: int) -> bool:
	if _background_until.has(seat): return true
	return _orphaned.has(seat) and Time.get_ticks_msec() < int(_orphaned[seat].get("ready_until", 0))

func _invalidate_ready() -> void:
	_countdown = -1.0
	_swap.clear()
	for peer in _members:
		_members[peer].ready = _ctrl_hint.get(_peer_seat[peer]) == AUTO

func all_ready() -> bool:
	if _members.is_empty() or not _swap.is_empty(): return false
	for seat in 4:
		if _waiting_for_reconnect(seat): return false
		var peer := int(_seat_peer.get(seat, -1))
		if peer < 1:
			if not _host_ai_fill and not _started: return false
		elif not bool(_members[peer].ready): return false
	return true

func _check_start() -> void:
	var can_start := not _started or (game != null and game.phase == RoundState.Phase.SETTLED and _ready_round == round_number)
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
		var ctrl_auto: bool = str(_ctrl_hint.get(seat, AUTO)) == AUTO
		var replaced := _orphaned.has(seat) and bool(_orphaned[seat].get("replaced", false))
		var ai: bool = ctrl_auto and ((peer < 1 and (_host_ai_fill or _started)) or peer > 0 or replaced)
		var disconnected := _orphaned.has(seat) or _background_until.has(seat)
		# Backgrounded peers are still connected and remain in _members; only
		# disconnected seats have an orphan record with the retained member.
		if _orphaned.has(seat): member = _orphaned[seat].member
		seats.append({"seat": seat, "peer": peer, "ai": ai, "disconnected": disconnected, "name": member.get("name", "人机" if ai else "空位"), "ready": (not _waiting_for_reconnect(seat) and ai) if disconnected else member.get("ready", ai), "wants_dealer": member.get("wants_dealer", false)})
	lobby = {"number": room_number, "name": room_name, "owner": _owner_peer, "started": _started, "ai_speed": ai_speed, "opening_speed": opening_speed, "ready_round": _ready_round, "countdown": ceili(_countdown) if _countdown >= 0.0 else -1, "seats": seats, "swap": _swap.duplicate(), "return_vote": _return_vote_data(), "test_vote": _test_vote.duplicate(true)}
	for peer in _peer_seat:
		if peer > 1 and _peer_connected(peer): rpc_id(peer, "lobby_sync", lobby)
	lobby_updated.emit()

func has_connected_humans() -> bool:
	# The local host (peer 1) is a human member only when this process is not
	# the dedicated room server.
	if not dedicated and _members.has(1):
		return true
	for peer in _members:
		if int(peer) > 1 and _peer_connected(int(peer)):
			return true
	return false

func _peer_connected(peer: int) -> bool:
	if peer not in multiplayer.get_peers(): return false
	var transport := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if transport == null: return false
	var connection := transport.get_peer(peer)
	return connection != null and connection.get_state() == ENetPacketPeer.STATE_CONNECTED

func _local_peer() -> int:
	return 1 if host_mode else multiplayer.get_unique_id()

func _exit_tree() -> void:
	if voice_chat != null:
		voice_chat.shutdown()
		voice_chat = null
	if _ai_service != null:
		var tree := get_tree()
		if tree != null:
			_ai_service.stop_async(tree)
		else:
			_ai_service.stop()
		_ai_service = null
	if game != null: game.cancel_opening()
	# Cancel delayed AI decisions belonging to a room that has been closed.
	if host_mode and game != null:
		game.phase = RoundState.Phase.IDLE

func _submit_lobby(action: String, data: Dictionary) -> void:
	if _reconnecting or _resume_sync_pending: return
	if host_mode:
		_apply_lobby_action(1, action, data)
	elif _client_joined and my_seat >= 0 and multiplayer.multiplayer_peer != null:
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
	if not host_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	# Burst-friendly bound: legitimate UI flows can send seat/ready/dealer
	# actions in one frame, while a spammer is still capped per source.
	var stamps: Array = _lobby_action_times.get(sender, [])
	stamps = stamps.filter(func(stamp): return now - int(stamp) < 5000)
	if stamps.size() >= 50:
		return
	stamps.append(now)
	_lobby_action_times[sender] = stamps
	_apply_lobby_action(sender, action, data)

func _apply_lobby_action(peer: int, action: String, data: Dictionary) -> void:
	if not _members.has(peer): return
	if action == "background":
		_apply_background(peer, bool(data.get("value", false)))
		return
	if action == "return_vote":
		_apply_return_vote_answer(peer, bool(data.get("agree", false)))
		return
	if action == "test_vote":
		_apply_test_vote_answer(peer, bool(data.get("agree", false)))
		return
	if action == "ai_speed":
		var speed_key := str(data.get("value", ""))
		if peer != _owner_peer or speed_key not in ["fast", "medium", "slow"]: return
		ai_speed = speed_key
		game.ai_delay_seconds = _ai_turn_delay()
		game.ai_response_delay_seconds = _ai_response_delay()
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
	# Background timers are seat-keyed. Swap them with the seats or a player
	# who backgrounded before a swap can affect the other player's seat.
	var background_source = _background_until.get(source)
	var background_target = _background_until.get(target)
	_background_until.erase(source)
	_background_until.erase(target)
	if background_target != null: _background_until[source] = background_target
	if background_source != null: _background_until[target] = background_source
	var vote_source = _background_vote_pending.get(source)
	var vote_target = _background_vote_pending.get(target)
	_background_vote_pending.erase(source)
	_background_vote_pending.erase(target)
	if vote_target != null: _background_vote_pending[source] = vote_target
	if vote_source != null: _background_vote_pending[target] = vote_source
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
		# Do not rely on the hint alone: a seat with no live peer must always
		# have an AI controller, even if an earlier lobby transition left the
		# hint as "remote"/"wait".
		var has_peer := int(_seat_peer.get(seat, -1)) > 0
		var use_ai: bool = _ctrl_hint[seat] == AUTO or not has_peer
		if use_ai: _ctrl_hint[seat] = AUTO
		var ai_actor := AiPlayer.new("AI%d" % seat) if use_ai else null
		ctrls.append(ai_actor)
	game.controllers = ctrls
	game.ai_delay_seconds = _ai_turn_delay()
	game.ai_response_delay_seconds = _ai_response_delay()
	if not dedicated:
		opening_speed = CONFIG.opening_animation_speed
	_apply_opening_delay()
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
	_apply_member_names()
	_host_broadcast()
	_sync_voice_room()
	host_game_started.emit()
	game_started.emit()
	return true

func _on_host_require_turn(seat: int) -> void:
	if game != null and seat >= 0 and seat < 4 and game.controllers.size() > seat \
		and game.controllers[seat] == null and int(_seat_peer.get(seat, -1)) < 1 \
		and not _orphaned.has(seat) and _ctrl_hint.get(seat, AUTO) != "wait":
		_install_ai_for_seat(seat)
	# 提示随最新快照一起到达，避免先显示按钮却仍拿着旧 prompt_id。
	_host_broadcast()

func _on_host_require_response(seat: int, _disc_seat: int, _tile: String, _opts: Dictionary) -> void:
	if game != null and seat >= 0 and seat < 4 and game.controllers.size() > seat \
		and game.controllers[seat] == null and int(_seat_peer.get(seat, -1)) < 1 \
		and not _orphaned.has(seat) and _ctrl_hint.get(seat, AUTO) != "wait":
		_install_ai_for_seat(seat)
	_host_broadcast()

func _host_broadcast() -> void:
	if not host_mode or game == null or game.phase == RoundState.Phase.IDLE: return
	_prepare_round_ready()
	if _state_queued:
		state_metrics.coalesced += 1
		return
	_state_queued = true
	call_deferred("_flush_host_state")

func _flush_host_state() -> void:
	_state_queued = false
	if not host_mode or game == null or game.phase == RoundState.Phase.IDLE: return
	_state_revision += 1
	# 整局状态只从模型序列化一次；每个对手只复制需要遮牌的玩家/事件。
	# 没有已连接对手时连这一次序列化也跳过。
	var base_state: Dictionary = {}
	for peer in _peer_seat:
		if peer > 1 and _peer_connected(peer):
			if base_state.is_empty():
				base_state = game.serialize()
			var state := game.mask_for_seat(base_state, int(_peer_seat[peer]))
			state["round_number"] = round_number
			state["revision"] = _state_revision
			if measure_state_traffic: state_metrics.full_bytes += var_to_bytes(state).size()
			var sent: Dictionary = _sent_audio.get(peer, {})
			var last_id := int(sent.get("id", 0)) if sent.get("session", "") == game.audio_session else 0
			state.audio_events = state.audio_events.filter(func(event): return int(event.id) > last_id)
			_sent_audio[peer] = {"session": game.audio_session, "id": game.audio_event_id}
			_send_state_frame(peer, state)
			_last_sent_state[peer] = state.duplicate(true)

func _send_state_frame(peer: int, state: Dictionary) -> void:
	var raw := var_to_bytes(state)
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	state_metrics.sent += 1
	var modern := int(_peer_protocol.get(peer, 0)) >= PROTOCOL_VERSION
	if modern:
		var previous: Dictionary = _last_sent_state.get(peer, {})
		if not previous.is_empty() and int(previous.get("revision", -1)) < int(state.revision):
			var ops: Array = []
			_build_state_delta(previous, state, [], ops)
			if not ops.is_empty():
				var delta := {"base": int(previous.revision), "revision": int(state.revision),
					"round_number": round_number, "ops": ops}
				var delta_raw := var_to_bytes(delta)
				var delta_packed := delta_raw.compress(FileAccess.COMPRESSION_DEFLATE)
				if mini(delta_raw.size(), delta_packed.size()) < mini(raw.size(), packed.size()):
					if measure_state_traffic: state_metrics.bytes += mini(delta_raw.size(), delta_packed.size())
					if delta_packed.size() < delta_raw.size():
						rpc_id(peer, "sync_delta_packed", delta_packed)
					else:
						rpc_id(peer, "sync_delta", delta)
					return
	if measure_state_traffic: state_metrics.bytes += mini(raw.size(), packed.size())
	if modern and packed.size() < raw.size():
		rpc_id(peer, "sync_packed", packed)
	else:
		rpc_id(peer, "sync", state)

func _build_state_delta(old_value: Variant, new_value: Variant, path: Array, ops: Array) -> void:
	if typeof(old_value) != typeof(new_value):
		ops.append(["s", path, new_value])
		return
	if old_value is Dictionary:
		for key in old_value.keys():
			if not new_value.has(key): ops.append(["r", path + [key]])
		for key in new_value.keys():
			if not old_value.has(key): ops.append(["s", path + [key], new_value[key]])
			elif old_value[key] != new_value[key]: _build_state_delta(old_value[key], new_value[key], path + [key], ops)
		return
	if old_value is Array:
		if old_value.size() != new_value.size():
			var prefix := true
			for index in mini(old_value.size(), new_value.size()):
				if old_value[index] != new_value[index]: prefix = false
			if prefix and new_value.size() > old_value.size():
				for index in range(old_value.size(), new_value.size()):
					ops.append(["a", path, new_value[index]])
			else:
				ops.append(["s", path, new_value])
			return
		for index in old_value.size():
			if old_value[index] != new_value[index]:
				_build_state_delta(old_value[index], new_value[index], path + [index], ops)
		return
	if old_value != new_value:
		ops.append(["s", path, new_value])

func _apply_state_delta(state: Dictionary, ops: Array) -> bool:
	for op in ops:
		if not op is Array or op.size() < 2 or not op[1] is Array: return false
		var path: Array = op[1]
		var kind := str(op[0])
		var parent: Variant = state
		var descend := path.size() if kind == "a" else maxi(0, path.size() - 1)
		for index in range(descend):
			var key: Variant = path[index]
			if parent is Dictionary:
				if not parent.has(key): return false
				parent = parent[key]
			elif parent is Array:
				if int(key) < 0 or int(key) >= parent.size(): return false
				parent = parent[int(key)]
			else:
				return false
		if kind == "a":
			if not parent is Array or op.size() < 3: return false
			parent.append(op[2])
		elif kind == "r":
			if path.is_empty(): return false
			if parent is Dictionary: parent.erase(path[-1])
			elif parent is Array: parent.remove_at(int(path[-1]))
			else: return false
		elif kind == "s":
			if path.is_empty() or op.size() < 3: return false
			if parent is Dictionary: parent[path[-1]] = op[2]
			elif parent is Array and int(path[-1]) < parent.size(): parent[int(path[-1])] = op[2]
			else: return false
		else:
			return false
	return true

func is_room_owner() -> bool:
	return int(lobby.get("owner", -1)) == _local_peer()

func next_round() -> void:
	# 每个玩家仅提交自己的准备，开局始终由服务器倒计时控制。
	set_ready(true)

## Return to seat selection requires every connected human seat to agree.
## AI seats never vote; disconnected/background humans auto-agree after 5s.
func request_return_to_lobby() -> void:
	if game == null or game.phase != RoundState.Phase.SETTLED:
		return
	if host_mode:
		_start_return_vote(_local_seat())
	elif _client_joined:
		rpc_id(1, "return_to_lobby_request")

func _local_seat() -> int:
	if host_mode: return my_seat
	return my_seat

func _human_seats() -> Array:
	var out: Array = []
	for seat in 4:
		if _ctrl_hint.get(seat, AUTO) == AUTO:
			continue
		var peer := int(_seat_peer.get(seat, -1))
		if peer > 0 or _orphaned.has(seat) or _background_until.has(seat):
			out.append(seat)
	return out

func _start_return_vote(initiator: int) -> void:
	if not host_mode or game == null or game.phase != RoundState.Phase.SETTLED:
		return
	if _return_vote_active:
		_publish_return_vote()
		return
	var humans := _human_seats()
	if initiator not in humans:
		initiator = int(humans[0]) if not humans.is_empty() else -1
	if initiator < 0: return
	_return_vote_active = true
	_return_vote_initiator = initiator
	# Each vote round starts from a clean set of answers. Carrying yes answers
	# across a cancelled vote lets a stale auto-answer skip a new round.
	_return_vote_yes.clear()
	for seat in humans:
		_return_vote_yes[int(seat)] = false
	# The initiator counts as yes, except a player who just rejected and then
	# initiates again: they must explicitly agree first.
	if initiator != _return_vote_rejecter:
		_return_vote_yes[initiator] = true
	_background_vote_pending.clear()
	for seat in humans:
		if _orphaned.has(seat) or _background_until.has(seat):
			_background_vote_pending[int(seat)] = Time.get_ticks_msec() + BACKGROUND_VOTE_DELAY_MS
	_publish_return_vote()
	_check_return_vote()

func propose_test_pattern(pattern: String) -> void:
	if not _started or game == null:
		return
	var seat := _local_seat()
	if seat < 0:
		return
	if host_mode:
		_start_test_vote(seat, pattern)
	elif _client_joined:
		rpc_id(1, "request_test_pattern", pattern)

@rpc("any_peer", "call_remote", "reliable")
func request_test_pattern(pattern: String) -> void:
	if not host_mode or not _started or game == null:
		return
	var seat := int(_peer_seat.get(multiplayer.get_remote_sender_id(), -1))
	_start_test_vote(seat, pattern)

func _start_test_vote(initiator: int, pattern: String) -> void:
	if not host_mode or game == null or pattern not in TEST_PATTERNS.ids():
		return
	var humans := _human_seats()
	if initiator not in humans or humans.is_empty():
		return
	# 发起者也要明确点“同意”，避免只有发起者一个真人时看起来像没弹确认。
	_test_vote = {"pattern": pattern, "seat": initiator, "humans": humans.duplicate(), "yes": []}
	_publish_lobby()
	_check_test_vote()

func answer_test_vote(agree: bool) -> void:
	if host_mode:
		_apply_test_vote_answer(_local_peer(), agree)
	elif _client_joined:
		rpc_id(1, "lobby_action", "test_vote", {"agree": agree})

func _apply_test_vote_answer(peer: int, agree: bool) -> void:
	if not host_mode or _test_vote.is_empty():
		return
	var seat := int(_peer_seat.get(peer, -1))
	if seat not in _test_vote.get("humans", []):
		return
	if not agree:
		var pattern := str(_test_vote.get("pattern", ""))
		_test_vote.clear()
		_publish_lobby()
		lobby_notice.emit("测试牌型“%s”被拒绝" % TEST_PATTERNS.get_entry(pattern).get("name", pattern))
		return
	var yes: Array = _test_vote.get("yes", [])
	if seat not in yes:
		yes.append(seat)
	_test_vote["yes"] = yes
	_publish_lobby()
	_check_test_vote()

func _check_test_vote() -> void:
	if _test_vote.is_empty():
		return
	var yes: Array = _test_vote.get("yes", [])
	for human in _test_vote.get("humans", []):
		if int(human) not in yes:
			return
	_test_pending = {"pattern": str(_test_vote.get("pattern", "")), "seat": int(_test_vote.get("seat", -1))}
	_test_vote.clear()
	_restart_with_test_hand()

func _restart_with_test_hand() -> void:
	if not host_mode or game == null or _test_pending.is_empty():
		return
	var pattern := str(_test_pending.get("pattern", ""))
	var seat := int(_test_pending.get("seat", -1))
	_test_pending.clear()
	var hand := TEST_PATTERNS.hand(pattern)
	if seat not in range(4) or hand.size() != 13:
		_publish_lobby()
		return
	game.test_hand_seat = seat
	game.test_hand = hand.duplicate()
	game.test_pattern = pattern
	# 重开本局，不推进庄家；当前局未结算的分数自然保留。
	game.next_dealer_seat = game.dealer_seat
	_ready_round = -1
	_invalidate_ready()
	_apply_opening_delay()
	game.start_round(my_seat)
	_apply_member_names()
	_host_broadcast()
	_publish_lobby()
	lobby_notice.emit("测试牌型“%s”已生效" % TEST_PATTERNS.get_entry(pattern).get("name", pattern))

@rpc("any_peer", "call_remote", "reliable")
func return_to_lobby_request() -> void:
	if not host_mode: return
	var peer := multiplayer.get_remote_sender_id()
	var seat := int(_peer_seat.get(peer, -1))
	if seat < 0: return
	_start_return_vote(seat)

func answer_return_vote(agree: bool) -> void:
	if host_mode:
		_apply_return_vote_answer(_local_peer(), agree)
	elif _client_joined:
		rpc_id(1, "lobby_action", "return_vote", {"agree": agree})

func _apply_return_vote_answer(peer: int, agree: bool) -> void:
	if not host_mode or not _return_vote_active: return
	var seat := int(_peer_seat.get(peer, -1))
	if seat < 0 or not _return_vote_yes.has(seat): return
	if agree:
		_return_vote_yes[seat] = true
		_background_vote_pending.erase(seat)
		_publish_return_vote()
		_check_return_vote()
	else:
		_return_vote_active = false
		_return_vote_yes[seat] = false
		_return_vote_rejecter = seat
		# Cancel all pending auto-answers; they belong to this vote only.
		_background_vote_pending.clear()
		_publish_return_vote()

func _check_return_vote() -> void:
	if not host_mode or not _return_vote_active: return
	var humans := _human_seats()
	if humans.is_empty(): return
	for seat in humans:
		if not bool(_return_vote_yes.get(int(seat), false)): return
	_reset_room_to_lobby()

func _return_vote_data() -> Dictionary:
	var humans := _human_seats()
	var yes: Dictionary = {}
	for seat in humans:
		yes[int(seat)] = bool(_return_vote_yes.get(int(seat), false))
	return {"active": _return_vote_active, "humans": humans, "yes": yes,
		"initiator": _return_vote_initiator, "rejecter": _return_vote_rejecter}

func _publish_return_vote() -> void:
	var data := _return_vote_data()
	return_vote_updated.emit(data)
	# Votes travel in the normal lobby snapshot so older/newer clients keep the
	# same RPC checksum; no extra RPC method is introduced.
	_publish_lobby()

func _reset_room_to_lobby() -> void:
	if not host_mode or not _started or game == null or game.phase != RoundState.Phase.SETTLED:
		return
	_started = false
	_countdown = -1.0
	_ready_round = -1
	_return_vote_active = false
	_return_vote_yes.clear()
	_return_vote_initiator = -1
	_return_vote_rejecter = -1
	_background_vote_pending.clear()
	_swap.clear()
	round_number = 0
	for peer in _members:
		_members[peer].ready = false
	for seat in 4:
		_ctrl_hint[seat] = "human" if int(_seat_peer.get(seat, -1)) > 0 else AUTO
	var next_game := RoundState.new()
	if _ai_service != null: next_game.ai_service = _ai_service
	next_game._recorder.auto_save = true
	game = next_game
	_publish_lobby()
	if multiplayer.multiplayer_peer != null:
		rpc("receive_returned_to_lobby")
	returned_to_lobby.emit()

@rpc("authority", "call_remote", "reliable")
func receive_returned_to_lobby() -> void:
	_started = false
	_countdown = -1.0
	_ready_round = -1
	round_number = 0
	var next_game := RoundState.new()
	game = next_game
	returned_to_lobby.emit()

func _prepare_round_ready() -> void:
	if game.phase != RoundState.Phase.SETTLED or _ready_round == round_number: return
	_ready_round = round_number
	_invalidate_ready()
	_check_start()
	_publish_lobby()

func _apply_round_ready(peer: int, data: Dictionary) -> void:
	if game == null or game.phase != RoundState.Phase.SETTLED or int(data.get("round_number", -1)) != round_number: return
	_prepare_round_ready()
	_members[peer].ready = bool(data.get("value", false))
	_check_start()
	_publish_lobby()

func _apply_opening_delay() -> void:
	if game == null:
		return
	game.opening_delay_seconds = CONFIG.OPENING_WAIT_SECONDS \
		* float(CONFIG.OPENING_SPEEDS.get(opening_speed, 1.0)) \
		if dedicated or DisplayServer.get_name() != "headless" else 0.0

func set_opening_speed(value: String) -> void:
	if value not in CONFIG.OPENING_SPEEDS:
		return
	if host_mode:
		opening_speed = value
		_apply_opening_delay()
		_publish_lobby()
	elif _client_joined and _owner_peer == _local_peer():
		rpc_id(1, "request_opening_speed", value)

@rpc("any_peer", "call_remote", "reliable")
func request_opening_speed(value: String) -> void:
	if not host_mode or multiplayer.get_remote_sender_id() != _owner_peer:
		return
	if value not in CONFIG.OPENING_SPEEDS:
		return
	opening_speed = value
	_apply_opening_delay()
	_publish_lobby()

func _start_next_round() -> void:
	if not host_mode or game == null or game.phase != RoundState.Phase.SETTLED or _ready_round != round_number or not all_ready() or _countdown > 0.0: return
	_ready_round = -1
	_invalidate_ready()
	round_number += 1
	_publish_lobby()
	_apply_opening_delay()
	game.start_round(my_seat)
	_apply_member_names()
	_host_broadcast()

func _apply_member_names() -> void:
	if game == null or game.players.size() != 4: return
	for seat in 4:
		var peer := int(_seat_peer.get(seat, -1))
		if peer > 0:
			game.players[seat].name_label = str(_members.get(peer, {}).get("name", "玩家"))
			game.players[seat].is_human = _ctrl_hint.get(seat, AUTO) != AUTO
		else:
			game.players[seat].name_label = str(_orphaned.get(seat, {}).get("member", {}).get("name", "人机%d" % (seat + 1)))
			game.players[seat].is_human = false
	game._recorder.update_players(game)

func client(ip: String, port: int = 0, number: String = "", player_name: String = "", owner_token: String = "", resume_token: String = "", resume_only: bool = false) -> bool:
	_server_ip = ip
	_server_port = port if port > 0 else 7500
	if resume_token != "": _resume_token = resume_token
	# A fresh client starts without a token. The authority issues one in
	# seat_assign after it has actually reserved a seat.
	_resume_requested = resume_only
	_resume_sync_pending = resume_only
	host_mode = false
	_join_number = number
	_join_name = player_name if player_name != "" else get_node("/root/GameConfig").player_name
	_join_token = owner_token
	game = game if game != null else RoundState.new()
	if resume_only:
		_reconnecting = true
		_reconnect_attempt = 0
		_reconnect_wait = 0.0
		return true
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
	_last_ping_ms = 0
	_last_pong_ms = Time.get_ticks_msec()
	rpc_id(1, "request_join", _join_number, _join_name, _join_token, _resume_token, _resume_requested, PROTOCOL_VERSION)

func _on_client_failed() -> void:
	_begin_reconnect("连接失败")

func _on_server_disconnected() -> void:
	_begin_reconnect("房间连接已断开")

func _begin_reconnect(_reason: String) -> void:
	if host_mode or _server_ip == "" or _reconnecting: return
	if not _client_joined and not _resume_requested:
		connection_error.emit("连接失败，房间可能已关闭或网络不可达")
		return
	_reconnecting = true
	_resume_requested = true
	_client_joined = false
	_client_sync_cache.clear()
	_pending_snapshot.clear()
	_resume_sync_pending = game != null and game.phase != RoundState.Phase.IDLE
	_reconnect_attempt = 0
	_reconnect_wait = 0.2
	reconnecting.emit(0, 5)

func retry_connection() -> bool:
	if host_mode or _server_ip == "" or _resume_token == "":
		return false
	_reconnecting = true
	_resume_requested = true
	_client_joined = false
	_reconnect_attempt = 0
	_reconnect_wait = 0.0
	_last_pong_ms = Time.get_ticks_msec()
	reconnecting.emit(0, 5)
	multiplayer.multiplayer_peer = null
	return true

func _poll_heartbeat() -> void:
	if not _client_joined or multiplayer.multiplayer_peer == null:
		return
	var now := Time.get_ticks_msec()
	if _last_pong_ms == 0:
		_last_pong_ms = now
		return
	if now - _last_pong_ms > HEARTBEAT_TIMEOUT_MS:
		_begin_reconnect("连接心跳超时")
		return
	if now - _last_ping_ms >= HEARTBEAT_INTERVAL_MS:
		_last_ping_ms = now
		_heartbeat_seq += 1
		heartbeat_ping.rpc_id(1, _heartbeat_seq)

func _reconnect_step() -> void:
	if host_mode or not _reconnecting: return
	if _reconnect_attempt >= 5:
		_reconnecting = false
		multiplayer.multiplayer_peer = null
		connection_error.emit("暂时无法恢复连接，请在联机房间点击“返回上次房间”重试")
		return
	_reconnect_attempt += 1
	reconnecting.emit(_reconnect_attempt, 5)
	_reconnect_wait = 5.0
	multiplayer.multiplayer_peer = null
	_open_client_peer()

func _sync_voice_room() -> void:
	if voice_chat == null or not voice_chat.has_method("connect_room"):
		return
	if not voice_chat_allowed() or my_seat < 0 or room_number.length() < 4:
		return
	var display_name := str(get_node("/root/GameConfig").player_name).strip_edges()
	var member_token := _resume_token if _resume_token != "" else _owner_token
	voice_chat.connect_room(room_number, my_seat, display_name if display_name != "" else "玩家", member_token)

func voice_chat_allowed() -> bool:
	# Clients do not set the host-only _started flag until their first snapshot.
	# Voice follows the active round instead, so a guest can talk as soon as the
	# first deal reaches the table.
	return game != null and game.phase != RoundState.Phase.IDLE and my_seat >= 0 and not dedicated

func toggle_voice_chat() -> bool:
	if voice_chat == null:
		return false
	return bool(voice_chat.set_enabled(not voice_chat.enabled))

func voice_chat_enabled() -> bool:
	return voice_chat != null and bool(voice_chat.enabled)

func send_local_voice(packet: PackedByteArray) -> void:
	if voice_chat == null or not voice_chat.uses_network_pcm():
		return
	if not voice_chat_allowed() or packet.size() < 6 or packet.size() > 1024:
		return
	packet[1] = clampi(my_seat, 0, 3)
	if host_mode:
		_relay_voice(packet, 0)
	elif multiplayer.multiplayer_peer != null:
		voice_packet.rpc_id(1, packet)

func _relay_voice(packet: PackedByteArray, except_peer: int) -> void:
	if not host_mode:
		return
	for peer in _peer_seat.keys():
		if int(peer) <= 1 or int(peer) == except_peer or not _peer_connected(int(peer)):
			continue
		voice_packet.rpc_id(int(peer), packet)

@rpc("any_peer", "call_remote", "unreliable")
func heartbeat_ping(seq: int) -> void:
	if not host_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _peer_seat.has(sender):
		_peer_last_seen[sender] = Time.get_ticks_msec()
		heartbeat_pong.rpc_id(sender, seq)

@rpc("authority", "call_remote", "unreliable")
func heartbeat_pong(_seq: int) -> void:
	if not host_mode:
		_last_pong_ms = Time.get_ticks_msec()

@rpc("any_peer", "call_remote", "unreliable")
func voice_packet(packet: PackedByteArray) -> void:
	if voice_chat != null and not voice_chat.uses_network_pcm():
		return
	if game == null or game.phase == RoundState.Phase.IDLE or packet.size() < 6 or packet.size() > 1024:
		return
	if not PCM_VOICE.valid_packet(packet):
		return
	var sender := multiplayer.get_remote_sender_id()
	if host_mode:
		if not _peer_seat.has(sender):
			return
		var now := Time.get_ticks_msec()
		if now - int(_voice_last_ms.get(sender, 0)) < 10:
			return
		_voice_last_ms[sender] = now
		var copy := packet.duplicate()
		copy[1] = int(_peer_seat[sender])
		if not dedicated and voice_chat != null:
			voice_chat.play_packet(copy)
		_relay_voice(copy, sender)
	else:
		if sender != 1:
			return
		if voice_chat != null:
			voice_chat.play_packet(packet)

func _on_client_sync(state: Dictionary) -> void:
	if not _client_joined:
		if int(state.get("revision", 0)) > int(_pending_snapshot.get("revision", -1)):
			_pending_snapshot = state
		return
	var revision := int(state.get("revision", _received_revision + 1))
	if revision <= _received_revision: return
	_received_revision = revision
	var first := game.phase == RoundState.Phase.IDLE
	round_number = int(state.get("round_number", 1))
	_client_sync_cache = state.duplicate(true)
	game.apply_sync(state)
	_resume_sync_pending = false
	_sync_voice_room()
	state_updated.emit()
	if first: game_started.emit()
	if game.awaiting and (game.current_turn == my_seat or game._awaiting_response.get("seat", -1) == my_seat): prompted.emit(my_seat)

@rpc("authority", "call_remote", "reliable")
func seat_assign(seat: int, issued_token: String = "") -> void:
	_client_joined = true
	_client_sync_cache.clear()
	if issued_token != "":
		_resume_token = issued_token
	_last_ping_ms = 0
	_last_pong_ms = Time.get_ticks_msec()
	_reconnecting = false
	_reconnect_attempt = 0
	my_seat = seat
	# 房主入座时就同步开局速度，确保服务器第一次 start_round 前已经拿到。
	if _owner_peer == _local_peer():
		call_deferred("set_opening_speed", CONFIG.opening_animation_speed)
	room_ready.emit(seat)
	if not _pending_snapshot.is_empty():
		var state := _pending_snapshot
		_pending_snapshot = {}
		_on_client_sync(state)

@rpc("authority", "call_remote", "reliable")
func lobby_sync(state: Dictionary) -> void:
	lobby = state
	room_number = str(state.number)
	room_name = str(state.name)
	if not bool(state.get("started", false)) and _client_joined: _resume_sync_pending = false
	lobby_updated.emit()

@rpc("authority", "call_remote", "reliable")
func join_rejected(message: String) -> void:
	_reconnecting = false
	_server_ip = ""
	_client_joined = false
	if _resume_requested: session_invalidated.emit()
	connection_error.emit(message)

@rpc("authority", "call_remote", "reliable")
func notice(message: String) -> void:
	lobby_notice.emit(message)

@rpc("any_peer", "call_remote", "reliable")
func send_turn(seat: int, dict: Dictionary) -> void:
	if not host_mode or not _started or game == null: return
	if _seat_peer.get(seat, -1) != multiplayer.get_remote_sender_id() or int(dict.get("prompt_id", -1)) != game.prompt_id:
		game._recorder.request(seat, "turn", dict, false, "座位身份或提示编号不匹配")
		return
	game.submit_turn(seat, dict)

@rpc("any_peer", "call_remote", "reliable")
func send_response(seat: int, tile: String, dict: Dictionary) -> void:
	if not host_mode or not _started or game == null: return
	if _seat_peer.get(seat, -1) != multiplayer.get_remote_sender_id() or int(dict.get("prompt_id", -1)) != game.prompt_id:
		game._recorder.request(seat, "response", dict, false, "座位身份或提示编号不匹配")
		return
	game.submit_response(seat, tile, dict)

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

@rpc("authority", "call_remote", "reliable", 1)
func sync_packed(payload: PackedByteArray) -> void:
	if payload.is_empty() or payload.size() > 2 * 1024 * 1024:
		return
	var raw := payload.decompress_dynamic(4 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return
	var state: Variant = bytes_to_var(raw)
	if state is Dictionary:
		_on_client_sync(state)

@rpc("authority", "call_remote", "reliable", 1)
func sync_delta(delta: Dictionary) -> void:
	_apply_sync_delta(delta)

@rpc("authority", "call_remote", "reliable", 1)
func sync_delta_packed(payload: PackedByteArray) -> void:
	if payload.is_empty() or payload.size() > 2 * 1024 * 1024:
		return
	var raw := payload.decompress_dynamic(8 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return
	var delta: Variant = bytes_to_var(raw)
	if delta is Dictionary:
		_apply_sync_delta(delta)

func _apply_sync_delta(delta: Dictionary) -> void:
	var base := int(delta.get("base", -1))
	if _client_sync_cache.is_empty() or int(_client_sync_cache.get("revision", -1)) != base:
		_request_full_state_throttled()
		return
	var ops = delta.get("ops", [])
	if not ops is Array:
		_request_full_state_throttled()
		return
	var state: Dictionary = _client_sync_cache.duplicate(true)
	if not _apply_state_delta(state, ops):
		_request_full_state_throttled()
		return
	state["revision"] = int(delta.get("revision", -1))
	state["round_number"] = int(delta.get("round_number", 1))
	_on_client_sync(state)

func _request_full_state_throttled() -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_resync_request.get("at", 0)) <= 1000:
		return
	_last_resync_request["at"] = now
	request_full_state.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func request_full_state() -> void:
	if not host_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not _peer_seat.has(sender):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_state_request.get(sender, 0)) < 1000:
		return
	_last_state_request[sender] = now
	_last_sent_state.erase(sender)
	_host_broadcast()

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


