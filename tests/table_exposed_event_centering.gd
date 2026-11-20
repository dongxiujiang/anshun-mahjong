extends SceneTree
const E := preload("res://scripts/ui/table/v2/ExposedLayout.gd")
const H := preload("res://tests/test_harness.gd")
var t := H.new()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for rel in 4:
		var groups := []
		var size := E.size_for(rel)
		for count in [1,3,1]:
			groups.append({"rel":rel,"count":count,"charge":false,"source_slot":-1,"opposite":false,"width":count*size.x+(count-1)*4})
		var row := E.centered_row(groups,[])
		t.expect(row.size()==5,"mixed groups remain intact at every rotation")
		var low := INF
		var high := -INF
		var previous := -INF
		for piece in row:
			var coordinate: float = (piece.center-E.origin(rel,false)).dot(E.AXES[rel])
			t.expect(coordinate>previous,"early groups precede later groups in owner left-to-right direction")
			previous=coordinate
			low=minf(low,coordinate-size.x/2)
			high=maxf(high,coordinate+size.x/2)
		t.expect(absf(low+high)<0.01,"mixed public row is centered ahead of hand")
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	t.expect(view._table_3d != null,"3D renderer initializes before layout checks")
	view.auto_sort_hands=false
	for viewer in 4:
		var r := RoundState.new()
		r.build_players(viewer)
		r.phase=RoundState.Phase.PLAYING
		r._presentation.session="center-test-%d" % viewer
		var p = r.players[0]
		p.concealed=["wan9","wan9","tong9","tong9"]
		p.discards=["tiao1","tong8"]
		p.discard_ids=[0,2]
		p.discard_count=3
		p.melds=[{"kind":"pung","tile":"wan1","from_seat":1,"formed_at":1,"after_discard":1},
			{"kind":"pung","tile":"wan2","from_seat":2,"formed_at":2,"after_discard":2}]
		view.set_round(r,viewer)
		var initial: Array = view._exposed_layout().duplicate(true)
		var original_poses := _public_poses(view,0)
		t.expect(original_poses.size()==8,"all owner0 public mesh poses are captured")
		t.expect(initial.size()==8,"mixed events all appear")
		var event_order := []
		for piece in initial:
			if not event_order.has(piece.event_order): event_order.append(piece.event_order)
		t.expect(event_order==[1,2,4,5],"discard and meld events interleave by first formation")
		p.discards.append("wan3")
		p.discard_ids.append(3)
		p.discard_count=4
		view.refresh()
		t.expect(view._exposed_layout()==initial,"ordinary discard does not reposition public groups")
		_expect_unchanged_poses(original_poses,_public_poses(view,0),"ordinary discard viewer%d" % viewer)
		r.players[1].discards=["tiao1"]
		r.players[1].discard_ids=[0]
		view.refresh()
		var unchanged: Array = view._exposed_layout().filter(func(piece): return piece.seat==0)
		t.expect(unchanged==initial,"another owner's chicken does not reposition this owner")
		_expect_unchanged_poses(original_poses,_public_poses(view,0),"another owner chicken viewer%d" % viewer)
		p.melds[0].kind="add_kong"
		p.melds[0].after_discard=4
		view.refresh()
		var upgraded: Array = view._exposed_layout().filter(func(piece): return piece.seat==0 and piece.meld_index==0)
		t.expect(upgraded.size()==4 and upgraded.all(func(piece): return piece.event_order==2),"added kong retains pung's first formation order")
	for viewer in 4:
		for kind in ["concealed","add_kong"]:
			var r := RoundState.new()
			r.build_players(viewer)
			r.phase=RoundState.Phase.PLAYING
			r._presentation.session="straight-%d-%s" % [viewer,kind]
			var p = r.players[0]
			p.concealed=["wan1","wan2","wan3","wan4","wan5","wan6","tiao2","tiao3","tiao4","tong9"]
			p.discard_count=5
			p.melds=[{"kind":"kong" if kind=="concealed" else kind,"tile":"tong8","concealed":kind=="concealed","from_seat":1,"formed_at":1,"after_discard":2}]
			view.set_round(r,viewer)
			var row: Array = view._exposed_layout()
			t.expect(row.size()==4,"concealed and added kongs retain all four tiles")
			var rel: int = view.G.relative_seat(viewer,0)
			var inward: Vector2 = E.INWARD[rel]
			var along: Vector2 = E.AXES[rel]
			for i in row.size():
				t.expect(not row[i].sideways and is_equal_approx(row[i].center.dot(inward),row[0].center.dot(inward)),"concealed and added kong main edges form one straight row")
				t.expect(Vector2(row[i].kong_offset_3d).is_equal_approx(along*i),"four kong slots are consecutive with no rear tile")
				if i>0: t.expect(is_equal_approx((row[i].center-row[i-1].center).dot(along),E.size_for(rel).x+4),"four kong tiles have equal adjacent spacing")
			var renderer = view._table_3d
			renderer.sync_tiles()
			var sources: Array = (view._meld_layer.get_children()+view._red_layer.get_children()).filter(func(tile): return int(tile.get_meta("v2_seat",-1))==0 and int(tile.get_meta("meld_index",-1))==0)
			sources.sort_custom(func(a,b): return int(a.get_meta("meld_slot"))<int(b.get_meta("meld_slot")))
			if not t.expect(sources.size()==4,"all four kong meshes are rendered"): continue
			var inward_3d := Vector3(inward.x,0,inward.y)
			var along_3d := Vector3(along.x,0,along.y)
			var first: Vector3 = renderer.tile_nodes[sources[0].get_instance_id()].position
			for i in sources.size():
				var node: MeshInstance3D = renderer.tile_nodes[sources[i].get_instance_id()]
				t.expect(absf((node.position-first).dot(inward_3d))<0.001,"3D concealed/added kong has no T-shaped rear tile viewer=%d kind=%s slot=%d" % [viewer,kind,i])
				if i>0:
					var previous: MeshInstance3D = renderer.tile_nodes[sources[i-1].get_instance_id()]
					t.expect((node.position-previous.position).dot(along_3d)>0,"3D kong slots progress consecutively left to right")
	for viewer in 4:
		for count in range(5):
			for chickens in [0,2,8]:
				var r := RoundState.new()
				r.build_players(viewer)
				r.phase=RoundState.Phase.PLAYING
				r._presentation.session="matrix-%d-%d-%d" % [viewer,count,chickens]
				r.round_meta["charge_chickens"]={"tiao1":{"owner":viewer,"location":"discard","discard_id":0}}
				for seat in 4:
					var p = r.players[seat]
					for i in 13-3*count: p.concealed.append("tong9")
					for i in count:
						p.melds.append({"kind":"kong","tile":"wan%d" % (i+1),"from_seat":posmod(seat+1+i%3,4),"formed_at":i,"after_discard":i})
					for i in (chickens if chickens<8 or seat==viewer else 0):
						p.discards.append("tiao1" if i<4 else "tong8")
						p.discard_ids.append(i)
				view.set_round(r,viewer)
				var specs: Array = view._exposed_layout()
				t.expect(specs.size()==16*count+(8 if chickens==8 else 4*chickens),"four-seat capacity viewer=%d melds=%d chickens=%d" % [viewer,count,chickens])
				for seat in 4:
					var row_ends := {}
					for piece in specs:
						if piece.seat != seat or piece.meld_slot != 0: continue
						var tile_size := E.size_for(piece.rel)
						var depth: int = roundi(piece.center.dot(E.INWARD[piece.rel])-(tile_size.x if piece.sideways else tile_size.y)/2.0)
						var along: float = piece.center.dot(E.AXES[piece.rel])
						t.expect(along>float(row_ends.get(depth,-INF)),"events progress left to right within each row v=%d m=%d c=%d seat=%d event=%d" % [viewer,count,chickens,seat,piece.event_order])
						row_ends[depth]=along
				for i in specs.size():
					for j in i:
						if specs[i].seat==specs[j].seat and specs[i].meld_index>=0 and specs[i].meld_index==specs[j].meld_index: continue
						t.expect(not specs[i].rect.grow(-0.05).intersects(specs[j].rect),"public groups avoid neighbouring groups v=%d m=%d c=%d a=%s b=%s" % [viewer,count,chickens,str(specs[i]),str(specs[j])])
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self,t.finish("table_exposed_event_centering"))

func _public_poses(view,owner:int) -> Dictionary:
	var renderer=view._table_3d
	renderer.sync_tiles()
	var poses := {}
	for source in view._red_layer.get_children()+view._meld_layer.get_children():
		if int(source.get_meta("v2_seat",-1))!=owner or not source.is_visible_in_tree(): continue
		var id: int=source.get_instance_id()
		if not renderer.tile_nodes.has(id): continue
		var node: MeshInstance3D=renderer.tile_nodes[id]
		poses[view._render_key(source)]={"source_id":id,"mesh_id":node.get_instance_id(),"transform":node.transform}
	return poses

func _expect_unchanged_poses(before:Dictionary,after:Dictionary,label:String) -> void:
	t.expect(after.size()==before.size(),label+" retains all public mesh identities")
	for key in before:
		if not t.expect(after.has(key),label+" retains render key "+str(key)): continue
		t.expect(before[key].source_id==after[key].source_id and before[key].mesh_id==after[key].mesh_id,label+" reuses source and mesh node "+str(key))
		var original: Transform3D=before[key].transform
		var current: Transform3D=after[key].transform
		t.expect(original.is_equal_approx(current),label+" preserves physical transform "+str(key)+" before="+str(original)+" after="+str(current))
