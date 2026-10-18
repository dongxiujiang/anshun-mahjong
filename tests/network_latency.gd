extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()

class PassingAI extends RefCounted:
	func decide_response(_round, _seat, _source, _tile, _options) -> Dictionary:
		return {"action": "pass"}

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var r := RoundState.new()
	r.build_players(0)
	r.phase = RoundState.Phase.PLAYING
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.controllers = [null, PassingAI.new(), null, null]
	r.ai_delay_seconds = 3.0
	r.last_discard = {"seat": 0, "tile": "tiao3"}
	r.players[1].concealed = ["tiao3", "tiao3", "wan1", "wan2", "wan4", "wan5", "wan7", "wan8", "tong1", "tong3", "tong5", "tong7", "tong9"]
	r._response_stage = RoundState.ResponseStage.MELD
	r._pending_responders = [1]
	var start := Time.get_ticks_usec()
	r._ask_next_responder(0, "tiao3")
	var next_seat := posmod(0 + GameConfig.TURN_DIRECTION, 4)
	t.expect(r.current_turn == next_seat and r.awaiting and r._awaiting_response.is_empty(), "AI pass advances immediately even at slow three-second speed")
	t.expect(Time.get_ticks_usec() - start < 100000, "AI pass adds no deliberate timer delay")
	# 快照与操作提示一起应用；旧快照不能把提示、牌面回退。
	var client = load("res://scripts/online/NetGameNode.gd").new()
	root.add_child(client)
	client.game = RoundState.new()
	client.my_seat = 1
	var state := r.serialize_for_seat(1)
	state.revision = 2
	state.round_number = 1
	client._on_client_sync(state)
	t.expect(client.game.phase == RoundState.Phase.IDLE, "Snapshot arriving before seat assignment cannot unlock an unknown seat")
	client.seat_assign(1)
	t.expect(client.game.current_turn == next_seat and client.game.awaiting and client.game.prompt_id == r.prompt_id, "Snapshot supplies a valid action prompt in one application")
	var old := state.duplicate(true)
	old.revision = 1
	old.current_turn = posmod(next_seat + 1, 4)
	old.prompt_id = 0
	client._on_client_sync(old)
	t.expect(client.game.current_turn == next_seat and client.game.prompt_id == r.prompt_id, "Old revision cannot replace current tiles or prompt")
	client.free()
	# 同一帧重复广播只生成一个快照。
	var host = load("res://scripts/online/NetGameNode.gd").new()
	root.add_child(host)
	t.expect(host.host(false, true, 7538), "Synchronization test opens a real host")
	t.expect(not (root.multiplayer as SceneMultiplayer).server_relay, "Authoritative rooms do not relay client connections or disconnects")
	host.set_wants_dealer(true)
	host.set_ready(true)
	t.expect(host.start_net_game(101), "Synchronization fixture starts")
	for index in 10: host._host_broadcast()
	await process_frame
	t.expect(host._state_revision == 1 and host.state_metrics.coalesced >= 10, "Repeated state changes produce one final snapshot per frame")
	host.free()
	root.multiplayer.multiplayer_peer = null
	quit(t.finish("network_latency"))
