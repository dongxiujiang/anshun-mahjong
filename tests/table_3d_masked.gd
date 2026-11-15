extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.get_node("UpdateManager").auto_check = false
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	var round := RoundState.new()
	round.build_players(0)
	round.controllers = [null, null, null, null]
	view.set_round(round, 0)
	var renderer = view._table_3d
	for settled in [false, true]:
		round.phase = RoundState.Phase.SETTLED if settled else RoundState.Phase.PLAYING
		for face_up in [false, true]:
			for hand in [false, true]:
				for flight_pitch in [-1.0, 0.0]:
					var source = view._tile(view._deal_layer, "hidden0", face_up, G.CENTER, G.WALL_UNIT, 0.0)
					source.set_meta("new_kind", "hand" if hand else "flight")
					source.flight_pitch = flight_pitch
					renderer.sync_tiles()
					var mesh: MeshInstance3D = renderer.tile_nodes[source.get_instance_id()]
					t.expect(mesh.mesh == renderer._meshes["wan1"], "masked network events use the anonymous model in live and settlement snapshots")
					t.expect(mesh.basis.y.normalized().dot(Vector3.UP) < 0.001, "stale reveal flags and flight poses never expose an invented tile face")
					view._release_visual_node(source)
					renderer.sync_tiles()
	for x in [-100.0, G.DESIGN_SIZE.x + 100.0]:
		var source = view._tile(view._deal_layer, "", false, Vector2(x, 1000), G.WALL_UNIT, -PI / 2.0)
		source.set_meta("new_kind", "hand")
		source.standing_back_view = 3 if x < 0 else 1
		renderer.sync_tiles()
		var bounds: Rect2 = renderer.project_tile(source)
		t.expect(bounds.position.x >= 7.9 and bounds.end.x <= G.DESIGN_SIZE.x - 7.9, "side hands stay fully in view while a dealt group recenters")
		view._release_visual_node(source)
	round.phase = RoundState.Phase.SETTLED
	round.players[0].concealed = ["tong1"]
	round.players[0].just_drew = "tong1"
	round.round_meta["winners"] = [0]
	view.set_round(round, 0)
	t.expect(view.draw_boxes[0].get_child_count() == 1, "the self-drawn winning tile stays on the table")
	for source in view.draw_boxes[0].get_children():
		t.expect(is_zero_approx(source._win_glow), "the winning tile has no automatic outline or pulse in 3D")
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("table_3d_masked"))
