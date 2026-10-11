class_name NetGameNode
extends Node
## 联机游戏传输（ENet，主机权威）。主机运行 RoundState，客户端仅渲染+前传真人动作。
## 席位分配：主机=seat0(peer1)，随后加入的客户端=seat1,2,3。空位由AI/本地补。

signal room_ready(seat)
signal state_updated          # 客户端收到新同步
signal prompted(seat)         # 需要真人决策（客户端显示）
signal host_game_started
signal connection_error(message)

const AUTO := "auto"   # 本地自动代打（测试/无真人）

var host_mode := false
var my_seat := -1
var game: RoundState
var round_number := 0

# 主机用
var _seat_peer := {}      # seat -> peer id（-1=AI/空）
var _peer_seat := {}      # peer -> seat
var _ctrl_hint := {}      # seat -> "auto"/"remote"/"human"
var _port := 7500

## 主机：建服（host_auto: 主机的seat0是否自动代打；auto_fill_ai: 空位补AI）
func host(host_auto: bool, ai_fill: bool, port: int = 0) -> bool:
	host_mode = true
	_port = port if port > 0 else _port
	var p := ENetMultiplayerPeer.new()
	var err := p.create_server(_port, 4)
	if err != OK:
		push_error("主机端口错误: %s" % str(err)); return false
	multiplayer.multiplayer_peer = p
	_seat_peer[0] = 1
	_peer_seat[1] = 0
	_ctrl_hint[0] = "auto" if host_auto else "human"
	my_seat = 0
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	game = RoundState.new()
	room_ready.emit(0)
	_host_ai_fill = ai_fill
	print("[net] 主机建立 port=%d" % _port)
	return true

var _host_ai_fill := false
var _next_seat := 1

func _on_peer_connected(peer: int) -> void:
	if not host_mode: return
	var seat := -1
	for candidate in range(1, 4):
		if int(_seat_peer.get(candidate, -1)) < 1:
			seat = candidate
			break
	if seat < 0:
		multiplayer.multiplayer_peer.disconnect_peer(peer)
		return
	_seat_peer[seat] = peer
	_peer_seat[peer] = seat
	_ctrl_hint[seat] = "remote"
	if game != null and game.controllers.size() == 4:
		game.controllers[seat] = null
	rpc_id(peer, "seat_assign", seat)
	# 若已在局中，立即补给该新玩家最新状态
	if game != null and game.phase != "idle":
		rpc_id(peer, "sync", game.serialize_for_seat(seat))
	print("[net] 席位 %d -> peer %d" % [seat, peer])

func _on_peer_disconnected(peer: int) -> void:
	if not host_mode or not _peer_seat.has(peer):
		return
	var seat: int = _peer_seat[peer]
	_peer_seat.erase(peer)
	_seat_peer[seat] = -1
	_ctrl_hint[seat] = "auto"
	if game == null or game.controllers.size() != 4:
		return
	var actor := AiPlayer.new("AI%d" % seat)
	game.controllers[seat] = actor
	if game.awaiting:
		if game._awaiting_response.get("seat", -1) == seat:
			var request: Dictionary = game._awaiting_response
			game.submit_response(seat, request.tile, actor.decide_response(game, seat, request.disc_seat, request.tile, request.options))
		elif game._awaiting_response.is_empty() and game.current_turn == seat:
			game.submit_turn(seat, actor.decide_turn(game, seat))
	_host_broadcast()

## 满4人或手动开局；空位由AI补
func start_net_game(seed_value: int = -1) -> void:
	if not host_mode: return
	# 未满的座位：_host_ai_fill 则补AI（本地同步），否则保留空(remote待真人)
	for seat in 4:
		if not _seat_peer.has(seat) or _seat_peer[seat] < 0:
			if _host_ai_fill:
				_seat_peer[seat] = -1
				_ctrl_hint[seat] = "auto"
	# 构建控制器
	var ctrls: Array = []
	for seat in 4:
		var hint: String = _ctrl_hint.get(seat, "auto")
		if hint == "auto":
			ctrls.append(AiPlayer.new("AI%d" % seat))
		else:
			ctrls.append(null)  # human(主机)/remote(客户端)
	game.controllers = ctrls
	game.ai_delay_seconds = GameConfig.ai_delay_seconds()
	if not game.require_turn.is_connected(_on_host_require_turn):
		game.require_turn.connect(_on_host_require_turn)
		game.require_response.connect(_on_host_require_response)
		game.state_update.connect(_host_broadcast)
	# 种子必须不可预测：客户端知道自己的手牌与时间，能靠枚举时间戳反推整副牌墙。
	if seed_value >= 0:
		game.set_rng_seed(seed_value)
	else:
		game.randomize_seed()
	game.start_round(0, -1)
	round_number += 1
	host_game_started.emit()

func _on_host_require_turn(seat: int) -> void:
	if not host_mode: return
	if _seat_peer.has(seat) and _seat_peer[seat] > 1:
		rpc_id(_seat_peer[seat], "your_turn", seat)
	# seat0(主机真人)：等待本机 UI 通过 submit_turn 提交

func _on_host_require_response(seat: int, disc_seat: int, tile: String, opts: Dictionary) -> void:
	if not host_mode: return
	if _seat_peer.has(seat) and _seat_peer[seat] > 1:
		rpc_id(_seat_peer[seat], "your_response", seat, disc_seat, tile, opts)

func _host_broadcast() -> void:
	if not host_mode or game == null: return
	for peer in _peer_seat:
		if peer <= 1:
			continue
		var state := game.serialize_for_seat(int(_peer_seat[peer]))
		state["round_number"] = maxi(1, round_number)
		rpc_id(peer, "sync", state)

func next_round() -> void:
	if host_mode and game != null and game.phase == "settled":
		round_number += 1
		game.start_round(0)

# ---- 客户端 ----
func client(ip: String, port: int = 0) -> bool:
	host_mode = false
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(ip, port if port > 0 else _port)
	if err != OK:
		return false
	multiplayer.multiplayer_peer = p
	game = RoundState.new()
	multiplayer.connection_failed.connect(func(): connection_error.emit("连接失败，请检查地址和网络"))
	multiplayer.server_disconnected.connect(func(): connection_error.emit("主机已断开连接"))
	return true

func _on_client_sync(state: Dictionary) -> void:
	round_number = int(state.get("round_number", 1))
	game.apply_sync(state)
	state_updated.emit()
	if game.awaiting and (game.current_turn == my_seat or game._awaiting_response.get("seat", -1) == my_seat):
		prompted.emit(my_seat)

# ---------------- RPC ----------------
@rpc("authority", "call_remote", "reliable")
func seat_assign(seat: int) -> void:
	my_seat = seat
	room_ready.emit(seat)

@rpc("any_peer", "call_remote", "reliable")
func send_turn(seat: int, dict: Dictionary) -> void:
	if not host_mode: return
	if _seat_peer.get(seat, -1) == multiplayer.get_remote_sender_id() and int(dict.get("prompt_id", -1)) == game.prompt_id:
		game.submit_turn(seat, dict)

@rpc("any_peer", "call_remote", "reliable")
func send_response(seat: int, tile: String, dict: Dictionary) -> void:
	if not host_mode: return
	if _seat_peer.get(seat, -1) == multiplayer.get_remote_sender_id() and int(dict.get("prompt_id", -1)) == game.prompt_id:
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

@rpc("authority", "call_remote", "reliable")
func sync(state: Dictionary) -> void:
	_on_client_sync(state)

# 客户端动作前传（供 GameTable 网络模式调用）
func submit_client_turn(dict: Dictionary) -> void:
	dict["prompt_id"] = game.prompt_id
	rpc_id(1, "send_turn", my_seat, dict)

func submit_client_response(tile: String, dict: Dictionary) -> void:
	dict["prompt_id"] = game.prompt_id
	rpc_id(1, "send_response", my_seat, tile, dict)

# 测试回执
var ack_flag := false
var ack_text := ""
@rpc("any_peer", "call_remote", "reliable")
func ack(text: String) -> void:
	if host_mode:
		ack_flag = true
		ack_text = text
