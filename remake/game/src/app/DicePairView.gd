extends SubViewportContainer
## The opening dice meshes, shown at the authoritative result without running physics again.
const Dice=preload("res://src/runtime/DiceRoll.gd")
const MotionConfig = preload("res://src/presentation/MotionConfig.gd")
var viewport: SubViewport
var values:=[1,1]
var dice:Array[Node3D]=[]
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	custom_minimum_size=Vector2(88,42);stretch=true
	viewport=SubViewport.new();viewport.size=Vector2i(176,84);viewport.own_world_3d=true
	viewport.transparent_bg=true
	apply_quality(MotionConfig.current_quality)
	add_child(viewport)
	var world:=Node3D.new();viewport.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.4
	world.add_child(environment)
	var lamp:=DirectionalLight3D.new();lamp.rotation_degrees=Vector3(-50,-25,0);world.add_child(lamp)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=0.75
	world.add_child(camera);camera.position=Vector3(1.3,2.8,2.2);camera.look_at(Vector3.ZERO)
	for index in 2:
		var die:=Node3D.new();world.add_child(die);die.add_child(Dice.create_visual(index==0))
		die.position=Vector3(-0.27 if index==0 else 0.27,0,0)
		die.basis=Basis(Quaternion(Dice.FACE_NORMALS[clampi(values[index],1,6)-1],Vector3.UP))
		dice.append(die)
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	resized.connect(func():viewport.render_target_update_mode=SubViewport.UPDATE_ONCE)

func apply_quality(value: String) -> void:
	var msaa: Viewport.MSAA = MotionConfig.value("fx", "decorative_msaa", Viewport.MSAA_DISABLED, value)
	if is_instance_valid(viewport) and viewport.msaa_3d != msaa:
		viewport.msaa_3d = msaa
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
