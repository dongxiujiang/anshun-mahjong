extends SceneTree

const H := preload("res://tests/test_harness.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var t := H.new()
	var slots: Array = []
	for i in 108: slots.append(str(i))
	for dealer in 4:
		var expected_seats := [posmod(dealer + 2, 4), posmod(dealer - 1, 4), dealer, posmod(dealer + 1, 4)]
		for die in range(1, 7):
			var label := "dealer=%d die=%d" % [dealer, die]
			var wall := WallRing.new(slots, dealer, true)
			var counts := expected_seats.map(func(seat): return wall.wall_remaining(seat))
			t.expect(counts == [28, 26, 28, 26], label + ": lengths follow the dealer")
			var opening: int = [0, 28, 0, 82, 0, 28][die - 1] + die * 2
			t.expect(WallRing.compute_break(die, dealer) == opening, label + ": red die skips whole columns")
			wall.set_head(opening)
			# Leave one lower tile between the two ends. Both ends must see
			# the same tile, and the second attempt must find the wall empty.
			for i in 53:
				t.expect(wall.draw_head() == str((opening + i) % 108), label + ": deal and first draw")
			for i in 54:
				var index := posmod((opening / 2 - 1 - i / 2) * 2 + i % 2, 108)
				t.expect(wall.draw_tail() == str(index), label + ": supplement reverses columns, not layers")
			var last := (opening + 53) % 108
			t.expect(wall.remaining == 1 and wall.peek_head_index() == last and wall.peek_head() == str(last), label + ": flip reads the last slot without drawing")
			t.expect(wall.draw_tail() == str(last), label + ": tail skips the already taken upper slot")
			t.expect(wall.remaining == 0 and wall.peek_head_index() == -1 and wall.peek_head() == "" and wall.draw_head() == "" and wall.draw_tail() == "", label + ": empty wall has no flip or draw")
			t.expect(wall._ring == slots and wall.draw_log.size() == 108, label + ": slot values remain fixed")
	quit(t.finish("dealer_wall_layout"))
