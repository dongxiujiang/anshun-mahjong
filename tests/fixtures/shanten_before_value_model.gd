## Frozen full-hand DFS used to verify the suit-cache optimization.
## Exact normal-hand DFS, with fixed melds and seven-pairs distance.
static var _cache := {}

static func shanten(concealed: Array, melds: Array) -> int:
	var counts := Tiles.hand_to_counts_array(concealed)
	var key := str(counts) + ":" + str(melds.size())
	if _cache.has(key):
		return _cache[key]
	var state := {"best": 8}
	_search(counts, 0, melds.size(), 0, 0, state)
	var result: int = state.best
	if melds.is_empty():
		var pairs := 0
		for count in counts:
			pairs += int(count) / 2
		result = mini(result, 6 - mini(7, pairs))
	if _cache.size() > 24000:
		_cache.clear()
	_cache[key] = result
	return result

static func _search(counts: Array, start: int, melds: int, partials: int, pair: int, state: Dictionary) -> void:
	if melds > 4:
		return
	var index := start
	while index < 27 and counts[index] == 0:
		index += 1
	if index == 27:
		state.best = mini(int(state.best), 8 - 2 * melds - mini(partials, 4 - melds) - pair)
		return
	if counts[index] >= 3:
		counts[index] -= 3
		_search(counts, index, melds + 1, partials, pair, state)
		counts[index] += 3
	if index % 9 <= 6 and counts[index + 1] > 0 and counts[index + 2] > 0:
		counts[index] -= 1
		counts[index + 1] -= 1
		counts[index + 2] -= 1
		_search(counts, index, melds + 1, partials, pair, state)
		counts[index] += 1
		counts[index + 1] += 1
		counts[index + 2] += 1
	if counts[index] >= 2:
		counts[index] -= 2
		if pair == 0:
			_search(counts, index, melds, partials, 1, state)
		_search(counts, index, melds, partials + 1, pair, state)
		counts[index] += 2
	for offset in [1, 2]:
		if index % 9 + offset < 9 and counts[index + offset] > 0:
			counts[index] -= 1
			counts[index + offset] -= 1
			_search(counts, index, melds, partials + 1, pair, state)
			counts[index] += 1
			counts[index + offset] += 1
	counts[index] -= 1
	_search(counts, index, melds, partials, pair, state)
	counts[index] += 1
