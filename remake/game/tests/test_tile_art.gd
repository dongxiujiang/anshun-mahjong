extends SceneTree
const Art = preload("res://src/presentation/TileArt.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(label)

func _initialize() -> void:
	for suit in Catalog.SUITS:
		for number in range(1, 10):
			var value: String = suit + str(number)
			var mesh: Mesh = Art.mesh(value)
			var face: AtlasTexture = Art.face(value)
			check(mesh != null and mesh.get_aabb().size.is_equal_approx(Vector3(1, 0.62, 1.34)), "original mesh dimensions retained: " + value)
			check(face != null and face.region.size.x > 40 and face.region.size.y > 60, "complete original face UVs: " + value)
			check(Rect2(Vector2.ZERO, face.atlas.get_size()).encloses(face.region), "icon stays inside original artwork: " + value)
	check(Art.material(true).get_shader_parameter("printed") == true, "public faces use source artwork")
	check(Art.material(false).get_shader_parameter("printed") == false, "unknown hands never print source artwork")
	check(Art.face("unknown") == null, "invalid face cannot display another tile")
	var prepared:MeshLibrary=load(Art.ROOT+"tile_meshes.res")
	check(prepared.get_meta("source_sha256")==FileAccess.get_sha256(Art.ROOT+"tiles.glb"),"runtime mesh library matches the approved source")
	var source:Node3D=load(Art.ROOT+"tiles.glb").instantiate()
	for node in source.find_children("*","MeshInstance3D"):
		var mesh:Mesh=Art.mesh(str(node.name))
		check(mesh.get_surface_count()==node.mesh.get_surface_count(),"source surface count retained: "+str(node.name))
		for surface in mesh.get_surface_count():
			check(mesh.surface_get_arrays(surface)==node.mesh.surface_get_arrays(surface),"source vertices, normals and UVs retained exactly: "+str(node.name))
			check(mesh.surface_get_material(surface)==null,"unused imported material omitted: "+str(node.name))
	source.free()
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Art.ROOT + "provenance.json"))
	for file in provenance.files:
		check(FileAccess.get_sha256(Art.ROOT + file.file) == file.sha256, "source asset exact bytes: " + file.file)
	print("TileArt: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
