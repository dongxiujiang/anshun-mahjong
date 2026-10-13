extends RefCounted
## 网络快照边界：内部状态使用枚举，发送格式保留历史字符串协议。

static func serialize(round_state) -> Dictionary:
	var state := {
		"current_turn": round_state.current_turn, "phase": round_state._phase_name(round_state.phase),
		"round_meta": round_state.round_meta.duplicate(true),
		"dealer_seat": round_state.dealer_seat, "next_dealer_seat": round_state.next_dealer_seat,
		"last_discard": _convert_kong_kinds(round_state.last_discard, true),
		"awaiting": round_state.awaiting, "prompt_id": round_state.prompt_id,
		"awaiting_response": round_state._awaiting_response.duplicate(true),
		"last_result": _convert_kong_kinds(round_state.last_result, true),
		"players": [], "wall": {}, "wall_stacks": {},
		"next_chicken_multiplier": round_state.next_chicken_multiplier,
		"audio_session": round_state.audio_session, "audio_event_id": round_state.audio_event_id,
		"audio_events": round_state.audio_events.duplicate(true),
	}
	if state.awaiting_response.has("stage"):
		state.awaiting_response.stage = round_state._response_stage_name(int(state.awaiting_response.stage))
	for player in round_state.players:
		state.players.append(_serialize_player(player))
	for seat in round_state.SEATS:
		if round_state.wall != null:
			state.wall[seat] = round_state.wall.wall_remaining(seat)
			state.wall_stacks[seat] = round_state.wall.wall_stack_counts(seat)
		else:
			state.wall[seat] = int(round_state.wall_remain.get(seat, 0))
			state.wall_stacks[seat] = round_state.wall_stacks.get(seat, []).duplicate()
	return state

static func _serialize_player(player: PlayerState) -> Dictionary:
	return {
		"seat": player.seat, "concealed": player.concealed.duplicate(),
		"melds": player.melds.duplicate(true), "discards": player.discards.duplicate(),
		"discard_history": player.discard_history.duplicate(),
		"discard_ids": player.discard_ids.duplicate(), "discard_count": player.discard_count,
		"score": player.score, "ready": player.ready, "name": player.name_label,
		"is_human": player.is_human, "is_dealer": player.is_dealer, "just_drew": player.just_drew,
		"first_turn_done": player.first_turn_done, "charge_chicken": player.charge_chicken,
	}

static func apply_sync(round_state, state: Dictionary) -> void:
	round_state.dealer_seat = int(state.get("dealer_seat", state.get("round_meta", {}).get("dealer_seat", 0)))
	round_state.next_dealer_seat = int(state.get("next_dealer_seat", round_state.dealer_seat))
	round_state.players.clear()
	for data in state.players:
		var player := PlayerState.new()
		player.seat = int(data.seat)
		player.concealed = data.concealed.duplicate()
		player.melds = data.melds.duplicate(true)
		player.discards = data.discards.duplicate()
		player.discard_history = data.get("discard_history", data.discards).duplicate()
		player.discard_ids = data.get("discard_ids", []).duplicate()
		player.discard_count = int(data.get("discard_count", player.discard_history.size()))
		player.score = float(data.score)
		player.ready = data.ready
		player.name_label = data.name
		player.is_human = data.is_human
		player.is_dealer = data.get("is_dealer", player.seat == round_state.dealer_seat)
		player.just_drew = data.get("just_drew", "")
		player.first_turn_done = data.get("first_turn_done", false)
		player.charge_chicken = data.get("charge_chicken", false)
		round_state.players.append(player)
	round_state.current_turn = int(state.current_turn)
	round_state.phase = round_state._phase_from_name(str(state.get("phase", "idle")))
	round_state.round_meta = state.round_meta.duplicate(true)
	round_state.next_chicken_multiplier = int(state.get("next_chicken_multiplier", 1))
	round_state.last_discard = _convert_kong_kinds(state.last_discard, false)
	round_state.awaiting = state.awaiting
	round_state.prompt_id = int(state.get("prompt_id", 0))
	round_state._awaiting_response = state.get("awaiting_response", {}).duplicate(true)
	if round_state._awaiting_response.has("stage"):
		round_state._awaiting_response.stage = round_state._response_stage_from_name(str(round_state._awaiting_response.stage))
	round_state.last_result = _convert_kong_kinds(state.get("last_result", {}), false)
	# 接收方没有完整牌墙，只保留各家的剩余数量。
	round_state.wall = null
	round_state.wall_remain = state.wall.duplicate()
	round_state.wall_stacks = state.get("wall_stacks", {}).duplicate(true)
	round_state._audio.apply_sync(state)

static func serialize_for_seat(round_state, seat: int) -> Dictionary:
	var state := serialize(round_state)
	if round_state.phase == round_state.Phase.SETTLED:
		return state
	for player in state.players:
		if int(player.seat) == seat:
			continue
		player.concealed.fill("hidden0")
		if player.just_drew != "":
			player.just_drew = "hidden0"
		for index in player.melds.size():
			if not round_state.is_meld_revealed(int(player.seat), index):
				player.melds[index].tile = "hidden0"
	return state

# 结算 items、points 等嵌套数据中的杠类型也要在边界转换。
static func _convert_kong_kinds(value: Variant, to_wire: bool) -> Variant:
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_convert_kong_kinds(item, to_wire))
		return result
	if value is Dictionary:
		var result := {}
		for key in value:
			if key == "kong_kind":
				result[key] = RoundState._kong_kind_name(int(value[key])) if to_wire else RoundState._kong_kind_from_name(str(value[key]))
			else:
				result[key] = _convert_kong_kinds(value[key], to_wire)
		return result
	return value
