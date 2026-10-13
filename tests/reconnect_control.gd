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
	r.build_players(0)
	r.phase = RoundState.Phase.PLAYING
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.controllers = [null, null, null, null]
	r.ai_delay_seconds = 0.08
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
	quit(t.finish("reconnect_control"))
