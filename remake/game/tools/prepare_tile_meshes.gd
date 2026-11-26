extends SceneTree
## Keep source geometry, but omit imported materials replaced by TileResin in play.
const ROOT="res://assets/tiles/classic/"
func _initialize()->void:
	var source:Node3D=load(ROOT+"tiles.glb").instantiate()
	var library:=MeshLibrary.new()
	library.set_meta("source_sha256",FileAccess.get_sha256(ROOT+"tiles.glb"))
	var index:=0
	for child in source.find_children("*","MeshInstance3D"):
		var mesh:ArrayMesh=child.mesh.duplicate()
		for surface in mesh.get_surface_count():mesh.surface_set_material(surface,null)
		library.create_item(index);library.set_item_name(index,str(child.name));library.set_item_mesh(index,mesh)
		index+=1
	var result:=ResourceSaver.save(library,ROOT+"tile_meshes.res")
	source.free()
	if result!=OK:printerr("Mesh library save failed: ",result);quit(1);return
	print("Prepared ",index," original tile meshes");quit()
