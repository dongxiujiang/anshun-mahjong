extends SceneTree
## 风险标定：记录每次 AI 主动弃牌时的预测点炮概率与实际点炮结果。

const AI := preload("res://scripts/ai/AiPlayer.gd")

func _initialize() -> void:
	var start := 0
	var count := 100
	var output := ""
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in args.size():
		if args[index] == "--start" and index + 1 < args.size():
			start = int(args[index + 1])
		elif args[index] == "--count" and index + 1 < args.size():
			count = int(args[index + 1])
		elif args[index] == "--output" and index + 1 < args.size():
			output = args[index + 1]
	if count <= 0:
		quit(2)
		return
	var samples: Array = []
	var games := 0
	var aborted := 0
	for offset in count:
		var seed := start + offset
		var game_samples := _play(seed)
		if game_samples.is_empty():
			aborted += 1
			continue
		samples.append_array(game_samples)
		games += 1
	var report := {"games": games, "aborted": aborted, "samples": samples}
	if output != "":
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report))
			file.close()
	print("AI_RISK_DONE start=%d games=%d samples=%d" % [start, games, samples.size()])
	quit(0)

func _play(seed: int) -> Array:
	var round := RoundState.new()
	round.build_players(0)
	round.ai_delay_seconds = 0.0
	round.ai_response_delay_seconds = 0.0
	round.opening_delay_seconds = 0.0
	var actors: Array = []
	for seat in 4:
		var actor = AI.new("AI%d" % seat, "low")
		actor.rng.seed = seed * 4 + seat + 1
		actors.append(actor)
	round.controllers = [null, null, null, null]
	round.set_rng_seed(seed)
	round.start_round(seed % 4, seed % 6 + 1)
	var samples: Array = []
	var pending_index := -1
	var pending_seat := -1
	var steps := 0
	while round.phase == RoundState.Phase.PLAYING and steps < 500:
		steps += 1
		if round.awaiting and not round._awaiting_response.is_empty():
			var prompt: Dictionary = round._awaiting_response
			var response_seat := int(prompt.get("seat", -1))
			var source := int(prompt.get("disc_seat", -1))
			var tile := str(prompt.get("tile", ""))
			var options: Dictionary = prompt.get("options", {})
			var response: Dictionary = actors[response_seat].decide_response(round, response_seat, source, tile, options)
			var claimed_win: bool = str(response.get("action", "pass")) == "win" and source == pending_seat and pending_index >= 0
			if not round.submit_response(response_seat, tile, response):
				return []
			if claimed_win and pending_index >= 0:
				samples[pending_index][1] = 1.0
				if round.phase == RoundState.Phase.SETTLED and not round.last_result.is_empty():
					var deltas: Array = round.last_result.get("deltas", [0.0, 0.0, 0.0, 0.0])
					samples[pending_index][3] = -float(deltas[pending_seat])
				pending_index = -1
				pending_seat = -1
			continue
		var seat := int(round.current_turn)
		if seat < 0 or seat >= 4:
			return []
		var decision: Dictionary = actors[seat].decide_turn(round, seat)
		var is_discard: bool = decision.has("discard") and not bool(decision.get("self_win", false)) \
			and decision.get("kong_declares", []).is_empty() and decision.get("add_kong", []).is_empty()
		var risk := float(actors[seat].last_discard_risk) if is_discard else 0.0
		var strength := float(actors[seat].last_risk_strength) if is_discard else 0.0
		if not round.submit_turn(seat, decision):
			return []
		if not is_discard:
			continue
		# 弃牌后先进入响应窗口；真正的点炮结果在后续 win 响应时回填。
		samples.append([risk, 0.0, strength, 0.0])
		pending_index = samples.size() - 1
		pending_seat = seat
	if round.phase != RoundState.Phase.SETTLED:
		return []
	return samples
