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

	var wall := G.wall_block_center(3, 0, 1)
	t.expect(wall.y < G.CENTER.y and wall.x < G.CENTER.x, "北墙在中心上方")
	t.expect(not own.intersects(Rect2(wall - Vector2(24, 32), Vector2(48, 64))), "牌墙不压自己手牌")

	var inner_center_y := (G.wall_block_center(3, 0, 1).y + 32.0 + G.wall_block_center(1, 0, 1).y - 32.0) / 2.0
	t.expect(is_equal_approx(G.wall_block_center(0, 6, 1).y, inner_center_y),
		"东墙中心对齐牌墙内框中心")
	t.expect(is_equal_approx(G.wall_block_center(2, 6, 1).y, inner_center_y),
		"西墙中心对齐牌墙内框中心")

	# 北/南、东/西弃牌方向镜像：第一张靠桌心。
	var south_first: Vector2 = G.ordinary_slot_center(1, 0, 1)
	var south_second: Vector2 = G.ordinary_slot_center(1, 12, 1)
	var north_first: Vector2 = G.ordinary_slot_center(3, 0, 1)
	var north_second: Vector2 = G.ordinary_slot_center(3, 12, 1)
	t.expect(absf(south_first.y - G.CENTER.y) < absf(south_second.y - G.CENTER.y), "南家第一行靠桌心")
	t.expect(absf(north_first.y - G.CENTER.y) < absf(north_second.y - G.CENTER.y), "北家第一行靠桌心")

	# 东/西弃牌旋转后 80×60，8张一行、5行，步进 84/64。
	var east_col0: Vector2 = G.ordinary_slot_center(0, 0, 1)
	var east_next_in_row: Vector2 = G.ordinary_slot_center(0, 1, 1)
	var east_next_row: Vector2 = G.ordinary_slot_center(0, 8, 1)
	t.expect(is_equal_approx(east_next_in_row.y - east_col0.y, -64.0), "东家本地一行第2张沿y镜像步进64")
	t.expect(is_equal_approx(east_next_row.x - east_col0.x, 84.0), "东家本地下一行沿x向牌墙外步进84")
	t.expect(G.ordinary_slot_center(0, 39, 1).x > G.ordinary_slot_center(0, 31, 1).x,
		"东家可显示第40张")
	t.expect(G.ordinary_slot_center(3, 35, 1).y < G.ordinary_slot_center(3, 23, 1).y,
		"北家可显示第36张")

	var inner := G.wall_inner_rect()
	var south_last: Vector2 = G.ordinary_slot_center(1, 35, 1)
	var north_last: Vector2 = G.ordinary_slot_center(3, 35, 1)
	var east_discard_last: Vector2 = G.ordinary_slot_center(0, 39, 1)
	var west_discard_last: Vector2 = G.ordinary_slot_center(2, 39, 1)
	t.expect(is_equal_approx(inner.end.y - (south_last.y + 40.0), 8.0), "南家最外一行距内框8")
	t.expect(is_equal_approx((north_last.y - 40.0) - inner.position.y, 8.0), "北家最外一行距内框8")
	t.expect(is_equal_approx(inner.end.x - (east_discard_last.x + 40.0), 8.0), "东家最外一排距内框8")
	t.expect(is_equal_approx((west_discard_last.x - 40.0) - inner.position.x, 8.0), "西家最外一排距内框8")

	var ordinary_ok := true
	for i in 24:
		var p: Vector2 = G.ordinary_slot_center(human, i, human)
		if not G.TABLE_BOUNDS.grow(-20.0).has_point(p): ordinary_ok = false
	t.expect(ordinary_ok, "24张普通弃牌在桌内")

	var red := G.red_anchor(human, human, 0)
	t.expect(is_equal_approx(red.x, own.position.x), "红色区起始边对齐13张手牌左边缘")

	quit(t.finish("table_v2_geometry"))
