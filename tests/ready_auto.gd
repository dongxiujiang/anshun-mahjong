extends SceneTree
## Ready mode auto-discards the drawn tile, but stops for a self-draw win.
const H := preload("res://tests/test_harness.gd")
const TENPAI13 := ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","wan5","wan5","wan2","wan4"]  # waits wan3

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _round(draw: String) -> RoundState:
	var r := RoundState.new()
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	r.current_turn = 0
	r.awaiting = true
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.players[0].concealed = TENPAI13.duplicate()
	r.players[0].concealed.append(draw)
	r.players[0].just_drew = draw
	r.players[0].ready = true
	r.players[0].first_turn_done = true
	return r

func _run() -> void:
	var table = load("res://scenes/GameTable.tscn").instantiate()
	root.add_child(table)
	await process_frame
	table._table_actions.auto_ready_enabled = true

	# Non-winning ready draw: auto discard the drawn tile.
	var auto_round := _round("tiao9")
	table.round = auto_round
	table.human_seat = 0
	table._table_animation_controller.reset()
	table._table_actions._on_require_turn(0)
	await create_timer(0.8).timeout
	t.expect(auto_round.players[0].discards.has("tiao9"), "ready auto-discards the drawn tile")
	t.expect(not auto_round.players[0].concealed.has("tiao9"), "ready auto-discard removes only the drawn tile")

	# Winning ready draw: do not discard; leave the self-draw action available.
	var win_round := _round("wan3")
	table.round = win_round
	table.human_seat = 0
	table._table_animation_controller.reset()
	table._table_actions._on_require_turn(0)
	await create_timer(0.8).timeout
	t.expect(win_round.players[0].concealed.has("wan3"), "self-draw tile is not auto-discarded")
	t.expect(table._table_actions.action_bar.get_children().any(func(control): return control is Button and control.text == "自摸"), "self-draw button remains available")

	table.queue_free()
	await process_frame
	quit(t.finish("ready_auto"))
