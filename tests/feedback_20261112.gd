extends SceneTree
const H=preload("res://tests/test_harness.gd")
const A=preload("res://scripts/ui/table/v2/HandArrangement.gd")
var t=H.new()
func _initialize():call_deferred("run")
func run():
	var start:=Time.get_ticks_msec()
	var hand: Array=[]
	for n in "1112223334445":hand.append("wan"+n)
	var choices:=A.with_one_tile_changes(hand,false)
	print("arrangement choices=",choices.size()," ms=",Time.get_ticks_msec()-start)
	var changes:={}
	for choice in choices:
		t.expect(Tiles.sort_hand(choice.cards)==hand,"sorting preserves all real tiles")
		if choice.has("change_from"): changes[choice.change_from+":"+choice.change_to]=true
	t.expect(not changes.is_empty(),"one-tile upgrades are enumerated")
	for sample in [hand, ["wan1","wan1","wan2","wan2","wan3","wan3","tiao4","tiao4","tiao5","tiao5","tong6","tong6","tong9"],
		["wan1","wan1","wan1","tiao2","tiao2","tiao2","tong3","tong3","tong3","wan4","wan4","wan5","tong8"]]:
		var listed := {}
		for choice in A.with_one_tile_changes(sample,true):
			if choice.has("change_from"): listed[choice.change_from+":"+choice.change_to] = true
		for outgoing in Tiles.to_counts(sample):
			for incoming in Tiles.all_values():
				if incoming==outgoing or sample.count(incoming)>=4: continue
				var modified: Array = sample.duplicate()
				modified.erase(outgoing)
				modified.append(incoming)
				var big_ready := false
				for win_tile in Tiles.all_values():
					var analyzed := RuleEngine.analyze(modified+[win_tile],[],win_tile)
					if analyzed.win and not A.SCORING._pattern_info(analyzed).is_empty(): big_ready=true
				t.expect(listed.has(outgoing+":"+incoming)==big_ready,"one-tile plan enumeration exactly covers every legal big-pattern wait")
	var r:=RoundState.new()
	r.controllers=[null,null,null,null]
	r.pause_after_opening=true
	r.set_rng_seed(20261112)
	var doubles:=0
	var bins:={}
	for i in 6000:
		r.start_round(1)
		var pair:=[r.round_meta.die,r.round_meta.die_white]
		doubles+=int(pair[0]==pair[1])
		bins[str(pair)]=int(bins.get(str(pair),0))+1
	print("dice samples=6000 doubles=",doubles," bins=",bins.size())
	t.expect(bins.size()==36 and doubles>850 and doubles<1150,"independent dice remain near one-sixth doubles")
	for viewer in 4:
		for seat in 4:
			var rel:=TableV2Geometry.relative_seat(viewer,seat)
			var width:=6 if rel in [1,3] else 12
			for count in range(1,25):
				for row in ceili(float(count)/width):
					var n:=mini(width,count-row*width)
					var first:=TableV2Geometry.ordinary_slot_center(seat,row*width,viewer,count)
					var last:=TableV2Geometry.ordinary_slot_center(seat,row*width+n-1,viewer,count)
					t.expect(is_equal_approx((first.x+last.x)/2,1140) if rel in [0,2] else is_equal_approx((first.y+last.y)/2,606),"each occupied river row remains centered")
	await H.quit_cleanly(self,t.finish("feedback_20261112"))
