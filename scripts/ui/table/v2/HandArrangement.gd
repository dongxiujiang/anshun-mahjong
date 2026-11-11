extends RefCounted
## Local display only. Use the rule engine to validate waits; never reorder RoundState.
const SCORING := preload("res://scripts/core/WinScoring.gd")

var _counts: Array
var _patterns := {}
var _layouts := {}
var _distance := 9

static func waiting_patterns(hand: Array) -> Dictionary:
	var patterns := {}
	for tile in Tiles.all_values():
		if hand.count(tile) >= 4: continue
		var pattern := RuleEngine.analyze(hand + [tile], [], tile)
		if pattern.win: patterns[Tiles.value_index(tile)] = pattern
	return patterns

static func build(hand: Array, pattern_first: bool, patterns: Dictionary = {}) -> Array:
	var search := new()
	search._counts = Tiles.hand_to_counts_array(hand)
	search._patterns = waiting_patterns(hand) if patterns.is_empty() else patterns
	search._split(0, [], [], [], [])
	var pairs: Array = []
	var singles: Array = []
	for index in 27:
		for pair in int(search._counts[index]) / 2: pairs.append([index, index])
		if int(search._counts[index]) % 2: singles.append(index)
	var wait: Array = singles if pairs.size() == 6 else []
	search._add(pairs, singles, 6 - pairs.size(), wait, "pairs")
	var layouts: Array = search._layouts.values()
	layouts.sort_custom(func(a, b):
		if pattern_first and a.score != b.score: return a.score > b.score
		if a.width != b.width: return a.width > b.width
		if a.score != b.score: return a.score > b.score
		if a.grouped != b.grouped: return a.grouped > b.grouped
		return a.key < b.key)
	return layouts

func _split(index: int, melds: Array, pairs: Array, partials: Array, singles: Array) -> void:
	# A 13-tile normal wait has at most one single/partial or two pairs.
	if not _patterns.is_empty() and (singles.size() > 1 or partials.size() > 1 or pairs.size() > 2): return
	while index < 27 and _counts[index] == 0: index += 1
	if index == 27:
		var has_pair := int(not pairs.is_empty())
		var distance := 8 - 2 * melds.size() - mini(partials.size() + pairs.size() - has_pair, 4 - melds.size()) - has_pair
		if distance > _distance: return
		var waits: Array = []
		var mode := "triplets" if melds.all(func(group): return group[0] == group[2]) else "sequences"
		if melds.size() == 4:
			waits = singles
		elif melds.size() == 3 and pairs.size() == 2:
			waits = [pairs[0][0], pairs[1][0]]
		elif melds.size() == 3 and pairs.size() == 1 and partials.size() == 1:
			var a: int = partials[0][0]
			var b: int = partials[0][1]
			if b == a + 2:
				waits = [a + 1]
			else:
				if a % 9 > 0: waits.append(a - 1)
				if b % 9 < 8: waits.append(b + 1)
			mode = "sequences"
		var loose := singles.duplicate()
		for partial in partials: loose.append_array(partial)
		loose.sort()
		_add(melds + pairs, loose, distance, waits, mode)
		return
	_counts[index] -= 1
	_split(index, melds, pairs, partials, singles + [index])
	if _counts[index] >= 1:
		_counts[index] -= 1
		_split(index, melds, pairs + [[index, index]], partials, singles)
		if _counts[index] >= 1 and melds.size() < 4:
			_counts[index] -= 1
			_split(index, melds + [[index, index, index]], pairs, partials, singles)
			_counts[index] += 1
		_counts[index] += 1
	var rank := index % 9
	if rank < 7 and melds.size() < 4 and _counts[index + 1] > 0 and _counts[index + 2] > 0:
		_counts[index + 1] -= 1
		_counts[index + 2] -= 1
		_split(index, melds + [[index, index + 1, index + 2]], pairs, partials, singles)
		_counts[index + 1] += 1
		_counts[index + 2] += 1
	if partials.size() < 4:
		for gap in [1, 2]:
			if rank + gap >= 9 or _counts[index + gap] == 0: continue
			_counts[index + gap] -= 1
			_split(index, melds, pairs, partials + [[index, index + gap]], singles)
			_counts[index + gap] += 1
	_counts[index] += 1

func _add(groups: Array, loose: Array, distance: int, waits: Array, mode: String) -> void:
	if distance > _distance: return
	waits = waits.filter(func(index): return _patterns.has(index))
	# Four copies in hand can make an apparent zero-distance split with no legal wait.
	if distance == 0 and waits.is_empty(): return
	if distance < _distance:
		_distance = distance
		_layouts.clear()
	var key := str(groups) + "|" + str(loose)
	var entry: Dictionary = _layouts.get(key, {})
	if entry.is_empty():
		var cards: Array = []
		var lengths: Array = []
		for group in groups:
			lengths.append(group.size())
			cards.append_array(group)
		entry = {"key": key, "groups": groups, "lengths": lengths, "grouped": cards.size(),
			"cards": (cards + loose).map(func(index): return Tiles.from_index(index)), "waits": {},
			"width": 0, "score": 0.0, "patterns": {}}
		_layouts[key] = entry
	for index in waits:
		entry.waits[index] = true
		var pattern: Dictionary = _patterns[index].duplicate()
		if mode != "pairs":
			for flag in ["seven_pairs", "dragon_seven_pairs", "clean_seven_pairs", "clean_dragon_seven_pairs"]:
				pattern[flag] = false
		if mode == "sequences":
			pattern["all_triplets"] = false
			pattern["clean_big_triplets"] = false
		var info := SCORING._pattern_info(pattern)
		entry.score = maxf(entry.score, float(info.get("score", 0)))
		entry.patterns[index] = str(info.get("label", "平胡"))
	entry.width = entry.waits.size()

static func retained_groups(previous: Dictionary, next: Dictionary) -> int:
	var remaining: Array = next.groups.duplicate()
	var shared := 0
	for group in previous.groups:
		var index := remaining.find(group)
		if index >= 0:
			shared += group.size()
			remaining.remove_at(index)
	return shared

static func with_one_tile_changes(hand: Array, pattern_first: bool) -> Array:
	var result := build(hand, pattern_first)
	for outgoing in Tiles.to_counts(hand):
		for incoming in Tiles.all_values():
			if incoming == outgoing or hand.count(incoming) >= 4: continue
			var changed := hand.duplicate()
			changed.erase(outgoing)
			changed.append(incoming)
			var patterns := waiting_patterns(changed)
			if not patterns.values().any(func(pattern): return not SCORING._pattern_info(pattern).is_empty()): continue
			for layout in build(changed, pattern_first, patterns):
				if layout.score <= 0 or layout.width == 0: continue
				var entry: Dictionary = layout.duplicate(true)
				var groups: Array = []
				var loose: Array = []
				var removed := false
				var incoming_index := Tiles.value_index(incoming)
				for group in entry.groups:
					if not removed and group.has(incoming_index):
						var partial: Array = group.duplicate()
						partial.erase(incoming_index)
						loose.append_array(partial.map(func(i): return Tiles.from_index(i)))
						removed = true
					else: groups.append(group)
				var grouped_count := int(entry.grouped)
				var tail: Array = entry.cards.slice(grouped_count)
				if not removed: tail.erase(incoming)
				loose.append_array(tail)
				loose.append(outgoing)
				entry.groups = groups
				entry.lengths = groups.map(func(group): return group.size())
				entry.cards = []
				for group in groups: entry.cards.append_array(group.map(func(i): return Tiles.from_index(i)))
				entry.grouped = entry.cards.size()
				entry.cards.append_array(loose)
				entry.change_from = outgoing
				entry.change_to = incoming
				entry.key = "%s>%s|%s" % [outgoing, incoming, entry.key]
				assert(Tiles.sort_hand(entry.cards) == Tiles.sort_hand(hand))
				result.append(entry)
	result.sort_custom(func(a, b):
		# A live wait always precedes a hypothetical exchange.
		if a.has("change_from") != b.has("change_from"): return not a.has("change_from")
		if pattern_first and a.score != b.score: return a.score > b.score
		if a.width != b.width: return a.width > b.width
		if a.score != b.score: return a.score > b.score
		return a.key < b.key)
	return result
