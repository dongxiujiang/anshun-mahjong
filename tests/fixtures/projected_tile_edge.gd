extends RefCounted

static func near_top(renderer, tile: MeshInstance3D, outward: Vector3) -> PackedVector2Array:
	var tangent := Vector3.UP.cross(outward)
	var vertices: PackedVector3Array = tile.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var rim: Array[Vector3] = []
	var top_y := tile.mesh.get_aabb().end.y
	var edge_depth := -INF
	for vertex in vertices:
		if not is_equal_approx(vertex.y, top_y): continue
		var corner: Vector3 = tile.transform * vertex
		edge_depth = maxf(edge_depth, corner.dot(outward))
		rim.append(corner)
	var edge: Array[Vector3] = rim.filter(func(point): return absf(point.dot(outward) - edge_depth) < 0.0001)
	edge.sort_custom(func(a, b): return a.dot(tangent) < b.dot(tangent))
	var screen: Transform2D = renderer.get_global_transform_with_canvas()
	var scale: Vector2 = renderer.size / Vector2(renderer.viewport.size)
	return PackedVector2Array([
		screen * (renderer.camera.unproject_position(edge.front()) * scale),
		screen * (renderer.camera.unproject_position(edge.back()) * scale),
	])

static func pixel_offsets(reference: PackedVector2Array, edge: PackedVector2Array) -> Vector2:
	var tangent := reference[0].direction_to(reference[1])
	return Vector2(tangent.cross(edge[0] - reference[0]), tangent.cross(edge[1] - reference[0]))

static func nearest_meld(renderer, sources: Array, charge: PackedVector2Array, outward: Vector3) -> PackedVector2Array:
	var closest := INF
	var reference := PackedVector2Array()
	var center := (charge[0] + charge[1]) / 2.0
	for tile in sources:
		if tile.get_meta("meld_sideways", -1) >= 0: continue
		var edge := near_top(renderer, renderer.tile_nodes[tile.get_instance_id()], outward)
		var distance := center.distance_squared_to((edge[0] + edge[1]) / 2.0)
		if distance < closest:
			closest = distance
			reference = edge
	return reference

static func add_guides(parent: Node, reference: PackedVector2Array, edge: PackedVector2Array) -> CanvasLayer:
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	parent.add_child(overlay)
	var tangent := reference[0].direction_to(reference[1])
	var first := (edge[0] - reference[0]).dot(tangent)
	var last := (edge[1] - reference[0]).dot(tangent)
	var start := reference[0] + tangent * (minf(0.0, minf(first, last)) - 20.0)
	var finish := reference[0] + tangent * (maxf(reference[0].distance_to(reference[1]), maxf(first, last)) + 20.0)
	for guide in [
		[PackedVector2Array([start, finish]), Color(0.18, 0.89, 1.0, 0.75)],
		[reference, Color(0.18, 0.89, 1.0)],
		[edge, Color(1.0, 0.77, 0.20)],
	]:
		var line := Line2D.new()
		line.points = guide[0]
		line.default_color = guide[1]
		line.width = 2.0
		line.antialiased = true
		overlay.add_child(line)
	return overlay
