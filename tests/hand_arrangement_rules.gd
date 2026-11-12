extends SceneTree

const H := preload("res://tests/test_harness.gd")
const A := preload("res://scripts/ui/table/v2/HandArrangement.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# The same completion may have both a normal split and seven pairs.
	# Its real scoring pattern must not depend on the visual split selected.
	var hand := _wan("1122334455667")
	for layout in A.build(hand, false):
		for index in layout.waits:
			var tile := Tiles.from_index(index)
			var info := A.SCORING._pattern_info(RuleEngine.analyze(hand + [tile], [], tile))
			t.expect(layout.patterns[index] == info.get("label", "平胡"), "wait labels use the actual highest scoring pattern")
	var fixed: Array = []
	for count in range(5):
		var cards := hand.slice(3 * count)
		_check(cards, fixed)
		if count < 4: fixed.append({"kind": "pung", "tile": "tiao" + str(count + 1)})
	var single := A.build(["wan9"], false, {}, fixed)
	t.expect(single.size() == 1 and single[0].score == 24 and single[0].patterns[8] == "大对子单吊", "four fixed melds enable the actual single-wait pattern")
	var flush: Array = []
	for value in range(1, 5): flush.append({"kind": "kong", "tile": "wan" + str(value)})
	t.expect(A.build(["wan9"], false, {}, flush)[0].score == 54, "four same-suit kongs count toward clean single wait")
	var dragon := _wan("1112233445566")
	var dragon_waits := A.waiting_patterns(dragon)
	t.expect(A.SCORING._pattern_info(dragon_waits[0]).score == 64, "only the actual fourth winning tile enables dragon seven pairs")
	for sample in [
		{"hand": ["wan1", "wan1", "wan1", "wan2", "wan2", "wan2", "wan3", "wan3", "wan4", "tong8"], "melds": [{"kind": "pung", "tile": "tiao1"}]},
		{"hand": ["wan9"], "melds": flush},
	]:
		_check_exchanges(sample.hand, sample.melds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026111201
	var values := Tiles.all_values()
	for fixed_count in range(5):
		for sample in range(60):
			var deck: Array = []
			for value in values:
				for copy in 4: deck.append(value)
			var melds: Array = []
			for m in fixed_count:
				var tile: String = values[(sample + m * 5) % 27]
				var kind := "pung" if sample % 2 else "kong"
				melds.append({"kind": kind, "tile": tile})
				for copy in (3 if kind == "pung" else 4): deck.erase(tile)
			var cards: Array = []
			for i in 13 - 3 * fixed_count:
				var at := rng.randi_range(0, deck.size() - 1)
				cards.append(deck.pop_at(at))
			_check(cards, melds)
	await H.quit_cleanly(self, t.finish("hand_arrangement_rules"))

func _check(hand: Array, melds: Array) -> void:
	var choices := A.build(hand, false, {}, melds)
	t.expect(not choices.is_empty(), "valid concealed sizes produce at least one arrangement")
	var listed := {}
	var keys := {}
	for choice in choices:
		t.expect(Tiles.sort_hand(choice.cards) == Tiles.sort_hand(hand), "arrangement preserves the real tile multiset")
		t.expect(not keys.has(choice.key), "each split appears once per cycle")
		keys[choice.key] = true
		for index in choice.waits:
			var tile := Tiles.from_index(index)
			listed[tile] = true
			var actual := RuleEngine.analyze(hand + [tile], melds, tile)
			var info := A.SCORING._pattern_info(actual)
			t.expect(actual.win and choice.patterns[index] == info.get("label", "平胡") and choice.scores[index] == info.get("score", 0), "all wait labels and points agree with settlement rules")
	var waits := RuleEngine.waiting_tiles(hand, melds)
	t.expect(listed.size() == waits.size() and waits.all(func(tile): return listed.has(tile)), "visual splits together cover every legal wait")

func _check_exchanges(hand: Array, melds: Array) -> void:
	var listed := {}
	for choice in A.with_one_tile_changes(hand, false, melds):
		t.expect(Tiles.sort_hand(choice.cards) == Tiles.sort_hand(hand), "exchange suggestions never insert imaginary tiles")
		if choice.has("change_from"): listed[choice.change_from + ":" + choice.change_to] = true
	var owned := Tiles.to_counts(hand)
	for meld in melds: owned[meld.tile] = int(owned.get(meld.tile, 0)) + (3 if meld.kind == "pung" else 4)
	for outgoing in Tiles.to_counts(hand):
		for incoming in Tiles.all_values():
			if outgoing == incoming: continue
			var changed := hand.duplicate()
			changed.erase(outgoing)
			changed.append(incoming)
			var possible := false
			if int(owned.get(incoming, 0)) < 4:
				for winning in Tiles.all_values():
					var result := RuleEngine.analyze(changed + [winning], melds, winning)
					if result.win and not A.SCORING._pattern_info(result).is_empty(): possible = true
			t.expect(listed.has(outgoing + ":" + incoming) == possible, "one-tile exchanges match exhaustive rules including fixed melds and four-copy limits")

func _wan(digits: String) -> Array:
	var result: Array = []
	for digit in digits: result.append("wan" + digit)
	return result
