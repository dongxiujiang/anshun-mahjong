extends RefCounted
## Shared live/reconnect/animation layout, ordered from each owner's left to right.
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const AXES := [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]
const INWARD := [Vector2.UP, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT]
const ANGLES := [0.0, -PI/2, PI, PI/2]

static func size_for(rel: int) -> Vector2:
	return Vector2(64.8,86.4) * (0.85 if rel in [1,3] else 1.0) * (1.08 if rel != 0 else 1.0)

static func rect_for(center: Vector2, size: Vector2, angle: float) -> Rect2:
	var extent := size if is_zero_approx(sin(angle)) else Vector2(size.y,size.x)
	var rect := Rect2(center - extent/2, extent)
	var shadow := Vector2(size.x/24,size.y/16).rotated(angle)
	return rect.merge(Rect2(rect.position+shadow,rect.size))

static func origin(rel: int, lower: bool) -> Vector2:
	if lower:
		return [Vector2(1140,G.HAND_BOTTOM),Vector2(G.HAND_RIGHT,640),Vector2(1140,G.HAND_TOP),Vector2(G.HAND_LEFT,640)][rel]
	return [Vector2(1140,G.HAND_BOTTOM-G.TILE_BASE.y*G.OWN_UNIT-8),Vector2(G.HAND_RIGHT-G.TILE_BASE.y*G.OPPONENT_UNIT-8,640),Vector2(1140,G.HAND_TOP+G.TILE_BASE.y*G.OPPONENT_UNIT+8),Vector2(G.HAND_LEFT+G.TILE_BASE.y*G.OPPONENT_UNIT+8,640)][rel]

static func interval(rect: Rect2, rel: int) -> Vector2:
	var axis: Vector2=AXES[rel]
	var middle := rect.get_center().dot(axis)-origin(rel,false).dot(axis)
	var half := absf(axis.x)*rect.size.x/2+absf(axis.y)*rect.size.y/2
	return Vector2(middle-half,middle+half)

static func axis_bounds(rel: int) -> Vector2:
	var half:=G.hand_span(13,G.OPPONENT_UNIT)/2
	if rel in [0,2]:half=(G.WALL_BOUNDS[0].position.x-G.WALL_BOUNDS[2].end.x)/2-16
	return Vector2(-half,half)

static func place(group: Dictionary, start: float, lower: bool, outward: float = 0.0) -> Array:
	var rel: int=group.rel
	var size:=size_for(rel)
	var out:=[]
	var cursor:=0.0
	for i in int(group.count):
		var sideways: bool=group.charge or i==group.source_slot
		var width:=size.y if sideways else size.x
		var depth:=size.x if sideways else size.y
		var x:=start+cursor+width/2
		if group.opposite and sideways: x=start+float(group.width)/2
		var center: Vector2=origin(rel,lower)+AXES[rel]*x+INWARD[rel]*depth/2
		if group.opposite and sideways: center+=INWARD[rel]*(size.y+8)
		center-=INWARD[rel]*outward
		var angle: float=ANGLES[rel]+(PI/2 if sideways else 0)
		var spec:=group.duplicate()
		spec.merge({"center":center,"sideways":sideways,"meld_slot":i,"rect":rect_for(center,size,angle),"lower":lower},true)
		var anchor: Vector2 = origin(rel,lower) + AXES[rel]*(start+size.x/2) + INWARD[rel]*size.y/2 - INWARD[rel]*outward
		var along := float(i) + (0.34 if group.source_slot == 0 and i > 0 else 0.0) + (0.17 if sideways else 0.0)
		if group.opposite and sideways: along = 1.0
		var inward := (-0.17 if sideways else 0.0) + (1.34 if group.opposite and sideways else 0.0)
		spec["kong_offset_2d"] = center - anchor if int(group.count) > 1 else Vector2.ZERO
		spec["kong_offset_3d"] = AXES[rel]*along + INWARD[rel]*inward if int(group.count) > 1 else Vector2.ZERO
		out.append(spec)
		cursor+=width+4
	return out

static func clear(specs: Array, obstacles: Array, offset: Vector2 = Vector2.ZERO) -> bool:
	for spec in specs:
		var rect: Rect2 = spec.rect
		rect.position += offset
		if not G.TABLE_BOUNDS.grow(0.1).encloses(rect): return false
		var span:=interval(rect,int(spec.rel))
		var bounds: Vector2=spec.get("bounds",axis_bounds(int(spec.rel)))
		if span.x<bounds.x or span.y>bounds.y:return false
		var interior := rect.grow(-0.05)
		for obstacle: Rect2 in obstacles:
			if interior.intersects(obstacle): return false
	return true

static func compact_obstacles(obstacles: Array) -> Array:
	var compact := []
	for obstacle: Rect2 in obstacles:
		var rect := obstacle
		for i in range(compact.size() - 1, -1, -1):
			var other: Rect2 = compact[i]
			# Only merge rectangles whose union is exactly another rectangle.
			var same_row := rect.position.y == other.position.y and rect.size.y == other.size.y
			var same_column := rect.position.x == other.position.x and rect.size.x == other.size.x
			if (same_row or same_column) and rect.intersects(other, true):
				rect = rect.merge(other)
				compact.remove_at(i)
		compact.append(rect)
	return compact

static func solve(view, context: Array = []) -> Array:
	var groups:=[]
	var obstacles:=[]
	var own_chicken_obstacles:=[]
	var north_reserve := []
	var reserved_side_rivers := []
	var projected_obstacles: Dictionary[Rect2, Dictionary] = {}
	for seat in 4:
		var rel: int=G.relative_seat(view.human_seat,seat)
		var player=view.round.players[seat]
		var size:=size_for(rel)
		var singles:=[]
		var melds:=[]
		for i in player.discards.size():
			var tile: String=str(player.discards[i])
			if not Tiles.is_chicken(tile): continue
			var charge: bool=view.round.is_charge_discard(seat,i)
			singles.append({"seat":seat,"rel":rel,"tile":tile,"count":1,"charge":charge,"source_slot":-1,"opposite":false,"width":size.y if charge else size.x,"meld_index":-1,"discard_id":int(player.discard_ids[i]),"event_order":int(player.discard_ids[i])*2+1,"kind":"charge" if charge else "ordinary","concealed":false,"revealed":true})
		var visible_melds: Array=view.MODEL.melds_for_seat(view.round,seat)
		for i in visible_melds.size():
			var m: Dictionary=visible_melds[i]
			var count:=3 if m.kind=="pung" else 4
			var slot:=G.exposed_kong_source_slot(seat,int(m.get("from_seat",-1))) if m.kind=="kong" and not m.get("concealed",false) else -1
			var opposite:=slot>=0 and posmod(int(m.from_seat)-seat,4)==2
			var n:=3 if opposite else count
			melds.append({"seat":seat,"rel":rel,"tile":m.tile,"count":count,"charge":false,"source_slot":slot,"opposite":opposite,"width":n*size.x+(n-1)*4+(size.y-size.x if slot>=0 and not opposite else 0),"source_seat":int(m.get("from_seat",-1)),"meld_index":i,"discard_id":-1,"event_order":int(m.get("formed_at",m.get("after_discard",0)))*2,"kind":m.kind,"concealed":m.get("concealed",false),"revealed":m.get("revealed",false)})
		var ordered := singles + melds
		ordered.sort_custom(func(a,b):
			if a.event_order != b.event_order: return a.event_order < b.event_order
			return a.meld_index < b.meld_index)
		var width := -8.0
		for g in ordered: width += float(g.width) + 8.0
		var cursor := -width / 2.0
		for g in ordered:
			g.start = cursor
			g.lower = false
			cursor += float(g.width) + 8.0
		groups.append_array(ordered)
		var hand_size:=G.hand_tile_size(seat,view.human_seat)
		if rel in [1,3] and not view._face_visible(seat): hand_size.x = 2.0 * hand_size.y
		var hand_shift := Vector2.ZERO
		var hand_stretch := 1.0
		if view._table_3d != null and rel in [1, 3]:
			# Match the raised 3D row both while standing and after settlement.
			var weight := 1.07 if view._face_visible(seat) else 1.30
			hand_size.y *= weight
			hand_stretch = weight * 0.95
			hand_shift.y = -112.0
		var hand_centers := []
		for i in view._current_hand_count(seat): hand_centers.append(view._hand_center(seat,i,view._current_hand_count(seat)))
		var north_3d: bool = view._table_3d != null and rel == 2
		if north_3d and view._held_hand_centers.has(seat):
			# A held hand closes its gaps after the discard. Both rows need to clear the meld.
			var count: int = view._current_hand_count(seat)
			for i in count:
				north_reserve.append(rect_for(G.hand_slot_center(seat,i,view.human_seat,count),hand_size,ANGLES[rel]))
			north_reserve.append(rect_for(G.draw_slot_center(seat,view.human_seat,count),hand_size,ANGLES[rel]))
		var side_play: bool = view._table_3d != null and view.round.phase == RoundState.Phase.PLAYING and rel in [1, 3]
		# Keep the side draw slot reserved when its tile leaves for the river.
		if not str(player.just_drew).is_empty() or side_play:
			hand_centers.append(view._draw_center(seat,view._current_hand_count(seat)))
		for center: Vector2 in hand_centers:
			if view._table_3d != null and rel in [1, 3]: center.x -= (center.y - G.CENTER.y) * 0.105 * (1 if rel == 1 else -1)
			center.y = G.CENTER.y + (center.y - G.CENTER.y) * hand_stretch
			var hand_rect := rect_for(center + hand_shift,hand_size,ANGLES[rel])
			if view._table_3d != null and rel in [1, 3]:
				# Leave a tile length for the projected ends of the raised hand row.
				var margin := G.TILE_BASE.y * G.OPPONENT_UNIT
				hand_rect = hand_rect.grow_individual(0, margin, 0, margin)
			if view._table_3d != null and rel == 0:
				# The foreground hand fans wider than its source rectangles.
				var margin := G.TILE_BASE.x*G.OWN_UNIT
				own_chicken_obstacles.append(hand_rect.grow_individual(margin,0,margin,0))
			obstacles.append(hand_rect)
		obstacles.append(view._seat_hud_rect(seat))
		var badge: Vector2=G.meld_anchor(seat,view.human_seat)
		var label_count:=int(seat==view.round.dealer_seat)+int(player.ready)
		for i in label_count:
			var c: Vector2=badge+AXES[rel]*64*(i-(label_count-1)/2.0)
			obstacles.append(Rect2(c-Vector2(28,28),Vector2(56,56)))
		var ordinary: int=view._ordinary_count(seat)
		var used := ordinary
		var columns := G.river_columns(rel)
		var reserved_count := 0
		if side_play:
			# An open river row recenters on each discard. Reserve its full width.
			ordinary = ceili(float(ordinary) / columns) * columns
			reserved_count = maxi(columns, ordinary)
		elif north_3d:
			reserved_count = mini(G.river_capacity(rel), (ordinary / columns + 1) * columns)
		if reserved_count > 0:
			# Reserve the actual shifted river band when placing a new north group.
			var first := rect_for(G.ordinary_slot_center(seat,0,view.human_seat,reserved_count),G.TILE_BASE*G.ORDINARY_UNIT,ANGLES[rel])
			var last := rect_for(G.ordinary_slot_center(seat,reserved_count-1,view.human_seat,reserved_count),G.TILE_BASE*G.ORDINARY_UNIT,ANGLES[rel])
			north_reserve.append(first.merge(last))
		# Keep the established meld belts when shifting the 3D river.
		var river_shift:=Vector2(0,G.RIVER_Y_SHIFT) if view._table_3d!=null else Vector2.ZERO
		for i in ordinary:
			var center := G.ordinary_slot_center(seat,i,view.human_seat,ordinary)-river_shift
			var river := rect_for(center,G.TILE_BASE*G.ORDINARY_UNIT,ANGLES[rel])
			if view._table_3d != null and rel in [1,3]:
				river = river.grow_individual(0,G.TILE_BASE.x*G.ORDINARY_UNIT,0,0)
			if used != ordinary and i >= ordinary - columns:
				# Keep surviving groups clear of actual tiles. Reserve the full open row for new placements.
				reserved_side_rivers.append(river)
				if i >= used: continue
				river.position += G.ordinary_slot_center(seat,i,view.human_seat,used) - river_shift - center
			if view._table_3d != null and rel in [1, 3]:
				projected_obstacles[river] = {"seat": seat, "slot": i, "count": used}
			else:
				obstacles.append(river)
	if groups.is_empty(): return []
	var walls := []
	for node in view._wall_layer.get_children():
		if node is TileView and (not view._reconciling or view._render_seen.has(node.get_instance_id())):
			var position: Vector2 = node.position.snapped(Vector2.ONE * 0.001)
			var dimensions: Vector2 = node.size.snapped(Vector2.ONE * 0.001)
			var wall_rect := rect_for(position+dimensions/2,dimensions*node.scale,node.rotation)
			if view._table_3d != null and absf(sin(node.rotation)) > 0.5:
				wall_rect = wall_rect.grow_individual(0,G.TILE_BASE.x*G.WALL_UNIT,0,0)
			if view._table_3d != null and is_zero_approx(node.rotation):
				projected_obstacles[wall_rect] = {"wall_index": int(node.get_meta("wall_ring_index", -1))}
			else:
				walls.append(wall_rect)
	obstacles.append_array(compact_obstacles(walls))
	obstacles.append(view.reserved_action_rect())
	var fixed_obstacles := obstacles
	obstacles = compact_obstacles(fixed_obstacles + projected_obstacles.keys())
	var stable_walls := walls.duplicate()
	var projected_walls: Dictionary[Rect2, Dictionary] = {}
	for rect in projected_obstacles:
		if projected_obstacles[rect].has("wall_index"):
			stable_walls.append(rect)
			projected_walls[rect] = projected_obstacles[rect]
	var prior_groups := {}
	if not context.is_empty():
		var key := [context, groups, view.round.dealer_seat, view.round.players.map(func(player): return player.ready)]
		var last = view._exposed_placement_key
		if last != null and last[0] == context:
			for seat in 4:
				var current: Array = groups.filter(func(g): return g.seat == seat)
				var previous: Array = last[1].filter(func(g): return g.seat == seat)
				if current != previous: continue
				for old in view._exposed_specs:
					if old.seat != seat: continue
					var id := Vector3i(old.seat, old.meld_index, old.discard_id)
					prior_groups.get_or_add(id, []).append(old)
		view._exposed_placement_key = key
	for id in prior_groups.keys():
		var saved: Array = prior_groups[id]
		if clear(saved,stable_walls): continue
		if saved[0].rel == 2 and clear(saved,walls) and view._table_3d.can_keep_north_exposed(saved,projected_walls): continue
		prior_groups.erase(id)
	# Solve complete rows before the legacy dense-board collision search.
	var seat_reserves := [own_chicken_obstacles, [], north_reserve, []]
	var centered := _centered_seats(groups, obstacles + reserved_side_rivers, seat_reserves, prior_groups)
	if not centered.is_empty(): return event_sorted(centered)
	for row_limit in range(11,0,-1):
		centered = _centered_seats(groups, obstacles + reserved_side_rivers, seat_reserves, prior_groups, row_limit)
		if not centered.is_empty(): return event_sorted(centered)
	# Early in a round the wall can leave room only over an unopened river row.
	if not north_reserve.is_empty():
		seat_reserves[2] = []
		centered = _centered_seats(groups, obstacles + reserved_side_rivers, seat_reserves, prior_groups)
		if not centered.is_empty(): return event_sorted(centered)
	# Preserve unchanged owners through every dense-board search.
	for attempt in 10:
		var order:=groups.duplicate()
		order.sort_custom(func(a,b):
			if (a.count==1)!=(b.count==1):return (a.count==1) if attempt==0 else (a.count!=1)
			if attempt>=5 and a.opposite!=b.opposite:return a.opposite
			if attempt>=2 and a.seat!=b.seat:return posmod(int(a.seat)-attempt,4)<posmod(int(b.seat)-attempt,4)
			return a.width>b.width)
		var occupied:=obstacles.duplicate()
		var result:=[]
		var failed:=false
		if not prior_groups.is_empty():
			for g in order.duplicate():
				var prior: Array = prior_groups.get(Vector3i(g.seat, g.meld_index, g.discard_id), [])
				if prior.size() != g.count: continue
				var old: Dictionary = prior[0]
				if g.tile != old.tile or g.kind != old.kind or g.charge != old.charge \
						or g.source_slot != old.source_slot or g.get("source_seat") != old.get("source_seat") \
						or g.concealed != old.concealed or g.revealed != old.revealed: continue
				var stable := []
				for saved in prior:
					var piece: Dictionary = g.duplicate()
					for field in ["center","sideways","meld_slot","rect","lower","kong_offset_2d","kong_offset_3d"]:
						piece[field] = saved[field]
					stable.append(piece)
				result.append_array(stable)
				for piece in stable:
					occupied.append(piece.rect)
				order.erase(g)
		occupied.append_array(reserved_side_rivers)
		for g in order:
			var blocked := occupied
			if g.seat == view.human_seat and g.count == 1: blocked = occupied + own_chicken_obstacles
			var specs:=place(g,float(g.start),bool(g.lower))
			if g.lower or not clear(specs,blocked):specs=find_space(g,blocked)
			if specs.is_empty():failed=true;break
			result.append_array(specs)
			for spec in specs:occupied.append(spec.rect)
		if not failed:
			if view._table_3d != null:
				_align_charge_rows(result, obstacles + reserved_side_rivers, own_chicken_obstacles, prior_groups)
			return event_sorted(result)
	push_error("碰杠区无法完整放置，禁止静默丢牌")
	return []

static func event_sorted(specs: Array) -> Array:
	specs.sort_custom(func(a,b):
		if a.seat != b.seat: return a.seat < b.seat
		if a.event_order != b.event_order: return a.event_order < b.event_order
		if a.meld_index != b.meld_index: return a.meld_index < b.meld_index
		return a.meld_slot < b.meld_slot)
	return specs

static func _centered_seats(groups: Array, obstacles: Array, seat_reserves: Array, prior: Dictionary, row_limit: int = 12) -> Array:
	var result := []
	var occupied := obstacles.duplicate()
	var pending := groups.duplicate()
	# Unchanged owners retain their landing even as ordinary rivers advance.
	for g in groups:
		var saved: Array = prior.get(Vector3i(g.seat,g.meld_index,g.discard_id), [])
		if saved.size() != g.count: continue
		result.append_array(saved)
		for piece in saved: occupied.append(piece.rect)
		pending.erase(g)
	for seat in 4:
		var row: Array = pending.filter(func(g): return g.seat == seat)
		var earlier_rows := []
		while not row.is_empty():
			var placed := []
			var used := mini(row.size(),row_limit)
			while used > 0:
				var blocked: Array = occupied + seat_reserves[row[0].rel]
				placed = centered_row(row.slice(0,used),blocked + earlier_rows)
				if not placed.is_empty(): break
				used -= 1
			if placed.is_empty(): return []
			result.append_array(placed)
			for piece in placed: occupied.append(piece.rect)
			var row_rect: Rect2 = placed[0].rect
			for piece in placed: row_rect = row_rect.merge(piece.rect)
			# A later row must not fill an earlier row's left-hand gap.
			var rel: int = row[0].rel
			var bounds := axis_bounds(rel)
			var left: Vector2 = origin(rel,false) + AXES[rel]*bounds.x
			if rel == 0:
				row_rect.size.x += row_rect.position.x-left.x
				row_rect.position.x = left.x
			elif rel == 2: row_rect.size.x = left.x-row_rect.position.x
			elif rel == 1: row_rect.size.y = left.y-row_rect.position.y
			else:
				row_rect.size.y += row_rect.position.y-left.y
				row_rect.position.y = left.y
			earlier_rows.append(row_rect)
			row = row.slice(used)
	return result

static func centered_row(groups: Array, obstacles: Array) -> Array:
	if groups.is_empty(): return []
	var rel: int = groups[0].rel
	var width := -12.0
	for g in groups: width += float(g.width) + 12.0
	var bounds: Vector2 = groups[0].get("bounds",axis_bounds(rel))
	if width > bounds.y - bounds.x - 16.0: return []
	var shape := []
	var cursor := -width / 2.0
	for g in groups:
		shape.append_array(place(g,cursor,false))
		cursor += float(g.width) + 12.0
	var inward: Vector2 = INWARD[rel]
	var depth := Vector2(INF,-INF)
	for piece in shape:
		var middle: float = (piece.rect.get_center()-origin(rel,false)).dot(inward)
		var half: float = (absf(inward.x)*piece.rect.size.x+absf(inward.y)*piece.rect.size.y)/2
		depth.x = minf(depth.x,middle-half)
		depth.y = maxf(depth.y,middle+half)
	var wall: Rect2 = G.WALL_BOUNDS[[1,0,3,2][rel]]
	var wall_depth: float = (wall.get_center()-origin(rel,false)).dot(inward)+(absf(inward.x)*wall.size.x+absf(inward.y)*wall.size.y)/2
	var offsets := {0.0:true}
	var shifts := {0.0:true}
	for obstacle: Rect2 in obstacles:
		var middle: float = (obstacle.get_center()-origin(rel,false)).dot(inward)
		var half: float = (absf(inward.x)*obstacle.size.x+absf(inward.y)*obstacle.size.y)/2
		for offset in [depth.y-middle+half+8,depth.x-middle-half-8]:
			# The inner wall edge is the final overflow belt for a full exposed hand.
			if offset >= -wall_depth-24.0 and offset <= (origin(rel,false)-origin(rel,true)).dot(inward): offsets[offset] = true
		var span := interval(obstacle,rel)
		shifts[span.y+8+width/2] = true
		shifts[span.x-8-width/2] = true
	var values: Array = offsets.keys()
	values.sort_custom(func(a,b): return absf(a)<absf(b))
	var starts: Array = shifts.keys()
	starts.sort_custom(func(a,b): return absf(a)<absf(b))
	# Exhaust centered depth candidates before moving a row sideways.
	for shift in starts:
		for outward in values:
			var delta: Vector2 = AXES[rel]*float(shift)-inward*float(outward)
			if not clear(shape,obstacles,delta): continue
			for piece in shape:
				piece.center += delta
				piece.rect.position += delta
			return shape
	return []

static func _align_charge_rows(specs: Array, obstacles: Array, own_chicken_obstacles: Array, prior: Dictionary = {}) -> void:
	for charge in specs:
		if not charge.charge or prior.has(Vector3i(charge.seat,charge.meld_index,charge.discard_id)): continue
		var size := size_for(charge.rel)
		var inward: Vector2 = INWARD[charge.rel]
		var along: Vector2 = AXES[charge.rel]
		var depth: float = charge.center.dot(inward) - size.x / 2.0
		var nearest := INF
		var shift := Vector2.ZERO
		for mate in specs:
			if mate.seat != charge.seat or mate.lower != charge.lower or mate.meld_index < 0 or mate.sideways: continue
			var delta: float = mate.center.dot(inward) - size.y / 2.0 - depth
			var distance: float = absf((mate.center - charge.center).dot(along))
			if absf(delta) < size.x and distance < nearest:
				nearest = distance
				shift = inward * delta
		if shift.is_zero_approx(): continue
		var blocked := obstacles + own_chicken_obstacles if charge.rel == 0 else obstacles.duplicate()
		for other in specs:
			if other != charge: blocked.append(other.rect)
		if clear([charge], blocked, shift):
			charge.center += shift
			charge.rect.position += shift

static func find_space(group: Dictionary, obstacles: Array) -> Array:
	var rel: int=group.rel
	var bounds: Vector2=group.get("bounds",axis_bounds(rel))
	var width: float=group.width
	var starts:={bounds.x+8:true,bounds.y-width-8:true,-36-width:true,36.0:true}
	var hand_half:=G.hand_span(13,G.OWN_UNIT if rel==0 else G.OPPONENT_UNIT)/2
	starts[-hand_half+8]=true;starts[hand_half-width-8]=true
	for obstacle: Rect2 in obstacles:
		var span:=interval(obstacle,rel)
		starts[span.y+8]=true;starts[span.x-width-8]=true
	for hand_space in [true,false]:
		var limits:=Vector2(maxf(bounds.x,-hand_half),minf(bounds.y,hand_half)) if hand_space else bounds
		for lower in [false,true]:
			var shape := place(group,0,lower)
			for side in [-1,1]:
				var candidates: Array=starts.keys().filter(func(x):return x>=limits.x+8 and x+width<=limits.y-8 and ((x<0 if side<0 else x>=0) if lower else (x+width<=-8 if side<0 else x>=8)))
				candidates.sort()
				if (side<0 and not lower) or (side>0 and lower):candidates.reverse()
				for start in candidates:
					if clear(shape,obstacles,AXES[rel]*float(start)):
						return place(group,float(start),lower)
	# A held hand or a two-row kong may leave neither fixed belt usable.
	# Search the free belt, including just inside that wall, as a whole group.
	var inward: Vector2=INWARD[rel]
	var max_outward: float=(origin(rel,false)-origin(rel,true)).dot(inward)
	var wall: Rect2=G.WALL_BOUNDS[[1,0,3,2][rel]]
	var wall_depth: float=(wall.get_center()-origin(rel,false)).dot(inward)+(absf(inward.x)*wall.size.x+absf(inward.y)*wall.size.y)/2
	var min_outward: float=-wall_depth-24
	var shape:=place(group,0,false)
	var depth:=Vector2(INF,-INF)
	for spec in shape:
		var center: float=(spec.rect.get_center()-origin(rel,false)).dot(inward)
		var half: float=(absf(inward.x)*spec.rect.size.x+absf(inward.y)*spec.rect.size.y)/2
		depth.x=minf(depth.x,center-half);depth.y=maxf(depth.y,center+half)
	var offsets:={}
	for obstacle: Rect2 in obstacles:
		var center: float=(obstacle.get_center()-origin(rel,false)).dot(inward)
		var half: float=(absf(inward.x)*obstacle.size.x+absf(inward.y)*obstacle.size.y)/2
		for offset in [depth.y-center+half+8,depth.x-center-half-8]:
			if offset>min_outward and offset<max_outward: offsets[offset]=true
		if group.opposite:
			# A crosswise tile leaves usable space beside it on its own row.
			var tip: Rect2 = shape[group.source_slot].rect
			var tip_span := interval(tip,rel)
			var span := interval(obstacle,rel)
			starts[span.y-tip_span.x+4] = true
			starts[span.x-tip_span.y-4] = true
			var tip_center := (tip.get_center()-origin(rel,false)).dot(inward)
			var tip_half := (absf(inward.x)*tip.size.x+absf(inward.y)*tip.size.y)/2
			for offset in [tip_center+tip_half-center+half+4,tip_center-tip_half-center-half-4]:
				if offset>min_outward and offset<max_outward: offsets[offset]=true
	var values: Array=offsets.keys()
	values.sort_custom(func(a,b):
		if (a>=0)!=(b>=0):return a>=0
		return absf(a)<absf(b))
	for offset in values:
		for start in starts:
			if start<bounds.x+8 or start+width>bounds.y-8:continue
			if clear(shape,obstacles,AXES[rel]*float(start)-inward*float(offset)):
				return place(group,float(start),false,float(offset))
	return []
