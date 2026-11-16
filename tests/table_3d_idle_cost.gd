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
	view._layout_arrangement_controls()
	var changes := [0]
	for node in [view._sort_button, view._restore_button, view._previous_sort_button, view._arrangement_caption]:
		node.theme_changed.connect(func(): changes[0] += 1)
	for frame in 10: view._layout_arrangement_controls()
	t.expect(changes[0] == 0, "unchanged bottom controls never invalidate their theme each frame")
	view._sort_button.add_theme_font_size_override("font_size", 18)
	view._layout_arrangement_controls()
	t.expect(view._sort_button.get_theme_font_size("font_size") == 24, "a changed control theme is still corrected")
	var renderer = view._table_3d
	var tile = view._tile(view._discard_layer, "wan1", true, G.CENTER, G.ORDINARY_UNIT, 0.0)
	tile.set_meta("new_kind", "ordinary")
	tile.set_meta("v2_seat", 0)
	tile.latest_highlight = true
	renderer.sync_tiles()
	t.expect(renderer.discard_marker.visible, "a new latest discard checks actual occlusion")
	var action: int = view._begin_visual_action()
	renderer._update_discard_marker(tile)
	t.expect(not renderer.discard_marker.visible, "pending actions hide a cached marker immediately")
	renderer._changed = false
	view._complete_visual_action(action, Callable())
	renderer._update_discard_marker(tile)
	t.expect(renderer.discard_marker.visible, "finished actions recheck occlusion before showing the marker")
	# Change a mesh directly without notifying the synchronizer to detect a repeated ray test.
	renderer.tile_nodes[tile.get_instance_id()].position.x += 100.0
	renderer._changed = false
	renderer._update_discard_marker(tile)
	t.expect(renderer.discard_marker.visible, "an unchanged table reuses its marker occlusion result")
	renderer._changed = true
	renderer._update_discard_marker(tile)
	t.expect(not renderer.discard_marker.visible, "a geometry change invalidates the cached result")
	renderer._changed = false
	renderer._update_discard_marker(null)
	t.expect(renderer._marker_source_id == 0 and not renderer.discard_marker.visible, "removing the latest discard clears its cached identity")
	view.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("table_3d_idle_cost"))
