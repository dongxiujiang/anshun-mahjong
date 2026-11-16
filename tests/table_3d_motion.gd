extends SceneTree
const H = preload("res://tests/test_harness.gd")
const G = preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.get_node("UpdateManager").auto_check = false
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	var round := RoundState.new()
	round.build_players(0)
	round.phase = RoundState.Phase.PLAYING
	for player in round.players:
		player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tong2"]
		player.melds = [{"kind": "pung", "tile": "tong3", "from_seat": (player.seat + 1) % 4}]
	for resolution in [Vector2(1600,1000), Vector2(1920,1080), Vector2(2400,1080)]:
		view.scale = resolution / G.DESIGN_SIZE
		for viewer in 4:
			view.set_round(round, viewer)
			var renderer = view._table_3d
			renderer.sync_tiles()
			for rel in [0,2]:
				var seat := posmod(viewer - rel, 4)
				var hand: Array = view.hand_boxes[seat].get_children()
				for i in range(1,hand.size()):
					var first: MeshInstance3D = renderer.tile_nodes[hand[i-1].get_instance_id()]
					var second: MeshInstance3D = renderer.tile_nodes[hand[i].get_instance_id()]
					t.expect(absf(first.position.x-second.position.x) <= first.basis.get_scale().x * 1.01, "near/far hand tiles have no gap in model space")
				var meld: Array = view._meld_layer.get_children().filter(func(tile): return int(tile.get_meta("v2_seat",-1)) == seat)
				for i in range(1,meld.size()):
					var first: MeshInstance3D = renderer.tile_nodes[meld[i-1].get_instance_id()]
					var second: MeshInstance3D = renderer.tile_nodes[meld[i].get_instance_id()]
					t.expect(is_equal_approx(first.position.distance_to(second.position), first.basis.get_scale().x), "pung tiles touch at both north and south")
	view.scale = Vector2.ONE
	view.set_round(round, 0)
	var renderer = view._table_3d
	for red in range(1,7):
		for white in range(1,7):
			view.animate_dice(red, white)
			view._dice_tween.kill()
			var initial := Basis.IDENTITY
			for progress in [0.0,0.3,0.55,0.8,1.0]:
				view._tick_dice(progress, red, white, G.CENTER + Vector2(-64,0), G.CENTER + Vector2(4,0))
				renderer.sync_tiles()
				for source in [view._dice_red,view._dice_white]:
					var node: MeshInstance3D = renderer.dice_nodes[source.get_instance_id()]
					if progress == 0.0 and source == view._dice_red: initial = node.basis.orthonormalized()
					if progress == 0.3 and source == view._dice_red:
						t.expect(not initial.is_equal_approx(node.basis.orthonormalized()), "dice rotate through space instead of changing their painted value")
					for i in 8:
						var point: Vector3 = node.transform * node.mesh.get_aabb().get_endpoint(i)
						t.expect(point.y >= -0.001, "rolling dice never penetrate the table")
					t.expect(source.value == (red if source == view._dice_red else white), "authority dice values stay fixed throughout the throw")
					if progress == 1.0:
						var color := "red" if source == view._dice_red else "black"
						var normal: Array = renderer._dice_normals[color][str(source.value)]
						var up := node.basis * Vector3(normal[0],normal[1],normal[2])
						t.expect(up.normalized().dot(Vector3.UP) > 0.999, "all 36 final dice pairs show the authoritative top face")
	view.clear_dice_visual()
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self,t.finish("table_3d_motion"))
