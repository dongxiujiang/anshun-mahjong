extends RefCounted

const SUITS := ["wan", "tiao", "tong"]
const COUNT := 108

static func ordered_values() -> Array[String]:
	var result: Array[String] = []
	for suit in SUITS:
		for rank in range(1, 10):
			for copy in 4:
				result.append(suit + str(rank))
	return result

static func values(seed_value: int) -> Array[String]:
	var result := ordered_values()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(result.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var held := result[i]
		result[i] = result[j]
		result[j] = held
	return result

static func valid_deck(deck: Array) -> bool:
	if deck.size() != COUNT:
		return false
	var counts := {}
	for value in deck:
		if not value is String or not valid_value(value):
			return false
		counts[value] = int(counts.get(value, 0)) + 1
		if counts[value] > 4:
			return false
	return counts.size() == 27

static func valid_value(value: String) -> bool:
	for suit in SUITS:
		if value.length() == suit.length() + 1 and value.begins_with(suit):
			return value.right(1) in ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
	return false
