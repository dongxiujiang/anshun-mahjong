extends RefCounted
## Shared live/reconnect/animation layout. Whole groups occupy the upper belt first.
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const AXES := [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]
const INWARD := [Vector2.UP, Vector2.LEFT, Vector2.DOWN, Vector2.RIGHT]
const ANGLES := [0.0, -PI/2, PI, PI/2]

static func size_for(rel: int) -> Vector2:
	return Vector2(64.8,86.4) * (0.85 if rel in [1,3] else 1.0)

static func rect_for(center: Vector2, size: Vector2, angle: float) -> Rect2:
	var extent := size if is_zero_approx(sin(angle)) else Vector2(size.y,size.x)
	var rect := Rect2(center - extent/2, extent)
	var shadow := Vector2(size.x/24,size.y/16).rotated(angle)
	return rect.merge(Rect2(rect.position+shadow,rect.size))

static func origin(rel: int, lower: bool) -> Vector2:
	if lower:
		return [Vector2(1140,G.HAND_BOTTOM),Vector2(G.HAND_RIGHT,640),Vector2(1140,G.HAND_TOP),Vector2(G.HAND_LEFT,640)][rel]
	return [Vector2(1140,G.HAND_BOTTOM-153.6-8),Vector2(G.HAND_RIGHT-86.4-8,640),Vector2(1140,G.HAND_TOP+86.4+8),Vector2(G.HAND_LEFT+86.4+8,640)][rel]

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
		out.append(spec)
		cursor+=width+4
	return out

static func clear(specs: Array, obstacles: Array) -> bool:
	for spec in specs:
		if not G.TABLE_BOUNDS.grow(0.1).encloses(spec.rect): return false
		var span:=interval(spec.rect,int(spec.rel))
		var bounds:=axis_bounds(int(spec.rel))
		if span.x<bounds.x or span.y>bounds.y:return false
		for obstacle: Rect2 in obstacles:
			if spec.rect.grow(-0.05).intersects(obstacle): return false
	return true

static func solve(view) -> Array:
	var groups:=[]
	var obstacles:=[]
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
			singles.append({"seat":seat,"rel":rel,"tile":tile,"count":1,"charge":charge,"source_slot":-1,"opposite":false,"width":size.y if charge else size.x,"meld_index":-1,"discard_id":int(player.discard_ids[i]),"kind":"charge" if charge else "ordinary","concealed":false,"revealed":true})
		var visible_melds: Array=view.MODEL.melds_for_seat(view.round,seat)
		for i in visible_melds.size():
			var m: Dictionary=visible_melds[i]
			var count:=3 if m.kind=="pung" else 4
			var slot:=G.exposed_kong_source_slot(seat,int(m.get("from_seat",-1))) if m.kind=="kong" and not m.get("concealed",false) else -1
			var opposite:=slot>=0 and posmod(int(m.from_seat)-seat,4)==2
			var n:=3 if opposite else count
			melds.append({"seat":seat,"rel":rel,"tile":m.tile,"count":count,"charge":false,"source_slot":slot,"opposite":opposite,"width":n*size.x+(n-1)*4+(size.y-size.x if slot>=0 and not opposite else 0),"meld_index":i,"discard_id":-1,"kind":m.kind,"concealed":m.get("concealed",false),"revealed":m.get("revealed",false)})
		var half:=60 if seat==view.round.dealer_seat and player.ready else 28
		var left: float=-half-8
		for i in range(mini(6,singles.size())-1,-1,-1):
			var g: Dictionary=singles[i]
			g.start=left-float(g.width);g.lower=false
			left-=float(g.width)+4
		var right: float=half+8
		var upper:=melds.slice(0,2)
		upper.reverse()
		var extra:=singles.slice(6);extra.reverse();upper.append_array(extra)
		for g in upper:
			g.start=right;g.lower=false;right+=float(g.width)+8
		for g in melds.slice(2):g.start=0.0;g.lower=true
		groups.append_array(singles+melds)
		var hand_size:=G.hand_tile_size(seat,view.human_seat)
		for i in view._current_hand_count(seat):obstacles.append(rect_for(view._hand_center(seat,i,view._current_hand_count(seat)),hand_size,ANGLES[rel]))
		if not str(player.just_drew).is_empty():obstacles.append(rect_for(view._draw_center(seat,view._current_hand_count(seat)),hand_size,ANGLES[rel]))
		obstacles.append(view._seat_hud_rect(seat))
		var badge: Vector2=G.meld_anchor(seat,view.human_seat)
		var label_count:=int(seat==view.round.dealer_seat)+int(player.ready)
		for i in label_count:
			var c: Vector2=badge+AXES[rel]*64*(i-(label_count-1)/2.0)
			obstacles.append(Rect2(c-Vector2(28,28),Vector2(56,56)))
		var ordinary: int=view._ordinary_count(seat)
		for i in ordinary:obstacles.append(rect_for(G.ordinary_slot_center(seat,i,view.human_seat,ordinary),Vector2(64.8,86.4),ANGLES[rel]))
	for node in view._wall_layer.get_children():
		if node is TileView and (not view._reconciling or view._render_seen.has(node.get_instance_id())):obstacles.append(rect_for(node.position+node.size/2,node.size*node.scale,node.rotation))
	obstacles.append(view.reserved_action_rect())
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
		for g in order:
			var specs:=place(g,float(g.start),bool(g.lower))
			if g.lower or not clear(specs,occupied):specs=find_space(g,occupied)
			if specs.is_empty():failed=true;break
			result.append_array(specs)
			for spec in specs:occupied.append(spec.rect)
		if not failed:return result
	push_error("碰杠区无法完整放置，禁止静默丢牌")
	return []

static func find_space(group: Dictionary, obstacles: Array) -> Array:
	var rel: int=group.rel
	var bounds:=axis_bounds(rel)
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
			for side in [-1,1]:
				var candidates: Array=starts.keys().filter(func(x):return x>=limits.x+8 and x+width<=limits.y-8 and ((x<0 if side<0 else x>=0) if lower else (x+width<=-8 if side<0 else x>=8)))
				candidates.sort()
				if (side<0 and not lower) or (side>0 and lower):candidates.reverse()
				for start in candidates:
					var specs:=place(group,float(start),lower)
					if clear(specs,obstacles):return specs
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
	var values: Array=offsets.keys()
	values.sort_custom(func(a,b):
		if (a>=0)!=(b>=0):return a>=0
		return absf(a)<absf(b))
	for offset in values:
		for start in starts:
			if start<bounds.x+8 or start+width>bounds.y-8:continue
			var specs:=place(group,float(start),false,float(offset))
			if clear(specs,obstacles):return specs
	return []
