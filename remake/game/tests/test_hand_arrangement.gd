extends SceneTree

const Arrange = preload("res://src/presentation/HandArrangement.gd")
const Order = preload("res://src/presentation/HandOrder.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_examples()
	_preferences()
	_visibility()
	_pattern_reuse()
	_insertion()
	_manual_shapes()
	print("HandArrangement: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(note)

func _faces(spec: String, start: int = 0) -> Array:
	var faces := []
	for group in spec.split(" ", false):
		var suit: String = {"w":"wan", "t":"tiao", "b":"tong"}[group.left(1)]
		for rank in group.substr(1):
			faces.append({"id": start + faces.size(), "value": suit + rank})
	return faces

func _view(spec: String) -> Dictionary:
	var rows := []
	for seat in 4:
		rows.append({"seat": seat, "hand": [], "draw_id": -1, "discard_count": 0, "melds": [], "discards": []})
	rows[1].hand = _faces(spec)
	return {"players": rows, "viewer_seat": 1, "last_discard": {}, "choices": {}, "wall_remaining": 55}

func _order(view: Dictionary) -> Order:
	var order := Order.new()
	order.sync_hand("sample", 1, 1, view.players[1].hand, view.players[1].draw_id)
	return order

func _ids_to_values(view: Dictionary, ids: Array) -> Array:
	var known := {}
	for face in view.players[1].hand:
		known[int(face.id)] = face.value
	return ids.map(func(id): return known[int(id)])

func _examples() -> void:
	var advice := Arrange.new()
	for spec in ["w112233", "w122334"]:
		var view := _view(spec)
		var order = _order(view)
		var natural := advice.arrange(view, order.view())
		check(natural.slots == order.view().slots, "ordinary sorted examples keep adjacent equal ranks")
		var novice := advice.arrange(view, order.view(), "multiple", true)
		var expected := "w123123" if spec == "w112233" else "w123234"
		check(_ids_to_values(view, novice.slots) == _faces(expected).map(func(face): return face.value), "illustrative novice runs")
		check(novice.groups.size() == 2 and novice.groups.all(func(g): return g.kind == "sequence"), "sequence groups contain real IDs")
		check(order.apply_auto_slots(novice.slots) and order.view().slots == novice.slots, "renderer and touch share novice slot order")
		check(not order.apply_auto_slots([0, 0, 1, 2, 3, 4]), "cannot duplicate a physical tile")
		var restored := advice.arrange(view, order.view(), "pattern", false)
		check(restored.slots == natural.slots, "turning novice off restores ordinary order")
	var simple := _view("w1234577")
	var result := advice.arrange(simple, _order(simple).view())
	check(result.groups.map(func(g): return g.kind) == ["sequence", "incomplete", "pair"], "ordinary 123/45/77 in order")
	var suit_view := _view("b33 t11 w22")
	var suit_order = _order(suit_view)
	for a in ["wan", "tiao", "tong"]:
		for b in ["wan", "tiao", "tong"]:
			if a == b: continue
			var remaining := ["wan", "tiao", "tong"]
			remaining.erase(a)
			remaining.erase(b)
			suit_order.set_suit_order([a, b, remaining[0]])
			var arranged := advice.arrange(suit_view, suit_order.view(), "multiple", true)
			var labels := _ids_to_values(suit_view, arranged.slots)
			check(labels[0].begins_with(a) and labels[2].begins_with(b) and labels[4].begins_with(remaining[0]), "personal suit order survives novice grouping")

func _preferences() -> void:
	var advice := Arrange.new()
	var two := _view("w123456789 t45 b55")
	two.players[0].discards = _faces("t36", 60)
	var six := advice.arrange(two, _order(two).view())
	var three := _view("t2223 w123 b123 b456")
	three.players[0].discards = _faces("t11133444", 60)
	var narrow := advice.arrange(three, _order(three).view())
	check(six.waits.size() == 2 and six.remaining_total == 6, "two real waits, six possible physical tiles")
	check(narrow.waits.size() == 3 and narrow.remaining_total == 3, "three real waits, three possible physical tiles")
	check(Arrange.best_candidates([narrow, six], "multiple") == [six], "M15 uses total remaining tiles")
	var flush := _view("w1234567891234")
	var triplets := _view("w111444 t222 b3338")
	triplets.chicken_multiplier = 2
	triplets.charge_chickens = {"tong8": {"owner": 1}}
	var big := advice.arrange(flush, _order(flush).view(), "pattern", true)
	var set_hand := advice.arrange(triplets, _order(triplets).view(), "pattern", true)
	check(big.best_pattern_score == 24 and set_hand.best_pattern_score == 14, "current pattern-only points, independent of chickens and multiplier")
	check(Arrange.best_candidates([set_hand, big], "pattern") == [big], "24 flush outranks 14 triplets")
	var combined := _view("w1122334455667")
	var physical := _order(combined)
	var source: Array = physical.view().slots.duplicate()
	for mode in ["multiple", "pattern"]:
		var variant := advice.arrange(combined, physical.view(), mode, true)
		var selected := Arrange.best_candidates(variant.candidates, mode)
		check(not selected.is_empty() and selected.size() == variant.preferred_indices.size(), "real hand exposes actual preferred structures, preserving equal candidates")
		var ids: Array = variant.slots.duplicate()
		ids.sort()
		check(ids == source and variant.waits.size() > 1, "priority never changes source IDs or legal waits")
	check(advice.arrange(combined, physical.view(), "other", true).is_empty(), "only one of two preference modes")

func _visibility() -> void:
	var advice := Arrange.new()
	var view := _view("w1122334466778")
	view.players[0].discards = _faces("w88", 75)
	view.last_discard = {"seat": 0, "tile": "wan8", "tile_id": 76}
	var order = _order(view)
	var result := advice.arrange(view, order.view())
	var one: Array = result.waits.filter(func(w): return w.tile == "wan8")
	check(one.size() == 1 and one[0].remaining == 1, "own one plus public two leaves one; last-discard reference deduplicated")
	view.players[3].hand = _faces("w8", 80)
	view["wall"] = ["wan8"]
	view.players[2].melds = [{"kind": "kong", "concealed": true, "tile": "wan9", "tile_ids": [81, 82, 83, 84], "formed_at": 0}]
	check(advice.arrange(view, order.view()) == result, "changing private opponents and wall values cannot influence arrangement")
	var with_meld := _view("w123456789 t45 b55")
	with_meld.players[0].melds = [{"kind":"pung","tile":"tiao3","tile_ids":[70,71,72]}]
	with_meld.last_discard = {"seat": 2, "tile": "tiao3", "tile_id": 70}
	var meld_order = _order(with_meld)
	var counted := advice.arrange(JSON.parse_string(JSON.stringify(with_meld)), meld_order.view())
	check(counted.remaining_total == 5, "JSON physical IDs in meld and winning-source reference only counted once")
	with_meld.players[2].melds = [{"kind": "kong", "concealed": true, "tile": "tiao6", "tile_ids": [86,87,88,89], "formed_at":0}]
	with_meld.players[2].discard_count = 1
	check(advice.arrange(with_meld, meld_order.view()).remaining_total == 5, "first post-kong discard still hides dark value")
	with_meld.players[2].discard_count = 2
	check(advice.arrange(with_meld, meld_order.view()).remaining_total == 1, "second discard now publicly accounts for four physical kong tiles")

func _insertion() -> void:
	var advice := Arrange.new()
	var view := _view("w124678")
	var order = _order(view)
	view.players[1].hand.append({"id": 90, "value": "wan3"})
	view.players[1].draw_id = 90
	order.sync_hand("sample", 1, 2, view.players[1].hand, 90)
	check(not advice.arrange(view, order.view()).slots.has(90), "draw remains a separate ID and slot before discard")
	var old_slots: Array = order.view().slots
	view.players[1].hand.remove_at(4)
	view.players[1].draw_id = -1
	view.last_discard = {"seat": 1, "tile": "wan7", "tile_id": 4}
	order.sync_hand("sample", 1, 3, view.players[1].hand)
	var plan := advice.arrange(view, order.view())
	check(plan.slots == [0,1,90,2,3,5] and plan.insertion.to_slot == 2, "kept new draw inserted by rank, not old discard slot")
	check(plan.insertion.make_room == [{"id":2,"from_slot":2,"to_slot":3},{"id":3,"from_slot":3,"to_slot":4}], "make room before moving new draw")
	check(plan.insertion.tile_id == 90 and plan.insertion.discard_id == old_slots[4], "two phases refer to original physical IDs")
	order.begin_drag(3)
	order.commit_drag(0)
	var fixed: Array = order.view().slots.duplicate()
	var fixed_result := advice.arrange(view, order.view(), "pattern", true)
	check(fixed_result.slots == fixed and fixed_result.insertion.is_empty() and not order.apply_auto_slots(fixed), "refresh and novice never overwrite a manual order")
	view.players[1].hand.append({"id":91, "value":"tiao1"})
	order.sync_hand("sample", 1, 4, view.players[1].hand)
	var unresolved := advice.arrange(view, order.view())
	check(unresolved.slots == fixed and unresolved.pending_insert_ids == [91] and unresolved.insertion.is_empty(), "unconfirmed exact manual insertion remains explicitly pending")
	# A real retained draw has a discard/merge identity and now receives an automatic local insertion.
	var merged := order.view()
	merged.draw_merge = {"tile_id": 91, "discard_id": 92, "before_slots": fixed + [92]}
	view.last_discard = {"seat": 1, "tile_id": 92}
	var inserted := advice.arrange(view, merged)
	check(inserted.pending_insert_ids.is_empty() and inserted.slots.has(91) and inserted.insertion.tile_id == 91, "manual retained draw has a real insertion plan instead of remaining pending")
	check(order.apply_manual_insertion(inserted.slots) and order.view().manual and order.view().pending_insert_ids.is_empty(), "insertion preserves manual mode and consumes exactly its pending entity")
	var unchanged: Array = inserted.slots.filter(func(id): return id != 91)
	check(unchanged == fixed, "unrelated incoming suit preserves every existing relative manual position")

func _pattern_reuse()->void:
	var advice:=Arrange.new()
	var view:=_view("w123456789 t45 b55")
	var order=_order(view)
	var first:Dictionary=advice.arrange(view,order.view())
	var key:PackedByteArray=advice._pattern_key.duplicate()
	view.players[0].discards=_faces("t3336",60)
	var changed:Dictionary=advice.arrange(view,order.view())
	check(advice._pattern_key==key and changed.remaining_total<first.remaining_total,"public discards refresh remaining tiles while reusing unchanged hand patterns")
	check(changed==Arrange.new().arrange(view,order.view()),"reused patterns preserve complete priority and novice arrangement results")
	view.players[1].hand=_faces("w111444 t222 b3338")
	var changed_order=_order(view)
	var replaced:Dictionary=advice.arrange(view,changed_order.view())
	check(advice._pattern_key!=key and replaced==Arrange.new().arrange(view,changed_order.view()),"own hand changes invalidate cached winning patterns")

func _manual_shapes() -> void:
	for priority in ["multiple", "pattern"]:
		var view := _view("w123456789 t45 b55")
		var row := [0,3,6,1,4,7,2,5,8,9,10,11]
		var merge := {"tile_id":12,"discard_id":90,"before_slots":row+[90]}
		var display := {"slots":row,"manual":true,"pending_insert_ids":[12],"draw_merge":merge,"suit_order":["wan","tiao","tong"]}
		view.last_discard = {"seat":1,"tile_id":90}
		var original := view.duplicate(true)
		var plan := Arrange.new().arrange(view,display,priority)
		var ids: Array = plan.slots.duplicate(); ids.sort()
		check(ids == range(13) and view == original, "manual insertion preserves all physical IDs and all game facts")
		check(absi(plan.slots.find(12)-plan.slots.find(11)) == 1 and plan.waits.size()==2, "called hand keeps the incoming pair together without losing either legal wait")
		check(plan.insertion.tile_id == 12 and plan.insertion.to_slot==plan.slots.find(12), "either priority yields an executable manual insertion animation")
	var faces := {0:"tiao2",1:"wan9",2:"tiao4",3:"tong9",4:"tiao3"}
	var placed := Arrange._manual_insert([0,1,2,3],4,faces,[],["wan","tiao","tong"])
	check(placed.slice(placed.find(4)-1,placed.find(4)+2)==[0,4,2], "necessary local rearrangement joins a split sequence around the new tile")
	check(placed.find(1)<placed.find(3), "unrelated manually placed cards retain their relative order")
