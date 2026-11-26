extends SceneTree

const Main := preload("res://scenes/Main.tscn")
const Settings := preload("res://src/app/AppSettings.gd")
const Match := preload("res://src/session/MatchSession.gd")
const Dice := preload("res://src/runtime/DiceRoll.gd")
const Wall := preload("res://src/domain/Wall.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")
const Result := preload("res://src/app/SettlementView.gd")
var checks := 0
var failures := 0
var app
var game
var dice

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func _run() -> void:
	var path := "user://settlement-name-test-%d.cfg" % Time.get_ticks_usec()
	app = Main.instantiate()
	app._settings = Settings.new(path)
	app._settings.save_profile("结算姓名甲乙", 1)
	root.add_child(app)
	game = Match.new("settlement-name-test")
	var ticket: Dictionary = game.join("winner", "结算姓名甲乙", "host", 100).ticket
	game.join("loser", "结算姓名丙丁", "guest", 100)
	game.set_ready("host", true, 100)
	game.set_ready("guest", true, 100)
	dice = Dice.new()
	root.add_child(dice)
	check(dice.roll(31605), "real authority dice starts")
	for tick in 1800:
		await physics_frame
		if dice.phase == "settled": break
	check(dice.phase == "settled", "real dice settles")
	if dice.phase == "settled":
		var deck := _winning_deck(int(dice.snapshot().result[0]))
		check(game.start_round(dice, deck, 100, 1), "actual match starts with a legal four-copy stock")
		var state: Dictionary = game.view_for("host", 100)
		game.begin_dealer_turn(ticket.room_instance_id, 1, state.round.prompt_id, 100)
		state = game.view_for("host", 100)
		check(game.submit("host", ticket.room_instance_id, 1, state.round.prompt_id, "self_win", -1, 100), "human wins through authoritative rules and scoring")
		var final: Dictionary = game.view_for("host", 100)
		app._view_changed(final)
		await process_frame
		await process_frame
		_check_result(final)
		await capture("settlement-original")
		var immutable: Dictionary = final.settlement.duplicate(true)
		check(game.move_to_empty_seat("host", 2, 110), "winner changes seat only after the round")
		var moved: Dictionary = game.view_for("host", 110)
		app._view_changed(moved)
		await process_frame
		_check_result(moved)
		check(app._table.viewer == 1 and moved.seat == 2, "the historical player keeps the ended round's camera rather than rotating to a new preparation seat")
		var newcomer: Dictionary = game.join("new-human", "后来玩家甲乙", "new", 110).view
		check(newcomer.settlement.viewer_seat == -1 and newcomer.seat == 1, "new member did not play in the ended round")
		var original_app = app
		original_app.hide()
		app = Main.instantiate()
		app._settings = Settings.new(path + "-new")
		app._settings.save_profile("后来玩家甲乙", 1)
		root.add_child(app)
		app._view_changed(newcomer)
		await process_frame
		await process_frame
		_check_result(newcomer)
		check(app._settlement_names.badges[0].name_label.text == "结算姓名甲乙", "new human is never credited with the old occupant's result")
		check(app._frame.find_children("*", "Button", true, false).all(func(button): return button.text != "提交本局记录"), "new member cannot submit another person's historical record")
		await capture("settlement-newcomer")
		app.queue_free()
		await process_frame
		app = original_app
		app.show()
		DirAccess.remove_absolute(path + "-new")
		game.disconnect_human("host", 120)
		var restored: Dictionary = game.resume(ticket.room_instance_id, "winner", ticket.member_token, "restored", 121)
		app._view_changed(restored)
		await process_frame
		_check_result(restored)
		check(restored.settlement == immutable and app._table.viewer == 1, "reconnection restores the immutable ledger and historical camera together")
		app._session_ended("disconnected")
		await process_frame
		check(app._screen == "home" and not app._settlement_names.visible, "connection loss hides the inactive settlement screen")
		app._view_changed(game.view_for("restored", 122))
		await process_frame
		await process_frame
		_check_result(game.view_for("restored", 122))
		check(app._screen == "settlement" and app._table.viewer == 1, "same-result recovery returns from home to the historical settlement")
		check(Result.delta_text(0) == "0" and Result.delta_text(4) == "+4" and Result.delta_text(-12) == "-12", "net changes format zero and both signs without changing value")
		app._show("room")
		app._view_changed(game.view_for("restored", 123))
		check(not app._settlement_names.visible, "preparation hides historical board labels")
		check(app._screen == "room", "normal room updates do not reopen a voluntarily dismissed settlement")
	app.queue_free()
	dice.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	print("Settlement names: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _winning_deck(red: int) -> Array:
	var probe := Wall.new(Catalog.values(697))
	probe.open(1, red)
	var cards := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tiao1", "tiao2", "tiao3", "tong5"]
	var fixed := {}
	for i in cards.size():
		var offset := 48 if i == 12 else (i / 4) * 16 + i % 4
		fixed[(probe.break_index + offset) % 108] = cards[i]
	fixed[(probe.break_index + 52) % 108] = "tong5"
	var pool := Catalog.values(285)
	for value in fixed.values(): pool.erase(value)
	var stock := []
	for i in 108: stock.append(fixed[i] if fixed.has(i) else pool.pop_back())
	return stock

func _check_result(state: Dictionary) -> void:
	check(app._screen == "settlement" and app._settlement_names.visible, "real Main displays ended-round board labels")
	var panel = app._frame.get_child(0)
	var rows = panel._body.get_child(1).get_child(0)
	var viewer := int(state.settlement.viewer_seat)
	var seats := [viewer, Result.Seats.previous(viewer), Result.Seats.opposite(viewer), Result.Seats.next(viewer)] if viewer >= 0 else [0, 1, 2, 3]
	for position in 4:
		var seat := posmod(int(app._table.viewer) - position, 4)
		var result: Dictionary = state.settlement
		var badge = app._settlement_names.badges[position]
		var score := int(result.scores[seat])
		var delta := Result.delta_text(int(result.ledger.deltas[seat]))
		check(badge.context.seat == seat and badge.name_label.text == result.seats[seat].nickname
			and badge.score_label.text == "%d 分 %s" % [score, delta], "board identity, total and net match the historical physical seat")
		var columns = rows.get_child(seats.find(seat)).get_child(0)
		var direction: String = Result.POSITIONS[Result.Seats.relative(viewer, seat)] if viewer >= 0 else Result.WINDS[seat]
		check(columns.get_child(0).get_child(0).text == "%s · %s" % [direction, result.seats[seat].nickname]
			and columns.get_child(2).get_child(0).text == "%s　累计 %d" % [delta, score], "each named panel row matches the board's historical identity, total and signed net")
		check(badge.disabled and badge.mouse_filter == Control.MOUSE_FILTER_IGNORE and badge.turn_dot.modulate.a == 0.0,
			"historical labels cannot operate a later occupant or show a stale turn")
		check(app._safe.get_global_rect().encloses(badge.get_global_rect()), "settlement name and full score stay inside the safe area")
		for node in app._table.tiles.values():
			var bounds: AABB = node.get_aabb()
			var projected := Rect2()
			for corner in 8:
				var world: Vector3 = node.global_transform * bounds.get_endpoint(corner)
				var point: Vector2 = app._board.position + app._table.camera.unproject_position(world) * app._board.size / Vector2(app._board_world.size)
				projected = Rect2(point, Vector2.ZERO) if corner == 0 else projected.expand(point)
			if badge.get_global_rect().intersects(projected):
				check(false, "read-only settlement name must not cover a rendered tile")
				break

func capture(name: String) -> void:
	var path := OS.get_environment("DONGXIU_SETTLEMENT_SCREENS")
	if path.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(path)
	root.get_texture().get_image().save_png(path.path_join(name + ".png"))
