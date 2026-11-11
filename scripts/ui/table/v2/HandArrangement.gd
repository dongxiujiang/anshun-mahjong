extends RefCounted
## Local display only. Use the rule engine to validate waits; never reorder RoundState.
const SCORING := preload("res://scripts/core/WinScoring.gd")

var _counts: Array
var _patterns := {}
var _layouts := {}
var _distance := 9

static func build(hand: Array, pattern_first: bool) -> Array:
	var search := new()
	search._counts = Tiles.hand_to_counts_array(hand)
	for tile in RuleEngine.waiting_tiles(hand, []):
		search._patterns[Tiles.value_index(tile)] = RuleEngine.analyze(hand + [tile], [], tile)
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
			"width": 0, "score": 0.0}
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
		entry.score = maxf(entry.score, float(SCORING._pattern_info(pattern).get("score", 0)))
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
