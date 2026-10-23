extends SceneTree
## Focused rules regression around the response-state machine and settlement
## boundaries that are easy to break when adding network/UI features.
const H := preload("res://tests/test_harness.gd")
const WAIT := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9"]
var t:= H.new()

func _initialize() -> void:
	call_deferred("_run")

func _fixture() -> RoundState:
	var r:= RoundState.new()
	r.set_rng_seed(20261023)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	r.current_turn = 0
	r.awaiting = true
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.players[0].concealed = ["wan9"]
	r.players[0].just_drew = "wan9"
	return r

func _waiting_hand() -> Array:
	return WAIT.duplicate()

func _run() -> void:
	var kong_first:= _fixture()
	kong_first.players[1].concealed = ["wan5", "wan5", "tong1", "tong2", "tong3", "tiao1", "tiao2", "tiao3", "wan1", "wan2", "wan3", "tong7", "tong8"]
	kong_first.players[2].concealed = ["wan5", "wan5", "wan5", "tong1", "tong2", "tong3", "tiao1", "tiao2", "tiao3", "wan1", "wan2", "wan3", "tong7"]
	kong_first.players[0].concealed = ["wan5"]
	kong_first.players[0].just_drew = "wan5"
	t.expect(kong_first.submit_turn(0, {"discard": "wan5"}), "discard opens priority window")
	t.expect(kong_first._response_stage == RoundState.ResponseStage.KONG, "kong stage precedes pong")
	t.expect(kong_first._awaiting_response.get("seat", -1) == 2, "only kong-capable seat is asked first")
	t.expect(not kong_first.submit_response(1, "wan5", {"action": "pong"}), "pong is rejected during kong stage")
	t.expect(kong_first.submit_response(2, "wan5", {"action": "kong"}), "kong is accepted")
	t.expect(kong_first.players[2].melds.size() == 1 and kong_first.players[2].melds[0].kind == "kong", "kong meld formed")
	t.expect(kong_first.players[1].melds.is_empty(), "earlier pong seat did not steal the kong")

	var hu_first:= _fixture()
	hu_first.players[1].concealed = ["wan5", "wan5", "wan5", "tong1", "tong2", "tong3", "tiao1", "tiao2", "tiao3", "wan1", "wan2", "wan3", "tong7"]
	hu_first.players[2].concealed = _waiting_hand()
	hu_first.players[2].ready = true
	hu_first.players[2].announced_ready = true
	t.expect(hu_first.submit_turn(0, {"discard": "wan9"}), "discard opens win priority window")
	t.expect(hu_first._response_stage == RoundState.ResponseStage.WIN, "win stage starts before kong")
	t.expect(hu_first.submit_response(2, "wan9", {"action": "win"}), "win is accepted before kong")
	t.expect(hu_first.phase == RoundState.Phase.SETTLED, "win settles without kong")
	t.expect(hu_first.players[1].melds.is_empty(), "would-be kong did not run")
	t.expect((hu_first.round_meta.get("winners", []) as Array).has(2), "winning seat is recorded")

	var multi: RoundState = _fixture()
	for seat in [1, 2]:
		multi.players[seat].concealed = _waiting_hand()
		multi.players[seat].ready = true
		multi.players[seat].announced_ready = true
	t.expect(multi.submit_turn(0, {"discard": "wan9"}), "multi-win discard accepted")
	t.expect(multi.submit_response(1, "wan9", {"action": "win"}), "first winner accepted")
	t.expect(multi.submit_response(2, "wan9", {"action": "win"}), "second winner accepted")
	t.expect(multi.phase == RoundState.Phase.SETTLED and (multi.round_meta.get("winners", []) as Array).size() == 2, "both winners settle")
	t.expect(is_equal_approx(multi.players.reduce(func(acc, p): return acc + p.score, 0.0), 800.0), "multi-win preserves 800 total")

	var dealer: RoundState = _fixture()
	dealer._last_deltas = [6.0, 18.0, 4.0, -28.0]
	dealer.round_meta.winners = [0, 1]
	dealer.round_meta.winner = 1
	dealer._rng.seed = 1234
	t.expect(dealer._choose_next_dealer([true, true, true, true]) == 1, "highest-net winner becomes dealer")

	var draw: RoundState = _fixture()
	draw._last_deltas = [-10.0, 2.0, -5.0, 13.0]
	draw._rng.seed = 22
	t.expect(draw._choose_next_dealer([true, false, true, false]) == 1, "lowest-net uncalled drawer becomes dealer when unique")

	var forbidden: RoundState = _fixture()
	forbidden.players[0].forbidden_discard_tile = "wan9"
	forbidden.players[0].concealed = ["wan9", "wan1", "wan2", "wan3", "tiao1", "tiao2", "tiao3", "tong1", "tong2", "tong3", "tiao7"]
	forbidden.players[0].just_drew = "tiao7"
	t.expect(not forbidden.legal_turn_options(0).discards.has("wan9"), "forbidden just-claimed tile is not legal")

	var stable: RoundState = _fixture()
	var before_prompt: int = stable.prompt_id
	var before_hand: Array = stable.players[0].concealed.duplicate()
	stable.awaiting = false
	t.expect(not stable.submit_turn(0, {"discard": "wan9"}), "turn rejected outside awaiting window")
	t.expect(stable.prompt_id == before_prompt and stable.players[0].concealed == before_hand, "rejected turn leaves state unchanged")

	var serialized: RoundState = _fixture()
	serialized._response_stage = RoundState.ResponseStage.KONG
	serialized._awaiting_response = {"seat": 1, "stage": RoundState.ResponseStage.KONG}
	var wire: Dictionary = serialized.serialize()
	t.expect(wire.awaiting_response.stage == "kong", "kong stage round-trips over the wire")
	var restored: RoundState = RoundState.new()
	restored.apply_sync(wire)
	t.expect(restored._response_stage == RoundState.ResponseStage.KONG, "kong stage restores internally")

	await H.quit_cleanly(self, t.finish("rules_priority_edges"))
