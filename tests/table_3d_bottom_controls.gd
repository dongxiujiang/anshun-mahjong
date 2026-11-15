extends SceneTree
const H = preload("res://tests/test_harness.gd")
const G = preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()

class Host extends Control:
	var surface: Control
	var _new_areas: Control
	var online := false
	var widgets := preload("res://scripts/ui/table/TableWidgets.gd").new()
	func _net_mode() -> String: return "host" if online else ""
	func _design_size() -> Vector2: return TableV2Geometry.DESIGN_SIZE
	func _next_round() -> void: pass
	func _box(parent): return widgets._box(parent)
	func _button(text, callback, dimensions, primary = false): return widgets._button(text, callback, dimensions, primary)
	func _label(parent, text, pos, dimensions, font_size, color): return widgets._label(parent, text, pos, dimensions, font_size, color)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("UpdateManager").auto_check = false
	var host := Host.new()
	root.add_child(host)
	host.surface = Control.new()
	host.add_child(host.surface)
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	host.surface.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	host._new_areas = view
	var card = load("res://scripts/ui/table/v2/TableV2SettlementCard.gd").new(host)
	card.build()
	card._post_controls.show()
	for pixels in [Vector2(1600, 1000), Vector2(1920, 1080), Vector2(2400, 1080)]:
		host.scale = pixels / G.DESIGN_SIZE
		for viewer in 4:
			for melds in [0, 2, 4]:
				var round := RoundState.new()
				round.build_players(viewer)
				round.phase = RoundState.Phase.SETTLED
				for player in round.players:
					player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tong1", "tong2", "tong3", "tiao2"].slice(0, 13 - melds * 3)
					for i in melds: player.melds.append({"kind": "kong", "tile": "wan6", "from_seat": posmod(player.seat + 1, 4), "revealed": true})
				view.set_round(round, viewer)
				view._table_3d._own_hand_pitch = 0.0
				view._table_3d.sync_tiles()
				for online in [false, true]:
					host.online = online
					card.refresh_layout()
					await process_frame
					var bounds: Rect2 = card._post_controls.get_rect()
					t.expect(is_equal_approx(bounds.end.y, G.DESIGN_SIZE.y), "next/ready controls align with the screen bottom")
					t.expect(Rect2(Vector2.ZERO, G.DESIGN_SIZE).encloses(bounds), "both solo and online controls stay fully on screen")
					for tile in view.hand_boxes[viewer].get_children() + view.draw_boxes[viewer].get_children():
						var mesh: MeshInstance3D = view._table_3d.tile_nodes[tile.get_instance_id()]
						for x in [-0.5, 0.5]:
							for z in [-0.67, 0.67]:
								var point: Vector2 = view._table_3d.camera.unproject_position(mesh.transform * Vector3(x, 0.31, z)) / Vector2(view._table_3d.viewport.size) * G.DESIGN_SIZE
								t.expect(point.y + 4.0 <= bounds.position.y, "next/ready controls leave the entire printed face clear")
	host.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("table_3d_bottom_controls"))
