extends SceneTree
const Art = preload("res://src/presentation/TileArt.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Geometry = preload("res://src/presentation/TileGeometry.gd")
const Profile = preload("res://src/presentation/TableLayoutProfile.gd")
const Placement = preload("res://src/presentation/RegionPlacement.gd")
const Layout = preload("res://src/presentation/TableLayout.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL geometry: " + message)
func _initialize() -> void:
	var values := Catalog.ordered_values()
	var unique := {}
	for value in values: unique[value] = true
	for value in unique:
		var real: AABB = Art.mesh(value).get_aabb()
		check(real.is_equal_approx(Geometry.BOUNDS), "measured geometry agrees with actual " + value + " mesh")
	check(Geometry.tile_bounds().size.is_equal_approx(Vector3(1, 0.62, 1.34)), "face-up width/thickness/length")
	check(Geometry.tile_bounds(90).size.is_equal_approx(Vector3(1, 1.34, 0.62)), "standing hand occupies width by thickness in top view")
	check(Geometry.tile_bounds(0, 90).size.is_equal_approx(Vector3(1.34, 0.62, 1)), "sideways tile exchanges length and width")
	check(Geometry.opposite_kong_bounds().size.is_equal_approx(Vector3(3, 0.62, 2.34)), "opposite-source kong uses the union of three face-up tiles and one sideways tile")
	for pair in [["hand", 0.62], ["draw", 0.62], ["wall", 1.34], ["discard", 1.34], ["public_front", 2.34], ["public_left", 2.34]]:
		check(is_equal_approx(Profile.default_depth(pair[0]), pair[1]), "type depth comes from actual stance: " + pair[0])
	check(is_equal_approx(Profile.default_depth("hand", 0), 1.34), "flat hand uses length rather than standing thickness")
	var real_vertices: PackedVector3Array = Art.mesh("wan1").surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for pitch in [0.0, 30.0, 63.0, 90.0]:
		var transform := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(pitch)), Vector3.ZERO)
		var footprint := Geometry.tile_bounds(pitch).grow(0.00001)
		var inside := true
		for vertex in real_vertices:
			if not footprint.has_point(transform * vertex): inside = false; break
		check(inside, "rotated physical mesh is fully covered at pitch " + str(pitch))
	var profile := Profile.new()
	var pack := Placement.new(profile)
	for seat in 4:
		for kind in ["hand", "draw", "discard", "wall"]:
			var pitch := 90.0 if kind in ["hand", "draw"] else 0.0
			var box := Geometry.tile_bounds(pitch)
			var target := pack.indexed(seat, kind, 0, box.size.x, box.size.z, box.size.y / 2, deg_to_rad(pitch), 1)
			check(not target.is_empty(), "default area fits its actual tile in every orientation")
			if target.is_empty(): continue
			var local: Transform3D = profile.region_pose(seat, kind).affine_inverse() * target.pose
			var row: Dictionary = profile.data.regions[Profile.key(seat, kind)]
			var fits := true
			for vertex in real_vertices:
				var p: Vector3 = local * vertex
				if p.x < -row.width / 2 - 0.00001 or p.x > row.width / 2 + 0.00001 or p.z < -row.depth - 0.00001 or p.z > 0.00001 or p.y < -0.00001: fits = false; break
			check(fits, "actual vertices fit default area and sit on the table")
	print("%d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
