extends SubViewportContainer
## Render the game's actual classic tile, including its thickness and resin material.
const Art=preload("res://src/presentation/TileArt.gd")
const MotionConfig = preload("res://src/presentation/MotionConfig.gd")
var viewport: SubViewport
var value:="tiao1"
var tile:MeshInstance3D
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	custom_minimum_size=Vector2(76,88);stretch=true
	viewport=SubViewport.new();viewport.size=Vector2i(152,176);viewport.own_world_3d=true
	viewport.transparent_bg=true
	apply_quality(MotionConfig.current_quality)
	add_child(viewport)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.6
	viewport.add_child(environment)
	var lamp:=DirectionalLight3D.new();lamp.rotation_degrees=Vector3(-45,-35,0);lamp.light_energy=1.1;viewport.add_child(lamp)
	tile=MeshInstance3D.new();tile.mesh=Art.mesh(value);tile.material_override=Art.material(true);tile.rotation_degrees.x=90
	viewport.add_child(tile)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.05
	viewport.add_child(camera);camera.position=Vector3(1.8,1.35,4.4);camera.look_at(Vector3.ZERO)
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	resized.connect(func():viewport.render_target_update_mode=SubViewport.UPDATE_ONCE)

func apply_quality(value: String) -> void:
	var msaa: Viewport.MSAA = MotionConfig.value("fx", "decorative_msaa", Viewport.MSAA_DISABLED, value)
	if is_instance_valid(viewport) and viewport.msaa_3d != msaa:
		viewport.msaa_3d = msaa
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
