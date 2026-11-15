extends SceneTree
## 离线渲染圆角实体，游戏只读取贴图，不增加运行时三维场景或改变牌位。
const OUT := "res://res/tiles/materials3d"
const CREAM := Color("#eae8df")
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var model: Node3D

func _initialize() -> void: call_deferred("run")

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.36
	material.clearcoat_enabled = true
	material.clearcoat = 0.15
	material.clearcoat_roughness = 0.2
	return material

func _coordinates(half_size: float, radius: float) -> Array[float]:
	var inner := half_size - radius
	return [-half_size, -inner - radius * 0.75, -inner - radius * 0.5, -inner - radius * 0.25, -inner, 0.0, inner, inner + radius * 0.25, inner + radius * 0.5, inner + radius * 0.75, half_size]

func _rounded_box(dimensions: Vector3, radius: float, material: Material, front: Material = null) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var half_size := dimensions * 0.5
	var inner := half_size - Vector3.ONE * radius
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP, half_size.x, half_size.z, half_size.y],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.UP, half_size.x, half_size.z, half_size.y],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK, half_size.y, half_size.x, half_size.z],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD, half_size.y, half_size.x, half_size.z],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP, half_size.z, half_size.x, half_size.y],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, half_size.z, half_size.x, half_size.y]]
	for face in faces:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(front if front != null and face[0] == Vector3.BACK else material)
		var xs := _coordinates(face[4], radius)
		var ys := _coordinates(face[5], radius)
		for y in range(ys.size() - 1):
			for x in range(xs.size() - 1):
				for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(0, 1)]:
					var point: Vector3 = face[0] * face[3] + face[1] * xs[x + corner.x] + face[2] * ys[y + corner.y]
					var center := point.clamp(-inner, inner)
					var normal := (point - center).normalized()
					surface.set_normal(normal)
					surface.add_vertex(center + normal * radius)
		surface.commit(mesh)
	return mesh

func _set_model(mesh: Mesh) -> void:
	if is_instance_valid(model): model.free()
	model = Node3D.new()
	stage.add_child(model)
	var body := MeshInstance3D.new()
	body.mesh = mesh
	model.add_child(body)

func _snapshot() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.get_node("UpdateManager").auto_check = false
	DirAccess.make_dir_recursive_absolute(OUT)
	viewport = SubViewport.new()
	viewport.size = Vector2i(384, 512)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0, 0, 0, 0)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("#dce3d0")
	world.environment.ambient_light_energy = 0.55
	stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.light_color = Color("#fffdf7")
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-35, -30, 0)
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("#d9e8df")
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(25, 145, 0)
	stage.add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.42
	stage.add_child(camera)
	camera.make_current()
	var ivory := _material(CREAM)
	var green := _material(Color("#347b2e"))
	for back in [false, true]:
		_set_model(_rounded_box(Vector3(1, 1.333, 0.26), 0.09, ivory, green if back else null))
		for top in [false, true]:
			camera.position = Vector3(0, 1.3 if top else -1.3, 4.0)
			camera.look_at(Vector3.ZERO)
			var shot: Image = await _snapshot()
			var name := "%s-%s.png" % ["back" if back else "ivory", "top" if top else "bottom"]
			assert(shot.save_png(OUT.path_join(name)) == OK)
			print("[bake_materials3d] ", name)
	await _dice(ivory)
	print("[bake_materials3d] passed")
	quit()

func _dice(ivory: Material) -> void:
	viewport.size = Vector2i(256, 256)
	camera.size = 1.9
	camera.position = Vector3(3, 4.8, 5.5)
	camera.look_at(Vector3.ZERO)
	_set_model(_rounded_box(Vector3.ONE, 0.13, ivory))
	var shader := Shader.new()
	shader.code = """shader_type spatial;
uniform vec3 cream : source_color;
uniform vec3 ink : source_color;
uniform int number;
float mark(vec2 uv) {
 int bits = number == 1 ? 16 : number == 2 ? 257 : number == 3 ? 273 : number == 4 ? 325 : number == 5 ? 341 : 365;
 float h = 0.0;
 for (int y = 0; y < 3; y++) for (int x = 0; x < 3; x++) {
  if ((bits & (1 << (y * 3 + x))) != 0) {
   float d = length(uv - vec2(0.23 + float(x) * 0.27, 0.23 + float(y) * 0.27));
   h = max(h, 1.0 - smoothstep(0.075, 0.10, d));
  }
 }
 return h;
}
void fragment() {
 float h = mark(UV);
 vec2 gradient = vec2(mark(UV + vec2(0.002, 0.0)) - h, mark(UV + vec2(0.0, 0.002)) - h) * 12.0;
 ALBEDO = mix(cream, ink, h);
 NORMAL_MAP = normalize(vec3(gradient.x, -gradient.y, 1.0)) * 0.5 + 0.5;
 ROUGHNESS = mix(0.26, 0.55, h);
 SPECULAR = 0.5;
}"""
	var paints: Array[ShaderMaterial] = []
	var faces := [[1, Vector3.UP], [2, Vector3.BACK], [3, Vector3.RIGHT], [4, Vector3.LEFT], [5, Vector3.FORWARD], [6, Vector3.DOWN]]
	for face in faces:
		var plate := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.74, 0.74)
		plate.mesh = quad
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("cream", CREAM)
		material.set_shader_parameter("number", face[0])
		paints.append(material)
		plate.material_override = material
		var normal: Vector3 = face[1]
		plate.transform = Transform3D(Basis.looking_at(-normal, Vector3.FORWARD if absf(normal.y) > 0.5 else Vector3.UP), normal * 0.5005)
		model.add_child(plate)
	var rotations := [Quaternion.IDENTITY, Quaternion(Vector3.RIGHT, -PI / 2), Quaternion(Vector3.FORWARD, -PI / 2), Quaternion(Vector3.FORWARD, PI / 2), Quaternion(Vector3.RIGHT, PI / 2), Quaternion(Vector3.RIGHT, PI)]
	var atlas := Image.create(1536, 512, false, Image.FORMAT_RGBA8)
	for row in 2:
		for material in paints: material.set_shader_parameter("ink", Color("#b12420") if row == 0 else Color("#17392b"))
		for index in 6:
			model.quaternion = rotations[index]
			assert((model.basis * faces[index][1]).dot(Vector3.UP) > 0.99, "骰子顶面必须匹配点数")
			var shot: Image = await _snapshot()
			atlas.blit_rect(shot, Rect2i(0, 0, 256, 256), Vector2i(index * 256, row * 256))
	assert(atlas.save_png(OUT.path_join("dice-atlas.png")) == OK)
