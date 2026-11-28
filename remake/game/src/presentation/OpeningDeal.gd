extends RefCounted
## One world-space track per player. The clock for an insertion stops during that player's pickup.
const Layout = preload("res://src/presentation/TableLayout.gd")
const Pace = preload("res://src/presentation/GamePace.gd")
const MotionConfig = preload("res://src/presentation/MotionConfig.gd")
const CADENCE := 0.23
const CARRY := 0.20
const SPREAD := 0.12
const FLIP := 0.12
const RACK := 0.10
const INSERT := Pace.ACTION_SECONDS

signal progress(seat: int, sorted: bool)

var keys := {}
var tracks := {}
var received := [0, 0, 0, 0]
var dealer := -1
var _rack_slots := {}
var _ranks := {}

static func nominal_gate_seconds() -> float:
	# At most 12 insertions for 13 tiles. Each full pass uses its sorting window first.
	var sort_window := 4 * CADENCE - Pace.ACTION_SECONDS
	var backlog := 0.0
	for pass_index in 3:
		backlog = maxf(0.0, backlog + (3 if pass_index == 0 else 4) * INSERT - sort_window)
	return maxf(15 * CADENCE + Pace.ACTION_SECONDS, 12 * CADENCE + Pace.ACTION_SECONDS + backlog + INSERT)

static func pickup_scale(count:int,style:String)->float:
	var stages:=2 if count==4 and style=="b" else 1
	var spread:=SPREAD if count==4 and style=="a" else 0.0
	return Pace.ACTION_SECONDS/(CARRY+spread+stages*(FLIP+RACK))

func ready_for_draw() -> bool:
	return received.min() == 13 and not tracks.has(dealer)

func cancel() -> void:
	for tween: Tween in tracks.values():
		tween.kill()
	tracks.clear()
	keys.clear()

func play(table, groups: Array, destinations: Dictionary) -> void:
	var opening_trans: Tween.TransitionType = MotionConfig.value("tile", "opening_trans", Tween.TRANS_SINE, table.quality)
	dealer = int(groups[0].seat)
	if table.custom_profile:
		for seat in 4:
			var cards := []
			for group in groups:
				if group.seat == seat: cards.append_array(group.cards)
			cards.sort_custom(func(a, b): return table.tiles[a].get_meta("hand_index") < table.tiles[b].get_meta("hand_index"))
			_rack_slots[seat] = cards.map(func(key): return destinations[key])
			for i in cards.size(): _ranks[cards[i]] = i
	for turn in 4:
		var seat: int = groups[turn].seat
		var track: Tween = table.create_tween().set_trans(opening_trans).set_ease(Tween.EASE_OUT)
		tracks[seat] = track
		if turn > 0:
			track.tween_interval(turn * CADENCE)
		var row := []
		var backlog := []
		var poses := {}
		for pass_index in 4:
			var group: Dictionary = groups[turn + 4 * pass_index]
			for key in group.cards:
				keys[key] = seat
				poses[key] = table.tiles[key].transform
			var spent := _pickup(track, table.tiles, group, row, poses, destinations)
			track.tween_callback(_received.bind(seat, row.size()))
			_queue_insertions(seat, group.cards.size(), row, poses, destinations, backlog)
			var budget := INF if pass_index == 3 else 4 * CADENCE - spent
			var left := _sort_during(track, table.tiles, backlog, budget, opening_trans)
			if pass_index < 3 and left > 0.00001:
				track.tween_interval(left)
		track.finished.connect(_finish.bind(seat))

func _received(seat: int, count: int) -> void:
	received[seat] = count
	if count == 13:
		progress.emit(seat, false)

func release_seat(seat: int) -> void:
	tracks.erase(seat)
	for key in keys.keys():
		if keys[key] == seat:
			keys.erase(key)

func _finish(seat: int) -> void:
	release_seat(seat)
	progress.emit(seat, true)

func _rack_pose(seat: int, slot: int, key, destinations: Dictionary) -> Transform3D:
	if _rack_slots.has(seat): return _rack_slots[seat][slot]
	var pose: Transform3D = destinations[key]
	pose.origin = Layout.facing(seat) * Vector3(slot - 6, pose.origin.y, (Layout.facing(seat).inverse() * pose.origin).z)
	return pose

static func _move(track: Tween, tiles: Dictionary, poses: Dictionary, goals: Dictionary, duration: float) -> void:
	var first := true
	for key in goals:
		if not first:
			track.parallel()
		first = false
		track.tween_property(tiles[key], "transform", goals[key], duration).from(poses[key])
		poses[key] = goals[key]

# Carry both stacks together, preserving their centre spacing while changing seat orientation.
static func _carry(t: float, nodes: Array, starts: Array, ends: Array, turn: float) -> void:
	var from_axis: Vector3 = starts[-1].origin - starts[0].origin
	var to_axis: Vector3 = ends[-1].origin - ends[0].origin
	if nodes.size() == 4:
		from_axis = starts[2].origin - starts[0].origin
		to_axis = ends[2].origin - ends[0].origin
	var center: Vector3 = starts[0].origin.lerp(ends[0].origin, t)
	center.y += sin(PI * t) * Layout.LONG
	var axis := from_axis.rotated(Vector3.UP, turn * t).normalized() * lerpf(from_axis.length(), to_axis.length(), t)
	for i in nodes.size():
		var pose: Transform3D = starts[i].interpolate_with(ends[i], t)
		pose.origin = center + (axis if i >= 2 else Vector3.ZERO)
		if i % 2 == 1:
			pose.origin.y -= Layout.THICK
		nodes[i].transform = pose

func _pickup(track: Tween, tiles: Dictionary, group: Dictionary, row: Array, poses: Dictionary, dest: Dictionary) -> float:
	var seat: int = group.seat
	var cards: Array = group.cards
	var timing:=pickup_scale(cards.size(),str(group.style))
	var count := row.size()
	var z := Layout.EDGE - 2.0
	var starts := []
	var stacks := []
	var nodes := []
	var top := []
	var bottom := []
	for i in cards.size():
		var key = cards[i]
		var upper := cards.size() == 4 and i % 2 == 0
		var stack := Layout.pose(seat, Vector3(count - 6 + floori(i / 2.0), Layout.THICK * (1.5 if upper else 0.5), z), PI)
		starts.append(poses[key])
		stacks.append(stack)
		nodes.append(tiles[key])
		poses[key] = stack
		if upper: top.append(key)
		else: bottom.append(key)
	var turn := 0.0
	if cards.size() == 4:
		var source_axis: Vector3 = starts[2].origin - starts[0].origin
		turn = source_axis.signed_angle_to(stacks[2].origin - stacks[0].origin, Vector3.UP)
	track.tween_method(_carry.bind(nodes, starts, stacks, turn), 0.0, 1.0, CARRY*timing)
	var pairs := [bottom]
	var spent := CARRY*timing
	if cards.size() == 4 and group.style == "a":
		var slide := {}
		var lower := {}
		for i in top.size():
			var key = top[i]
			var pose: Transform3D = poses[key]
			pose.origin += Layout.facing(seat) * Vector3.RIGHT * 2
			slide[key] = pose
			pose.origin.y -= Layout.THICK
			lower[key] = pose
		_move(track, tiles, poses, slide, SPREAD * 0.65*timing)
		_move(track, tiles, poses, lower, SPREAD * 0.35*timing)
		spent += SPREAD*timing
		pairs = [bottom + top]
	elif cards.size() == 4:
		pairs = [top, bottom]
	for pair: Array in pairs:
		var flip := {}
		var rack := {}
		for key in pair:
			var goal := _rack_pose(seat, row.size(), key, dest)
			rack[key] = goal
			row.append(key)
			# Turn toward the owner first. Flat, masked views keep opaque geometry.
			var turned := goal
			turned.origin = poses[key].origin.lerp(goal.origin, 0.55)
			turned.origin.y = maxf(goal.origin.y, poses[key].origin.y) + Layout.LONG * 0.65
			flip[key] = turned
		_move(track, tiles, poses, flip, FLIP*timing)
		_move(track, tiles, poses, rack, RACK*timing)
		spent += (FLIP + RACK)*timing
	return spent

# The projected final order supplies ranks for both visible IDs and opaque opponent keys.
func _queue_insertions(seat: int, added: int, row: Array, poses: Dictionary, dest: Dictionary, queue: Array) -> void:
	var right := Layout.facing(seat) * Vector3.RIGHT
	for i in range(row.size() - added, row.size()):
		var key = row[i]
		var slot := i
		while slot > 0 and (_ranks[row[slot - 1]] > _ranks[key] if _ranks.has(key) else dest[row[slot - 1]].origin.dot(right) > dest[key].origin.dot(right)):
			slot -= 1
		if slot == i:
			continue
		var raised: Transform3D = poses[key]
		raised.origin.y += Layout.LONG + 0.12
		var target := _rack_pose(seat, slot, key, dest)
		var over := target
		over.origin.y = raised.origin.y
		_queue_move(queue, poses, {key: raised}, INSERT * 0.25)
		var slide := {key: over}
		for j in range(slot, i):
			slide[row[j]] = _rack_pose(seat, j + 1, row[j], dest)
		_queue_move(queue, poses, slide, INSERT * 0.50)
		_queue_move(queue, poses, {key: target}, INSERT * 0.25)
		row.remove_at(i)
		row.insert(slot, key)

static func _queue_move(queue: Array, poses: Dictionary, goals: Dictionary, duration: float) -> void:
	var starts := {}
	for key in goals:
		starts[key] = poses[key]
		poses[key] = goals[key]
	queue.append({"starts": starts, "goals": goals, "duration": duration, "elapsed": 0.0})

static func _sort_frame(t: float, tiles: Dictionary, step: Dictionary, trans: Tween.TransitionType) -> void:
	var eased: float = Tween.interpolate_value(0.0, 1.0, t, 1.0, trans, Tween.EASE_IN_OUT)
	for key in step.goals:
		tiles[key].transform = step.starts[key].interpolate_with(step.goals[key], eased)

static func _sort_during(track: Tween, tiles: Dictionary, queue: Array, budget: float, trans: Tween.TransitionType) -> float:
	while not queue.is_empty() and budget > 0.00001:
		var step: Dictionary = queue.front()
		var duration: float = step.duration
		var from: float = step.elapsed
		var time := minf(duration - from, budget)
		step.elapsed += time
		# Advance the clock uniformly so a pickup can pause and resume the same eased curve.
		track.tween_method(_sort_frame.bind(tiles, step, trans), from / duration, step.elapsed / duration, time).set_trans(Tween.TRANS_LINEAR)
		budget -= time
		if step.elapsed >= duration - 0.00001:
			queue.pop_front()
	return budget
