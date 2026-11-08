extends SceneTree
## 逐家验证红色区：冲锋鸡边缘、组内4、碰碰8、杠杠8、异类12。
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

func _initialize() -> void: call_deferred("_run")

func _run() -> void:
	var deck = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(deck)
	deck.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	deck.size = G.DESIGN_SIZE
	deck.human_seat = 1
	deck._build_layers()
	await process_frame

	var cases := [
		[
			{"kind": "ordinary", "tile": "tiao1"},
			{"kind": "ordinary", "tile": "tong8"},
			{"kind": "ordinary", "tile": "tiao1"},
			{"kind": "ordinary", "tile": "tong8"},
			{"kind": "pung", "tile": "tiao1"},
			{"kind": "pung", "tile": "tong8"},
		],
		[
			{"kind": "ordinary", "tile": "tiao1"},
			{"kind": "ordinary", "tile": "tong8"},
			{"kind": "kong", "tile": "tiao1"},
			{"kind": "kong", "tile": "tong8"},
		],
	]
	for seat in 4:
		for ci in cases.size():
			var specs: Array = deck.red_layout(cases[ci], seat, G.relative_seat(1, seat))
			var horizontal := seat in [1, 3]
			var groups := {}
			for s in specs:
				var key := int(s.group)
				groups[key] = groups.get(key, []) + [s]
			var order: Array = groups.keys()
			order.sort()
			# 组内4。
			for key in order:
				var arr: Array = groups[key]
				for i in range(1, arr.size()):
					var a: Dictionary = arr[i - 1]
					var b: Dictionary = arr[i]
					var gap := _gap(a, b, horizontal)
					t.expect(is_equal_approx(gap, 4.0), "组内牌间距4")
			# 组间：同碰/同杠8，异类12，鸡4。
			for i in range(1, order.size()):
				var a: Dictionary = groups[order[i - 1]][groups[order[i - 1]].size() - 1]
				var b: Dictionary = groups[order[i]][0]
				var gap := _gap(a, b, horizontal)
				var ka := str(a.kind)
				var kb := str(b.kind)
				var want := 12.0
				if ka == kb: want = 4.0 if ka in ["charge", "ordinary"] else 8.0
				t.expect(is_equal_approx(gap, want), "红色组间间距%d (%s-%s)" % [int(want), ka, kb])
			# 冲锋鸡基准边。
			var charges: Array = []
			var ordinary: Array = []
			for s in specs:
				if bool(s.charge): charges.append(s)
				elif str(s.kind) == "ordinary": ordinary.append(s)
			if charges.size() >= 2 and not ordinary.is_empty():
				var c0: Dictionary = charges[0]
				var o0: Dictionary = ordinary[0]
				var cc: Vector2 = c0.center
				var oc: Vector2 = o0.center
				if seat == 0:
					t.expect(is_equal_approx(cc.x + 22.0, oc.x + 28.0), "东家冲锋鸡右边缘对齐")
				elif seat == 2:
					t.expect(is_equal_approx(cc.x - 22.0, oc.x - 28.0), "西家冲锋鸡左边缘对齐")
				elif seat == 3:
					t.expect(is_equal_approx(cc.y - 22.0, oc.y - 28.0), "北家冲锋鸡上边缘对齐")
				else:
					t.expect(is_equal_approx(cc.y + 22.0, oc.y + 28.0), "南家冲锋鸡下边缘对齐")

	deck.queue_free()
	await process_frame
	quit(t.finish("table_v2_red_spacing"))

func _gap(a: Dictionary, b: Dictionary, horizontal: bool) -> float:
	var ea := 56.0 if bool(a.charge) else 44.0
	var eb := 56.0 if bool(b.charge) else 44.0
	if horizontal:
		var ca: float = a.center.x
		var cb: float = b.center.x
		return absf(cb - ca) - ea * 0.5 - eb * 0.5
	var ya: float = a.center.y
	var yb: float = b.center.y
	return absf(yb - ya) - ea * 0.5 - eb * 0.5
