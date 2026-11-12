extends SceneTree
const H := preload("res://tests/test_harness.gd")
const CONTEXT := preload("res://scripts/ai/AiTurnContext.gd")
const ARRANGE := preload("res://scripts/ui/table/v2/HandArrangement.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	for ready in [false, true]:
		var r := RoundState.new()
		r.build_players(0)
		r.controllers = [null, null, null, null]
		r.phase = RoundState.Phase.PLAYING
		r.current_turn = 0
		r.awaiting = true
		var p: PlayerState = r.players[0]
		p.ready = ready
		for digit in "11122233344455": p.concealed.append("wan" + digit)
		p.just_drew = "wan5"
		var hand := p.concealed.duplicate()
		var prompt := r.prompt_id
		t.expect(r.legal_turn_options(0).self_win, "winning draw starts with a legal self-win")
		t.expect(not r.submit_turn(1, {"pass_self_win": true}), "only the current player can decline")
		t.expect(not r.submit_turn(0, {"pass_self_win": true, "self_win": true}), "cannot win and pass together")
		t.expect(r.submit_turn(0, {"pass_self_win": true}), "explicit self-win pass is accepted")
		t.expect(r.awaiting and r.current_turn == 0 and r.prompt_id > prompt and p.concealed == hand, "passing neither discards nor advances the turn")
		t.expect(p.passed_self_draw and not p.passed_win_until_draw, "self-win pass is distinct from ready discard-win pass")
		t.expect(not r.legal_turn_options(0).self_win and not r.submit_turn(0, {"self_win": true}), "authority and cached options reject a second self-win attempt")
		t.expect(not r.submit_turn(0, {"pass_self_win": true}), "repeated self-win pass is rejected")
		var clone := RoundState.new()
		clone.apply_sync(r.serialize_for_seat(0))
		t.expect(clone.players[0].passed_self_draw and not clone.allowed_actions(0).options.self_win, "reconnection preserves a passed self-win")
		for observer in [1, 2, 3]:
			t.expect(not r.serialize_for_seat(observer).players[0].passed_self_draw, "other players do not learn the private self-win status")
		t.expect(CONTEXT.build(r, 0).players[0].passed_self_draw and not CONTEXT.build(r, 0).legal_options.self_win, "server AI proxy keeps the self-win pass")
		clone.apply_sync(AiVisibleSnapshot.build(r, 0))
		t.expect(not clone.legal_turn_options(0).self_win, "client AI snapshot keeps the self-win pass")
		var started := Time.get_ticks_usec()
		var choices := ARRANGE.build_turn(hand, false, [], r.legal_turn_options(0).discards)
		print("[sort timing] ready=", ready, " ms=", (Time.get_ticks_usec()-started)/1000.0, " choices=", choices.size())
		t.expect(not choices.is_empty(), "fourteen tiles have discard-and-wait arrangements")
		for choice in choices:
			t.expect(Tiles.sort_hand(choice.cards) == Tiles.sort_hand(hand), "sorting all fourteen tiles preserves each real tile")
			if ready: t.expect(choice.discard == p.just_drew, "ready discard plans only discard the new tile")
			var after := hand.duplicate()
			after.erase(choice.discard)
			for index in choice.waits:
				t.expect(RuleEngine.can_win_on(after, [], Tiles.from_index(index)), "every suggested wait follows a legal discard")
		r._clear_draw_locks(p)
		t.expect(not p.passed_self_draw and r.legal_turn_options(0).self_win, "the next draw clears only the current self-win pass")
		p.passed_self_draw = true
		p.passed_win_until_draw = true
		r._clear_draw_locks(p)
		t.expect(not p.passed_self_draw and p.passed_win_until_draw == ready, "ready whole-round pass lock retains its independent lifetime")
	await H.quit_cleanly(self, t.finish("sort_pass_self_win"))
