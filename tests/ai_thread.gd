extends SceneTree
## Stage 1: snapshot parity and serial worker smoke test.
const H := preload("res://tests/test_harness.gd")
const AI_CONTEXT := preload("res://scripts/ai/AiTurnContext.gd")
const SERVICE := preload("res://scripts/ai/AiDecisionService.gd")
const TENPAI13 := ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","wan5","wan5","wan2","wan4"]

class NeverService:
	var token := 0
	func submit_turn(_context, _seat: int) -> int:
		token += 1
		return token
	func submit_response(_context, _seat: int, _source: int, _tile: String, _options: Dictionary) -> int:
		token += 1
		return token
	func take_result(_token: int) -> Dictionary:
		return {}
	func cancel(_token: int) -> void:
		pass

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _round() -> RoundState:
	var r := RoundState.new()
	r.build_players(0)
	r.phase = RoundState.Phase.PLAYING
	r.current_turn = 0
	r.players[0].concealed = TENPAI13.duplicate()
	r.players[0].concealed.append("tiao9")
	r.players[0].just_drew = "tiao9"
	r.players[0].first_turn_done = true
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.controllers = [AiPlayer.new("A"), AiPlayer.new("B"), AiPlayer.new("C"), AiPlayer.new("D")]
	return r

func _run() -> void:
	var r := _round()
	var context := AI_CONTEXT.build(r, 0)
	var sync_ai := AiPlayer.new("sync")
	var thread_ai := AiPlayer.new("thread")
	var expected: Dictionary = sync_ai.decide_turn(r, 0)
	var actual: Dictionary = thread_ai.decide_turn(context, 0)
	t.expect(expected == actual, "snapshot AI decision matches live RoundState decision")
	t.expect(context.players[1].concealed.is_empty(), "snapshot never exposes an opponent concealed hand")

	var service = SERVICE.new()
	var token: int = service.submit_turn(context, 0)
	t.expect(token > 0, "worker accepts a turn task")
	var result: Dictionary = {}
	for _index in 600:
		await process_frame
		result = service.take_result(token)
		if not result.is_empty(): break
	t.expect(not result.is_empty(), "worker returns a result")
	if not result.is_empty():
		t.expect(result.decision == expected, "worker decision matches synchronous decision")
	service.stop()

	var cancelled_service = SERVICE.new()
	var cancelled_token: int = cancelled_service.submit_turn(AI_CONTEXT.build(_round(), 0), 0)
	cancelled_service.cancel(cancelled_token)
	await create_timer(0.1).timeout
	t.expect(cancelled_service.take_result(cancelled_token).is_empty(), "cancelled worker result is discarded")
	cancelled_service.stop()

	var live := _round()
	var service2 = SERVICE.new()
	live.ai_service = service2
	live.ai_delay_seconds = 0.0
	live._ask_turn_actor()
	for _index in 600:
		await process_frame
		live.poll_ai()
		if not live._ai_pending.is_empty(): continue
		if live.current_turn != 0 or not live.players[0].discards.is_empty(): break
	t.expect(live.players[0].discards.has("tiao9"), "RoundState applies a worker decision")
	t.expect(live.ai_timeouts == 0 and live.ai_fallbacks == 0, "normal worker path does not timeout or fall back")
	service2.stop()

	var takeover := _round()
	var service3 = SERVICE.new()
	takeover.ai_service = service3
	takeover.ai_delay_seconds = 0.0
	takeover._ask_turn_actor()
	takeover.restore_human_control(0)
	await create_timer(0.2).timeout
	takeover.poll_ai()
	t.expect(takeover.players[0].discards.is_empty(), "takeover cancels a pending AI move")
	t.expect(takeover.ai_cancelled >= 1, "takeover records cancellation")
	service3.stop()

	var timeout_round := _round()
	timeout_round.ai_service = NeverService.new()
	timeout_round.ai_delay_seconds = 0.0
	timeout_round._ask_turn_actor()
	await create_timer(3.2).timeout
	timeout_round.poll_ai()
	t.expect(timeout_round.ai_timeouts == 1 and timeout_round.ai_fallbacks == 1,
		"worker timeout uses a bounded fallback")
	t.expect(timeout_round.players[0].discards.size() == 1, "timeout fallback still makes a legal move")

	quit(t.finish("ai_thread"))
