extends SceneTree
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Wall = preload("res://src/domain/Wall.gd")
const Seats = preload("res://src/domain/Seats.gd")
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		printerr("FAIL: ", label)

func _run() -> void:
	var values := Catalog.values(239)
	check(Catalog.valid_deck(values), "108 legal shuffled tiles")
	check(values == Catalog.values(239), "seed reproducible")
	var corrupt := values.duplicate()
	corrupt[0] = "flower1"
	check(not Catalog.valid_deck(corrupt), "reject unknown value")
	check(not Wall.new(corrupt).open(1, 5), "reject invalid inventory")
	var expected_starts := [28, 54, 82, 0]
	for dealer in 4:
		for red in range(1, 7):
			var wall = Wall.new(values)
			check(wall.take_head() == -1, "cannot draw unopened wall")
			check(wall.open(dealer, red), "open all dealer/dice combinations")
			var target := posmod(dealer + (2 if red % 2 else (1 if red == 4 else 3)), 4)
			var expected: int = expected_starts[target] + red * 2
			check(wall.break_index == expected, "fixed-seat opening")
			check(not wall.open(dealer, red), "opening cannot reset consumed state")
			for segment in Wall.SEGMENTS:
				check(wall.slot_info(segment.start).seat == segment.seat, "dealer never changes physical ownership")
			var head_order: Array[int] = []
			var tail_order: Array[int] = []
			for i in 108:
				head_order.append((expected + i) % 108)
			for column in 54:
				var upper: int = posmod(expected - 2 - column * 2, 108)
				tail_order.append(upper)
				tail_order.append(upper + 1)
			var seen := {}
			for draw in 108:
				var tail := draw % 5 in [1, 2]
				var order: Array[int] = tail_order if tail else head_order
				var wanted := -1
				for candidate in order:
					if not seen.has(candidate):
						wanted = candidate
						break
				var before: Dictionary = wall.snapshot()
				var peek: int = wall.peek_head()
				check(wall.snapshot() == before and not seen.has(peek), "peek never consumes")
				var actual: int = wall.take_tail() if tail else wall.take_head()
				check(actual == wanted, "head/tail independently enumerated expected order")
				check(not seen.has(actual), "no duplicated physical tile")
				seen[actual] = true
				check(wall.remaining == 107 - draw, "shared remaining inventory")
			check(wall.take_head() == -1 and wall.take_tail() == -1 and wall.peek_head() == -1, "empty wall")
			check(wall.snapshot().tiles == values, "original tile array fixed")
	_test_deal()
	_test_flip()
	print("test_wall: ", checks, " checks, ", failed, " failures")
	quit(1 if failed else 0)

func _test_deal() -> void:
	var wall = Wall.new(Catalog.values(7))
	wall.open(1, 5)
	var hands := [[], [], [], []]
	for cycle in 3:
		for player_offset in 4:
			var seat := posmod(1 - player_offset, 4)
			for take in 4:
				hands[seat].append(wall.take_head())
	for player_offset in 4:
		hands[posmod(1 - player_offset, 4)].append(wall.take_head())
	check(hands[1].slice(0, 4) == [10, 11, 12, 13], "south dealer red5 takes north columns6 and7")
	check(hands[0].slice(0, 4) == [14, 15, 16, 17], "east next player takes after dealer")
	check(hands.all(func(hand): return hand.size() == 13) and wall.remaining == 56, "52 distributed before first draw")
	check(wall.take_head() == 62 and wall.remaining == 55, "dealer independent fourteenth tile")
	check(wall.take_tail() == 8 and wall.take_tail() == 9, "supplement starts before opening upper then lower")

func _test_flip() -> void:
	var wall = Wall.new(Catalog.values(9))
	wall.open(1, 5)
	check(wall.flip_landing(wall.peek_head()).stack_count == 2, "supported upper stays on its column")
	wall.take_head()
	var before: Dictionary = wall.snapshot()
	check(wall.flip_landing(11) == {"source_id": 11, "column": 6, "stack_count": 3}, "bottom flips to next complete column")
	check(before == wall.snapshot(), "visual landing never changes wall")
	while wall.remaining > 1:
		wall.take_tail()
	var last: int = wall.peek_head()
	check(wall.flip_landing(last).stack_count == 1, "last tile stays in original slot")
	check(wall.snapshot().remaining == 1, "flip leaves final tile unconsumed")
