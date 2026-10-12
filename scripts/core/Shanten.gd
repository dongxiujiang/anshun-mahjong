class_name Shanten
## Exact normal-hand distance, with cached suit decompositions and seven pairs.
static var _cache := {}
static var _suit_cache := {}

static func shanten(concealed: Array, melds: Array) -> int:
	var counts := Tiles.hand_to_counts_array(concealed)
	var key := str(counts) + ":" + str(melds.size())
	if _cache.has(key):
		return _cache[key]
	if melds.size() > 4: return 8
	# Only the largest partial count per (complete meld count, head-pair count)
	# matters. Reuse suit decompositions across hypothetical draws/discards.
	var combined := _empty_states()
	combined[2 * melds.size()] = 0
	for suit in 3:
		var states := _suit_states(counts.slice(9 * suit, 9 * suit + 9))
		var next := _empty_states()
		for left in 10:
			if combined[left] < 0: continue
			for right in 10:
				if states[right] < 0: continue
				var completed: int = left / 2 + right / 2
				var heads := left % 2 + right % 2
				if completed > 4 or heads > 1: continue
				var target := 2 * completed + heads
				next[target] = maxi(next[target], combined[left] + states[right])
		combined = next
	var result := 8
	for index in 10:
		if combined[index] >= 0:
			var completed: int = index / 2
			result = mini(result, 8 - 2 * completed - mini(combined[index], 4 - completed) - index % 2)
	if melds.is_empty():
		var pairs := 0
		for count in counts:
			pairs += int(count) / 2
		result = mini(result, 6 - mini(7, pairs))
	if _cache.size() > 24000:
		_cache.clear()
	_cache[key] = result
	return result

static func _empty_states() -> Array[int]:
	var states: Array[int] = []
	states.resize(10)
	states.fill(-1)
	return states

static func _suit_states(counts: Array) -> Array[int]:
	var key := str(counts)
	if _suit_cache.has(key): return _suit_cache[key]
	var states := _empty_states()
	_search(counts, 0, 0, 0, 0, states)
	if _suit_cache.size() >= 6000: _suit_cache.clear()
	_suit_cache[key] = states
	return states

static func _search(counts: Array, start: int, melds: int, partials: int, pair: int, states: Array[int]) -> void:
	if melds > 4:
		return
	var index := start
	while index < 9 and counts[index] == 0:
		index += 1
	if index == 9:
		var target := 2 * melds + pair
		states[target] = maxi(states[target], partials)
		return
	if counts[index] >= 3:
		counts[index] -= 3
		_search(counts, index, melds + 1, partials, pair, states)
		counts[index] += 3
	if index <= 6 and counts[index + 1] > 0 and counts[index + 2] > 0:
		counts[index] -= 1
		counts[index + 1] -= 1
		counts[index + 2] -= 1
		_search(counts, index, melds + 1, partials, pair, states)
		counts[index] += 1
		counts[index + 1] += 1
		counts[index + 2] += 1
	if counts[index] >= 2:
		counts[index] -= 2
		if pair == 0:
			_search(counts, index, melds, partials, 1, states)
		_search(counts, index, melds, partials + 1, pair, states)
		counts[index] += 2
	for offset in [1, 2]:
		if index + offset < 9 and counts[index + offset] > 0:
			counts[index] -= 1
			counts[index + offset] -= 1
			_search(counts, index, melds, partials + 1, pair, states)
			counts[index] += 1
			counts[index + offset] += 1
	counts[index] -= 1
	_search(counts, index, melds, partials, pair, states)
	counts[index] += 1
