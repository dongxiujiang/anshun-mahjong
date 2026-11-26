extends RefCounted
## Read-only plans made from the owner's hand and public facts; hypothetical tiles never become entities.
const Arrange = preload("res://src/presentation/HandArrangement.gd")
const Rules = preload("res://src/anshun/scoring/RuleEngine.gd")
const Win = preload("res://src/anshun/scoring/WinScoring.gd")
const Shanten = preload("res://src/anshun/scoring/Shanten.gd")
const Tiles = preload("res://src/anshun/scoring/Tiles.gd")

static func safe_view(view: Dictionary, suits: Array, priority: String) -> Dictionary:
	var safe := {}
	for key in ["viewer_seat","phase","turn","prompt_id","choices","last_discard"]:
		safe[key] = view.get(key,{} if key in ["choices","last_discard"] else -1)
	safe.choices = safe.choices.duplicate(true); safe.choices.prompt_id = safe.prompt_id
	safe.players = []
	for source in view.get("players",[]):
		var mine: bool = source.seat == safe.viewer_seat
		var row := {"seat":source.seat,"hand":source.hand.duplicate(true) if mine else [],
			"draw_id":source.get("draw_id",-1) if mine else -1,"ready":source.get("ready",false),
			"discards":source.discards.duplicate(true),"discard_count":source.get("discard_count",0),"melds":[]}
		for meld in source.melds:
			var hidden: bool = not mine and meld.get("concealed",false) and row.discard_count < int(meld.get("formed_at",row.discard_count))+2
			row.melds.append({"concealed":true} if hidden else meld.duplicate(true))
		safe.players.append(row)
	safe.suits = suits.duplicate(); safe.priority = priority
	return safe

static func calculate(view: Dictionary, _level: String = "low") -> Dictionary:
	var seat: int = view.viewer_seat
	var own: Dictionary = view.players[seat]
	var faces: Array = own.hand
	var known := Arrange._known(view,seat)
	var plans := []; var seen := {}
	var full: bool = faces.size() % 3 == 2 and not own.ready
	if full:
		var checked := {}
		for face in faces:
			if not view.choices.get("discard_ids",[]).has(face.id) or checked.has(face.value): continue
			checked[face.value] = true
			var after := faces.filter(func(item): return item.id != face.id)
			for choice in _plans(view,after):
				choice.slots.append(int(face.id)); choice.merge_draw = true
				choice.message = "打%s后，%s" % [_name(face.value),choice.message]
				_append(plans,seen,choice)
	else:
		var regular := faces.filter(func(face): return face.id != own.draw_id)
		for choice in _plans(view,regular): _append(plans,seen,choice)
		if not own.ready: _hypothetical(view,regular,known,plans,seen)
	var key: String = "remaining_total" if view.priority == "multiple" else "best_pattern_score"
	plans.sort_custom(func(a,b):
		if a.tier != b.tier: return a.tier < b.tier
		if a.distance != b.distance: return a.distance < b.distance
		if a[key] != b[key]: return a[key] > b[key]
		return a.message < b.message)
	return {"plans":plans}

static func _plans(view: Dictionary, faces: Array) -> Array:
	var subset := view.duplicate(true)
	subset.players[int(view.viewer_seat)].hand = faces
	subset.players[int(view.viewer_seat)].draw_id = -1
	# A proposed discard leaves the hand, but remains known to its owner as a public physical tile.
	var retained: Array = faces.map(func(face):return int(face.id))
	for face in view.players[int(view.viewer_seat)].hand:
		if not retained.has(int(face.id)): subset.players[int(view.viewer_seat)].discards.append(face.duplicate())
	var result := Arrange.new().arrange(subset,{"slots":faces.map(func(face):return int(face.id)),"suit_order":view.suits},view.priority)
	var choices: Array = result.get("candidates",[])
	if choices.is_empty():
		var values: Array = faces.map(func(face):return face.value); values.sort()
		choices = [{"groups":Arrange._novice(values,view.suits),"waits":[],"remaining_total":0,"best_pattern_score":0}]
	var plans := []
	var own: Dictionary = view.players[int(view.viewer_seat)]
	var distance := Shanten.shanten(faces.map(func(face):return face.value),own.melds)
	for choice in choices:
		var groups: Array = choice.groups.duplicate(true)
		groups.sort_custom(func(a,b):
			if _group_rank(a.kind) != _group_rank(b.kind): return _group_rank(a.kind) < _group_rank(b.kind)
			var sa: int = view.suits.find(str(a.values[0]).left(-1)); var sb: int = view.suits.find(str(b.values[0]).left(-1))
			return sa < sb if sa != sb else str(a.values) < str(b.values))
		var buckets := {}
		for face in faces:
			if not buckets.has(face.value): buckets[face.value] = []
			buckets[face.value].append(int(face.id))
		var ids := []; var parts := []
		for group in groups:
			var words := []
			for value in group.values: ids.append(buckets[value].pop_front()); words.append(_name(value))
			parts.append("·".join(words))
		var waits: Array = choice.waits
		plans.append({"slots":ids,"merge_draw":false,"tier":0 if not waits.is_empty() else 1,"distance":distance,
			"remaining_total":choice.remaining_total,"best_pattern_score":choice.best_pattern_score,
			"message":("听"+"、".join(waits.map(_name))) if not waits.is_empty() else "接近叫牌的排法",
			"structure":"｜".join(parts)})
	return plans

static func _hypothetical(view: Dictionary, faces: Array, known: Dictionary, plans: Array, seen: Dictionary) -> void:
	var own: Dictionary = view.players[int(view.viewer_seat)]
	var checked := {}
	for discard in faces:
		if checked.has(discard.value): continue
		checked[discard.value] = true
		var rest := faces.filter(func(face):return face.id != discard.id)
		var values: Array = rest.map(func(face):return face.value)
		for incoming in Tiles.all_values():
			if incoming == discard.value or int(known.get(incoming,0)) >= 4: continue
			var after: Array = values+[incoming]
			if Shanten.shanten(after,own.melds) != 0: continue
			var waits := []; var points := 0; var total := 0
			for tile in Tiles.all_values():
				var pattern: Dictionary = Rules.hand_pattern(after+[tile],own.melds,tile)
				if not pattern.win: continue
				var score: int = Win.best_wait_pattern({tile:pattern}).get("score",0)
				if score < 14: continue
				waits.append(tile); points = maxi(points,score)
				total += maxi(0,4-int(known.get(tile,0))-int(tile==incoming))
			if waits.is_empty(): continue
			var order: Array = rest.map(func(face):return int(face.id)); order.append(int(discard.id))
			_append(plans,seen,{"slots":order,"merge_draw":false,"tier":2,"distance":0,"remaining_total":total,"best_pattern_score":points,
				"message":"若摸到%s，再打%s，听%s"%[_name(incoming),_name(discard.value),"、".join(waits.map(_name))],"structure":"换一张后的大牌方案"})

static func _append(plans: Array, seen: Dictionary, choice: Dictionary) -> void:
	var key: String = str(choice.slots)+choice.message+choice.structure
	if not seen.has(key): seen[key]=true; plans.append(choice)
static func _group_rank(kind: String) -> int:
	return 0 if kind in ["sequence","triplet"] else (1 if kind=="pair" else 2)
static func _name(value: String) -> String:
	return value.right(1)+{"wan":"万","tiao":"条","tong":"筒"}.get(value.left(-1),"")
