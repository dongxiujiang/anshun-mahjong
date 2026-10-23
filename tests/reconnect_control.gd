extends SceneTree
## A delayed substitute must not play after a human has reclaimed the prompt.
const H := preload("res://tests/test_harness.gd")
var t := H.new()

class Substitute extends RefCounted:
	func decide_turn(round, seat: int) -> Dictionary:
		return {"discard": round.players[seat].just_drew}
	func decide_response(_round, _seat, _source, _tile, _options) -> Dictionary:
		return {"action": "pong"}

class WinningSubstitute extends Substitute:
	func decide_response(_round, _seat, _source, _tile, _options) -> Dictionary:
		return {"action": "win"}

func _initialize() -> void: call_deferred("_run")

func _fixture() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261018)
	r.build_players(0)
	r.phase = RoundState.Phase.PLAYING
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.controllers = [null, null, null, null]
	r.ai_delay_seconds = 0.08
	r.ai_response_delay_seconds = 0.08
	return r

func _run() -> void:
	var turn := _fixture()
	turn.players[0].concealed = ["wan1", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tong1", "tong2", "tong3", "tiao4", "tiao5", "tiao6", "tong9"]
	turn.players[0].just_drew = "tong9"
	turn.controllers[0] = Substitute.new()
	turn._ask_turn_actor()
	t.expect(not turn.awaiting, "AI turn is queued")
	turn.restore_human_control(0)
	var prompt := turn.prompt_id
	await create_timer(0.16).timeout
	t.expect(turn.current_turn == 0 and turn.awaiting and turn.prompt_id == prompt, "Old timer preserves reclaimed human turn")
	t.expect(turn.players[0].discards.is_empty() and turn.players[0].concealed.size() == 14, "Substitute cannot discard after reconnect")
	t.expect(turn.submit_turn(0, {"discard": "tong9"}), "Human can discard using restored turn")
	turn.phase = RoundState.Phase.IDLE

	var response := _fixture()
	response.players[1].concealed = ["tiao3", "tiao3", "wan1", "wan2", "wan4", "wan5", "wan7", "wan8", "tong1", "tong3", "tong5", "tong7", "tong9"]
	response.players[0].discards = ["tiao3"]
	response.last_discard = {"seat": 0, "tile": "tiao3"}
	response._response_stage = RoundState.ResponseStage.MELD
	response._pending_responders = [1]
	response.controllers[1] = Substitute.new()
	response._ask_next_responder(0, "tiao3")
	t.expect(not response.awaiting, "AI pong is queued")
	response.restore_human_control(1)
	prompt = response.prompt_id
	await create_timer(0.16).timeout
	t.expect(response.awaiting and response._awaiting_response.get("seat", -1) == 1 and response.prompt_id == prompt, "Old timer preserves reclaimed response")
	t.expect(response.players[1].melds.is_empty(), "Substitute cannot pong after reconnect")
	t.expect(response.submit_response(1, "tiao3", {"action": "pass"}), "Human can pass using restored response")
	response.phase = RoundState.Phase.IDLE

	var rob := _fixture()
	rob.players[1].concealed = ["wan1", "wan1", "wan2", "wan2", "wan3", "wan3", "tong1", "tong1", "tong2", "tong2", "tiao1", "tiao1", "tong5"]
	rob.players[0].melds = [{"kind": "pung", "tile": "tong5", "from": 2}]
	rob.players[0].concealed = ["tong5"]
	rob.last_discard = {"seat": 2, "tile": "tiao8"}
	rob._pending_kong = {"seat": 0, "tile": "tong5", "index": 0}
	rob._response_stage = RoundState.ResponseStage.ROB
	rob._pending_responders = [1]
	rob.controllers[1] = WinningSubstitute.new()
	rob._ask_next_responder(0, "tong5")
	rob.restore_human_control(1)
	t.expect(rob._awaiting_response.get("tile", "") == "tong5" and rob._awaiting_response.get("disc_seat", -1) == 0, "Rob-kong restoration uses pending kong instead of previous discard")
	await create_timer(0.16).timeout
	t.expect(rob.phase == RoundState.Phase.PLAYING and rob.awaiting, "Old timer cannot claim a rob-kong win for reconnected human")
	t.expect(rob.submit_response(1, "tong5", {"action": "pass"}), "Reconnected human chooses whether to rob kong")
	rob.phase = RoundState.Phase.IDLE

	# 断线→AI替打→凭token收回座位→结算后第二局作废（避免离线玩家卡住牌桌）。
	var net := NetGameNode.new()
	root.add_child(net)
	net.host_mode = true
	net._started = true
	net.game = _fixture()
	net.game.phase = RoundState.Phase.PLAYING
	net.game.current_turn = 1
	net.game.awaiting = false
	net._owner_peer = 1
	net._members[7] = {"name": "离线玩家", "ready": true, "wants_dealer": false, "resume_token": "token-xyz"}
	net._peer_seat[7] = 1
	net._seat_peer[1] = 7
	net._peer_protocol[7] = NetGameNode.PROTOCOL_VERSION
	net._ctrl_hint[1] = "remote"
	net._on_peer_disconnected(7)
	t.expect(net._orphaned.has(1) and net._ctrl_hint[1] == "wait", "Disconnect pauses the seat during the grace window")
	net._orphaned[1]["until"] = 0
	await process_frame
	await process_frame
	t.expect(bool(net._orphaned[1].get("replaced", false)) and net._orphaned.has(1), "Expired pause keeps the reclaimable reservation")
	t.expect(net.game.controllers[1] is AiPlayer, "AI substitutes after the pause")
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	net._pending_peers[0] = Time.get_ticks_msec()
	net.request_join("", "回场玩家", "", "token-xyz", true, NetGameNode.PROTOCOL_VERSION)
	t.expect(net._seat_peer[1] == 0 and net._orphaned.is_empty(), "Resume token reclaims the replaced seat")
	t.expect(net.game.controllers[1] == null, "Reclaim removes the AI controller")
	t.expect(net._members[0].resume_token == "token-xyz" and bool(net._members[0].ready), "Reclaimed member keeps the authority token")
	t.expect(net._ctrl_hint[1] == "remote", "Reclaimed seat is human-controlled again")
	# The full-snapshot push for the reclaimed peer is covered end-to-end by the
	# multi-process network suites (an offline fake peer cannot receive frames).
	await process_frame
	# 第二个座位：凭证跨局一直保留，直到房间关闭。
	net._members[8] = {"name": "第二位离线", "ready": true, "wants_dealer": false, "resume_token": "token-two"}
	net._peer_seat[8] = 2
	net._seat_peer[2] = 8
	net._peer_protocol[8] = NetGameNode.PROTOCOL_VERSION
	net._ctrl_hint[2] = "remote"
	net._on_peer_disconnected(8)
	net._orphaned[2]["until"] = 0
	net._orphaned[2]["ready_until"] = 0
	await process_frame
	await process_frame
	t.expect(bool(net._orphaned[2].get("replaced", false)), "Substituted seat keeps its credential through the settlement screen")
	t.expect(net.has_reconnect_reservations(), "Replaced seat keeps the otherwise-empty room alive")
	net.game.phase = RoundState.Phase.SETTLED
	net._ready_round = net.round_number
	net._start_next_round()
	t.expect(net.round_number == 1 and net._orphaned.has(2) and bool(net._orphaned[2].get("replaced", false)), "Round 2 keeps the reclaimable credential")
	# 回到大厅也保留凭证，让长时间切后台的玩家还能回到原座位。
	net._members[9] = {"name": "第三位离线", "ready": true, "wants_dealer": false, "resume_token": "token-three"}
	net._peer_seat[9] = 3
	net._seat_peer[3] = 9
	net._peer_protocol[9] = NetGameNode.PROTOCOL_VERSION
	net._ctrl_hint[3] = "remote"
	net._on_peer_disconnected(9)
	net._orphaned[3]["until"] = 0
	await process_frame
	await process_frame
	net.game.phase = RoundState.Phase.SETTLED
	net._reset_room_to_lobby()
	await process_frame
	t.expect(not net._started and net._orphaned.has(3) and net._ctrl_hint[3] == "auto", "Lobby return keeps the credential while the AI fills the seat")
	net.free()
	await process_frame

	var client := NetGameNode.new()
	root.add_child(client)
	client.game = _fixture()
	client._client_joined = true
	client._server_ip = "127.0.0.1"
	client._begin_reconnect("test")
	client.seat_assign(1)
	t.expect(client._resume_sync_pending, "Seat assignment alone cannot enable stale game input")
	var decision := {"discard": "tong9"}
	client.submit_client_turn(decision)
	t.expect(not decision.has("prompt_id"), "Client blocks turn submission before fresh state")
	var state := client.game.serialize_for_seat(1)
	state.revision = 1
	client._received_revision = 2
	client._on_client_sync(state)
	t.expect(client._resume_sync_pending, "An outdated snapshot cannot unlock reconnect input")
	state.revision = 3
	client._on_client_sync(state)
	t.expect(not client._resume_sync_pending, "Applying current state restores input")
	client.free()
	var resumed := NetGameNode.new()
	root.add_child(resumed)
	resumed._resume_requested = true
	resumed._reconnecting = false
	resumed._client_joined = false
	resumed._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	t.expect(resumed._reconnecting and resumed._reconnect_attempt == 0, "Resuming Android restarts an exhausted reconnect budget")
	resumed.free()
	quit(t.finish("reconnect_control"))
