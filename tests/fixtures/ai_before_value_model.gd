## Frozen AI before the expected-value/opponent-sampling upgrade. Benchmark only.
extends RefCounted

var name := "AI"
var rng := RandomNumberGenerator.new()
var inference_weight := 1.0

func _init(label := "AI") -> void:
	name = label
	rng.randomize()

func decide_turn(round, seat: int) -> Dictionary:
	var player: PlayerState = round.players[seat]
	if player.just_drew != "" and RuleEngine.analyze(player.concealed, player.melds).win:
		return {"self_win": true}
	if player.ready:
		return {"discard": player.just_drew}
	if round._wall_count() > 0:
		for tile in Tiles.to_counts(player.concealed):
			if Tiles.count(player.concealed, tile) == 4 and _kong_keeps_shape(player, tile, false):
				return {"kong_declares": [tile]}
		for meld in player.melds:
			if meld.kind == "pung" and player.concealed.has(meld.tile) and _danger(round, seat, meld.tile) < 3.0:
				return {"add_kong": [meld.tile]}
	var choice := _pick_discard(round, seat)
	return {"discard": choice.tile, "ready": choice.ready_capable}

func _pick_discard(round, seat: int) -> Dictionary:
	var player: PlayerState = round.players[seat]
	var seen := _seen_map(round, seat)
	var candidates: Array = []
	var lowest := 99
	for tile in Tiles.to_counts(player.concealed):
		var after := player.concealed.duplicate()
		after.erase(tile)
		var distance := Shanten.shanten(after, player.melds)
		lowest = mini(lowest, distance)
		candidates.append({"tile": tile, "after": after, "distance": distance})
	var threat := _threat(round, seat)
	var risks := {}
	for candidate in candidates: risks[candidate.tile] = _danger(round, seat, candidate.tile)
	var best := -INF
	var chosen: String = player.concealed[0]
	var ready := false
	for candidate in candidates:
		if candidate.distance > lowest + (1 if threat > 0 and lowest > 1 else 0):
			continue
		var improvement := 0
		var continuation := 0.0
		# Evaluate all unseen draws that reduce distance, without inspecting opponents' hands.
		for tile in Tiles.all_values():
			var available := maxi(0, 4 - int(seen.get(tile, 0)))
			if available == 0:
				continue
			var trial: Array = candidate.after.duplicate()
			trial.append(tile)
			if Shanten.shanten(trial, player.melds) < candidate.distance:
				improvement += available
				# Prefer improving draws that retain live pairs and adjacent shapes.
				continuation += available * _shape_quality(trial, seen)
		var danger: float = risks[candidate.tile]
		var defense_weight := (55.0 if lowest > 1 else 13.0) * threat
		var merit: float = -100.0 * candidate.distance + 2.0 * improvement - defense_weight * danger
		merit += _inference_value(round, seat, candidate.tile, candidate.distance, seen)
		if improvement > 0: merit += 0.6 * continuation / float(improvement)
		merit += 1.5 if Tiles.is_chicken(candidate.tile) and not round.has_charge(candidate.tile) else 0.0
		if merit > best:
			best = merit
			chosen = candidate.tile
			ready = candidate.distance == 0 and round.can_declare_ready(seat) and RuleEngine.is_tenpai(candidate.after, player.melds)
	return {"tile": chosen, "ready_capable": ready}

## Cheap information-set evaluation: visible discard frequencies and live
## copies approximate opponent waits without peeking at concealed hands.
func _inference_value(round, seat: int, tile: String, distance: int, seen: Dictionary) -> float:
	var value := 0.0
	var live := maxi(0, 4 - int(seen.get(tile, 0)))
	value += float(live) * 0.12
	var rank: int = Tiles.rank(tile)
	for opponent in round.players:
		if opponent.seat == seat: continue
		var weight := 1.0 if opponent.ready else (0.55 if opponent.melds.size() >= 2 else 0.25)
		if opponent.discard_history.has(tile): value += weight * 0.35
		if rank in [1, 9]: value += weight * 0.08
	return value * inference_weight - float(distance) * 0.02

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

func _threat(round, seat: int) -> float:
	var threat := 0.0
	for opponent in round.players:
		if opponent.seat == seat:
			continue
		threat = maxf(threat, 1.5 if opponent.ready else (0.9 if opponent.melds.size() >= 3 else (0.45 if opponent.discard_count >= 10 else 0.0)))
	return threat

func _danger(round, seat: int, tile: String) -> float:
	var seen := _seen_map(round, seat)
	if int(seen.get(tile, 0)) >= 4:
		return 0.0
	var risk := 0.0
	for opponent in round.players:
		if opponent.seat == seat:
			continue
		var weight := 1.5 if opponent.ready else (0.9 if opponent.melds.size() >= 3 else 0.5)
		var history: Array = opponent.discard_history
		# Discarded values are reduced risk, not absolute safety: this variant has no furiten.
		var value := 0.2 if history.has(tile) else 1.0
		var rank := Tiles.rank(tile)
		if rank in [1, 9]:
			value *= 0.7
		for offset in [-3, 3]:
			var neighbor: int = rank + offset
			if neighbor >= 1 and neighbor <= 9 and history.has(Tiles.val(Tiles.suit(tile), neighbor)):
				value *= 0.65
		value *= maxf(0.15, 1.0 - 0.18 * int(seen.get(tile, 0)))
		# Single-suit exposed sets plus off-suit discards suggest a flush.
		# Concealed kongs remain unknown until the table reveals them.
		var suit_counts := {}
		for index in opponent.melds.size():
			if not round.is_meld_revealed(opponent.seat, index): continue
			var suit := Tiles.suit(str(opponent.melds[index].tile))
			suit_counts[suit] = int(suit_counts.get(suit, 0)) + 1
		if suit_counts.size() == 1:
			var target_suit: String = str(suit_counts.keys()[0])
			if int(suit_counts[target_suit]) >= 2:
				value *= 1.8 if Tiles.suit(tile) == target_suit else 0.8
		# Late discards of neighboring tiles imply the player kept competing
		# connected shapes. No tile is absolutely safe in these no-furiten rules.
		for recent in history.slice(maxi(0, history.size() - 3)):
			if Tiles.suit(recent) == Tiles.suit(tile) and absi(Tiles.rank(recent) - rank) in [1, 2]:
				value *= 1.08
		risk += weight * value
	return risk

func _kong_keeps_shape(player: PlayerState, tile: String, exposed: bool) -> bool:
	var after := player.concealed.duplicate()
	for index in (3 if exposed else 4):
		after.erase(tile)
	var melds := player.melds.duplicate(true)
	melds.append({"kind": "kong", "tile": tile})
	var before := 99
	for discard in Tiles.to_counts(player.concealed):
		var trial := player.concealed.duplicate()
		trial.erase(discard)
		before = mini(before, Shanten.shanten(trial, player.melds))
	return Shanten.shanten(after, melds) <= before

func decide_response(round, seat: int, source: int, tile: String, options: Dictionary) -> Dictionary:
	if options.get("can_win", false):
		return {"action": "win"}
	var player: PlayerState = round.players[seat]
	if player.ready or options.get("rob_kong", false):
		return {"action": "pass"}
	if options.get("can_kong", false) and _kong_keeps_shape(player, tile, true):
		return {"action": "kong"}
	if options.get("can_pong", false) and _pong_helps(round, seat, tile):
		return {"action": "pong"}
	return {"action": "pass"}

func _pong_helps(round, seat: int, tile: String) -> bool:
	var player: PlayerState = round.players[seat]
	var after := player.concealed.duplicate()
	after.erase(tile)
	after.erase(tile)
	var melds := player.melds.duplicate(true)
	melds.append({"kind": "pung", "tile": tile})
	var distance := Shanten.shanten(player.concealed, player.melds)
	if player.melds.is_empty():
		var pairs := 0
		for copies in Tiles.to_counts(player.concealed).values(): pairs += int(copies) / 2
		# Preserve valuable seven-pairs/dragon-seven-pairs routes near completion.
		if pairs >= 5: return false
	var best := 99
	for discard in Tiles.to_counts(after):
		var trial := after.duplicate()
		trial.erase(discard)
		var merit := Shanten.shanten(trial, melds)
		if _threat(round, seat) < 1.0 or _danger(round, seat, discard) < 1.5:
			best = mini(best, merit)
	return best < distance or (best == 0 and distance == 0)
