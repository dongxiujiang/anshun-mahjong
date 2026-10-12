extends SceneTree
const H := preload("res://tests/test_harness.gd")
const BEFORE := preload("res://tests/fixtures/shanten_before_value_model.gd")
var t := H.new()
func _initialize() -> void: call_deferred("_run")
func _run() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 12102026
	var comparisons := 0
	var started := Time.get_ticks_msec()
	for sample in 350:
		var deck := TileSetFactory.create_deck()
		for index in range(deck.size() - 1, 0, -1):
			var swap := random.randi_range(0, index)
			var tile: String = deck[index]
			deck[index] = deck[swap]
			deck[swap] = tile
		var melds: Array = []
		var fixed := sample % 5
		for index in fixed: melds.append({"kind": "pung", "tile": Tiles.from_index(3 * index)})
		var hand := deck.slice(0, 13 - 3 * fixed + sample % 2)
		t.expect(Shanten.shanten(hand, melds) == BEFORE.shanten(hand, melds), "Suit cache matches original exact distance, sample %d" % sample)
		comparisons += 1
		if hand.size() % 3 == 1:
			for tile in Tiles.all_values():
				if Tiles.count(hand, tile) >= 4: continue
				var trial := hand.duplicate()
				trial.append(tile)
				t.expect(Shanten.shanten(trial, melds) == BEFORE.shanten(trial, melds), "Every improving-draw probe preserves original distance")
				comparisons += 1
	print("[shanten_cache] %d exact comparisons in %d ms" % [comparisons, Time.get_ticks_msec() - started])
	quit(t.finish("shanten_cache"))
