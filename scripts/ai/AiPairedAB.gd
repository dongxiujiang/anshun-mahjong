extends RefCounted
## 配对 A/B：同一 seed、同一牌墙、同一发牌，只替换候选座位的一个 AI。
## 每个 pair 先跑候选局，再跑全 baseline 局，比较同一座位的得分。

const AI := preload("res://scripts/ai/AiPlayer.gd")

static func run_pair(seed: int, candidate_level: String, baseline_level: String, candidate_seat: int, candidate_defense: float = 0.0, inference_weight: float = 1.0, candidate_calibrated: bool = false, candidate_risk_aversion: float = 1.0) -> Dictionary:
	# 冷启动会影响第一次搜索的耗时；按 seed 交替先后，避免候选/基准的
	# 耗时统计被固定执行顺序污染。
	var candidate: Dictionary
	var baseline: Dictionary
	if seed % 2 == 0:
		candidate = _play(seed, candidate_level, candidate_seat, candidate_defense, inference_weight, candidate_calibrated, candidate_risk_aversion)
		baseline = _play(seed, baseline_level, candidate_seat, 0.0, inference_weight, false, 1.0)
	else:
		baseline = _play(seed, baseline_level, candidate_seat, 0.0, inference_weight, false, 1.0)
		candidate = _play(seed, candidate_level, candidate_seat, candidate_defense, inference_weight, candidate_calibrated, candidate_risk_aversion)
	if not bool(candidate.get("ok", false)) or not bool(baseline.get("ok", false)):
		return {"ok": false, "seed": seed, "seat": candidate_seat}
	return {
		"ok": true, "seed": seed, "seat": candidate_seat,
		"candidate": candidate, "baseline": baseline,
		"score_delta": float(candidate.score) - float(baseline.score),
	}

static func _play(seed: int, level: String, focus_seat: int, focus_defense: float = 0.0, inference_weight: float = 1.0, focus_calibrated: bool = false, focus_risk_aversion: float = 1.0) -> Dictionary:
	var round := RoundState.new()
	round.build_players(0)
	round.ai_delay_seconds = 0.0
	round.ai_response_delay_seconds = 0.0
	round.opening_delay_seconds = 0.0
	var actors: Array = []
	for seat in 4:
		var actor = AI.new("AI%d" % seat, level)
		# 两边使用相同 seed，保证候选和 baseline 的随机分支对齐。
		actor.rng.seed = seed * 4 + seat + 1
		actor.inference_weight = inference_weight
		if seat == focus_seat and focus_calibrated:
			actor.set_risk_calibrated(true)
			actor.set_risk_aversion(focus_risk_aversion)
		if seat == focus_seat and focus_defense > 0.0:
			actor.set_defense_weight(focus_defense)
		actors.append(actor)
	round.controllers = [null, null, null, null]
	round.set_rng_seed(seed)
	round.start_round(0, seed % 6 + 1)
	if round.phase != RoundState.Phase.PLAYING and round.phase != RoundState.Phase.SETTLED:
		return {"ok": false}
	var steps := 0
	var decision_ms: Array[float] = []
	var focus_ms: Array[float] = []
	var discard_expected_loss := 0.0
	var ready_declares := 0
	var ready_step := -1
	while round.phase == RoundState.Phase.PLAYING and steps < 500:
		steps += 1
		var started := Time.get_ticks_usec()
		var accepted := false
		var actor_seat := -1
		var discarded := false
		if round.awaiting and not round._awaiting_response.is_empty():
			var prompt: Dictionary = round._awaiting_response
			actor_seat = int(prompt.get("seat", -1))
			if actor_seat < 0 or actor_seat >= 4:
				return {"ok": false}
			var source := int(prompt.get("disc_seat", -1))
			var tile := str(prompt.get("tile", ""))
			var options: Dictionary = prompt.get("options", {})
			var decision: Dictionary = actors[actor_seat].decide_response(round, actor_seat, source, tile, options)
			accepted = round.submit_response(actor_seat, tile, decision)
		else:
			actor_seat = int(round.current_turn)
			if actor_seat < 0 or actor_seat >= 4:
				return {"ok": false}
			var decision: Dictionary = actors[actor_seat].decide_turn(round, actor_seat)
			discarded = decision.has("discard") and not bool(decision.get("self_win", false)) \
				and decision.get("kong_declares", []).is_empty() and decision.get("add_kong", []).is_empty()
			if actor_seat == focus_seat and bool(decision.get("ready", false)):
				ready_declares += 1
				if ready_step < 0: ready_step = steps
			accepted = round.submit_turn(actor_seat, decision)
		if not accepted:
			return {"ok": false}
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		decision_ms.append(elapsed)
		if actor_seat == focus_seat:
			focus_ms.append(elapsed)
			if discarded:
				discard_expected_loss += float(actors[focus_seat].last_calibrated_loss)
	if round.phase != RoundState.Phase.SETTLED or round.last_result.is_empty():
		return {"ok": false}
	var meta: Dictionary = round.last_result.get("round_meta", {})
	var winners: Array = meta.get("winners", [])
	if winners.is_empty() and int(meta.get("winner", -1)) >= 0:
		winners = [int(meta.get("winner", -1))]
	var deltas: Array = round.last_result.get("deltas", [0.0, 0.0, 0.0, 0.0])
	return {
		"ok": true,
		"win": winners.has(focus_seat),
		"deal_in": not bool(meta.get("self_draw", false)) and int(meta.get("discard_seat", -1)) == focus_seat and not winners.is_empty(),
		"score": float(deltas[focus_seat]),
		"discard_expected_loss": discard_expected_loss,
		"discard_actual_loss": -float(deltas[focus_seat]) if (not bool(meta.get("self_draw", false)) and int(meta.get("discard_seat", -1)) == focus_seat and not winners.is_empty()) else 0.0,
		"ready_declares": ready_declares,
		"ready_step": ready_step,
		"decision_ms": decision_ms,
		"focus_ms": focus_ms,
		"steps": steps,
	}

static func summarize(pairs: Array, candidate_level: String, baseline_level: String) -> Dictionary:
	var out := {
		"pairs": 0, "failed": 0, "candidate": candidate_level, "baseline": baseline_level,
		"candidate_wins": 0, "baseline_wins": 0,
		"candidate_deals": 0, "baseline_deals": 0,
		"candidate_ready_declares": 0, "baseline_ready_declares": 0,
		"candidate_ready_step_sum": 0, "baseline_ready_step_sum": 0,
		"candidate_score": 0.0, "baseline_score": 0.0,
		"candidate_expected_discard_loss": 0.0, "baseline_expected_discard_loss": 0.0,
		"candidate_actual_discard_loss": 0.0, "baseline_actual_discard_loss": 0.0,
		"expected_loss_deltas": [], "actual_loss_deltas": [],
		"deltas": [], "candidate_ms": [], "baseline_ms": [],
	}
	for pair in pairs:
		if not bool(pair.get("ok", false)):
			out.failed = int(out.failed) + 1
			continue
		out.pairs = int(out.pairs) + 1
		var cand: Dictionary = pair.candidate
		var base: Dictionary = pair.baseline
		if bool(cand.win): out.candidate_wins = int(out.candidate_wins) + 1
		if bool(base.win): out.baseline_wins = int(out.baseline_wins) + 1
		if bool(cand.deal_in): out.candidate_deals = int(out.candidate_deals) + 1
		if bool(base.deal_in): out.baseline_deals = int(out.baseline_deals) + 1
		out.candidate_ready_declares = int(out.candidate_ready_declares) + int(cand.get("ready_declares", 0))
		out.baseline_ready_declares = int(out.baseline_ready_declares) + int(base.get("ready_declares", 0))
		if int(cand.get("ready_step", -1)) >= 0:
			out.candidate_ready_step_sum = int(out.candidate_ready_step_sum) + int(cand.ready_step)
		if int(base.get("ready_step", -1)) >= 0:
			out.baseline_ready_step_sum = int(out.baseline_ready_step_sum) + int(base.ready_step)
		out.candidate_score = float(out.candidate_score) + float(cand.score)
		out.baseline_score = float(out.baseline_score) + float(base.score)
		out.deltas.append(float(pair.get("score_delta", 0.0)))
		var cand_expected := float(cand.get("discard_expected_loss", 0.0))
		var base_expected := float(base.get("discard_expected_loss", 0.0))
		var cand_actual := float(cand.get("discard_actual_loss", 0.0))
		var base_actual := float(base.get("discard_actual_loss", 0.0))
		out.candidate_expected_discard_loss = float(out.candidate_expected_discard_loss) + cand_expected
		out.baseline_expected_discard_loss = float(out.baseline_expected_discard_loss) + base_expected
		out.candidate_actual_discard_loss = float(out.candidate_actual_discard_loss) + cand_actual
		out.baseline_actual_discard_loss = float(out.baseline_actual_discard_loss) + base_actual
		out.expected_loss_deltas.append(cand_expected - base_expected)
		out.actual_loss_deltas.append(cand_actual - base_actual)
		out.candidate_ms.append_array(cand.get("focus_ms", []))
		out.baseline_ms.append_array(base.get("focus_ms", []))
	return out
