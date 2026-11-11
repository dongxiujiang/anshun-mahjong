extends SceneTree
const H := preload("res://tests/test_harness.gd")
const AI_CONTEXT := preload("res://scripts/ai/AiTurnContext.gd")
const HAND := ["tiao2","tiao3","tiao4","tong2","tong3","tong4","tong6","tong7","tong8","wan9","wan9","wan4","wan5"]
const OTHER := ["wan1","wan2","wan3","wan6","wan7","wan8","tiao1","tiao5","tiao6","tiao7","tiao8","tiao9","tong1"]
var t := H.new()

func _initialize(): call_deferred("run")

func fixture(ready: bool = true, hand: Array = HAND) -> RoundState:
	var r := RoundState.new()
	r.build_players(0)
	r.controllers = [null,null,null,null]
	r.phase = RoundState.Phase.PLAYING
	r.current_turn = 0
	r.awaiting = true
	var taken: Array = []
	for seat in 4:
		r.players[seat].concealed = hand.duplicate() if seat==0 else OTHER.duplicate()
		taken.append_array(r.players[seat].concealed)
	r.players[0].concealed.append("tong9")
	r.players[0].just_drew = "tong9"
	taken.append("tong9")
	var rest := TileSetFactory.create_deck()
	for tile in taken:
		t.expect(rest.has(tile),"fixture uses at most four physical copies")
		rest.erase(tile)
	r.wall = WallRing.new(taken+rest)
	r.wall.set_head(0)
	for _tile in taken: r.wall.draw_head()
	t.expect(r.submit_turn(0,{"discard":"tong9","ready":ready}),"first discard declares ready through the real action path")
	return r

func draw_for(r: RoundState, tile: String) -> void:
	var head := r.wall.peek_head_index()
	for i in 108:
		if not r.wall._drawn[i] and r.wall._ring[i]==tile:
			r.wall._ring[i] = r.wall._ring[head]
			r.wall._ring[head] = tile
			break
	t.expect(r.wall.peek_head()==tile,"requested draw exists in remaining real deck")
	r.current_turn = 0
	r._begin_turn()

func run():
	var r := fixture()
	t.expect(RuleEngine.waiting_tiles(r.players[0].concealed,[])==["wan3","wan6"],"ready hand has two distinct winning tiles")
	t.expect(r.serialize().players[0].get("ready_wait_tiles",[])==["wan3","wan6"],"ready declaration records every winning tile")
	t.expect(r.can_win_on_discard(0,3,"wan3") and r.can_win_on_discard(0,3,"wan6"),"both waits can win before passing")
	t.expect(r.submit_turn(3,{"discard":"wan3"}),"another player discards the first wait")
	t.expect(r.allowed_actions(0).options.can_win,"ready player is offered win")
	t.expect(r.submit_response(0,"wan3",{"action":"pass"}),"ready player explicitly passes a legal win")
	t.expect(r.players[0].passed_win_until_draw,"passing establishes the win restriction")
	for source in [1,2,3]:
		for tile in ["wan3","wan6"]:
			t.expect(not r.can_win_on_discard(0,source,tile),"passing either wait blocks every opponent and every wait")
	for tile in ["tong9","tong5"]:
		draw_for(r,tile)
		t.expect(r.players[0].passed_win_until_draw,"ready win restriction survives subsequent draws")
		t.expect(r.submit_turn(0,{"discard":tile}),"ready player may still discard the drawn tile")
		t.expect(not r.can_win_on_discard(0,1,"wan6",RoundState.ResponseStage.ROB),"restriction also blocks robbing an added kong")
	for viewer in 4:
		var state := r.serialize_for_seat(viewer)
		var clone := RoundState.new()
		clone.apply_sync(state)
		t.expect(clone.players[0].passed_win_until_draw,"reconnect preserves the ready restriction for every viewer")
		var waits: Array = state.players[0].get("ready_wait_tiles",[])
		t.expect(waits==(["wan3","wan6"] if viewer==0 else []),"wait list is private to its owner during play")
		if viewer==0:
			t.expect(not clone.can_win_on_discard(0,1,"wan6",RoundState.ResponseStage.ROB),"reconnected client cannot offer rob-kong win")
			clone.awaiting = true
			clone._awaiting_response = {"seat":0,"disc_seat":1,"tile":"wan6","stage":RoundState.ResponseStage.WIN}
			t.expect(not clone.submit_response(0,"wan6",{"action":"win"}),"authority rejects a forged win even with a matching response window")
	var ai_state := AiVisibleSnapshot.build(r,0)
	var ai_clone := RoundState.new()
	ai_clone.apply_sync(ai_state)
	t.expect(ai_state.players[0].get("ready_wait_tiles",[])==["wan3","wan6"],"AI proxy retains its owner's ready waits")
	t.expect(not ai_clone.can_win_on_discard(0,1,"wan6"),"AI proxy follows the same restriction")
	t.expect(AiVisibleSnapshot.build(r,1).players[0].get("ready_wait_tiles",[]).is_empty(),"opponent AI cannot see private waits")
	t.expect(AI_CONTEXT.build(r,0).players[0].passed_win_until_draw,"server AI retains the restriction")
	t.expect(AI_CONTEXT.build(r,0).players[0].ready_wait_tiles==["wan3","wan6"],"server AI retains only its own waits")
	t.expect(AI_CONTEXT.build(r,1).players[0].ready_wait_tiles.is_empty(),"server AI cannot inspect another player's waits")
	draw_for(r,"wan6")
	t.expect(r.legal_turn_options(0).self_win,"self draw remains available after passing")
	t.expect(r.submit_turn(0,{"self_win":true}) and r.round_meta.self_draw,"self draw settles successfully")
	r.pause_after_opening = true
	r.start_round(0,1,2)
	t.expect(not r.players[0].passed_win_until_draw and r.serialize().players[0].get("ready_wait_tiles",[]).is_empty(),"new round clears ready waits and restriction")
	r.cancel_opening()
	var ordinary := fixture(false)
	ordinary.players[0].passed_win_until_draw = true
	draw_for(ordinary,"tong9")
	t.expect(not ordinary.players[0].passed_win_until_draw,"non-ready player's restriction still clears on next draw")
	var single := fixture(true,["tiao2","tiao2","tiao3","tiao3","tong2","tong2","tong3","tong3","tong4","tong4","tong6","tong6","wan3"])
	t.expect(single.players[0].ready_wait_tiles==["wan3"],"single wait is recorded too")
	t.expect(single.submit_turn(3,{"discard":"wan3"}) and single.submit_response(0,"wan3",{"action":"pass"}),"single-wait player passes through the real response path")
	draw_for(single,"tong9")
	t.expect(single.players[0].passed_win_until_draw,"single wait also stays locked after drawing")
	var self_pass := fixture()
	draw_for(self_pass,"wan6")
	t.expect(self_pass.legal_turn_options(0).self_win and self_pass.submit_turn(0,{"discard":"wan6"}),"player can decline their own self draw")
	t.expect(not self_pass.players[0].passed_win_until_draw,"declining self draw does not count as passing another player's win")
	await H.quit_cleanly(self,t.finish("ready_pass_win"))
