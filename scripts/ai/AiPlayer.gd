class_name AiPlayer
extends RefCounted

var name := "AI"
var rng := RandomNumberGenerator.new()
var inference_weight := 1.0
const VALUE := preload("res://scripts/ai/AiValueModel.gd")
const OPPONENT := preload("res://scripts/ai/AiOpponentModel.gd")
const MCTS := preload("res://scripts/ai/AiMctsSearch.gd")
const RISK_CALIBRATION := preload("res://scripts/ai/AiRiskCalibration.gd")
var opponent_model := OPPONENT.new()
var mcts := MCTS.new()
var last_analysis: Array = []
var last_discard_risk := 0.0
var last_calibrated_loss := 0.0
var last_risk_strength := 0.0
var use_mcts := true
var difficulty := "low"
var defense_weight := 0.0
var risk_inflation := 0.0
var candidate_slack := 0
var search_window := 0.35
var safety_margin := 0.0
var ready_bonus := 0.0
var risk_calibrated := false
var risk_aversion := 1.0
## B18 test profile: 向听/进张权重与保叫牌门槛。
var tenpai_weight := 8.0
var distance_weight := -24.0
var outs_weight := 0.60
var keep_tenpai := false
var keep_tenpai_slack := 0

func _init(label := "AI", level := "low") -> void:
	name = label
	rng.randomize()
	set_difficulty(level)

func set_risk_calibrated(value: bool) -> void:
	risk_calibrated = value

func set_risk_aversion(value: float) -> void:
	risk_aversion = maxf(0.0, value)

func set_defense_weight(weight: float) -> void:
	defense_weight = maxf(0.0, weight)
	mcts.defense_weight = defense_weight

func set_difficulty(level: String) -> void:
	difficulty = level
	var factor := 1.0
	tenpai_weight = 8.0
	distance_weight = -24.0
	outs_weight = 0.60
	keep_tenpai = false
	keep_tenpai_slack = 0
	match level:
		"low":
			# 测试包：低档使用 main 1.6.3 中档参数。
			factor = 1.0
			defense_weight = 0.15
			risk_inflation = 0.15
			candidate_slack = 0
			search_window = 0.35
			ready_bonus = 0.5
			safety_margin = 3.0
			opponent_model.set_wait_model(true)
		"medium":
			# 测试包：中档使用 B18。
			factor = 1.0
			defense_weight = 0.50
			risk_inflation = 0.35
			candidate_slack = 0
			search_window = 0.20
			ready_bonus = 1.5
			safety_margin = 3.0
			tenpai_weight = 40.0
			distance_weight = -60.0
			outs_weight = 1.80
			keep_tenpai = true
			keep_tenpai_slack = 2
			risk_calibrated = true
			opponent_model.set_wait_model(true)
		"high":
			factor = 2.0
			defense_weight = 0.65
			risk_inflation = 0.45
			candidate_slack = 1
			ready_bonus = 1.0
			opponent_model.set_wait_model(true)
		_:
			defense_weight = 0.15
			risk_inflation = 0.15
			candidate_slack = 0
			search_window = 0.35
			ready_bonus = 0.5
			safety_margin = 3.0
			opponent_model.set_wait_model(true)
	mcts.iterations = roundi(16.0 * factor)
	mcts.defense_weight = defense_weight

func decide_turn(round, seat: int) -> Dictionary:
	last_discard_risk = 0.0
	last_calibrated_loss = 0.0
	var player: PlayerState = round.players[seat]
	var options: Dictionary = round.legal_turn_options(seat)
	if options.self_win: return {"self_win": true}
	if player.ready: return {"discard": player.just_drew}
	for tile in options.kong_declares:
		if keep_tenpai and not _kong_keeps_tenpai(round, seat, tile, false): continue
		if _kong_helps(round, seat, tile, false): return {"kong_declares": [tile]}
	for tile in options.add_kong:
		if keep_tenpai and not _add_kong_keeps_tenpai(round, seat, tile): continue
		if _add_kong_helps(round, seat, tile): return {"add_kong": [tile]}
	var choice := _pick_discard(round, seat)
	return {"discard": choice.tile, "ready": choice.ready_capable and options.ready_discards.has(choice.tile)}

func _pick_discard(round, seat: int) -> Dictionary:
	var player: PlayerState = round.players[seat]
	var seen := _seen_map(round, seat)
	var context := opponent_model.observe(round, seat, seen)
	last_risk_strength = 0.0
	for opponent in context.opponents:
		last_risk_strength = maxf(last_risk_strength, float(opponent.tenpai_probability))
	var after_kong: bool = round._kong_draw_turn
	last_analysis = _discard_options(round, seat, player.concealed, player.melds, seen, context, round.can_declare_ready(seat), after_kong)
	var ordinary := last_analysis.filter(func(candidate): return not bool(candidate.get("declare_ready", false)))
	var search_candidates: Array = ordinary.duplicate(true)
	search_candidates.sort_custom(func(left, right): return float(left.merit) > float(right.merit))
	if not search_candidates.is_empty():
		var top_merit := float(search_candidates[0].merit)
		# Only refine genuinely close alternatives. Medium keeps one more
		# near-equal route so it is less likely to look mechanically locked
		# onto a single discard.
		var merit_window := search_window
		search_candidates = search_candidates.filter(func(candidate): return top_merit - float(candidate.merit) <= merit_window)
	var candidate_limit := 6 + (2 if difficulty == "medium" else 0)
	if search_candidates.size() > candidate_limit:
		search_candidates = search_candidates.slice(0, candidate_limit)
	var tree: Dictionary = mcts.rank(round, seat, player.concealed, player.melds, seen, search_candidates, context, defense_weight) if use_mcts and search_candidates.size() > 1 else {}
	for candidate in last_analysis:
		var search: Dictionary = tree.get(candidate.tile, {})
		candidate["mcts_visits"] = int(search.get("visits", 0))
		candidate["mcts_value"] = float(search.get("value", 0.0))
		# MCTS refines equal/near-equal routes; the hard shanten filter and
		# expected-loss term above still dominate a speculative branch.
		candidate.merit += 0.40 * candidate.mcts_value
	var best: Dictionary = last_analysis[0]
	for candidate in last_analysis:
		if float(candidate.merit) > float(best.merit): best = candidate
	# 后段高威胁时，在成本相近的牌中优先选择别家已经打过、场上
	# 已见张数更多的牌，作为标定 wait 模型的补充。
	if safety_margin > 0.0 and last_risk_strength >= 0.45 and round._wall_count() <= 28:
		var seen_best := int(seen.get(str(best.tile), 0))
		var safe_best := best
		for candidate in last_analysis:
			if float(candidate.merit) < float(best.merit) - safety_margin: continue
			var seen_candidate := int(seen.get(str(candidate.tile), 0))
			if seen_candidate >= seen_best + 1 and (safe_best == best or seen_candidate > int(seen.get(str(safe_best.tile), 0))):
				safe_best = candidate
		best = safe_best
	last_discard_risk = float(best.get("discard_risk", 0.0))
	# 机制指标保持 λ=1 的纯校准尺度，不能把风险厌恶系数混进损失口径。
	last_calibrated_loss = RISK_CALIBRATION.expected_loss(last_discard_risk, last_risk_strength)
	return {"tile": best.tile, "ready_capable": best.declare_ready}

func _discard_options(round, seat: int, hand: Array, melds: Array, seen: Dictionary, context: Dictionary, allow_ready: bool = false, after_kong: bool = false) -> Array:
	var options: Array = []
	var candidates: Array = []
	var player: PlayerState = round.players[seat]
	var lowest := 99
	var threat := 0.0
	for opponent in context.opponents:
		threat = maxf(threat, float(opponent.tenpai_probability))
	for tile in Tiles.to_counts(hand):
		# A tile just claimed by pong is temporarily forbidden. The UI and
		# RoundState both exclude it; the AI candidate pool must do the same.
		if tile == player.forbidden_discard_tile: continue
		var after := hand.duplicate()
		after.erase(tile)
		var distance := Shanten.shanten(after, melds)
		lowest = mini(lowest, distance)
		candidates.append({"tile": tile, "hand": after, "distance": distance})
	# A distant, threatened hand may retreat one step. Otherwise preserve the
	# fastest completion routes before comparing uncertain score estimates.
	var retreat := 1 if threat >= 0.55 and lowest > 1 else 0
	# 中档在对手明显听牌时允许再保留一条转换路线；低档保持严格最短
	# 向听，避免为了“灵活”把明显更差的牌纳入选择。
	var slack: int = candidate_slack if threat >= 0.35 else 0
	for candidate in candidates:
		if int(candidate.distance) > lowest + retreat + slack: continue
		var ordinary := _evaluate_hand(round, seat, candidate.hand, melds, seen, context, candidate.tile, false, after_kong)
		options.append(ordinary)
		if allow_ready and int(ordinary.distance) == 0:
			var declared := _evaluate_hand(round, seat, candidate.hand, melds, seen, context, candidate.tile, true, after_kong)
			options.append(declared)
	return options

func _evaluate_hand(round, seat: int, hand: Array, melds: Array, seen: Dictionary, context: Dictionary, discard: String = "", declared: bool = false, after_kong: bool = false) -> Dictionary:
	var distance := Shanten.shanten(hand, melds)
	var outs := 0
	var ron_outs := 0.0
	var self_value := 0.0
	var ron_value := 0.0
	for tile in Tiles.all_values():
		var available := maxi(0, 4 - int(seen.get(tile, 0)))
		if available == 0: continue
		var full := hand.duplicate()
		full.append(tile)
		if Shanten.shanten(full, melds) >= distance: continue
		outs += available
		if distance != 0: continue
		var pattern := RuleEngine.analyze(full, melds, tile)
		if not pattern.win: continue
		var draw_seen := seen.duplicate()
		draw_seen[tile] = int(draw_seen.get(tile, 0)) + 1
		var win_flips := VALUE.flip_distribution(draw_seen)
		self_value += available * VALUE.win_value(round, seat, full, melds, win_flips, context.opponents, declared, true, -1, discard, false, tile)
		for opponent in context.opponents:
			if VALUE.allows_ron(pattern, melds, declared) or opponent.ready:
				ron_outs += available / 3.0
				ron_value += available / 3.0 * VALUE.win_value(round, seat, full, melds, win_flips, context.opponents, declared, false, int(opponent.seat), discard, false, tile)
	if distance == 0:
		self_value /= maxi(1, outs)
		ron_value /= maxf(1.0, ron_outs)
	else:
		self_value = VALUE.win_value(round, seat, hand, melds, context.flips, context.opponents, false, true, -1, discard)
	var most_called := 0.0
	var enemy_survival := 1.0
	for opponent in context.opponents:
		most_called = maxf(most_called, float(opponent.tenpai_probability))
		enemy_survival *= 1.0 - 0.35 * float(opponent.tenpai_probability)
	var turns: float = round._wall_count() / 4.0 * (1.0 - 0.35 * most_called)
	var rate := clampf(outs / float(maxi(1, int(context.unknown))), 0.0, 1.0)
	var progress := 1.0 - pow(1.0 - rate, turns)
	var called_probability := 1.0 if distance == 0 else pow(progress, maxi(1, distance))
	var self_probability := progress
	if distance > 0:
		# Early broad improvements are not the final winning outs. Reusing their
		# rate for every stage severely overvalues breaking a ready hand.
		var stage_turns := turns / float(distance + 1)
		var improve_stage := 1.0 - pow(1.0 - rate, stage_turns)
		var finish_rate := minf(rate, 6.0 / float(maxi(1, int(context.unknown))))
		self_probability = 0.70 * pow(improve_stage, distance) * (1.0 - pow(1.0 - finish_rate, stage_turns))
	var ron_probability := 1.0 - pow(1.0 - clampf(0.25 * ron_outs / float(maxi(1, int(context.unknown))), 0.0, 1.0), 3.0 * turns)
	var win_probability := self_probability + (1.0 - self_probability) * ron_probability
	var normal := VALUE.settlement_value(round, seat, hand, melds, context.flips, context.opponents, discard)
	var drawn := VALUE.draw_value(round, seat, hand, melds, context.opponents, discard)
	var draw_weight := clampf(1.0 - round._wall_count() / 56.0, 0.25, 1.0)
	var called_balance: float = lerpf(float(normal.called), float(drawn.called), draw_weight)
	var uncalled_balance: float = lerpf(float(normal.uncalled), float(drawn.uncalled), draw_weight)
	var own := VALUE.profile(round, seat, hand, melds, context.flips, discard)
	var risk := {"probability": 0.0, "loss": 0.0}
	if discard != "":
		risk = opponent_model.risk(context, discard, declared, after_kong, false, seat, float(own.total) if distance == 0 else 0.0, distance == 0)
	var risk_loss := float(risk.loss)
	if risk_calibrated and discard != "":
		risk_loss = RISK_CALIBRATION.expected_loss(float(risk.probability), last_risk_strength) * risk_aversion
	var merit := self_probability * self_value + (1.0 - self_probability) * ron_probability * ron_value
	merit += (1.0 - win_probability) * (called_probability * called_balance + (1.0 - called_probability) * uncalled_balance)
	# 中档的额外防守只在对手已经明显听牌时放大；无人听牌时仍按正常
	# 速度做牌，避免整局都缩手缩脚、丢掉该拿的分。
	var extra_defense := risk_inflation if last_risk_strength >= 0.50 else 0.0
	merit -= risk_loss * inference_weight * (1.0 + extra_defense)
	if declared:
		merit += ready_bonus
	var expected_net := merit
	# Future hand probabilities are approximate. Preserve an attack-efficiency
	# anchor so speculative pattern income cannot outweigh real live improvements.
	merit += tenpai_weight * called_probability + distance_weight * distance + outs_weight * outs + 0.10 * _shape_quality(hand, seen)
	return {"tile": discard, "distance": distance, "outs": outs, "win_probability": win_probability,
		"win_value": self_value, "called_probability": called_probability, "expected_loss": risk_loss,
		"discard_risk": risk.probability, "declare_ready": declared, "expected_net": expected_net, "merit": merit}

func _shape_quality(hand: Array, seen: Dictionary) -> float:
	var counts := Tiles.to_counts(hand)
	var result := 0.0
	for tile in counts:
		var copies := int(counts[tile])
		var remaining := maxi(0, 4 - int(seen.get(tile, 0)))
		if copies == 2: result += 0.25 * remaining
		for offset in [1, 2]:
			var rank: int = Tiles.rank(tile) + offset
			if rank <= 9 and counts.has(Tiles.val(Tiles.suit(tile), rank)):
				result += 0.2 if offset == 1 else 0.1
	return result

func _seen_map(round, seat: int = -1) -> Dictionary:
	var seen := {}
	for player in round.players:
		for tile in player.discards:
			seen[tile] = seen.get(tile, 0) + 1
		for index in player.melds.size():
			var meld: Dictionary = player.melds[index]
			if player.seat == seat or round.is_meld_revealed(player.seat, index):
				seen[meld.tile] = seen.get(meld.tile, 0) + (3 if meld.kind == "pung" else 4)
	if seat >= 0:
		for tile in round.players[seat].concealed:
			seen[tile] = seen.get(tile, 0) + 1
	return seen

func _danger(round, seat: int, tile: String) -> float:
	var context := opponent_model.observe(round, seat, _seen_map(round, seat))
	return 10.0 * float(opponent_model.risk(context, tile, round.players[seat].ready, false, false, seat).probability)

func _kong_keeps_shape(player: PlayerState, tile: String, exposed: bool) -> bool:
	var after := player.concealed.duplicate()
	for _index in (3 if exposed else 4): after.erase(tile)
	var melds := player.melds.duplicate(true)
	melds.append({"kind": "kong", "tile": tile})
	var before := Shanten.shanten(player.concealed, player.melds)
	if player.concealed.size() % 3 == 2:
		before = 99
		for discard in Tiles.to_counts(player.concealed):
			var trial := player.concealed.duplicate()
			trial.erase(discard)
			before = mini(before, Shanten.shanten(trial, player.melds))
	return Shanten.shanten(after, melds) <= before

func _best_option(options: Array) -> Dictionary:
	var best: Dictionary = options[0]
	for option in options:
		if float(option.merit) > float(best.merit): best = option
	return best

func _before_meld(round, seat: int, seen: Dictionary, context: Dictionary) -> Dictionary:
	var player: PlayerState = round.players[seat]
	if player.concealed.size() % 3 == 2:
		return _best_option(_discard_options(round, seat, player.concealed, player.melds, seen, context, round.can_declare_ready(seat)))
	return _evaluate_hand(round, seat, player.concealed, player.melds, seen, context)

func _claim_context(round, context: Dictionary, source: int, tile: String) -> Dictionary:
	if not Tiles.is_chicken(tile): return context
	var updated := context.duplicate(true)
	var source_player: PlayerState = round.players[source]
	var index := source_player.discards.rfind(tile)
	if index < 0: return context
	var charge: bool = round.is_charge_discard(source, index)
	# risk() applies the round multiplier once after summing; keep this local
	# adjustment at single-round value to avoid double counting.
	var amount := VALUE.tile_value(tile, context.flips, 1, charge)
	var draw_amount := VALUE.tile_value(tile, {}, 1, charge)
	for opponent in updated.opponents:
		if int(opponent.seat) != source: continue
		opponent.discarded = maxf(0.0, float(opponent.discarded) - amount)
		opponent.chickens = maxf(0.0, float(opponent.chickens) - amount)
		opponent.draw_discarded = maxf(0.0, float(opponent.draw_discarded) - draw_amount)
	return updated

func _pong_keeps_tenpai(round, seat: int, tile: String) -> bool:
	var player: PlayerState = round.players[seat]
	var after: Array = player.concealed.duplicate()
	after.erase(tile); after.erase(tile)
	var melds: Array = player.melds.duplicate(true)
	melds.append({"kind": "pung", "tile": tile})
	for discard in Tiles.to_counts(after).keys():
		var hand := after.duplicate()
		hand.erase(discard)
		if Shanten.shanten(hand, melds) <= keep_tenpai_slack: return true
	return false

func _kong_keeps_tenpai(round, seat: int, tile: String, exposed: bool) -> bool:
	var player: PlayerState = round.players[seat]
	var after: Array = player.concealed.duplicate()
	var amount := 3 if exposed else 4
	for i in amount: after.erase(tile)
	var melds: Array = player.melds.duplicate(true)
	var meld := {"kind": "kong", "tile": tile}
	if not exposed: meld["concealed"] = true
	melds.append(meld)
	return Shanten.shanten(after, melds) <= keep_tenpai_slack

func _add_kong_keeps_tenpai(round, seat: int, tile: String) -> bool:
	var player: PlayerState = round.players[seat]
	var after: Array = player.concealed.duplicate()
	after.erase(tile)
	var melds: Array = player.melds.duplicate(true)
	for meld in melds:
		if str(meld.get("tile", "")) == tile and str(meld.get("kind", "")) == "pung":
			meld["kind"] = "kong"
			return Shanten.shanten(after, melds) <= keep_tenpai_slack
	return false

func _kong_helps(round, seat: int, tile: String, exposed: bool, source: int = -1) -> bool:
	var player: PlayerState = round.players[seat]
	if not _kong_keeps_shape(player, tile, exposed): return false
	var seen := _seen_map(round, seat)
	var context := opponent_model.observe(round, seat, seen)
	var before := _before_meld(round, seat, seen, context)
	var hand := player.concealed.duplicate()
	for _index in (3 if exposed else 4): hand.erase(tile)
	var melds := player.melds.duplicate(true)
	melds.append({"kind": "kong", "tile": tile, "concealed": not exposed, "from_seat": source})
	var after_context := _claim_context(round, context, source, tile) if exposed and source >= 0 else context
	var after := _evaluate_hand(round, seat, hand, melds, seen, after_context)
	# The replacement draw is immediate; future own-kong discards are evaluated
	# with unrestricted ron eligibility by _pick_discard after the kong occurs.
	var replacement := float(after.outs) / float(maxi(1, int(context.unknown)))
	var immediate_bonus := replacement * (float(after.win_value) + 3.0 * VALUE.CFG.SCORE_KONG_DRAW) if int(after.distance) == 0 else 2.0 * replacement
	return float(after.merit) + immediate_bonus > float(before.merit)

func _add_kong_helps(round, seat: int, tile: String) -> bool:
	var player: PlayerState = round.players[seat]
	var seen := _seen_map(round, seat)
	var context := opponent_model.observe(round, seat, seen)
	var before := _before_meld(round, seat, seen, context)
	var hand := player.concealed.duplicate()
	hand.erase(tile)
	var melds := player.melds.duplicate(true)
	for meld in melds:
		if meld.kind == "pung" and meld.tile == tile: meld.kind = "add_kong"
	var after := _evaluate_hand(round, seat, hand, melds, seen, context)
	var rob := opponent_model.risk(context, tile, false, false, true, seat, 0.0, int(after.distance) == 0)
	var own := VALUE.profile(round, seat, hand, melds, context.flips)
	var burned_loss := float(rob.probability) * 3.0 * float(own.total)
	var replacement := float(after.outs) / float(maxi(1, int(context.unknown)))
	var bonus := replacement * (float(after.win_value) + 3.0 * VALUE.CFG.SCORE_KONG_DRAW) if int(after.distance) == 0 else 2.0 * replacement
	# Only realized score income is contingent on surviving a robbery. Scaling
	# a negative shanten prior would perversely reward a dangerous added kong.
	var income := maxf(0.0, float(after.expected_net) + bonus)
	return float(after.merit) + bonus - float(rob.probability) * income - float(rob.loss) - burned_loss > float(before.merit)

func decide_response(round, seat: int, source: int, tile: String, options: Dictionary) -> Dictionary:
	if options.get("can_win", false):
		return {"action": "win"}
	var player: PlayerState = round.players[seat]
	if player.ready or options.get("rob_kong", false):
		return {"action": "pass"}
	if options.get("can_kong", false) \
		and (not keep_tenpai or _kong_keeps_tenpai(round, seat, tile, true)) \
		and _kong_helps(round, seat, tile, true, source):
		return {"action": "kong"}
	if options.get("can_pong", false) \
		and (not keep_tenpai or _pong_keeps_tenpai(round, seat, tile)) \
		and _pong_helps(round, seat, tile):
		return {"action": "pong"}
	return {"action": "pass"}

func _pong_helps(round, seat: int, tile: String) -> bool:
	var player: PlayerState = round.players[seat]
	if player.melds.is_empty():
		var pairs := 0
		for copies in Tiles.to_counts(player.concealed).values(): pairs += int(copies) / 2
		if pairs >= 5: return false
	var seen := _seen_map(round, seat)
	var context := opponent_model.observe(round, seat, seen)
	var before := _evaluate_hand(round, seat, player.concealed, player.melds, seen, context)
	var after := player.concealed.duplicate()
	after.erase(tile)
	after.erase(tile)
	var melds := player.melds.duplicate(true)
	melds.append({"kind": "pung", "tile": tile})
	var source := int(round.last_discard.get("seat", -1))
	var after_context := _claim_context(round, context, source, tile) if source >= 0 else context
	var best := _best_option(_discard_options(round, seat, after, melds, seen, after_context))
	return float(best.merit) > float(before.merit) + 0.5

