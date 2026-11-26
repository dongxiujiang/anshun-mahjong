extends SceneTree
const Profile = preload("res://src/presentation/TableLayoutProfile.gd")
const Table = preload("res://src/presentation/TableView.gd")
const Layout = preload("res://src/presentation/TableLayout.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL table size: " + message)
func _run() -> void:
	root.size = Vector2i(1600, 950)
	var profile := Profile.new()
	check(is_equal_approx(profile.data.regions["1/hand"].depth, 0.62), "default hand region retains true 0.62 thickness")
	check(profile.data.table_side == 36, "default table side is 36")
	var regions: Dictionary = profile.data.regions.duplicate(true)
	profile.data.table_side = 48
	check(profile.data.regions == regions, "table resize never moves or scales regions")
	var path := "user://resized-table-test.json"
	check(profile.save_file(path) == OK, "table size saves with the scheme")
	var restored := Profile.new()
	check(restored.load_file(path) and restored.data.table_side == 48, "table size survives reopening")
	DirAccess.remove_absolute(path)
	var old := restored.data.duplicate(true); old.erase("table_side")
	check(restored.accept(old) and restored.data.table_side == 24.5, "older saved schemes retain their original physical table size")
	var invalid := restored.data.duplicate(true); invalid.table_side = 1000
	check(not restored.accept(invalid) and restored.data.table_side == 24.5, "invalid table dimensions cannot overwrite an old scheme")
	var table := Table.new(false)
	table.custom_profile = profile
	root.add_child(table); await process_frame
	check(table.table_edge() == 24, "real game reads the same configured table edge")
	var surface: MeshInstance3D = table.get_node("PlayingSurface")
	check(surface.mesh.size.is_equal_approx(Vector3(48, 0.28, 48)), "actual game mesh expands with configured table side")
	for seat in 4:
		var rail: MeshInstance3D = table.get_node("Rail" + str(seat))
		check(is_equal_approx((Layout.facing(seat).inverse() * rail.position).z, 24.26), "all four wooden edges follow new table size")
	var corner := table.camera.unproject_position(Vector3(24, 0, 24))
	check(Rect2(Vector2.ZERO, root.get_visible_rect().size).has_point(corner), "game camera frames expanded table")
	table.free(); await process_frame
	print("%d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
