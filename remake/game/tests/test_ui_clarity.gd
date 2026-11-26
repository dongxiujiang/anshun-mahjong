extends SceneTree
const Main = preload("res://scenes/Main.tscn")
const Result = preload("res://src/app/SettlementView.gd")
const Profile = preload("res://src/presentation/TableLayoutProfile.gd")
const Dice = preload("res://src/runtime/DiceRoll.gd")
const Settings = preload("res://src/app/AppSettings.gd")
const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Wall = preload("res://src/domain/Wall.gd")
const Scoring = preload("res://src/anshun/scoring/ScoringEngine.gd")
const Retire = preload("res://tests/AudioRetirement.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL clarity: " + note)

func settle() -> void:
	for i in 10:
		await process_frame

func _make_finish(app, viewer: int, white: int, carry: int) -> void:
	var probe := Wall.new(Catalog.values(697))
	probe.open(viewer, 4)
	var cards := ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","tiao1","tiao2","tiao3","tong5"]
	var fixed := {}
	for index in cards.size():
		var offset: int = 48 if index == 12 else (index / 4) * 16 + index % 4
		fixed[(probe.break_index + offset) % 108] = cards[index]
	fixed[(probe.break_index + 52) % 108] = "tong5"
	var pool: Array = Catalog.values(285)
	for value in fixed.values():
		pool.erase(value)
	var stock := []
	for index in 108:
		stock.append(fixed[index] if fixed.has(index) else pool.pop_back())
	var round_state := Round.new()
	round_state.start(viewer, 4, white, stock, carry)
	round_state.begin_dealer_turn()
	round_state.submit(viewer, round_state.prompt_id, "self_win", -1)
	var snap: Dictionary = round_state.snapshot_for(viewer)
	var facts: Dictionary = round_state.settlement_facts()
	var ledger: Dictionary = Scoring.settle(facts)
	var members := []
	for seat in 4:
		members.append({"nickname": ["东秀", "牌友小明", "麻将搭子", "清风"][seat], "score": 200 + int(ledger.deltas[seat]), "ai_id": seat, "connected": true, "player_id": "p-" + str(seat), "avatar": seat + 1})
	app._round_projection = snap
	app._view = {"seat": viewer, "room": {"room_instance_id": "clarity", "round_number": 1, "seats": members, "mode": "solo"}, "round": snap,
		"settlement": {"round_number": 1, "next_dealer_seat": viewer, "viewer_seat": viewer,
			"scores": members.map(func(m): return m.score), "seats": members,
			"players": facts.players, "round_meta": facts.round_meta, "last_discard": facts.last_discard, "ledger": ledger}}
	app._mode = "solo"
	app._table.viewer = viewer
	app._table.apply_view(snap)
	app._show("settlement")
	await settle()
	app._queue_hud_layout()
	await settle()

func run() -> void:
	var entries := []
	for i in 3:
		entries.append({"kind":"flip","label":"翻鸡","tiles":["wan"+str(i+1)],"tile_ids":[i],"amount":1,"opponents":[0,2,3]})
	entries.append({"kind":"bonus","label":"自摸基础分","tiles":[],"tile_ids":[],"amount":4,"opponents":[0,2,3]})
	var original := JSON.stringify(entries)
	var grouped := Result.display_items(entries)
	check(JSON.stringify(entries) == original, "grouping never rewrites the ledger")
	check(grouped.size() == 2 and grouped[0].tiles == ["wan1","wan2","wan3"] and grouped[0].tile_ids == [0,1,2] and grouped[0].amount == 3, "three flip tiles share one +3 caption")
	var other: Dictionary = entries[0].duplicate(true); other.opponents = [2]; entries.append(other)
	other = entries[0].duplicate(true); other.amount = -1; entries.append(other)
	check(Result.display_items(entries).size() == 4, "different payers and opposite signs are never combined")

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1602, 720)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var cfg := "user://clarity-test-%d.cfg" % Time.get_ticks_usec()
	var app = Main.instantiate()
	app.table_play_only = true
	app._settings = Settings.new(cfg)
	app._settings.save_profile("清晰验证", 1)
	viewport.add_child(app)
	await settle()
	check(not app._clock_face._caption.visible, "countdown text stays hidden while numerical timer remains")
	for viewer in [1, 0, 3, 2]:
		var rs := Round.new()
		rs.start(viewer, 4, 2, Catalog.values(541))
		rs.begin_dealer_turn()
		app._table.apply_view(rs.snapshot_for(viewer))
		await settle()
		check(app._table._badges.is_empty(), "dealer and ready markers are shown beside player names rather than as 3D table badges")
		for white in [2, 4]:
			await _make_finish(app, viewer, white, 2)
			var panel = app._frame.get_child(0)
			var heading = panel._headings[0]
			var reason = heading.get_child(0)
			check(heading.get_child(1).text == "你自摸", "middle heading shows round outcome")
			check(heading.get_child(2).get_child_count() == 0, "upper-right flip tile removed")
			if white == 4:
				var pair = reason.get_child(0)
				check(pair.values == [4, 4] and pair.dice.size() == 2, "double dice take priority")
				for idx in 2:
					check((pair.dice[idx].basis * Dice.FACE_NORMALS[3]).dot(Vector3.UP) > 0.999, "opening dice mesh matches value")
			else:
				check(reason.get_child(0).text == "上局流局", "carry-only round shows previous draw reason")
			var rect: Rect2 = panel.get_global_rect()
			check(app._settlement_area.grow(1).encloses(rect) and app._safe.get_global_rect().grow(1).encloses(rect), "settlement stays in fixed centered area inside safe bounds (viewer=%d white=%d area=%s rect=%s)" % [viewer, white, app._settlement_area, rect])
			var labels: Array = panel.find_children("*", "Label", true, false).map(func(n): return n.text)
			check(labels.has("自摸+4") and not labels.has("自摸基础分+4"), "self draw uses short +4 label")
			var opposite := posmod(viewer + 2, 4)
			for node in app._table.tiles.values():
				if node.get_meta("zone", "") != "hand" or node.get_meta("seat", -1) != opposite:
					continue
				check(is_equal_approx(node.basis.get_scale().x, 1.24), "opposite ended-round hand uses enlarged settlement size")
				var normal: Vector3 = node.basis.y.normalized()
				var toward_camera: Vector3 = (app._table.camera.position - node.position).normalized()
				check(absf(normal.dot(Vector3.UP) - cos(deg_to_rad(20.0))) < 0.001 and normal.dot(toward_camera) > Vector3.UP.dot(toward_camera), "opposite revealed hand tilts 20 deg toward camera")
				var bounds := Rect2()
				for corner in 8:
					var pt: Vector2 = app._table_screen_point(node.global_transform * node.get_aabb().get_endpoint(corner))
					bounds = Rect2(pt, Vector2.ZERO) if corner == 0 else bounds.expand(pt)
				check(not rect.intersects(bounds), "settlement panel does not cover opposite hand")
	await Retire.release_app(app, self)
	viewport.free()
	DirAccess.remove_absolute(cfg)
	print("UI clarity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
