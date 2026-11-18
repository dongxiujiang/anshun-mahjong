extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const REPLAY := preload("res://scripts/core/RoundReplay.gd")
const TILES := preload("res://scripts/core/Tiles.gd")
const FIXTURE := "res://tests/fixtures/river-corner-round1.json"
var t := H.new()
var evidence := []
var retired_discard_playbacks: Array[WeakRef] = []

class LandingSoundContract extends RefCounted:
	var enabled := true
	func defers_discard_sound() -> bool: return enabled
	func visual_hold_active() -> bool: return false
	func deal_sequence_active() -> bool: return false
	func opening_active() -> bool: return false
	func dice_gate_active() -> bool: return false
	func dealt_count(_seat: int) -> int: return 13
	func holds_draw_slot(_seat: int) -> bool: return false

class Host extends Control:
	var round: RoundState
	var human_seat := 1
	var _table_animation_controller = null
	func _net_mode() -> String: return ""
	func _refresh() -> void: pass
	func _update_interactivity() -> void: pass
	func _pump_visual_animation() -> void: pass

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	root.get_node("UpdateManager").auto_check = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1600, 1000)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var full: Dictionary = REPLAY.replay(record)
	t.expect(full.ok, "unmodified real round replays to its original terminal fingerprint")
	if not full.ok:
		await H.quit_cleanly(self, t.finish("table_3d_river_discard_flight"))
		return
	for screen in [Vector2i(1600, 1000), Vector2i(1920, 1080), Vector2i(2400, 1080)]:
		for relative in 4:
			for settled in [false, true]: await _case(record, settled, screen, relative)
	for relative in 4: await _case(record, false, Vector2i(1600, 1000), relative, false)
	for mode in ["instant", "missing", "cancel"]:
		for relative in [0, 1]: await _case(record, false, Vector2i(1600, 1000), relative, true, mode)
	for mode in ["claim-own", "claim-opposite"]:
		await _case(record, false, Vector2i(1600, 1000), 1, true, mode)
	for mode in ["claim-right", "claim-left"]:
		await _case(record, false, Vector2i(1600, 1000), 2, true, mode)
	for relative in 4:
		for row_number in range(2, 4 if relative % 2 == 0 else 5):
			await _case(record, false, Vector2i(1600, 1000), relative, true, "normal", row_number)
	var cleanup_started := Time.get_ticks_msec()
	var released := await H.drain_audio(self)
	var alive_after_drain := retired_discard_playbacks.filter(func(ref): return ref.get_ref() != null).size()
	var deadline := Time.get_ticks_msec() + 2000
	while retired_discard_playbacks.any(func(ref): return ref.get_ref() != null) and Time.get_ticks_msec() < deadline:
		await create_timer(0.05, true, false, true).timeout
	var alive_at_exit := retired_discard_playbacks.filter(func(ref): return ref.get_ref() != null).size()
	t.expect(released and alive_at_exit == 0, "all stopped discard playbacks release before test shutdown")
	var out := OS.get_environment("RIVER_FLIGHT_EVIDENCE")
	if not out.is_empty():
		var file := FileAccess.open(out.path_join("samples.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"fixture": FIXTURE, "provenance": record.provenance, "cases": evidence, "audio_cleanup": {"retired_playbacks_observed": retired_discard_playbacks.size(), "alive_after_initial_drain": alive_after_drain, "alive_at_exit": alive_at_exit, "elapsed_ms": Time.get_ticks_msec() - cleanup_started}}, "  "))
	quit(t.finish("table_3d_river_discard_flight"))

func _prefix(record: Dictionary, count: int) -> Dictionary:
	var data := record.duplicate(true)
	data.actions = data.actions.slice(0, count)
	data.final = {}
	return REPLAY.replay(data)

func _case(record: Dictionary, settled: bool, screen: Vector2i, relative: int, full_row: bool = true, mode: String = "normal", row_number: int = 1) -> void:
	# Rotate the viewer, never the authoritative hand, wall, actions or scores.
	var north_south := relative % 2 == 0
	var decision := (37 if north_south else 34) if full_row else (28 if north_south else 25)
	var owner: int = record.actions[decision].seat
	var viewer := posmod(owner + relative, 4)
	var card: String = record.actions[decision].decision.discard
	var before := _prefix(record, decision)
	var after := _prefix(record, decision + 1)
	t.expect(before.ok and after.ok, "real decision prefixes %d/%d are legal" % [decision, decision + 1])
	if not before.ok or not after.ok: return
	var columns := G.river_columns(relative)
	var claiming := mode.begins_with("claim-")
	var claimant := viewer if mode == "claim-own" else posmod(viewer + 2, 4)
	if mode in ["claim-right", "claim-left"]: claimant = posmod(viewer - (1 if mode == "claim-right" else 3), 4)
	if claiming:
		# Synthetic visual handoff, not a claim that this replay legally allows a pung.
		for result in [before, after]:
			result.round.players[claimant].concealed[0] = card
			result.round.players[claimant].concealed[1] = card
	if row_number > 1:
		# Synthetic display pressure, not a legal real round or scoring verification.
		# Keep the real draw/hand; extend only this seat's river within UI capacity.
		var player = before.round.players[owner]
		var ordinary: Array = player.discards.filter(func(tile): return not TILES.is_chicken(str(tile)))
		var added := columns * row_number - 1 - ordinary.size()
		for index in added:
			player.discards.append(ordinary[index % ordinary.size()])
			player.discard_ids.append(1000000 + index)
		after.round.players[owner].discards = player.discards.duplicate()
		after.round.players[owner].discard_ids = player.discard_ids.duplicate()
		after.round.players[owner].discards.append(card)
		after.round.players[owner].discard_ids.append(2000000)
	var config = root.get_node("GameConfig")
	var saved_duration: float = config.tile_motion_seconds()
	config.set_tile_animation_seconds(0.0 if mode == "instant" else 0.20, false)
	root.size = screen
	var host := Host.new()
	# Reproduce Android canvas_items/expand and TableLayout's 28-unit safe inset.
	var canvas_scale := minf(screen.x / G.DESIGN_SIZE.x, screen.y / G.DESIGN_SIZE.y)
	host.size = Vector2(screen) / canvas_scale
	host.scale = Vector2.ONE * canvas_scale
	host.human_seat = viewer
	host._table_animation_controller = LandingSoundContract.new()
	host._table_animation_controller.enabled = mode != "instant"
	root.add_child(host)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	view.set_script(load("res://tests/fixtures/table_touch_footer_view.gd"))
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.position = Vector2(28, 28)
	view.size = G.DESIGN_SIZE
	view.scale = (host.size - Vector2(56, 28)) / G.DESIGN_SIZE
	# R01's measured 90px sort control is the actual 48dp footer, not a guessed DPI.
	view.test_touch_height = 90.0 / (host.scale.y * view.scale.y)
	host.add_child(view)
	view.table = host
	view.auto_sort_hands = false
	host.round = before.round
	view.set_round(host.round, viewer)
	view._sort_started = true
	view.refresh()
	await process_frame
	var renderer = view._table_3d
	renderer.set_process(false)
	renderer.sync_tiles()
	var source_ok: bool = view.draw_boxes[owner].get_child_count() == 1 and str(before.round.players[owner].just_drew) == card
	t.expect(source_ok, "real source is the recorded drawn %s (opponents remain concealed until discard)" % card)
	if not source_ok:
		host.queue_free()
		config.set_tile_animation_seconds(saved_duration, false)
		await process_frame
		return
	var count: int = view._ordinary_count(owner)
	t.expect(count + 1 == (columns * row_number if full_row else columns - (2 if north_south else 1)), "prefix/display pressure reaches the intended full/nonfull row boundary")
	var moving: TileView = view.draw_boxes[owner].get_child(0)
	var id: int = moving.get_instance_id()
	var initial_transform: Transform3D = renderer.tile_nodes[id].transform
	host.round = after.round
	view.round = host.round
	var audio = root.get_node("AudioManager")
	audio.enabled.effects = true
	audio.volumes.effects = 1.0
	audio.begin_table(host)
	var complete := {"count": 0, "impacts": 0}
	var heard := func(): complete.impacts += 1
	audio.discard_impact_played.connect(heard)
	if mode == "missing": view._release_visual_node(moving)
	view.animate_draw_discard(owner, func(): complete.count += 1, card)
	if mode == "missing": moving = view._take_river_node(owner, int(host.round.players[owner].discard_ids.back()))
	if mode not in ["instant", "missing"]:
		renderer.sync_tiles()
		t.expect(renderer.tile_nodes[id].transform.is_equal_approx(initial_transform), "ordinary discard starts at the actual same-Mesh transform without snapping")
	var initial_flight: Dictionary = view._discard_flights.values()[0] if not view._discard_flights.is_empty() else {}
	if not initial_flight.is_empty():
		t.expect(bool(initial_flight.center_during_flight) == full_row, "only the full row centers during flight")
		t.expect(Vector2(initial_flight.target).is_equal_approx(initial_flight.centered_target) == full_row, "full-row target is final; nonfull row retains its half-slot landing")
	if settled:
		host.round = REPLAY.replay(record).round
		view.round = host.round
		view.refresh()
		t.expect(view.native_presentation_pending() and not view.native_settlement_started() and moving.get_instance_id() == id, "SETTLED pending preserves the moving entity before settlement begins")
	var fingerprint: String = REPLAY.fingerprint(host.round)
	var samples := []
	var blocked := {"approach": [], "contact": [], "centering": [], "landed": []}
	var first_contact := false
	var contact_ms := -1.0
	var elapsed := 0.0
	var terminal_probe := {}
	while not view._discard_flights.is_empty() and elapsed < 0.4:
		var data: Dictionary = view._discard_flights.values()[0]
		var tween: Tween = data.tween
		tween.pause()
		tween.custom_step(0.001)
		elapsed += 0.001
		renderer.sync_tiles()
		if mode == "normal" and elapsed > 0.1985 and elapsed < 0.1995:
			# Probe the exact tween terminal pose before _place_discard_flight changes
			# kind draw -> ordinary. Restore it before the real completion callback.
			var pose := [moving.position, moving.scale, moving.rotation, moving.flight_pitch, moving.flight_progress]
			moving.position = Vector2(data.target) - moving.size / 2.0
			moving.scale = G.TILE_BASE * G.ORDINARY_UNIT / moving.size
			moving.rotation = data.angle
			moving.flight_pitch = 0.0
			moving.flight_progress = 1.0
			renderer.sync_tiles()
			terminal_probe = _sample(renderer, moving)
			moving.position = pose[0]
			moving.scale = pose[1]
			moving.rotation = pose[2]
			moving.flight_pitch = pose[3]
			moving.flight_progress = pose[4]
			renderer.sync_tiles()
		if mode == "cancel" and elapsed >= 0.10:
			view._reset_round_visual_state()
			await create_timer(0.25).timeout
			break
		if claiming and elapsed >= 0.10:
			var mesh: MeshInstance3D = renderer.tile_nodes[id]
			var handoff: Transform3D = mesh.transform
			var player = host.round.players[claimant]
			var meld_index: int = player.melds.size()
			player.concealed.remove_at(1)
			player.concealed.remove_at(0)
			player.melds.append({"kind": "pung", "tile": card, "from_seat": owner})
			var discard_id: int = host.round.players[owner].discard_ids.pop_back()
			host.round.players[owner].discards.pop_back()
			fingerprint = REPLAY.fingerprint(host.round)
			var meld_done := {"count": 0}
			view.animate_meld({"seat": claimant, "tile": card, "kind": "pung", "index": meld_index, "source": owner, "source_discard_id": discard_id, "hand_indices": [0, 1]}, func(): meld_done.count += 1)
			renderer.sync_tiles()
			t.expect(renderer.tile_nodes[id] == mesh and mesh.transform.is_equal_approx(handoff), "%s keeps the exact same 3D pose when the flying discard is claimed" % mode)
			t.expect(not moving.has_meta("ordinary_flight_3d"), "claim removes the ordinary flight destination")
			await create_timer(0.60).timeout
			renderer.sync_tiles()
			t.expect(meld_done.count == 1 and moving.get_meta("v2_seat") == claimant and moving.get_meta("new_kind") == "meld", "claimed same entity finishes in the new meld exactly once")
			t.expect(not moving.has_meta("claimed_flight_origin_3d"), "completed meld clears the claimed-flight origin")
			t.expect(view._take_river_node(owner, discard_id) == null, "cancelled discard landing does not create a ghost river tile")
			break
		var centered: bool = bool(data.get("centered", false))
		if moving.flight_progress < 0.85 and not centered: continue
		var phase := "centering" if centered else "approach"
		if centered and not first_contact:
			phase = "contact"
			first_contact = true
			contact_ms = elapsed * 1000.0
		if moving.get_parent() == view._discard_layer: phase = "landed"
		var sample := _sample(renderer, moving)
		sample.merge({"phase": phase, "elapsed_ms": elapsed * 1000, "flight_progress": moving.flight_progress, "centered": centered, "target": [data.target.x, data.target.y], "centered_target": [data.centered_target.x, data.centered_target.y]})
		samples.append(sample)
		if not sample.blocked.is_empty(): blocked[phase].append(sample)
	renderer.sync_tiles()
	if mode in ["instant", "missing"]:
		var sample := _sample(renderer, moving)
		sample.merge({"phase": "landed", "elapsed_ms": 0.0})
		samples.append(sample)
		if not sample.blocked.is_empty(): blocked.landed.append(sample)
	t.expect(complete.count == (0 if mode == "cancel" else 1) and not view.native_presentation_pending(), "completion/cancellation releases the lock without a repeated callback")
	t.expect(complete.impacts == (0 if mode in ["instant", "cancel"] or claiming else 1), "graphical landing-sound contract emits exactly one actual impact signal, or none for instant/cancel/claim")
	t.expect(REPLAY.fingerprint(host.round) == fingerprint, "flight preserves the original authoritative hand, wall and score")
	if mode == "normal":
		t.expect(first_contact and absf(elapsed - 0.20) < 0.002, "full and nonfull cases retain the same total 0.20 second animation budget")
		t.expect(absf(contact_ms - (200.0 if full_row else 140.0)) < 2.0, "full row lands at 0.20; nonfull retains its 0.14 contact plus 0.06 centering")
	for phase in blocked:
		t.expect(blocked[phase].is_empty(), "%s rel%d %s %s: interior artwork stays readable (%d blocked samples)" % [screen, relative, mode, phase, blocked[phase].size()])
	var terminal_jump := 0.0
	if mode == "normal":
		var landed := _sample(renderer, moving)
		for index in 4:
			var a: Array = terminal_probe.printed_polygon_viewport_pixels[index]
			var b: Array = landed.printed_polygon_viewport_pixels[index]
			terminal_jump = maxf(terminal_jump, Vector2(a[0], a[1]).distance_to(Vector2(b[0], b[1])))
		t.expect(terminal_probe.blocked.is_empty(), "row%d rel%d exact flight t1 artwork stays readable" % [row_number, relative])
		t.expect(terminal_jump < 0.1, "row%d rel%d flight t1 -> land has no projection jump (%.3fpx)" % [row_number, relative, terminal_jump])
	t.expect(not moving.has_meta("ordinary_flight_3d"), "land, cancel or claim removes ordinary flight metadata")
	var marker_blocked := _marker_print_occlusions(renderer)
	if renderer.discard_marker.visible:
		t.expect(marker_blocked.is_empty(), "latest-discard triangle does not cover visible printed faces: %s" % JSON.stringify(marker_blocked))
		var marker: MeshInstance3D = renderer.discard_marker
		var tip: Vector2 = renderer.camera.unproject_position(marker.global_transform * Vector3(0, 0.275, 0))
		var base: Vector2 = renderer.camera.unproject_position(marker.global_transform * Vector3(0, -0.275, 0))
		var target: Vector2 = renderer.camera.unproject_position(renderer.tile_nodes[moving.get_instance_id()].global_position)
		t.expect((tip - base).normalized().dot((target - base).normalized()) > 0.98 and renderer._marker_source_id == moving.get_instance_id(), "triangle tip points at the latest discard")
	evidence.append({"decision_prefix": decision, "owner": owner, "viewer": viewer, "relative": relative, "tile": card, "columns": columns, "full_row": full_row, "row_number": row_number, "synthetic_display_pressure_not_legal_round": row_number > 1 or claiming, "terminal_probe": terminal_probe, "terminal_jump_pixels": terminal_jump, "mode": mode, "settled_pending": settled, "screen": [screen.x, screen.y], "renderer_viewport": [renderer.viewport.size.x, renderer.viewport.size.y], "footer_design_units": view.test_touch_height, "duration_seconds": config.tile_motion_seconds(), "contact_animation_ms": contact_ms, "total_animation_ms": elapsed * 1000, "samples": samples, "blocked_counts": blocked.values().map(func(rows): return rows.size()), "marker_occluded_print_points": marker_blocked, "complete_count": complete.count, "impact_count": complete.impacts})
	print("[river-discard-flight] screen=", screen, " rel=", relative, " row=", row_number, " full=", full_row, " mode=", mode, " settled=", settled, " blocked=", blocked.values().map(func(rows): return rows.size()), " t1_jump_px=", terminal_jump)
	audio.discard_impact_played.disconnect(heard)
	# Capture before stop detaches the playback from its player.
	if audio.effects_player.has_stream_playback(): retired_discard_playbacks.append(weakref(audio.effects_player.get_stream_playback()))
	audio.end_table(host)
	view._reset_round_visual_state()
	host.queue_free()
	config.set_tile_animation_seconds(saved_duration, false)
	await process_frame

func _sample(renderer, moving: TileView) -> Dictionary:
	var mesh: MeshInstance3D = renderer.tile_nodes[moving.get_instance_id()]
	var polygon := []
	for point in [Vector2(-0.30, -0.42), Vector2(0.30, -0.42), Vector2(0.30, 0.42), Vector2(-0.30, 0.42)]:
		var pixel: Vector2 = renderer.camera.unproject_position(mesh.transform * Vector3(point.x, 0.31, point.y))
		polygon.append([pixel.x, pixel.y])
	var blocked := []
	# Interior print points exclude the ivory rim/base; ray picking resolves depth.
	for x in [-0.28, 0.0, 0.28]:
		for z in [-0.35, 0.0, 0.35]:
			var point: Vector2 = renderer.camera.unproject_position(mesh.transform * Vector3(x, 0.31, z)) / Vector2(renderer.viewport.size) * renderer.size
			var hit: TileView = renderer.pick_tile(point, false)
			if hit != moving:
				blocked.append({"local": [x, z], "projected_design": [point.x, point.y], "occluder": hit.tile if hit != null else "none", "seat": int(hit.get_meta("v2_seat", -1)) if hit != null else -1, "kind": str(hit.get_meta("new_kind", "")) if hit != null else ""})
	return {"printed_polygon_viewport_pixels": polygon, "blocked": blocked}

func _marker_print_occlusions(renderer) -> Array:
	var blocked := []
	var marker: MeshInstance3D = renderer.discard_marker
	if not marker.visible: return blocked
	var arrays: Array = marker.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for id in renderer.tile_nodes:
		var source = renderer._sources[id].get_ref()
		var mesh: MeshInstance3D = renderer.tile_nodes[id]
		if not is_instance_valid(source) or not mesh.visible or not source.face_up or source.tile in ["", "hidden0"]: continue
		for x in [-0.28, 0.0, 0.28]:
			for z in [-0.35, 0.0, 0.35]:
				var point: Vector3 = mesh.global_transform * Vector3(x, 0.31, z)
				var pixel: Vector2 = renderer.camera.unproject_position(point)
				if renderer.pick_tile(pixel / Vector2(renderer.viewport.size) * renderer.size, false) != source: continue
				var origin: Vector3 = renderer.camera.project_ray_origin(pixel)
				var direction: Vector3 = renderer.camera.project_ray_normal(pixel)
				for triangle in range(0, indices.size(), 3):
					var a: Vector3 = marker.global_transform * vertices[indices[triangle]]
					var b: Vector3 = marker.global_transform * vertices[indices[triangle + 1]]
					var c: Vector3 = marker.global_transform * vertices[indices[triangle + 2]]
					var hit = Geometry3D.ray_intersects_triangle(origin, direction, a, b, c)
					if hit != null and origin.distance_to(hit) < origin.distance_to(point) - 0.0001:
						blocked.append({"tile": source.tile, "seat": int(source.get_meta("v2_seat", -1)), "kind": str(source.get_meta("new_kind", "")), "local_point": [x, z], "pixel": [pixel.x, pixel.y]})
						break
	return blocked
