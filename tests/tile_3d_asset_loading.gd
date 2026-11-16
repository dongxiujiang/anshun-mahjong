extends SceneTree
const H := preload("res://tests/test_harness.gd")
var t := H.new()
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("UpdateManager").auto_check = false
	var tile = load("res://scripts/ui/TileView.gd").new()
	tile.presentation_3d = true
	root.add_child(tile)
	tile._draw()
	for path in ["backs-atlas.png", "materials3d/hand-faces.png", "materials3d/flat-faces.png",
			"materials3d/standing-right.png", "materials3d/standing-north.png", "materials3d/standing-left.png",
			"materials3d/back-top.png", "materials3d/back-bottom.png"]:
		t.expect(not ResourceLoader.has_cached("res://res/tiles/" + path), "a 3D tile does not retain unused 2D artwork: " + path)
	tile.queue_free()
	await process_frame
	await H.quit_cleanly(self, t.finish("tile_3d_asset_loading"))
