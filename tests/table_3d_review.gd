extends SceneTree
const H := preload("res://tests/test_harness.gd")
const G := preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
var t := H.new()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("UpdateManager").auto_check = false
	var view = load("res://scenes/table/TableV2.tscn").instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	view.size = G.DESIGN_SIZE
	var round := RoundState.new()
	round.build_players(0)
	round.controllers = [null, null, null, null]
	round.phase = RoundState.Phase.PLAYING
	for player in round.players:
		player.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tiao1", "tiao2", "tong1", "tong2", "tong3"]
		player.just_drew = "tong3"
	view.set_round(round, 0)
	var renderer = view._table_3d
	t.expect(RenderingServer.frame_pre_draw.is_connected(renderer._sync_before_draw), "3D snapshots are synchronized after animation tweens")
	var tile = view._tile(view._deal_layer, "wan8", false, G.CENTER, 1.0, 0.0)
	t.expect(tile.presentation_3d, "new tile sources never enable old 2D artwork")
	renderer.sync_tiles()
	view._release_visual_node(tile)
	var reused = view._tile(view._deal_layer, "tong1", true, G.CENTER + Vector2(100, 0), 1.0, 0.0)
	t.expect(reused == tile and reused.presentation_3d, "pooled sources remain exclusively 3D when reused between process and drawing")
	renderer._sync_before_draw()
	t.expect(renderer.project_tile(reused).get_center().x > G.CENTER.x, "the final reused source transform reaches the same rendered frame")
	view._release_visual_node(reused)
	for x in [-100.0, G.DESIGN_SIZE.x + 100.0]:
		var flight = view._tile(view._deal_layer, "wan8", false, Vector2(x, 1000), 1.05, PI / 2.0)
		flight.flight_pitch = PI / 2.0 + 0.001
		renderer._sync_before_draw()
		var bounds: Rect2 = renderer.project_tile(flight)
		t.expect(bounds.position.x >= 7.9 and bounds.end.x <= G.DESIGN_SIZE.x - 7.9, "draw flights stay on screen before landing and acquiring hand metadata")
		view._release_visual_node(flight)
	for pixels in [Vector2(1920, 1080), Vector2(2400, 1080), Vector2(1600, 1000)]:
		view.scale = pixels / G.DESIGN_SIZE
		for human in 4:
			view.set_round(round, human)
			for settled in [false, true]:
				round.phase = RoundState.Phase.SETTLED if settled else RoundState.Phase.PLAYING
				renderer._own_hand_pitch = 0.0 if settled else deg_to_rad(63)
				renderer.sync_tiles()
				view._layout_arrangement_controls()
				for box in [view.hand_boxes[human], view.draw_boxes[human]]:
					for source in box.get_children():
						var bounds: Rect2 = renderer.project_tile(source)
						t.expect(absf(bounds.end.y - (G.DESIGN_SIZE.y - 44.0)) < 0.2, "live and flattened own tiles share a baseline inside the near wood rail")
						t.expect(bounds.position.x >= 0 and bounds.end.x <= G.DESIGN_SIZE.x, "a full hand plus its draw fits the phone width")
						t.expect(not view._sort_button.get_rect().intersects(bounds), "sorting does not cover the enlarged hand")
						t.expect(not view._seat_hud_rect(human).intersects(bounds), "own name and score remain above the hand")
				for seat in 4:
					for box in [view.hand_boxes[seat], view.draw_boxes[seat]]:
						for source in box.get_children():
							var bounds: Rect2 = renderer.project_tile(source)
							t.expect(settled or not view._sort_button.get_rect().intersects(bounds), "sorting avoids side hands: %s settled=%s seat=%d button=%s tile=%s" % [pixels, settled, seat, view._sort_button.get_rect(), bounds])
							t.expect(not view._seat_hud_rect(human).intersects(bounds), "own information also avoids the side players' hands")
				round.phase = RoundState.Phase.PLAYING
		view._show_native_settlement_notice("胡牌")
		var notice: Rect2 = view._settlement_notice.get_rect()
		t.expect(not notice.intersects(view._seat_hud_rect(posmod(view.human_seat + 2, 4))), "settlement stage text avoids the opposite player's name")
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("table_3d_review"))
