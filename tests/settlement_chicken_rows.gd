extends SceneTree
const H := preload("res://tests/test_harness.gd")
const ROWS := preload("res://scripts/ui/table/v2/SettlementRows.gd")
const PLAN := preload("res://scripts/ui/table/SettlementAnimationPlan.gd")
var t := H.new()
class TableStub extends Node:
	var round: RoundState
	var human_seat := 1
	var _table_animation_controller = null
	func _net_mode() -> String: return ""
	func _clear_actions() -> void: pass
	func _update_interactivity() -> void: pass
	func _on_settlement_animation_finished() -> void: pass

func _initialize() -> void: call_deferred("_run")
func _text(entries: Array) -> String:
	var out: Array[String] = []
	for entry in entries:
		for part in entry.parts:
			out.append("%s %+.0f%s" % [part.label,part.amount,part.get("suffix", "")])
	return " / ".join(out)
func _run() -> void:
	var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/settlement_chicken_row.json"))
	var r := RoundState.new()
	r.build_players(0)
	for seat in 4:
		r.players[seat].concealed.assign(result.players[seat].concealed)
		r.players[seat].discards.assign(result.players[seat].discards)
		r.players[seat].discard_ids.assign(range(r.players[seat].discards.size()))
		r.players[seat].melds.assign(result.players[seat].melds)
	r.round_meta = result.round_meta.duplicate(true)
	var before := var_to_bytes([result, r.round_meta, r.players.map(func(player): return [player.concealed,player.discards,player.melds])])
	var plan := PLAN.build(result, r.round_meta, r.players, 1)
	var entries := ROWS.entries(result, r.round_meta, r.players, plan, 1)
	t.expect(_text(entries) == "基础 +4（对） / 幺鸡 +6（对） / 八筒 +6（对）", "云端原局显示基础和两组碰中鸡，金额为单倍单家："+_text(entries))
	var amount := 0.0
	for entry in entries:
		for part in entry.parts:amount += float(part.amount)
	t.expect(amount * r.round_meta.chicken_multiplier == result.deltas[1], "显示项目乘本局倍数等于实际+32")
	for viewer in 4:
		var other_plan := PLAN.build(result,r.round_meta,r.players,viewer)
		t.expect(ROWS.entries(result,r.round_meta,r.players,other_plan,1) == entries, "对手括号始终相对本行玩家")
	t.expect(var_to_bytes([result,r.round_meta,r.players.map(func(player): return [player.concealed,player.discards,player.melds])])==before,"展示不改云端结算和玩家数据")
	# 所有三家付款时不加括号，部分付款按上/对/下排序。
	for mask in range(1,8):
		var sample := result.duplicate(true)
		sample.transfers=[]
		var called: Array = [true,true,true,true]
		var words: Array[String]=[]
		for offset in [1,2,3]:
			if mask & (1 << (offset-1)):
				var payer := posmod(1+offset,4)
				called[payer]=false
				words.append(["", "上", "对", "下"][offset])
				sample.transfers.append({"from":payer,"to":1,"amount":24.0,"reason":"荒牌包鸡"})
				sample.transfers.append({"from":payer,"to":1,"amount":8.0,"reason":"荒牌基础补付"})
		var rows := ROWS.entries(sample,r.round_meta,r.players,{"called":called,"is_draw":true},1)
		var suffix := "" if mask==7 else "（"+"/".join(words)+"）"
		t.expect(_text(rows)=="基础 +4%s / 幺鸡 +6%s / 八筒 +6%s" % [suffix,suffix,suffix], "七种付款组合："+_text(rows))
	var mixed := result.duplicate(true)
	mixed.transfers = [{"from":0,"to":1,"amount":24.0,"reason":"荒牌包鸡"}, {"from":2,"to":1,"amount":24.0,"reason":"荒牌包鸡"}, {"from":3,"to":1,"amount":24.0,"reason":"荒牌包鸡"}, {"from":3,"to":1,"amount":8.0,"reason":"荒牌基础补付"}]
	var ordered := ROWS.entries(mixed,r.round_meta,r.players,{"called":[false,true,false,false],"is_draw":true},1)
	t.expect(_text(ordered)=="幺鸡 +6 / 八筒 +6 / 基础 +4（对）", "所有三家都付的项目优先，局部项目靠后")
	var none := result.duplicate(true)
	none.transfers=[]
	t.expect(ROWS.entries(none,r.round_meta,r.players,{"called":[true,true,true,true],"is_draw":true},1).is_empty(), "四家叫牌流局不显示未实际得分的手牌鸡和碰中鸡")
	for shift in range(1,4):
		var shifted := result.duplicate(true)
		var rotated: Array=[]
		rotated.resize(4)
		for old in 4:rotated[posmod(old+shift,4)]=r.players[old]
		for transfer in shifted.transfers:
			transfer.from=posmod(int(transfer.from)+shift,4)
			transfer.to=posmod(int(transfer.to)+shift,4)
		var shifted_called: Array=[]
		shifted_called.resize(4)
		for old in 4:shifted_called[posmod(old+shift,4)]=plan.called[old]
		t.expect(_text(ROWS.entries(shifted,r.round_meta,rotated,{"called":shifted_called,"is_draw":true},posmod(1+shift,4)))==_text(entries), "四个座位的相对付款方一致")
	print("[settlement_chicken_rows] cloud example: "+_text(entries))
	await _check_panel(r,result)
	await H.quit_cleanly(self,t.finish("settlement_chicken_rows"))

func _check_panel(r: RoundState, result: Dictionary) -> void:
	r.phase=RoundState.Phase.SETTLED
	r.last_result=result
	for seat in 4:r.players[seat].score=float(result.scores[seat])
	var stub := TableStub.new()
	stub.round=r
	root.add_child(stub)
	var view=load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.table=stub
	view.set_round(r,1)
	view.start_native_settlement(true)
	await process_frame
	var panel: Control=view._native_settlement
	var row: Control=panel.find_child("ScoreItems1",true,false)
	t.expect(row!=null,"真实汇总面板生成本人得分行")
	if row!=null:
		var text: Array[String]=[]
		for node in row.find_children("*","Label",true,false):text.append(node.text)
		t.expect(text==["基础 +4（对）","幺鸡 +6（对）","八筒 +6（对）"],"实际面板文字逐项完整："+str(text))
		for line in row.get_children():
			var rect: Rect2=Rect2(line.position,line.size*line.scale)
			t.expect(Rect2(Vector2.ZERO,row.size).grow(1).encloses(rect),"新增鸡牌、文字保持在本行内")
	view.queue_free()
	stub.queue_free()
	await process_frame

