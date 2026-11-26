extends RefCounted
## 以当前查看者的脱敏快照和权威选项计算一次操作。

const Shanten := preload("res://src/anshun/scoring/Shanten.gd")
const RuleEngine := preload("res://src/anshun/scoring/RuleEngine.gd")
const Tiles := preload("res://src/anshun/scoring/Tiles.gd")
const Observation := preload("res://src/ai/AiObservation.gd")
const VALUE := preload("res://src/ai/AiValueModel.gd")
const OPPONENT := preload("res://src/ai/AiOpponentModel.gd")
const MCTS := preload("res://src/ai/AiMctsSearch.gd")
const RISK_CALIBRATION := preload("res://src/ai/AiRiskCalibration.gd")
const DIFFICULTIES := ["low", "medium", "high"]
const SEARCH_WINDOW := 0.35
const KEEP_TENPAI_SLACK := 2

var opponent_model := OPPONENT.new()
var mcts := MCTS.new()
var risk_strength := 0.0
var advanced: bool
var defense_weight: float
var risk_inflation: float
var candidate_limit: int
var safety_margin: float
var ready_bonus: float
var tenpai_weight: float
var distance_weight: float
var outs_weight: float

func _init(difficulty: String) -> void:
	# 生产配置中，高档与中档参数相同。
	advanced = difficulty in ["medium", "high"]
	defense_weight = 0.55 if advanced else 0.15
	risk_inflation = 0.40 if advanced else 0.15
	candidate_limit = 8 if advanced else 6
	safety_margin = 4.0 if advanced else 3.0
	ready_bonus = 2.5 if advanced else 0.5
	tenpai_weight = 65.0 if advanced else 8.0
	distance_weight = -85.0 if advanced else -24.0
	outs_weight = 2.30 if advanced else 0.60

static func decide(view: Dictionary, difficulty: String) -> Dictionary:
	var legal: Dictionary = view.get("choices", {})
	if legal.is_empty() or difficulty not in DIFFICULTIES:
		return {}
	var actions: Array = legal.actions
	var selected: Dictionary
	if "self_win" in actions:
		selected = {"action": "self_win", "tile_id": -1}
	elif "win" in actions:
		selected = {"action": "win", "tile_id": legal.tile_id}
	elif actions == ["pass"]:
		selected = {"action": "pass", "tile_id": legal.get("tile_id", -1)}
	else:
		var observation := Observation.new(view)
		var policy = new(difficulty)
		if view.phase == "response":
			var action: String = policy._decide_response(observation)
			selected = {"action": action, "tile_id": legal.tile_id}
		else:
			selected = policy._decide_turn(observation)
	if not selected.is_empty():
		selected["prompt_id"] = legal.prompt_id
	return selected

func _decide_turn(observation: Observation) -> Dictionary:
	var seat := observation.viewer_seat
	for tile in observation.values_for("concealed_kong"):
		if advanced and not _kong_keeps_tenpai(observation, seat, tile, false): continue
		if _kong_helps(observation, seat, tile, false):
			return {"action": "concealed_kong", "tile_id": observation.id_for("concealed_kong", tile)}
	for tile in observation.values_for("add_kong"):
		if advanced and not _add_kong_keeps_tenpai(observation, seat, tile): continue
		if _add_kong_helps(observation, seat, tile):
			return {"action": "add_kong", "tile_id": observation.id_for("add_kong", tile)}
	var choice := _pick_discard(observation, seat)
	if choice.is_empty():
		return {}
	var action := "ready" if choice.declare_ready else "discard"
	return {"action": action, "tile_id": observation.id_for(action, choice.tile)}

func _pick_discard(observation: Observation, seat: int) -> Dictionary:
	var player: Dictionary = observation.players[seat]
	var seen := _seen_map(observation, seat)
	var context := opponent_model.observe(observation, seat, seen)
	risk_strength = 0.0
	for opponent in context.opponents:
		risk_strength = maxf(risk_strength, float(opponent.tenpai_probability))
	var after_kong: bool = observation.draw_kind != "none"
	var analysis := _discard_options(observation, seat, player.concealed, player.melds, seen, context,
		observation.values_for("discard"), observation.values_for("ready"), after_kong)
	if analysis.is_empty():
		return {}
	var ordinary := analysis.filter(func(candidate): return not bool(candidate.get("declare_ready", false)))
	var search_candidates: Array = ordinary.duplicate(true)
	search_candidates.sort_custom(func(left, right): return float(left.merit) > float(right.merit))
	if not search_candidates.is_empty():
		var top_merit := float(search_candidates[0].merit)
		# 搜索只比较评分接近的普通弃牌。
		search_candidates = search_candidates.filter(func(candidate): return top_merit - float(candidate.merit) <= SEARCH_WINDOW)
	if search_candidates.size() > candidate_limit:
		search_candidates = search_candidates.slice(0, candidate_limit)
	var tree: Dictionary = mcts.rank(observation, seat, player.concealed, player.melds, seen, search_candidates, context, defense_weight) if search_candidates.size() > 1 else {}
	for candidate in analysis:
		var search: Dictionary = tree.get(candidate.tile, {})
		# MCTS refines equal/near-equal routes; the hard shanten filter and
		# expected-loss term above still dominate a speculative branch.
		candidate.merit += 0.40 * float(search.get("value", 0.0))
	var best := _best_option(analysis)
	# 后段高威胁时，在成本相近的牌中优先选择别家已经打过、场上
	# 已见张数更多的牌，作为标定 wait 模型的补充。
	if safety_margin > 0.0 and risk_strength >= 0.45 and observation.wall_remaining <= 28:
		var seen_best := int(seen.get(str(best.tile), 0))
		var safe_best := best
		for candidate in analysis:
			if float(candidate.merit) < float(best.merit) - safety_margin: continue
			var seen_candidate := int(seen.get(str(candidate.tile), 0))
			if seen_candidate >= seen_best + 1 and (safe_best == best or seen_candidate > int(seen.get(str(safe_best.tile), 0))):
				safe_best = candidate
		best = safe_best
	return best

func _discard_options(observation: Observation, seat: int, hand: Array, melds: Array, seen: Dictionary, context: Dictionary, discard_values: Array, ready_values: Array = [], after_kong: bool = false) -> Array:
	var options: Array = []
	var candidates: Array = []
	var lowest := 99
	var threat := 0.0
	for opponent in context.opponents:
		threat = maxf(threat, float(opponent.tenpai_probability))
	for tile in Tiles.to_counts(hand):
		if tile not in discard_values and tile not in ready_values: continue
		var after := hand.duplicate()
		after.erase(tile)
		var distance := Shanten.shanten(after, melds)
		lowest = mini(lowest, distance)
		candidates.append({"tile": tile, "hand": after, "distance": distance})
	# A distant, threatened hand may retreat one step. Otherwise preserve the
	# fastest completion routes before comparing uncertain score estimates.
	var retreat := 1 if threat >= 0.55 and lowest > 1 else 0
	for candidate in candidates:
		if int(candidate.distance) > lowest + retreat: continue
		if candidate.tile in discard_values:
			options.append(_evaluate_hand(observation, seat, candidate.hand, melds, seen, context, candidate.tile, false, after_kong))
		if candidate.tile in ready_values and int(candidate.distance) == 0:
			options.append(_evaluate_hand(observation, seat, candidate.hand, melds, seen, context, candidate.tile, true, after_kong))
	return options

func _evaluate_hand(observation: Observation, seat: int, hand: Array, melds: Array, seen: Dictionary, context: Dictionary, discard: String = "", declared: bool = false, after_kong: bool = false) -> Dictionary:
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
		self_value += available * VALUE.win_value(observation, seat, full, melds, win_flips, context.opponents, declared, true, -1, discard, false, tile)
		for opponent in context.opponents:
			if VALUE.allows_ron(pattern, melds, declared) or opponent.ready:
				ron_outs += available / 3.0
				ron_value += available / 3.0 * VALUE.win_value(observation, seat, full, melds, win_flips, context.opponents, declared, false, int(opponent.seat), discard, false, tile)
	if distance == 0:
		self_value /= maxi(1, outs)
		ron_value /= maxf(1.0, ron_outs)
	else:
		self_value = VALUE.win_value(observation, seat, hand, melds, context.flips, context.opponents, false, true, -1, discard)
	var most_called := 0.0
	for opponent in context.opponents:
		most_called = maxf(most_called, float(opponent.tenpai_probability))
	var turns: float = observation.wall_remaining / 4.0 * (1.0 - 0.35 * most_called)
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
	var normal := VALUE.settlement_value(observation, seat, hand, melds, context.flips, context.opponents, discard)
	var drawn := VALUE.draw_value(observation, seat, hand, melds, context.opponents, discard)
	var draw_weight := clampf(1.0 - observation.wall_remaining / 56.0, 0.25, 1.0)
	var called_balance: float = lerpf(float(normal.called), float(drawn.called), draw_weight)
	var uncalled_balance: float = lerpf(float(normal.uncalled), float(drawn.uncalled), draw_weight)
	var own := VALUE.profile(observation, seat, hand, melds, context.flips, discard)
	var risk := {"probability": 0.0, "loss": 0.0}
	if discard != "":
		risk = opponent_model.risk(context, discard, declared, after_kong, false, seat, float(own.total) if distance == 0 else 0.0, distance == 0)
	var risk_loss := float(risk.loss)
	if advanced and discard != "":
		risk_loss = RISK_CALIBRATION.expected_loss(float(risk.probability), risk_strength)
	var merit := self_probability * self_value + (1.0 - self_probability) * ron_probability * ron_value
	merit += (1.0 - win_probability) * (called_probability * called_balance + (1.0 - called_probability) * uncalled_balance)
	# 中档的额外防守只在对手已经明显听牌时放大；无人听牌时仍按正常
	# 速度做牌，避免整局都缩手缩脚、丢掉该拿的分。
	var extra_defense := risk_inflation if risk_strength >= 0.50 else 0.0
	merit -= risk_loss * (1.0 + extra_defense)
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

func _seen_map(observation: Observation, seat: int = -1) -> Dictionary:
	var seen := {}
	for player in observation.players:
		for tile in player.discards:
			seen[tile] = seen.get(tile, 0) + 1
		for index in player.melds.size():
			var meld: Dictionary = player.melds[index]
			if meld.tile != "hidden0":
				seen[meld.tile] = seen.get(meld.tile, 0) + (3 if meld.kind == "pung" else 4)
	if seat >= 0:
		for tile in observation.players[seat].concealed:
			seen[tile] = seen.get(tile, 0) + 1
	return seen

func _kong_keeps_shape(player: Dictionary, tile: String, exposed: bool) -> bool:
	var after: Array = player.concealed.duplicate()
	for _index in (3 if exposed else 4): after.erase(tile)
	var melds: Array = player.melds.duplicate(true)
	melds.append({"kind": "kong", "tile": tile})
	var before := Shanten.shanten(player.concealed, player.melds)
	if player.concealed.size() % 3 == 2:
		before = 99
		for discard in Tiles.to_counts(player.concealed):
			var trial: Array = player.concealed.duplicate()
			trial.erase(discard)
			before = mini(before, Shanten.shanten(trial, player.melds))
	return Shanten.shanten(after, melds) <= before

func _best_option(options: Array) -> Dictionary:
	var best: Dictionary = options[0]
	for option in options:
		if float(option.merit) > float(best.merit): best = option
	return best

func _before_meld(observation: Observation, seat: int, seen: Dictionary, context: Dictionary) -> Dictionary:
	var player: Dictionary = observation.players[seat]
	if player.concealed.size() % 3 == 2:
		return _best_option(_discard_options(observation, seat, player.concealed, player.melds, seen, context,
			observation.values_for("discard"), observation.values_for("ready")))
	return _evaluate_hand(observation, seat, player.concealed, player.melds, seen, context)

func _claim_context(observation: Observation, context: Dictionary, source: int, tile: String) -> Dictionary:
	if not Tiles.is_chicken(tile): return context
	var updated := context.duplicate(true)
	var source_player: Dictionary = observation.players[source]
	var index: int = source_player.discards.rfind(tile)
	if index < 0: return context
	var charge: bool = observation.is_charge_discard(source, index)
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

func _pong_keeps_tenpai(observation: Observation, seat: int, tile: String) -> bool:
	var player: Dictionary = observation.players[seat]
	var after: Array = player.concealed.duplicate()
	after.erase(tile)
	after.erase(tile)
	var melds: Array = player.melds.duplicate(true)
	melds.append({"kind": "pung", "tile": tile})
	for discard in Tiles.to_counts(after).keys():
		var hand := after.duplicate()
		hand.erase(discard)
		if Shanten.shanten(hand, melds) <= KEEP_TENPAI_SLACK: return true
	return false

func _kong_keeps_tenpai(observation: Observation, seat: int, tile: String, exposed: bool) -> bool:
	var player: Dictionary = observation.players[seat]
	var after: Array = player.concealed.duplicate()
	var amount := 3 if exposed else 4
	for _index in amount: after.erase(tile)
	var melds: Array = player.melds.duplicate(true)
	var meld := {"kind": "kong", "tile": tile}
	if not exposed: meld["concealed"] = true
	melds.append(meld)
	return Shanten.shanten(after, melds) <= KEEP_TENPAI_SLACK

func _add_kong_keeps_tenpai(observation: Observation, seat: int, tile: String) -> bool:
	var player: Dictionary = observation.players[seat]
	var after: Array = player.concealed.duplicate()
	after.erase(tile)
	var melds: Array = player.melds.duplicate(true)
	for meld in melds:
		if str(meld.get("tile", "")) == tile and str(meld.get("kind", "")) == "pung":
			meld["kind"] = "kong"
			return Shanten.shanten(after, melds) <= KEEP_TENPAI_SLACK
	return false

func _kong_helps(observation: Observation, seat: int, tile: String, exposed: bool, source: int = -1) -> bool:
	var player: Dictionary = observation.players[seat]
	if not _kong_keeps_shape(player, tile, exposed): return false
	var seen := _seen_map(observation, seat)
	var context := opponent_model.observe(observation, seat, seen)
	var before := _before_meld(observation, seat, seen, context)
	var hand: Array = player.concealed.duplicate()
	for _index in (3 if exposed else 4): hand.erase(tile)
	var melds: Array = player.melds.duplicate(true)
	melds.append({"kind": "kong", "tile": tile, "concealed": not exposed, "from_seat": source})
	var after_context := _claim_context(observation, context, source, tile) if exposed and source >= 0 else context
	var after := _evaluate_hand(observation, seat, hand, melds, seen, after_context)
	# The replacement draw is immediate; future own-kong discards are evaluated
	# with unrestricted ron eligibility by _pick_discard after the kong occurs.
	var replacement := float(after.outs) / float(maxi(1, int(context.unknown)))
	var immediate_bonus := replacement * (float(after.win_value) + 3.0 * VALUE.CFG.SCORE_KONG_DRAW) if int(after.distance) == 0 else 2.0 * replacement
	return float(after.merit) + immediate_bonus > float(before.merit)

func _add_kong_helps(observation: Observation, seat: int, tile: String) -> bool:
	var player: Dictionary = observation.players[seat]
	var seen := _seen_map(observation, seat)
	var context := opponent_model.observe(observation, seat, seen)
	var before := _before_meld(observation, seat, seen, context)
	var hand: Array = player.concealed.duplicate()
	hand.erase(tile)
	var melds: Array = player.melds.duplicate(true)
	for meld in melds:
		if meld.kind == "pung" and meld.tile == tile: meld.kind = "add_kong"
	var after := _evaluate_hand(observation, seat, hand, melds, seen, context)
	var rob := opponent_model.risk(context, tile, false, false, true, seat, 0.0, int(after.distance) == 0)
	var own := VALUE.profile(observation, seat, hand, melds, context.flips)
	var burned_loss := float(rob.probability) * 3.0 * float(own.total)
	var replacement := float(after.outs) / float(maxi(1, int(context.unknown)))
	var bonus := replacement * (float(after.win_value) + 3.0 * VALUE.CFG.SCORE_KONG_DRAW) if int(after.distance) == 0 else 2.0 * replacement
	# Only realized score income is contingent on surviving a robbery. Scaling
	# a negative shanten prior would perversely reward a dangerous added kong.
	var income := maxf(0.0, float(after.expected_net) + bonus)
	return float(after.merit) + bonus - float(rob.probability) * income - float(rob.loss) - burned_loss > float(before.merit)

func _decide_response(observation: Observation) -> String:
	var seat := observation.viewer_seat
	var legal := observation.choices
	var tile: String = legal.value
	if "kong" in legal.actions \
		and (not advanced or _kong_keeps_tenpai(observation, seat, tile, true)) \
		and _kong_helps(observation, seat, tile, true, legal.source):
		return "kong"
	if "pong" in legal.actions \
		and (not advanced or _pong_keeps_tenpai(observation, seat, tile)) \
		and _pong_helps(observation, seat, tile):
		return "pong"
	return "pass"

func _pong_helps(observation: Observation, seat: int, tile: String) -> bool:
	var player: Dictionary = observation.players[seat]
	if player.melds.is_empty():
		var pairs := 0
		for copies in Tiles.to_counts(player.concealed).values(): pairs += int(copies) / 2
		if pairs >= 5: return false
	var seen := _seen_map(observation, seat)
	var context := opponent_model.observe(observation, seat, seen)
	var before := _evaluate_hand(observation, seat, player.concealed, player.melds, seen, context)
	var after: Array = player.concealed.duplicate()
	after.erase(tile)
	after.erase(tile)
	var melds: Array = player.melds.duplicate(true)
	melds.append({"kind": "pung", "tile": tile})
	var source := int(observation.last_discard.get("seat", -1))
	var after_context := _claim_context(observation, context, source, tile) if source >= 0 else context
	var best := _best_option(_discard_options(observation, seat, after, melds, seen, after_context, Tiles.to_counts(after).keys()))
	return float(best.merit) > float(before.merit) + 0.5

