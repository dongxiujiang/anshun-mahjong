extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var human := 1
	var own := G.hand13_rect(human, human)
	var north := G.hand13_rect(3, human)
	var east := G.hand13_rect(0, human)
	t.expect(is_equal_approx(own.size.x, 13.0 * (115.2 + 4.0) - 4.0), "自己13张参考宽度")
	t.expect(is_equal_approx(own.size.y, 153.6), "自己13张参考高度")
	t.expect(is_equal_approx(north.size.x, 13.0 * (64.8 + 4.0) - 4.0), "北家13张参考宽度")
	t.expect(is_equal_approx(east.size.y, 13.0 * (64.8 + 4.0) - 4.0), "东家13张参考高度")

	var s0: Vector2 = G.hand_slot_center(human, 0, human)
	var s3: Vector2 = G.hand_slot_center(human, 3, human)
	var s4: Vector2 = G.hand_slot_center(human, 4, human)
	t.expect(s0.x < s3.x and s3.x < s4.x, "手牌槽从左到右递增")
	t.expect(is_equal_approx(s0.x, own.position.x + 115.2 / 2.0), "第一张在手牌最左槽中心")
	t.expect(is_equal_approx(s0.y, own.position.y + 153.6 / 2.0), "第一张在手牌行中心")

	var d0: Vector2 = G.draw_slot_center(human, human)
	var span := G.hand_span(13, G.OWN_UNIT)
	var own_half: float = G.TILE_BASE.x * G.hand_unit(human, human) * 0.5
	t.expect(is_equal_approx(d0.x, G.CENTER.x + span / 2.0 + 20.0 + own_half),
		"摸牌在手牌外侧20")
	var last_slot: Vector2 = G.hand_slot_center(human, 12, human)
	t.expect(is_equal_approx(d0.x - own_half - (last_slot.x + own_half), 20.0),
		"摸牌区与手牌间距20")

	var east_draw: Vector2 = G.draw_slot_center(0, human)
	var west_draw: Vector2 = G.draw_slot_center(2, human)
	var east_hand := G.hand13_rect(0, human)
	var west_hand := G.hand13_rect(2, human)
	t.expect(east_draw.y < east_hand.position.y, "东家摸牌在手牌上端")
	t.expect(west_draw.y > west_hand.end.y, "西家摸牌在手牌下端")

	# 四家手牌自身居中，摸牌放在手牌外侧并保持20间距。
	for seat in 4:
		var rel := G.relative_seat(human, seat)
		var unit := G.hand_unit(seat, human)
		var extent := G.TILE_BASE.x * unit
		var axis_x := rel in [0, 2]
		var lo := INF
		var hi := -INF
		for slot in 13:
			var c := G.hand_slot_center(seat, slot, human, 13)
			var v := c.x if axis_x else c.y
			lo = minf(lo, v - extent * 0.5)
			hi = maxf(hi, v + extent * 0.5)
		var want := G.CENTER.x if axis_x else G.CENTER.y
		t.expect(is_equal_approx((lo + hi) * 0.5, want),
			"%s家手牌自身居中" % ["南", "东", "北", "西"][seat])
		var d := G.draw_slot_center(seat, human, 13)
		var dv := d.x if axis_x else d.y
		var total_lo := minf(lo, dv - extent * 0.5)
		var total_hi := maxf(hi, dv + extent * 0.5)
		var gap := (total_hi - total_lo) - (hi - lo) - extent
		t.expect(is_equal_approx(gap, 20.0),
			"%s家摸牌区距手牌20" % ["南", "东", "北", "西"][seat])

	var river: Array[Rect2] = []
	for seat in 4:
		var rel := G.relative_seat(human, seat)
		var side := rel in [1, 3]
		var wall_size := G.MELD_SIZE if seat in [1, 3] else Vector2(G.MELD_SIZE.y, G.MELD_SIZE.x)
		var wall_clear := true
		for columns in [13, 14]:
			for column in columns:
				for layer in 2:
					var center := G.wall_block_center(seat, column, layer, columns)
					var bounds: Rect2 = G.WALL_BOUNDS[seat]
					wall_clear = wall_clear and bounds.grow(0.01).encloses(Rect2(center - wall_size / 2, wall_size))
		t.expect(wall_clear, "both equal-size layers fit all wall columns: %d" % seat)
		var size := G.TILE_BASE * G.ORDINARY_UNIT
		if side: size = Vector2(size.y, size.x)
		for i in G.river_capacity(rel):
			var center := G.ordinary_slot_center(seat, i, human)
			var rect := Rect2(center - size / 2, size)
			var clear := G.TABLE_BOUNDS.encloses(rect)
			for obstacle in river + G.WALL_BOUNDS:
				if rect.intersects(obstacle): clear = false
			t.expect(clear, "river slot %d/%d clears other slots and walls" % [seat, i])
			river.append(rect)

	for viewer in 4:
		for seat in 4:
			var size := G.hand_tile_size(seat, viewer)
			if G.relative_seat(viewer, seat) in [1, 3]: size = Vector2(size.y, size.x)
			for count in [1, 4, 7, 10, 13]:
				var draw := Rect2(G.draw_slot_center(seat, viewer, count) - size / 2.0, size)
				var clear := true
				for wall: Rect2 in G.WALL_BOUNDS:
					clear = clear and G.TABLE_BOUNDS.encloses(wall.grow(6))
					clear = clear and not wall.grow(6).intersects(draw)
					clear = clear and not wall.grow(6).intersects(G.hand13_rect(seat, viewer))
				t.expect(clear, "viewer%d seat%d count%d: full walls and shadows leave hand and draw slots clear" % [viewer, seat, count])
	quit(t.finish("table_v2_geometry"))
