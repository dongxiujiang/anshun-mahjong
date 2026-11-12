class_name AiVisibleSnapshot
extends RefCounted
## 只复制 AI 可公开观察的信息，避免主线程复制整副牌墙和所有暗手。

static func build(round, seat: int) -> Dictionary:
	var players: Array = []
	for p in round.players:
		var melds: Array = []
		for index in p.melds.size():
			var meld: Dictionary = p.melds[index].duplicate(true)
			if p.seat != seat and not round.is_meld_revealed(p.seat, index):
				meld["tile"] = ""
				meld["tiles"] = []
				meld["concealed"] = true
			melds.append(meld)
		var own: bool = p.seat == seat
		players.append({
			"seat": p.seat,
			"concealed": p.concealed.duplicate() if own else [],
			"melds": melds,
			"discards": p.discards.duplicate(),
			"discard_history": p.discard_history.duplicate(),
			"discard_ids": p.discard_ids.duplicate(),
			"discard_count": p.discard_count,
			"score": p.score,
			"ready": p.ready,
			"ready_wait_tiles": p.ready_wait_tiles.duplicate() if own else [],
			"name": p.name_label,
			"is_human": p.is_human,
			"is_dealer": p.is_dealer,
			"just_drew": p.just_drew if own else "",
			"first_turn_done": p.first_turn_done,
			"charge_chicken": p.charge_chicken,
			"passed_win_until_draw": p.passed_win_until_draw,
			"passed_self_draw": p.passed_self_draw if own else false,
			"passed_pong_tiles": p.passed_pong_tiles.duplicate(),
			"add_kong_locked_tiles": p.add_kong_locked_tiles.duplicate(),
			"forbidden_discard_tile": p.forbidden_discard_tile,
		})
	var wall_counts := {}
	var wall_stacks := {}
	for index in 4:
		wall_counts[index] = int(round.wall_remain.get(index, round._wall_count()))
		wall_stacks[index] = round.wall_stacks.get(index, []).duplicate()
	return {
		"current_turn": seat, "phase": "playing", "round_meta": round.round_meta.duplicate(true),
		"dealer_seat": round.dealer_seat, "next_dealer_seat": round.next_dealer_seat,
		"last_discard": round.last_discard.duplicate(true), "awaiting": true, "prompt_id": 0,
		"awaiting_response": {}, "last_result": {},
		"next_chicken_multiplier": round.next_chicken_multiplier,
		"opening_speed": round.opening_speed,
		"audio_session": round.audio_session, "audio_event_id": round.audio_event_id,
		"audio_events": [], "visual_session": round._presentation.session, "visual_event_id": 0,
		"visual_events": [], "players": players, "wall": wall_counts, "wall_stacks": wall_stacks,
	}
