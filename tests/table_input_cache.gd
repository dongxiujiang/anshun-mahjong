extends SceneTree
const H = preload("res://tests/test_harness.gd")
var t = H.new()
class CountingRound extends RoundState:
	var queries := 0
	func allowed_actions(seat: int) -> Dictionary:
		queries += 1
		return super.allowed_actions(seat)
func _initialize(): call_deferred("run")
func run():
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	table.round.cancel_ai()
	table._table_animation_controller.reset()
	var r = CountingRound.new()
	r.build_players(table.human_seat)
	r.phase = RoundState.Phase.PLAYING
	r.awaiting = true
	r.current_turn = table.human_seat
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	var p = r.players[table.human_seat]
	p.concealed = ["wan1","wan2","wan3","wan2","wan3","wan4","tong3","tong4","tong5","tiao3","tiao4","tiao5","wan9","tiao8"]
	p.just_drew = "tiao8"
	table.round = r
	var actions = table._table_actions
	actions._selecting = true
	for i in 30: actions._update_interactivity()
	t.expect(r.queries==1,"repeated input refresh computes the ready/discard window once")
	t.expect(actions._input_window.options==r.legal_turn_options(table.human_seat),"cached options equal authoritative options")
	p.forbidden_discard_tile = "wan1"
	actions._update_interactivity()
	t.expect(r.queries==2 and not actions._input_window.options.discards.has("wan1"),"forbidden discard expires cached input options")
	p.ready = true
	actions._update_interactivity()
	t.expect(r.queries==3 and actions._input_window.options.discards==["tiao8"],"ready hand only enables the drawn tile")
	r.prompt_id += 1
	actions._update_interactivity()
	t.expect(r.queries==4,"new prompt cannot reuse a prior operation window")
	r.awaiting = false
	actions._update_interactivity()
	t.expect(not actions._selecting,"closed authoritative window disables selection")
	r.awaiting = true
	r.current_turn = (table.human_seat+1)%4
	actions._selecting = true
	actions._update_interactivity()
	t.expect(not actions._selecting,"turn moving to another seat disables selection")
	if table._ai_service!=null: table._ai_service.stop()
	table.queue_free()
	await process_frame
	await H.quit_cleanly(self,t.finish("table_input_cache"))
