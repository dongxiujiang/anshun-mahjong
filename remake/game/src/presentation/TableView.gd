extends Node3D
## Runtime world for both play and player previews. All private information enters through a seat-filtered view.
const Profile = preload("res://src/presentation/TableLayoutProfile.gd")
const Regions = preload("res://src/presentation/RegionPlacement.gd")
const LAYOUT_PATH := "res://assets/layouts/table-layout.json"
const Geometry = preload("res://src/presentation/TileGeometry.gd")
const Layout = preload("res://src/presentation/TableLayout.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
const Wall = preload("res://src/domain/Wall.gd")
const Seats = preload("res://src/domain/Seats.gd")
const TileArt = preload("res://src/presentation/TileArt.gd")
const TableTheme = preload("res://src/presentation/TableTheme.gd")
const DiceRoll = preload("res://src/runtime/DiceRoll.gd")
const FELT_SHADER = preload("res://src/presentation/TableFelt.gdshader")
const TILE_BOUNDS := Geometry.BOUNDS
const DIE_BOUNDS := AABB(-Vector3.ONE * DiceRoll.SIDE * 0.5, Vector3.ONE * DiceRoll.SIDE)
const Pace = preload("res://src/presentation/GamePace.gd")
const MOVE_SECONDS := Pace.ACTION_SECONDS
const ADDED_KONG_SECONDS := Pace.ACTION_SECONDS
const OpeningDeal = preload("res://src/presentation/OpeningDeal.gd")
# Candidate input timing and tolerance are presentation parameters.
const HOLD_SECONDS := 0.30
const DRAG_SHIFT_SECONDS := 0.11
const DRAG_SETTLE_SECONDS := 0.12
const HAND_TOLERANCE := 1.5
const TAP_SLOP := 14.0
const OWN_HAND_FORWARD_SHIFT := 3.65
# The face-up tile's near corner sits lower, so it needs less Z offset on screen.
const OWN_HAND_FLAT_FORWARD_SHIFT := 3.00
const OPPOSITE_REVEAL_OUTWARD_SHIFT := 0.45

signal tile_clicked(tile_id: int)
signal blank_tapped()
signal wall_center_requested(seat: int)
signal drag_started(tile_id: int)
signal drag_slot_changed(slot: int)
signal drag_finished(slot: int)
signal hand_drag_position(position: Array)
signal swipe_discard(tile_id: int)
signal discard_drag_state_changed(active: bool, ready_to_release: bool)
signal presentation_finished(prompt_id: int)
signal hand_stability_changed()
signal layout_conflict(seat: int, group: String)

var layout := Layout.new()
var custom_profile
var region_placement
var camera := Camera3D.new()
var frame_camera_enabled := true
var _key_light: DirectionalLight3D
var _rim_light: DirectionalLight3D
var _reflection_probe: ReflectionProbe
var _felt_material: ShaderMaterial
var _wood_material: StandardMaterial3D
var _trim_material: StandardMaterial3D
var _corner_material: StandardMaterial3D
var _table_theme_id := "jade_classic"
var _tile_back_id := "jade"
var _match_highlight_value := ""
var _hint_tile_id := -1
var _hint_tile_ids := {}
var _chicken_highlight_ids := {}
var _shake_amount := 0.0
var _shake_time := 0.0
var _camera_base_pos := Vector3.ZERO
var quality := "smooth"
var tiles := {} # Known tiles use physical IDs. Hidden hands and hidden kongs use opaque, seat-local slots.
var viewer := 1
var _safe_insets := Vector4.ZERO
var flat_hands := false
var view := {}
var hand_order := {}
var _destinations := {}
var _motions := {}
var _seen := {}
var _selectable := {}
var _hand_slots := {}
var _discard_marker := MeshInstance3D.new()
var _felt_obstacles: Array[MeshInstance3D] = []
var _pending_prompt := -1
var _prompt_motions := {}
var _opening: OpeningDeal
var _deal_start := {}
var _press_id := -1
var _press_play_prompt := -1
var _press_began_stable := false
var _press_was_selected := false
var _pointer := -2
var _press_point := Vector2.ZERO
var _pointer_point := Vector2.ZERO
var _dragging := false
var _discard_dragging := false
var _drag_from_hold := false
var _hold_drag_moved := false
var _hold_tap_confirms := false
var _drag_hint_active := false
var _drag_hint_ready := false
var _last_drag_slot := -1
var _carry_offset := Vector3.ZERO
var _settling_id := -1
var _blank_moved := false
var _hold: Tween
var _reconciled_prompt := -1
var _draw_source := -1
var _retired_backs := {}
var _last_insert_discard := -1
var _insertion_tile := -1
var _shared_motion_tokens := {}
var _adding_kong := []
var _supplement_after_landing := {}
var _badges := {}
var _badge_seen := {}
var _marker_origin:=Vector3.ZERO
var _marker_time:=0.0
var _use_saved_layout:=true
var _framed_profile
var _wall_pose_cache:={}
var _wall_pose_signature:=[]
var _hand_anchor_cache := {}
var _hand_anchor_profile
var _ripple_mesh: TorusMesh

func _init(use_saved_layout: bool=true) -> void:
	_use_saved_layout=use_saved_layout
var _hand_was_stable := true

func _ready() -> void:
	if _use_saved_layout and custom_profile == null and FileAccess.file_exists(LAYOUT_PATH):
		var candidate := Profile.new()
		if candidate.load_file(LAYOUT_PATH):
			custom_profile = candidate
			region_placement = Regions.new(candidate)
		else: push_warning(candidate.error)
	if custom_profile and region_placement == null: region_placement=Regions.new(custom_profile)
	_build_table()
	add_child(camera)
	camera.current = true
	camera.far = 130.0
	get_viewport().size_changed.connect(_frame_camera)
	_frame_camera()
	_render(false)
	visibility_changed.connect(func(): _sync_process_state())

func _sync_process_state() -> void:
	set_process(is_visible_in_tree() and (_discard_marker.visible or _shake_amount > 0.001))

func _build_table() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#0e211d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#fff6e4")
	environment.ambient_light_energy = 0.56
	camera.environment = environment
	_felt_material = ShaderMaterial.new()
	_felt_material.shader = FELT_SHADER
	_felt_material.set_shader_parameter("half_side", table_edge())
	_box("PlayingSurface", Vector3(0, -0.14, 0), Vector3(table_edge() * 2, 0.28, table_edge() * 2), _felt_material)
	_wood_material = StandardMaterial3D.new()
	_wood_material.albedo_color = Color("#4d2f1c")
	_wood_material.roughness = 0.44
	_wood_material.metallic = 0.04
	_trim_material = StandardMaterial3D.new()
	_trim_material.albedo_color = Color("#b48f52")
	_trim_material.roughness = 0.32
	_trim_material.metallic = 0.65
	_corner_material = StandardMaterial3D.new()
	_corner_material.albedo_color = Color("#d1af68")
	_corner_material.roughness = 0.28
	_corner_material.metallic = 0.78
	var edge := table_edge()
	for seat in 4:
		var facing := Layout.facing(seat)
		var rail := _box("Rail" + str(seat), facing * Vector3(0, -0.16, edge + 0.26), Vector3(edge * 2 + 1.04, 0.42, 0.52), _wood_material)
		rail.basis = facing
		_felt_obstacles.append(rail)
		var inlay := _box("Inlay" + str(seat), facing * Vector3(0, 0.056, edge + 0.36), Vector3(edge * 2 + 0.70, 0.012, 0.036), _trim_material)
		inlay.basis = facing
		_felt_obstacles.append(inlay)
		var cap_a := _box("CornerA" + str(seat), facing * Vector3(edge + 0.28, 0.058, edge - 0.36), Vector3(0.54, 0.022, 1.32), _corner_material)
		cap_a.basis = facing
		cap_a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cap_b := _box("CornerB" + str(seat), facing * Vector3(edge - 0.36, 0.058, edge + 0.28), Vector3(1.32, 0.022, 0.54), _corner_material)
		cap_b.basis = facing
		cap_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-61, -30, 0)
	key.light_energy = 0.52
	key.shadow_opacity = 0.36
	key.shadow_blur = 1.35
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 42.0
	add_child(key)
	_key_light = key
	_rim_light = DirectionalLight3D.new()
	_rim_light.rotation_degrees = Vector3(-38, 135, 0)
	_rim_light.light_color = Color("#fff0d4")
	_rim_light.light_energy = 0.22
	_rim_light.shadow_enabled = false
	_rim_light.visible = quality == "detail"
	add_child(_rim_light)
	apply_quality(quality)
	apply_theme(_table_theme_id, _tile_back_id)
	var pointer_mesh := CylinderMesh.new()
	pointer_mesh.top_radius = 0.22
	pointer_mesh.bottom_radius = 0.0
	pointer_mesh.height = 0.46
	pointer_mesh.radial_segments = 16
	var color := StandardMaterial3D.new()
	color.albedo_color = Color("#ffbd1f")
	color.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	color.emission_enabled = true
	color.emission = Color("#ff9b16")
	color.emission_energy_multiplier = 0.85
	pointer_mesh.material = color
	_discard_marker.mesh = pointer_mesh
	_discard_marker.visible = false
	add_child(_discard_marker)
	var halo := MeshInstance3D.new()
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.16
	halo_mesh.outer_radius = 0.24
	halo_mesh.rings = 16
	halo_mesh.ring_segments = 8
	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color = Color("#ffe39a")
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.emission_enabled = true
	halo_mat.emission = Color("#ffc857")
	halo_mat.emission_energy_multiplier = 0.9
	halo_mesh.material = halo_mat
	halo.mesh = halo_mesh
	halo.position.y = 0.24
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_discard_marker.add_child(halo)
	var glow := MeshInstance3D.new()
	var glow_mesh := QuadMesh.new(); glow_mesh.size = Vector2(1.05, 1.05); glow.mesh = glow_mesh
	var gradient := Gradient.new(); gradient.colors = PackedColorArray([Color(1, 0.72, 0.14, 0.42), Color(1, 0.65, 0.06, 0)])
	var texture := GradientTexture2D.new(); texture.gradient = gradient; texture.width = 32; texture.height = 32; texture.fill = GradientTexture2D.FILL_RADIAL; texture.fill_from = Vector2(0.5, 0.5); texture.fill_to = Vector2(1, 0.5)
	var glow_material := StandardMaterial3D.new(); glow_material.albedo_texture = texture; glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow.material_override = glow_material; glow.position.y = 0.08; glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _discard_marker.add_child(glow)
	_felt_obstacles.append(_discard_marker)

func apply_theme(table_theme_id: String, tile_back_id: String = "") -> void:
	_table_theme_id = table_theme_id if TableTheme.TABLE_THEMES.has(table_theme_id) else "jade_classic"
	if not tile_back_id.is_empty():
		_tile_back_id = tile_back_id if TableTheme.TILE_BACKS.has(tile_back_id) else "jade"
	TileArt.apply_back_theme(_tile_back_id)
	var spec: Dictionary = TableTheme.table_data(_table_theme_id)
	if camera.environment:
		camera.environment.background_color = spec.bg
		camera.environment.ambient_light_color = spec.ambient
		camera.environment.ambient_light_energy = spec.ambient_energy
	if is_instance_valid(_key_light):
		_key_light.light_color = spec.key_color
		_key_light.light_energy = spec.key_energy
	if _felt_material != null:
		_felt_material.set_shader_parameter("felt_center", spec.felt_center)
		_felt_material.set_shader_parameter("felt_edge", spec.felt_edge)
		_felt_material.set_shader_parameter("trim_gold", spec.trim_gold)
		_felt_material.set_shader_parameter("half_side", table_edge())
	if _wood_material != null:
		_wood_material.albedo_color = spec.wood
		_wood_material.roughness = spec.wood_roughness
	if _trim_material != null:
		_trim_material.albedo_color = spec.inlay
	if _corner_material != null:
		_corner_material.albedo_color = spec.corner_metal
	apply_quality(quality)

func pulse_table_shake(intensity: float = 0.14) -> void:
	_shake_amount = maxf(_shake_amount, clampf(intensity, 0.0, 0.35))
	_shake_time = 0.0
	_sync_process_state()

func _spawn_landing_ripple(world_pos: Vector3, color: Color = Color("#ffd575"), scale_mult: float = 1.0) -> void:
	if not is_visible_in_tree():
		return
	if _ripple_mesh == null:
		_ripple_mesh = TorusMesh.new()
		_ripple_mesh.inner_radius = 0.42
		_ripple_mesh.outer_radius = 0.54
		_ripple_mesh.rings = 20
		_ripple_mesh.ring_segments = 6
	var ring := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.15
	ring.mesh = _ripple_mesh
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = Vector3(world_pos.x, 0.028, world_pos.z)
	ring.scale = Vector3(0.45 * scale_mult, 0.12, 0.45 * scale_mult)
	add_child(ring)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(1.55 * scale_mult, 0.05, 1.55 * scale_mult), 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(a: float):
		mat.albedo_color.a = a
		mat.emission_energy_multiplier = a * 1.15, 0.72, 0.0, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(ring.queue_free)

func set_match_highlight(tile_value: String) -> void:
	if _match_highlight_value == tile_value:
		return
	_match_highlight_value = tile_value
	_refresh_tile_highlights()

func set_hint_tile(tile_id: int) -> void:
	var previous := _hint_tile_id
	_hint_tile_id = tile_id
	var ids := {tile_id: true} if tile_id >= 0 else {}
	if _hint_tile_ids != ids or previous != tile_id:
		_hint_tile_ids = ids
		_refresh_tile_highlights()

func set_hint_tiles(tile_ids: Array) -> void:
	var ids := {}
	for id in tile_ids:
		if int(id) >= 0:
			ids[int(id)] = true
	_hint_tile_id = int(tile_ids[0]) if tile_ids.size() == 1 else -1
	if _hint_tile_ids != ids:
		_hint_tile_ids = ids
		_refresh_tile_highlights()

func set_chicken_highlights(tile_ids: Array) -> void:
	_chicken_highlight_ids.clear()
	for id in tile_ids:
		_chicken_highlight_ids[int(id)] = true
	_refresh_tile_highlights()

func clear_chicken_highlights() -> void:
	if _chicken_highlight_ids.is_empty():
		return
	_chicken_highlight_ids.clear()
	_refresh_tile_highlights()

func _refresh_tile_highlights() -> void:
	for key in tiles:
		var node: MeshInstance3D = tiles[key]
		if not is_instance_valid(node):
			continue
		var value: String = str(node.get_meta("value", ""))
		if not Catalog.valid_value(value):
			continue
		var zone: String = str(node.get_meta("zone", ""))
		if key is int and _chicken_highlight_ids.has(key):
			node.material_override = TileArt.highlight_material("chicken")
		elif not _match_highlight_value.is_empty() and value == _match_highlight_value and zone in ["discard", "chicken", "meld"]:
			node.material_override = TileArt.highlight_material("match")
		elif key is int and (_hint_tile_ids.has(key) or key == _hint_tile_id) and zone == "hand":
			node.material_override = TileArt.highlight_material("hint")
		else:
			node.material_override = _material(value)

func _process(delta: float) -> void:
	_marker_time += delta
	if _discard_marker.visible:
		_discard_marker.position = _marker_origin + Vector3.UP * sin(_marker_time * 3.8) * 0.11
		_discard_marker.rotation.y = _marker_time * 1.35
	if _shake_amount > 0.001:
		_shake_time += delta
		var decay := exp(-_shake_time * 22.0)
		var amp := _shake_amount * decay
		if amp < 0.002 or _shake_time > 0.22:
			_shake_amount = 0.0
			camera.position = _camera_base_pos
			_sync_process_state()
		else:
			var offset := camera.basis * Vector3(sin(_shake_time * 68.0) * amp * 0.45, cos(_shake_time * 82.0) * amp, 0.0)
			camera.position = _camera_base_pos + offset

func _box(label: String, center: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.position = center
	add_child(node)
	return node

func set_safe_insets(insets: Vector4) -> void:
	_safe_insets = insets
	_frame_camera()

func apply_quality(value: String) -> void:
	quality = "detail" if value == "detail" else "smooth"
	var detailed := quality == "detail"
	var spec: Dictionary = TableTheme.table_data(_table_theme_id)
	if is_instance_valid(_key_light):
		_key_light.shadow_enabled = detailed
		_key_light.shadow_opacity = 0.36
		_key_light.shadow_blur = 1.35
		_key_light.directional_shadow_max_distance = 42.0
		_key_light.light_energy = spec.key_energy * (1.06 if detailed else 1.0)
	if is_instance_valid(_rim_light):
		_rim_light.visible = detailed
	if _felt_material != null:
		_felt_material.set_shader_parameter("detail_mode", 1.0 if detailed else 0.0)
	if _wood_material != null:
		_wood_material.clearcoat_enabled = detailed
		_wood_material.clearcoat = 0.42 if detailed else 0.0
		_wood_material.roughness = 0.28 if detailed else spec.wood_roughness
	if _trim_material != null:
		_trim_material.roughness = 0.18 if detailed else 0.32
	if _corner_material != null:
		_corner_material.roughness = 0.14 if detailed else 0.28
	TileArt.apply_quality(quality)
	if camera.environment:
		camera.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED if quality == "smooth" else Environment.REFLECTION_SOURCE_BG
		camera.environment.tonemap_mode = Environment.TONE_MAPPER_ACES if detailed else Environment.TONE_MAPPER_LINEAR
		# Reserve highlight headroom for the glaze under Compatibility's ACES curve.
		camera.environment.tonemap_white = 2.4 if detailed else 1.0
		camera.environment.tonemap_exposure = 0.96 if detailed else 1.0
		camera.environment.ambient_light_energy = spec.ambient_energy * (0.96 if detailed else 1.0)

func _frame_camera() -> void:
	if not frame_camera_enabled or not camera.is_inside_tree():
		return
	_framed_profile=custom_profile
	var facing := Layout.facing(viewer)
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x < 2 or viewport_size.y < 2: return
	var aspect := maxf(0.1, viewport_size.aspect())
	var pitch: float=custom_profile.data.presentation.camera_pitch if custom_profile else 34.92
	if custom_profile: pitch=rad_to_deg(asin(clampf(sin(deg_to_rad(pitch))*minf(1.0,pow((16.0/9.0)/aspect,0.75)),sin(deg_to_rad(20.0)),sin(deg_to_rad(75.0)))))
	# A longer lens reduces near/far size disparity while framing the same physical table.
	var distance:=maxf(180,table_edge()*14.4) if custom_profile else maxf(60,table_edge()*4.8)
	camera.far=maxf(130,distance+table_edge()*3)
	camera.position = facing * Vector3(0, sin(deg_to_rad(pitch))*distance, cos(deg_to_rad(pitch))*distance)
	_camera_base_pos = camera.position
	camera.look_at(Vector3.ZERO)
	if custom_profile:
		_frame_saved_table(facing,viewport_size,aspect)
		_camera_base_pos = camera.position
		return
	var usable_x := maxf(0.1, 1.0 - 2 * maxf(_safe_insets.x, _safe_insets.z) / maxf(1, viewport_size.x))
	var usable_y := maxf(0.1, 1.0 - 2 * maxf(_safe_insets.y, _safe_insets.w) / maxf(1, viewport_size.y))
	var half_extent := 0.0
	for x in [-table_edge(), table_edge()]:
		for z in [-table_edge(), table_edge()]:
			for y in [0.0, Layout.LONG]:
				var p := camera.to_local(Vector3(x, y, z))
				half_extent = maxf(half_extent, maxf(absf(p.y) / usable_y, absf(p.x) / (aspect * usable_x)) / -p.z)
	camera.fov = rad_to_deg(2.0 * atan(half_extent * 1.045))

func _frame_saved_table(facing: Basis, viewport_size: Vector2, aspect: float) -> void:
	var points: Array[Vector3]=[]
	var edge:=table_edge()+0.52
	for x in [-edge,edge]:
		for z in [-edge,edge]:
			for y in [-0.37,0.062]:points.append(Vector3(x,y,z))
	var frame_points:=points.size()
	for seat in 4:
		for kind in ["hand","wall"]:
			for key in custom_profile.region_keys(seat,kind):
				var row: Dictionary=custom_profile.data.regions[key]
				if not row.visible:continue
				var pose:Transform3D=custom_profile.region_pose(seat,kind,key)
				var own:bool=seat==viewer and kind!="wall"
				var bounds:=Geometry.tile_bounds(float(custom_profile.data.presentation.get("self_hand_pitch",custom_profile.data.presentation.hand_pitch)) if own else float(custom_profile.data.presentation.hand_pitch))
				var height:float=(2*Layout.THICK if kind=="wall" else bounds.size.y)*row.scale
				var depth:float=maxf(row.depth,bounds.size.z*row.scale) if own else row.depth
				for x in [-row.width*0.5,row.width*0.5]:
					for z in [-depth,0.0]:
						for y in [0.0,height]:
							var point:Vector3=pose*Vector3(x,y,z)
							if own: points.append(_magnify_own_hand(Transform3D(Basis.IDENTITY,point),seat,false).origin)
							if own:point=_magnify_own_hand(Transform3D(Basis.IDENTITY,point),seat,true).origin
							points.append(point)
							if own: points.append(point + Vector3.UP * 0.56)
		var extension := _hand_extension(seat,13)
		if not extension.is_empty():
			for pitch in [0.0,float(custom_profile.data.presentation.get("self_hand_pitch",custom_profile.data.presentation.hand_pitch) if seat==viewer else custom_profile.data.presentation.hand_pitch)]:
				var pose := _pitch_hand(extension.pose,pitch)
				if seat==viewer:pose=_magnify_own_hand(pose,seat,pitch != 0.0)
				for corner in 8:points.append(pose*Geometry.BOUNDS.get_endpoint(corner))
		if view.get("phase", "") == "settled":
			var bounds := Geometry.tile_bounds(float(custom_profile.data.presentation.hand_pitch))
			for index in 14:
				var placement: Dictionary = _hand_extension(seat,13) if index == 13 else region_placement.indexed(seat,"hand",index,bounds.size.x,bounds.size.z,bounds.size.y*0.5,deg_to_rad(float(custom_profile.data.presentation.hand_pitch)),13)
				if placement.is_empty(): continue
				var pose := _settlement_hand(placement.pose, seat)
				for corner in 8: points.append(pose*Geometry.BOUNDS.get_endpoint(corner))
	var top:=maxf(0.1,1-2*_safe_insets.y/maxf(1,viewport_size.y))
	var bottom:=maxf(0.1,1-2*_safe_insets.w/maxf(1,viewport_size.y))
	var left:=maxf(0.1,1-2*_safe_insets.x/maxf(1,viewport_size.x))
	var right:=maxf(0.1,1-2*_safe_insets.z/maxf(1,viewport_size.x))
	# The wooden frame may fill the display; tiles keep the phone's safe margins.
	var frame_x:=maxf(0.1,1-8/maxf(1,viewport_size.x))
	var frame_y:=maxf(0.1,1-8/maxf(1,viewport_size.y))
	var low:=-table_edge()*0.5;var high:=table_edge()*0.5
	# Center the projected table envelope; aiming at the geometric center leaves a large top margin.
	for iteration in 18:
		var middle:float=(low+high)*0.5
		camera.look_at(facing*Vector3(0,0,middle))
		var up:=0.0;var down:=0.0
		for i in points.size():
			var p:=camera.to_local(points[i])
			up=maxf(up,p.y/-p.z/(frame_y if i<frame_points else top));down=maxf(down,-p.y/-p.z/(frame_y if i<frame_points else bottom))
		if up<down:low=middle
		else:high=middle
	var extent:=0.0
	for i in points.size():
		var p:=camera.to_local(points[i])
		var limit_y:=frame_y if i<frame_points else (top if p.y>0 else bottom)
		var limit_x:=frame_x if i<frame_points else (right if p.x>0 else left)
		extent=maxf(extent,maxf(absf(p.y)/limit_y,absf(p.x)/(aspect*limit_x))/-p.z)
	camera.fov=rad_to_deg(2*atan(extent*1.005))

func set_viewer(seat: int) -> void:
	if seat not in range(4):
		return
	viewer = seat
	_frame_camera()
	# A camera switch by itself must never expose the previous player's private faces.
	if not view.is_empty() and int(view.get("viewer_seat", seat)) != seat:
		hand_order.clear()
		_render(false)

func set_flat_hands(flat: bool) -> void:
	if flat_hands == flat:
		return
	flat_hands = flat
	_render(_opening != null)

func set_hand_order(order_view: Dictionary) -> void:
	if order_view == hand_order:
		return
	_accept_hand_order(order_view)
	if not view.is_empty() and view.get("phase") != "dealt":
		_render(view.get("phase") != "settled")
	_insertion_tile = -1

func _accept_hand_order(order_view: Dictionary) -> void:
	hand_order = order_view.duplicate(true)
	var plan: Dictionary = hand_order.get("insertion", {})
	var discard: int = plan.get("discard_id", -1)
	if discard != -1 and discard != _last_insert_discard:
		_last_insert_discard = discard
		_insertion_tile = int(plan.get("tile_id", -1))

func show_full_wall(seat: int) -> void:
	if view.get("phase") == "full_wall" and viewer == seat:
		return
	apply_view({})
	set_viewer(seat)
	view = {"viewer_seat": seat, "phase": "full_wall", "players": [], "wall_slots": range(Wall.COUNT)}
	_render(false)

func apply_view(round_view: Dictionary, display_order: Dictionary = {}) -> void:
	if custom_profile and (region_placement == null or region_placement.profile != custom_profile): region_placement = Regions.new(custom_profile)
	_refresh_wall_pose_cache(round_view.get("wall_offsets",[]))
	var old := view
	var next_phase: String = round_view.get("phase", "")
	var prompt: int = round_view.get("prompt_id", -1)
	if _opening:
		if next_phase in ["", "settled"] or int(round_view.get("viewer_seat", viewer)) != viewer or (next_phase != "dealt" and not _opening.ready_for_draw()):
			_cancel_opening()
		elif next_phase != "dealt":
			for seat in _opening.tracks.keys():
				var before: Dictionary = old.players[seat]
				var after: Dictionary = round_view.players[seat]
				if before.hand_count != after.hand_count or before.get("has_draw") != after.get("has_draw"):
					for key in _opening.keys:
						if _opening.keys[key] == seat:
							_destinations.erase(key)
					_opening.tracks[seat].kill()
					_opening.release_seat(seat)
			if _opening.tracks.is_empty():
				_opening = null
	if next_phase.is_empty():
		_cancel_press()
		layout = Layout.new()
		if custom_profile: region_placement = Regions.new(custom_profile)
		hand_order = {}
		_reconciled_prompt = -1
		_last_insert_discard = -1
		_insertion_tile = -1
		_shared_motion_tokens.clear()
		_deal_start.clear()
		_pending_prompt = -1
		_prompt_motions.clear()
		_supplement_after_landing.clear()
	view = round_view
	if not view.is_empty():
		var seat: int = view.get("viewer_seat", viewer)
		var needs_framing:bool=seat!=viewer or old.is_empty() or _framed_profile!=custom_profile or (old.get("phase", "") == "settled") != (next_phase == "settled")
		var old_rows: Array = old.get("players", [])
		var new_rows: Array = view.get("players", [])
		var same_hand: bool = seat == viewer and old_rows.size() == 4 and new_rows.size() == 4 and old_rows[seat].hand == new_rows[seat].hand and old_rows[seat].draw_id == new_rows[seat].draw_id
		if not same_hand or next_phase == "settled":
			var was_dragging := _dragging
			_cancel_press()
			hand_order = {}
			if was_dragging:
				drag_finished.emit(-1)
		elif old.get("prompt_id", -1) != prompt and not _dragging:
			_cancel_press()
		viewer = seat
		if needs_framing:_frame_camera()
	if not display_order.is_empty():
		_accept_hand_order(display_order)
	var dealing: bool = next_phase == "dealt" and old.get("phase", "") == "full_wall"
	var groups := _prepare_deal() if dealing else []
	_draw_source = -1
	if not old.is_empty() and not view.is_empty() and next_phase != "dealt":
		var previous: Array = old.get("wall_slots", [])
		var current: Array = view.get("wall_slots", [])
		if previous.size() == current.size() + 1:
			for id in previous:
				if not current.has(id):
					_draw_source = int(id)
					break
	if _draw_source >= 0 and int(view.get("turn", -1)) in range(4) and old.get("players", []).size() == 4:
		var seat: int = view.turn
		var before: Dictionary = old.players[seat]
		var after: Dictionary = view.players[seat]
		for i in mini(before.melds.size(), after.melds.size()):
			if before.melds[i].kind == "pung" and after.melds[i].kind == "add_kong":
				_adding_kong = after.melds[i].tile_ids
				if seat != viewer:
					var back = before.get("display", {}).get("draw", _hidden_key(seat, int(before.hand_count) - 1))
					if tiles.has(back): _reuse_source(back, _adding_kong.back())
				break
	_render((dealing or not old.is_empty()) and next_phase not in ["settled", ""])
	if not _adding_kong.is_empty():
		var seat: int = view.turn
		var row: Dictionary = view.players[seat]
		var draw_key = row.draw_id if viewer == seat else row.get("display", {}).get("draw", _hidden_key(seat, int(row.hand_count) - 1))
		var fourth: int = _adding_kong.back()
		if _motions.has(fourth) and _motions.has(draw_key):
			_supplement_after_landing = {"id": fourth, "landing": _motions[fourth], "draw": _motions[draw_key]}
			_supplement_after_landing.draw.pause()
		_adding_kong = []
	_insertion_tile = -1
	if dealing:
		_opening = OpeningDeal.new()
		_opening.progress.connect(_opening_progress)
		_opening.play(self, groups, _destinations)
	_deal_start.clear()
	_draw_source = -1
	if prompt >= 0 and prompt != _reconciled_prompt and is_inside_tree():
		_reconciled_prompt = prompt
		_pending_prompt = prompt
		_prompt_motions = _motions.duplicate()
	_check_presentation.call_deferred()

func _cancel_opening() -> void:
	if _opening:
		for key in _opening.keys:
			_destinations.erase(key)
		_opening.cancel()
		_opening = null

func _opening_progress(seat: int, sorted: bool) -> void:
	if sorted:
		if _opening.tracks.is_empty():
			_opening = null
		# Reconcile changes to the shared order or posture received during pickup.
		var changed := false
		for key in tiles:
			var node: MeshInstance3D = tiles[key]
			if node.get_meta("zone") == "hand" and node.get_meta("seat", -1) == seat and not node.transform.is_equal_approx(_destinations[key]):
				_destinations.erase(key)
				changed = true
		if changed:
			_render(true)
			if view.phase == "dealt" and seat == int(view.dealer):
				for key in _motions:
					if tiles[key].get_meta("seat", -1) == seat:
						_prompt_motions[key] = _motions[key]
	_check_presentation.call_deferred()

func _check_presentation() -> void:
	_update_hand_stability()
	if not _supplement_after_landing.is_empty() and _motions.get(_supplement_after_landing.id) != _supplement_after_landing.landing:
		if _supplement_after_landing.draw.is_valid(): _supplement_after_landing.draw.play()
		_supplement_after_landing.clear()
	if _pending_prompt < 0 or _pending_prompt != int(view.get("prompt_id", -1)):
		return
	if view.phase == "dealt" and _opening and not _opening.ready_for_draw():
		return
	for key in _prompt_motions:
		if _motions.get(key) == _prompt_motions[key]:
			return
	var prompt := _pending_prompt
	_pending_prompt = -1
	_prompt_motions.clear()
	presentation_finished.emit(prompt)

func _prepare_deal() -> Array:
	var groups := []
	var wall := Wall.new(Catalog.ordered_values())
	var dealer: int = view.dealer
	var styles: Array = view.get("deal_styles", [])
	wall.open(dealer, int(view.red))
	var counts := [0, 0, 0, 0]
	for amount in [4, 4, 4, 1]:
		var seat := dealer
		for turn_in_pass in 4:
			var cards := []
			var deal_keys: Array = view.players[seat].get("display", {}).get("deal_keys", [])
			for offset in amount:
				var id := wall.take_head()
				var key = id if seat == viewer else _hidden_key(seat, counts[seat])
				if seat != viewer and deal_keys.size() > counts[seat]:
					key = deal_keys[counts[seat]]
				_deal_start[key] = id
				cards.append(key)
				counts[seat] += 1
			groups.append({"cards": cards, "seat": seat, "style": styles[seat] if styles.size() == 4 else "a"})
			seat = Seats.next(seat)
	return groups

func _render(animate: bool) -> void:
	if not is_node_ready() and not camera.is_inside_tree():
		return
	if not animate:
		_cancel_opening()
	_seen.clear()
	_badge_seen.clear()
	_selectable.clear()
	_hand_slots.clear()
	_retired_backs.clear()
	for p in view.get("players", []):
		var seat := int(p.seat)
		var backs := []
		for i in range(int(p.hand_count), 15):
			var key := _hidden_key(seat, i)
			if tiles.has(key):
				backs.append(key)
		_retired_backs[seat] = backs
	var offsets: Array = view.get("wall_offsets", [])
	_refresh_wall_pose_cache(offsets)
	var result: Dictionary = view.get("result", {})
	var flip: int = result.get("flip_wall_index", -1)
	for raw in view.get("wall_slots", []):
		var id := int(raw)
		var destination := _wall_pose(id, offsets)
		var value := ""
		if id == flip and result.has("flip_landing") and not result.flip_landing.is_empty():
			var landing: Dictionary = result.flip_landing
			destination = _wall_pose(int(landing.column) * 2, offsets, int(landing.stack_count) - 1)
			value = result.flip_tile
		_place(id, value, destination, "wall", animate)
	for p in view.get("players", []):
		_hand(p, animate)
		_public(p, animate)
	var latest: int = view.get("last_discard", {}).get("tile_id", -1)
	_discard_marker.visible = view.get("phase") != "settled" and _seen.has(latest) and tiles[latest].get_meta("zone") in ["discard", "chicken"]
	if _discard_marker.visible:
		_marker_origin = _destinations[latest].origin + Vector3.UP * 0.94
		_discard_marker.position = _marker_origin
	_sync_process_state()
	for key in tiles.keys():
		if not _seen.has(key):
			_remove(key)
	for key in _badges.keys():
		if not _badge_seen.has(key):
			_badges[key].queue_free(); _badges.erase(key)
	_refresh_tile_highlights()
	_update_hand_stability()
	if _pending_prompt >= 0:
		_check_presentation.call_deferred()

static func _hidden_key(seat: int, index: int) -> String:
	return "back_%d_%d" % [seat, index]

func _hand(p: Dictionary, animate: bool) -> void:
	var seat := int(p.seat)
	var settled: bool = view.phase == "settled"
	var shared: Dictionary = p.get("display", {})
	var motion: Dictionary = shared.get("motion",{})
	var new_motion: bool = not motion.is_empty() and int(_shared_motion_tokens.get(seat,-1)) != int(motion.token)
	if new_motion: _shared_motion_tokens[seat] = int(motion.token)
	var faces := {}
	var ids := []
	var private_visible := seat == viewer and int(view.viewer_seat) == viewer
	if settled or private_visible:
		for face in p.hand:
			var id := int(face.id)
			faces[id] = face.value
			ids.append(id)
	var result: Dictionary = view.get("result", {})
	var winning_id: int = result.get("win_tile_id", -1)
	if settled and not result.get("self_draw", false) and seat == int(result.get("winner", -1)) and winning_id >= 0 and not faces.has(winning_id):
		ids.append(winning_id)
		faces[winning_id] = result.win_tile
	var separate: bool = p.get("has_draw", int(p.draw_id) >= 0)
	if shared.get("draw_merged",false): separate = false
	if faces.is_empty():
		if shared.has("slots"):
			for key in shared.slots + shared.get("pending", []):
				ids.append(key if key != "" else shared.get("dragged", ""))
			if shared.get("draw", "") != "": ids.append(shared.draw)
		else:
			for i in int(p.hand_count):
				ids.append(_hidden_key(seat, i))
	else:
		var draw_id := int(p.draw_id)
		if private_visible and hand_order.get("draw_merged",false): draw_id = -1
		if settled and winning_id >= 0 and ids.has(winning_id) and seat == int(result.get("winner", -1)):
			draw_id = winning_id
		separate = ids.has(draw_id)
		var order := []
		if private_visible and not hand_order.is_empty() and not settled:
			for slot in hand_order.get("slots", []) + hand_order.get("pending_insert_ids", []):
				var id := int(slot)
				if id < 0:
					id = int(hand_order.get("dragged_id", -1))
				if faces.has(id) and id != draw_id and not order.has(id):
					order.append(id)
		var unassigned := ids.filter(func(id): return id != draw_id and not order.has(id))
		unassigned.sort_custom(func(a, b):
			var va: String = faces[a]
			var vb: String = faces[b]
			var sa := Catalog.SUITS.find(va.left(-1))
			var sb := Catalog.SUITS.find(vb.left(-1))
			return (sa < sb if sa != sb else (va < vb if va != vb else a < b)))
		ids = order + unassigned
		if separate:
			ids.append(draw_id)
	var held = hand_order.get("dragged_id", -1) if private_visible else shared.get("dragged", "")
	var has_held: bool = int(held) >= 0 if private_visible else held != ""
	var merged: bool = not settled and (hand_order.get("draw_merged",false) if private_visible else shared.get("draw_merged",false))
	var use_draw_space := false
	if custom_profile and merged:
		var pitch: float = custom_profile.data.presentation.hand_pitch
		var bounds := Geometry.tile_bounds(pitch)
		use_draw_space = region_placement.indexed(seat,"hand",ids.size()-1,bounds.size.x,bounds.size.z,bounds.size.y*0.5,deg_to_rad(pitch),ids.size()).is_empty()
	for i in ids.size():
		var id = ids[i]
		var selected: bool = id == hand_order.get("selected_id", -1) if private_visible else (id is String and id == shared.get("selected", ""))
		var flat := flat_hands or settled
		var pose := Layout.hand_pose(seat, i, ids.size(), separate, flat, selected)
		if custom_profile:
			# Separate draws follow the row; a merged overflow continues it without a gap.
			var drawing := (separate or use_draw_space) and i == ids.size() - 1
			var pitch: float = custom_profile.data.presentation.hand_pitch
			var bounds := Geometry.tile_bounds(pitch)
			var placement: Dictionary = _hand_extension(seat,ids.size()-1,0.0 if use_draw_space else Layout.GAP) if drawing else region_placement.indexed(seat,"hand",i,bounds.size.x,bounds.size.z,bounds.size.y*0.5,deg_to_rad(pitch),ids.size()-int(separate or use_draw_space))
			pose = _planned_pose(placement, pose, seat, "draw" if drawing else "hand")
			if settled:pose=_settlement_hand(pose,seat)
			else:
				if flat:pose=_pitch_hand(pose,0.0)
				elif seat==viewer:pose=_tilt_own_hand(pose,false)
				if seat==viewer:pose=_magnify_own_hand(pose,seat,not flat)
			if selected: pose.origin.y += 0.56
		var value: String = faces.get(id, "")
		if flat and value.is_empty():
			pose.basis *= Basis(Vector3.RIGHT, PI)
		if private_visible and not settled and value != "":
			_selectable[id] = true
			_hand_slots[i] = pose
		if (_dragging or _discard_dragging) and id is int and id == _press_id:
			var carry = _held_point(_pointer_point)
			if carry != null:
				pose.origin = carry + _carry_offset + Vector3.UP * (0.22 if _drag_hint_ready else 0.0)
		elif not private_visible and id is String and id == shared.get("dragged", ""):
			var point: Array = shared.get("drag_position", [])
			if point.size() == 2:
				pose.origin = Layout.facing(seat) * Vector3(point[0], 1.9, point[1])
		var source = _draw_source if separate and i == ids.size() - 1 and seat == int(view.get("turn", -1)) else -1
		if settled and tiles.has(_hidden_key(seat, i)):
			source = _hidden_key(seat, i)
		elif settled and not tiles.has(id):
			source = view.get("public_origins", {}).get(str(id), source)
		var delay := MOVE_SECONDS if private_visible and id == _insertion_tile else 0.0
		if not private_visible and new_motion and id == motion.get("tile", ""): delay = MOVE_SECONDS
		var reorder: Array = hand_order.get("insertion",{}).get("reorder_ids",[]) if private_visible else (motion.get("reorder",[]) if new_motion else [])
		var shifting: bool = has_held and (private_visible or id is String) and id != held
		var following_pointer: bool = (_dragging or _discard_dragging) and id is int and id == _press_id
		_place(id, value, pose, "hand", animate and not following_pointer, source, delay, seat if shifting else -1, reorder.find(id))
		tiles[id].set_meta("seat", seat)
		tiles[id].set_meta("hand_index", i)

func _public(p: Dictionary, animate: bool) -> void:
	var seat := int(p.seat)
	if custom_profile and p.has("public_regions"):
		if p.get("public_layout_hash") == JSON.stringify(custom_profile.data).sha256_text():
			if not region_placement.restore_public(seat, p.public_regions): layout_conflict.emit(seat, "layout_state")
		else: layout_conflict.emit(seat, "layout_version")
	var groups := {}
	var river := 0
	for face in p.discards:
		var id := int(face.id)
		if face.value in ["tiao1", "tong8"]:
			var charge: Dictionary = view.get("charge_chickens", {}).get(face.value, {})
			var cross: bool = int(charge.get("discard_id", -1)) == id and charge.get("location") == "discard"
			var chicken := {"pieces": [[id, face.value, 0.0, 0.0, cross]], "zone": "chicken"}
			chicken.merge(Regions.chicken(cross) if custom_profile else Layout.chicken_footprint(cross))
			groups["c" + str(id)] = chicken
		else:
			var discard_pose := Layout.discard_pose(seat, river)
			if custom_profile: discard_pose = _planned_pose(region_placement.indexed(seat, "discard", river, Layout.WIDTH, Layout.LONG, Layout.THICK * 0.5, 0), discard_pose, seat, "discard")
			_place(id, face.value, discard_pose, "discard", animate, _back_source(seat, id))
			river += 1
	for i in p.melds.size():
		var meld: Dictionary = p.melds[i]
		if view.phase != "settled" and seat != viewer and meld.get("concealed", false) and int(p.discard_count) < int(meld.get("formed_at", p.discard_count)) + 2:
			meld = {"kind": "kong", "concealed": true, "count": 4, "display_keys": meld.get("display_keys", [])}
		groups["m" + str(i)] = _meld(seat, i, meld)
	var order: Array = p.get("public_order", groups.keys()).duplicate()
	if custom_profile:
		order = order.filter(func(key): return not str(key).begins_with("badge_"))
	var reserved_hand := 14
	var authoritative: bool = p.has("public_centers") and not custom_profile
	if authoritative:
		layout.anchors[seat] = {}
	for key in order:
		if not groups.has(key):
			continue
		if custom_profile:
			if region_placement.public_group(seat, key, groups[key], order, groups).is_empty(): layout_conflict.emit(seat, key)
			continue
		if str(key).begins_with("m"):
			reserved_hand -= 3
		if authoritative:
			var center: Array = p.public_centers.get(key, [])
			if center.size() == 2:
				layout.anchors[seat][key] = Layout._footprint(center[0], center[1], groups[key])
			else:
				layout_conflict.emit(seat, key)
		elif not custom_profile and not layout.reserve(seat, key, groups[key], reserved_hand, groups):
			layout_conflict.emit(seat, key)
	# All necessary horizontal slides start alongside the new group in this render pass.
	for key in order:
		if not groups.has(key):
			continue
		var group: Dictionary = groups[key]
		if str(key).begins_with("badge_"):
			var placement: Dictionary = region_placement._public[seat].get(key, {})
			if not placement.is_empty(): _show_badge(seat, key, group.marker, placement, animate)
			continue
		if not custom_profile and not layout.anchors[seat].has(key):
			for piece in group.pieces:
				if tiles.has(piece[0]):
					_seen[piece[0]] = true
			continue
		var center: Vector2 = layout.anchors[seat].get(key, {"center": Vector2(0, Layout.PUBLIC_RADIUS)}).center
		var planned := {}
		if custom_profile:
			planned = region_placement._public[seat].get(key, {})
		for i in group.pieces.size():
			var piece: Array = group.pieces[i]
			var yaw := 0.0
			if piece[4]:
				yaw = -PI / 2.0 if group.zone == "meld" else PI / 2.0
			var pose := Layout.pose(seat, Vector3(center.x + piece[2], Layout.THICK * 0.5, center.y + piece[3]), PI if piece[1] == "" else 0.0, yaw)
			if not planned.is_empty():
				pose = planned.pose * Transform3D(Layout.facing(seat).inverse() * pose.basis, Vector3(piece[2], Layout.THICK * 0.5, piece[3]))
			var hidden_meld_key := "kong_%d_%s_%d" % [seat, str(key).trim_prefix("m"), i]
			var source = hidden_meld_key if tiles.has(hidden_meld_key) else _back_source(seat, piece[0])
			_place(piece[0], piece[1], pose, group.zone, animate, source)
			tiles[piece[0]].set_meta("seat", seat)

func _back_source(seat: int, id):
	var known_source: String = view.get("public_origins", {}).get(str(id), "")
	if known_source != "" and tiles.has(known_source): return known_source
	if tiles.has(id) or _retired_backs[seat].is_empty():
		return -1
	return _retired_backs[seat].pop_back()

func _hand_extension(seat: int, base_count: int, gap: float = Layout.GAP) -> Dictionary:
	var pitch: float = custom_profile.data.presentation.hand_pitch
	var bounds := Geometry.tile_bounds(pitch)
	var placement: Dictionary = region_placement.indexed(seat,"hand",maxi(0,base_count-1),bounds.size.x,bounds.size.z,bounds.size.y*0.5,deg_to_rad(pitch),maxi(1,base_count))
	if not placement.is_empty() and base_count > 0:
		placement.pose = placement.pose.translated_local(Vector3((1.0+gap)*Layout.WIDTH,0,0))
	return placement

func _magnify_own_hand(pose: Transform3D, seat: int, standing: bool = true) -> Transform3D:
	var scale: float=custom_profile.data.presentation.self_hand_scale
	pose = _magnify_hand(pose,seat,scale)
	if seat == viewer and standing: pose.origin += Layout.facing(seat) * Vector3(0,0,OWN_HAND_FORWARD_SHIFT)
	return pose

func _settlement_hand(pose: Transform3D, seat: int) -> Transform3D:
	var opposite := Seats.relative(viewer,seat) == 2
	# Shift perpendicular to the row so rotated layouts keep their tile centering.
	var outward := pose.basis.x.cross(Vector3.UP).normalized()
	pose = _pitch_hand(pose, -20.0 if opposite else 0.0)
	if seat == viewer:
		pose = _magnify_own_hand(pose,seat,false)
		pose.origin += outward * OWN_HAND_FLAT_FORWARD_SHIFT
		return pose
	pose = _magnify_hand(pose,seat,1.24)
	# The far-side reveal tilts toward the viewer. Leave room for the public row in projection.
	if opposite: pose.origin += outward * OPPOSITE_REVEAL_OUTWARD_SHIFT
	return pose

func _magnify_hand(pose: Transform3D, seat: int, scale:float) -> Transform3D:
	if is_equal_approx(scale,1): return pose
	if _hand_anchor_profile != custom_profile:
		_hand_anchor_profile = custom_profile
		_hand_anchor_cache.clear()
	if not _hand_anchor_cache.has(seat):
		var left:=INF;var right:=-INF;var near:=-INF
		for key in custom_profile.region_keys(seat,"hand"):
			var row: Dictionary=custom_profile.data.regions[key]
			if not row.visible: continue
			left=minf(left,row.x-row.width*0.5);right=maxf(right,row.x+row.width*0.5);near=maxf(near,row.z)
		var extension := _hand_extension(seat,13)
		if not extension.is_empty():
			for corner in 8:
				var point: Vector3 = Layout.facing(seat).inverse()*(extension.pose*Geometry.BOUNDS.get_endpoint(corner))
				left=minf(left,point.x);right=maxf(right,point.x);near=maxf(near,point.z)
		if not is_finite(left): return pose
		_hand_anchor_cache[seat] = Layout.facing(seat)*Vector3((left+right)*0.5,0,near)
	var anchor: Vector3 = _hand_anchor_cache[seat]
	pose.origin=anchor+(pose.origin-anchor)*scale
	pose.basis=pose.basis.scaled(Vector3.ONE*scale)
	return pose

func _tilt_own_hand(pose: Transform3D, flat: bool) -> Transform3D:
	if flat:return pose
	var logical:float=custom_profile.data.presentation.hand_pitch
	var shown:float=custom_profile.data.presentation.get("self_hand_pitch",logical)
	return _pitch_hand(pose,shown)

func _pitch_hand(pose: Transform3D, shown:float) -> Transform3D:
	var logical:float=custom_profile.data.presentation.hand_pitch
	if is_equal_approx(logical,shown):return pose
	var original:=Geometry.tile_bounds(logical)
	var tilted:=Geometry.tile_bounds(shown)
	var rack:=pose.basis*Basis(Vector3.RIGHT,-deg_to_rad(logical))
	pose.origin+=rack*Vector3(0,(tilted.size.y-original.size.y)*0.5,-(tilted.size.z-original.size.z)*0.5)
	pose.basis=rack*Basis(Vector3.RIGHT,deg_to_rad(shown))
	return pose

func _meld(seat: int, index: int, meld: Dictionary) -> Dictionary:
	var ids: Array = meld.get("tile_ids", []).duplicate()
	if ids.is_empty():
		if not meld.get("display_keys", []).is_empty():
			ids = meld.display_keys.duplicate()
		else:
			for i in int(meld.get("count", 4)):
				ids.append("kong_%d_%d_%d" % [seat, index, i])
	var value: String = meld.get("tile", "")
	var pieces := []
	if meld.kind == "kong" and not meld.get("concealed", false):
		var source := int(meld.get("source_id", -1))
		ids.erase(source)
		var relative := Seats.relative(seat, int(meld.from_seat))
		var start := -1.0
		var cross_x := 0.0
		var cross_z := -(Layout.LONG + 1.0) * 0.5
		if relative != 2:
			var side := 1 if relative == 1 else -1
			start -= side * Layout.LONG * 0.5
			cross_x = side * 1.5
			cross_z = (Layout.LONG - Layout.WIDTH) * 0.5
		for i in ids.size():
			pieces.append([int(ids[i]), value, start + i, 0.0, false])
		pieces.append([source, value, cross_x, cross_z, true])
	else:
		for i in ids.size():
			var id = int(ids[i]) if ids[i] is float else ids[i]
			pieces.append([id, value, i - (ids.size() - 1) * 0.5, 0.0, false])
	var group := {"pieces": pieces, "zone": "meld"}
	group.merge(Regions.footprint(seat, meld) if custom_profile else Layout.meld_footprint(seat, meld))
	return group

func _show_badge(seat: int, key: String, kind: String, placement: Dictionary, animate: bool) -> void:
	var id := str(seat) + "/" + key
	_badge_seen[id] = true
	var node: MeshInstance3D = _badges.get(id)
	var is_dealer := kind == "dealer"
	var token_height := 0.24 if is_dealer else 0.18
	if node == null:
		node = MeshInstance3D.new()
		add_child(node)
		_badges[id] = node
		var base_mesh := CylinderMesh.new()
		if is_dealer:
			# 鎏金朱砂圆盘庄家令（低矮实体圆筹，精雕金边+深朱漆内盘）
			base_mesh.top_radius = Regions.BADGE_SIDE * 0.45
			base_mesh.bottom_radius = Regions.BADGE_SIDE * 0.48
			base_mesh.height = token_height
			base_mesh.radial_segments = 24
			var brass := StandardMaterial3D.new()
			brass.albedo_color = Color("#cfa252")
			brass.metallic = 0.72
			brass.roughness = 0.26
			node.mesh = base_mesh
			node.material_override = brass
			var disc := MeshInstance3D.new()
			var disc_mesh := CylinderMesh.new()
			disc_mesh.top_radius = Regions.BADGE_SIDE * 0.37
			disc_mesh.bottom_radius = Regions.BADGE_SIDE * 0.375
			disc_mesh.height = 0.028
			disc_mesh.radial_segments = 24
			var lacquer := StandardMaterial3D.new()
			lacquer.albedo_color = Color("#8f1f1a")
			lacquer.roughness = 0.20
			lacquer.metallic = 0.08
			disc_mesh.material = lacquer
			disc.mesh = disc_mesh
			disc.position.y = token_height * 0.5 + 0.008
			node.add_child(disc)
			var ring := MeshInstance3D.new()
			var ring_mesh := TorusMesh.new()
			ring_mesh.inner_radius = Regions.BADGE_SIDE * 0.35
			ring_mesh.outer_radius = Regions.BADGE_SIDE * 0.39
			ring_mesh.rings = 24
			ring_mesh.ring_segments = 8
			var ring_mat := StandardMaterial3D.new()
			ring_mat.albedo_color = Color("#f0cf80")
			ring_mat.metallic = 0.78
			ring_mat.roughness = 0.24
			ring_mesh.material = ring_mat
			ring.mesh = ring_mesh
			ring.position.y = token_height * 0.5 + 0.016
			ring.scale = Vector3(1.0, 0.45, 1.0)
			node.add_child(ring)
		else:
			# 翡翠八角报听玉牌（温润青玉八方牌+鎏金内圈）
			base_mesh.top_radius = Regions.BADGE_SIDE * 0.43
			base_mesh.bottom_radius = Regions.BADGE_SIDE * 0.47
			base_mesh.height = token_height
			base_mesh.radial_segments = 8
			var jade := StandardMaterial3D.new()
			jade.albedo_color = Color("#146750")
			jade.roughness = 0.18
			jade.metallic = 0.06
			jade.emission_enabled = true
			jade.emission = Color("#1e9e79")
			jade.emission_energy_multiplier = 0.18
			node.mesh = base_mesh
			node.material_override = jade
			var rim := MeshInstance3D.new()
			var rim_mesh := TorusMesh.new()
			rim_mesh.inner_radius = Regions.BADGE_SIDE * 0.33
			rim_mesh.outer_radius = Regions.BADGE_SIDE * 0.37
			rim_mesh.rings = 24
			rim_mesh.ring_segments = 8
			var rim_mat := StandardMaterial3D.new()
			rim_mat.albedo_color = Color("#e3c575")
			rim_mat.metallic = 0.72
			rim_mat.roughness = 0.25
			rim_mesh.material = rim_mat
			rim.mesh = rim_mesh
			rim.position.y = token_height * 0.5 + 0.010
			rim.scale = Vector3(1.0, 0.42, 1.0)
			node.add_child(rim)
		var top := Label3D.new()
		top.name = "Glyph"
		top.text = "庄" if is_dealer else "听"
		top.font_size = 56 if is_dealer else 52
		top.pixel_size = Regions.BADGE_SIDE / 96.0
		top.modulate = Color("#fff0bd") if is_dealer else Color("#f4fff8")
		top.outline_size = 7
		top.outline_modulate = Color("#4a0e09") if is_dealer else Color("#092c21")
		top.shaded = false
		top.position.y = token_height * 0.5 + (0.028 if is_dealer else 0.018)
		top.rotation.x = -PI / 2.0
		node.add_child(top)
		node.set_meta("glyph", top)
		node.set_meta("token_height", token_height)
	# 始终让顶面“庄/听”字朝向本家视角，四家标记都清晰可读
	var glyph: Label3D = node.get_meta("glyph", null)
	if is_instance_valid(glyph):
		glyph.rotation = Vector3(-PI / 2.0, float(seat - viewer) * PI * 0.5, 0.0)
	var target: Transform3D = placement.pose
	target.origin.y = token_height * 0.5 * target.basis.get_scale().y
	if node.has_meta("target") and node.get_meta("target").is_equal_approx(target):
		if not animate:
			if node.has_meta("motion") and node.get_meta("motion").is_valid(): node.get_meta("motion").kill()
			node.transform = target
		return
	node.set_meta("target", target)
	if animate and not node.transform.is_equal_approx(target) and node.has_meta("placed"):
		if node.has_meta("motion") and node.get_meta("motion").is_valid(): node.get_meta("motion").kill()
		var motion := create_tween(); motion.tween_property(node, "transform", target, MOVE_SECONDS); node.set_meta("motion", motion)
	else: node.transform = target
	node.set_meta("placed", true)

func _material(value: String) -> Material:
	return TileArt.material(Catalog.valid_value(value))

func _reuse_source(source, key) -> MeshInstance3D:
	var node: MeshInstance3D = tiles[source]
	tiles.erase(source)
	_destinations.erase(source)
	if _motions.has(source):
		_motions[source].kill()
		_motions.erase(source)
	tiles[key] = node
	return node

func _place(key, value: String, target: Transform3D, zone: String, animate: bool, source_id = -1, delay: float = 0.0, shifting_seat: int = -1, reorder_level: int = -1) -> void:
	_seen[key] = true
	var source = _deal_start.get(key, source_id)
	var node: MeshInstance3D = tiles.get(key)
	var from_wall: bool = source is int and source >= 0 and (node == null or node.get_meta("zone", "") == "wall")
	if node == null and tiles.has(source) and not _seen.has(source):
		from_wall = from_wall and tiles[source].get_meta("zone", "") == "wall"
		node = _reuse_source(source, key)
	var fresh := node == null
	if fresh:
		node = MeshInstance3D.new()
		add_child(node)
		tiles[key] = node
	if node.get_meta("value", "unset") != value:
		node.mesh = TileArt.mesh(value)
		node.material_override = _material(value)
		node.set_meta("value", value)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if zone in ["wall", "discard"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.set_meta("zone", zone)
	if _deal_start.has(key) or (_opening and _opening.keys.has(key)):
		_destinations[key] = target
		return
	if delay == 0.0 and not fresh and _destinations.has(key) and _destinations[key].is_equal_approx(target):
		if not animate and _motions.has(key):
			_motions[key].kill()
			_motions.erase(key)
			node.transform = target
		return
	if _motions.has(key):
		_motions[key].kill()
		_motions.erase(key)
	var previous: Transform3D = _destinations.get(key, node.transform)
	_destinations[key] = target
	if not animate or (fresh and (not source is int or source < 0)):
		node.transform = target
		return
	if fresh and source is int and source >= 0:
		node.transform = _wall_pose(source, view.get("wall_offsets", []))
	var tween := create_tween()
	_motions[key] = tween
	# Selecting a tile only raises it vertically. A second tap can confirm that same tile.
	var travels := not previous.basis.is_equal_approx(target.basis) or not is_equal_approx(previous.origin.x, target.origin.x) or not is_equal_approx(previous.origin.z, target.origin.z)
	if zone in ["hand", "meld"] and (travels or delay > 0):
		tween.set_meta("hand_travel", true)
		if shifting_seat >= 0: tween.set_meta("drag_preview", true)
	if _adding_kong.has(key) and custom_profile:
		var origin := node.transform
		var fourth: bool = key == _adding_kong.back()
		tween.tween_method(func(progress: float):
			node.transform = origin.interpolate_with(target, progress)
			if fourth: node.position.y += 0.9 * 4.0 * progress * (1.0 - progress), 0.0, 1.0, ADDED_KONG_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif not _adding_kong.is_empty() and custom_profile and zone in ["chicken", "meld"]:
		tween.tween_property(node, "transform", target, ADDED_KONG_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif _adding_kong.has(key):
		# The released 1.6.31 table first makes room, then arcs the fourth tile into slot 3.
		var room := ADDED_KONG_SECONDS * 0.3
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if key == _adding_kong.back():
			var origin := node.transform
			tween.tween_interval(room)
			tween.tween_method(func(progress: float):
				node.transform = origin.interpolate_with(target, progress)
				node.position.y += 0.9 * 4.0 * progress * (1.0 - progress), 0.0, 1.0, ADDED_KONG_SECONDS - room)
		else:
			tween.tween_property(node, "transform", target, room)
	elif delay > 0.0:
		tween.tween_interval(delay)
		var raised := node.transform
		raised.origin.y = maxf(raised.origin.y, target.origin.y) + Layout.LONG + 0.1
		var over_slot := target
		over_slot.origin.y = raised.origin.y
		# Cross above the standing row; a direct sideways insertion passes through intervening tiles.
		tween.tween_property(node, "transform", raised, MOVE_SECONDS * 0.25).set_trans(Tween.TRANS_SINE)
		tween.tween_property(node, "transform", over_slot, MOVE_SECONDS * 0.50).set_trans(Tween.TRANS_SINE)
		tween.tween_property(node, "transform", target, MOVE_SECONDS * 0.25).set_trans(Tween.TRANS_SINE)
	elif zone == "hand" and reorder_level >= 0:
		var level: int = reorder_level
		var lifted := node.transform
		lifted.origin.y = maxf(lifted.origin.y, target.origin.y) + Layout.LONG * (1.5 + level * 0.7)
		var over := target; over.origin.y = lifted.origin.y
		tween.tween_property(node, "transform", lifted, MOVE_SECONDS * 0.2)
		tween.tween_property(node, "transform", over, MOVE_SECONDS * 0.6)
		tween.tween_property(node, "transform", target, MOVE_SECONDS * 0.2)
	elif shifting_seat >= 0:
		tween.tween_property(node, "transform", target, DRAG_SHIFT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	elif zone in ["discard", "chicken"]:
		var origin := node.transform
		var arc_h := 0.72 if zone == "chicken" else 0.48
		tween.tween_method(func(progress: float):
			node.transform = origin.interpolate_with(target, progress)
			node.position.y += arc_h * 4.0 * progress * (1.0 - progress), 0.0, 1.0, MOVE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_callback(func():
			if zone == "chicken":
				_spawn_landing_ripple(target.origin, Color("#ffb82e"), 1.35)
				create_tween().tween_callback(_spawn_landing_ripple.bind(target.origin, Color("#ffd76a"), 1.85)).set_delay(0.09)
				pulse_table_shake(0.11)
			else:
				_spawn_landing_ripple(target.origin, Color("#e8d49c"), 0.85))
	elif zone == "hand" and from_wall and _adding_kong.is_empty():
		var origin := node.transform
		var arc_h := 0.55
		tween.tween_method(func(progress: float):
			node.transform = origin.interpolate_with(target, progress)
			node.position.y += arc_h * 4.0 * progress * (1.0 - progress), 0.0, 1.0, MOVE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	elif zone == "hand" and (not travels or (key is int and key == _settling_id)):
		var settling: bool = key is int and key == _settling_id
		var lifting := not settling and target.origin.y > previous.origin.y + 0.01
		var duration := DRAG_SETTLE_SECONDS if settling else (0.11 if lifting else 0.085)
		tween.tween_property(node, "transform", target, duration).set_trans(Tween.TRANS_BACK if lifting else Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		tween.tween_property(node, "transform", target, MOVE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func():
		_motions.erase(key)
		_check_presentation.call_deferred())

func _remove(key) -> void:
	if _motions.has(key):
		_motions[key].kill()
		_motions.erase(key)
	tiles[key].queue_free()
	tiles[key].visible = false
	tiles.erase(key)
	_destinations.erase(key)

func _pick(point: Vector2, wall: bool) -> int:
	var hit = _closest_tile(camera.project_ray_origin(point), camera.project_ray_normal(point), wall)
	if hit == null or (wall and tiles[hit].get_meta("zone") != "wall"):
		return -1
	return int(hit)

func _closest_tile(origin: Vector3, direction: Vector3, all_tiles: bool):
	var nearest := INF
	var hit = null
	for key in (tiles if all_tiles else _selectable):
		if not all_tiles and _opening and _opening.keys.has(key):
			continue
		var node: MeshInstance3D = tiles[key]
		var depth := _ray_depth(node, TILE_BOUNDS, origin, direction)
		if depth < nearest:
			nearest = depth
			hit = key
	return hit

func _ray_depth(node: Node3D, bounds: AABB, origin: Vector3, direction: Vector3) -> float:
	var local := node.global_transform.affine_inverse()
	var hit = bounds.intersects_ray(local * origin, local.basis * direction)
	return INF if hit == null else origin.distance_squared_to(node.global_transform * Vector3(hit))

func _blank_at(point: Vector2) -> bool:
	if _selectable.is_empty() or not is_visible_in_tree():
		return false
	var origin := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var felt = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if felt == null or maxf(absf(felt.x), absf(felt.z)) > table_edge():
		return false
	if _closest_tile(origin, direction, true) != null:
		return false
	for obstacle in _felt_obstacles:
		if obstacle.visible and _ray_depth(obstacle, obstacle.get_aabb(), origin, direction) < INF:
			return false
	for sibling in get_parent().get_children():
		if sibling is DiceRoll and sibling.is_visible_in_tree():
			for die in sibling.dice:
				if _ray_depth(die, DIE_BOUNDS, origin, direction) < INF:
					return false
	return true

func _tap_slop() -> float:
	var vp := get_viewport().get_visible_rect().size
	return clampf(minf(vp.x, vp.y) * 0.022, TAP_SLOP, 28.0)

func _screen_bounds(t: Transform3D) -> Rect2:
	var bounds := Rect2()
	for i in 8:
		var corner := camera.unproject_position(global_transform * (t * TILE_BOUNDS.get_endpoint(i)))
		bounds = Rect2(corner, Vector2.ZERO) if i == 0 else bounds.expand(corner)
	return bounds

func tile_at(point: Vector2) -> int:
	var hit := _pick(point, false)
	if hit >= 0: return hit
	var nearest := INF
	var slop := _tap_slop()
	for id in _selectable:
		if not tiles.has(id): continue
		var bounds := _screen_bounds(tiles[id].transform)
		var expanded := bounds.grow_individual(slop * 0.45, slop * 1.1, slop * 0.45, slop * 1.1)
		if not expanded.has_point(point): continue
		# 水平中心距权重更高，避免手指点在牌底边缘时误选相邻牌或已抬起的邻牌
		var dx := absf(bounds.get_center().x - point.x)
		var dy := absf(bounds.get_center().y - point.y)
		var score := dx * dx + dy * dy * 0.25
		if score < nearest:
			hit = int(id)
			nearest = score
	return hit

func _world_point(point: Vector2, y: float):
	return Plane(Vector3.UP, y).intersects_ray(camera.project_ray_origin(point), camera.project_ray_normal(point))

func _held_point(point: Vector2):
	var hit = _world_point(point, 1.9)
	if hit == null:
		return null
	var facing := Layout.facing(viewer)
	var local: Vector3 = facing.inverse() * Vector3(hit)
	return facing * Vector3(clampf(local.x, -table_edge(), table_edge()), 1.9, clampf(local.z, -table_edge(), _foreground_z()))

func _foreground_z() -> float:
	var edge := table_edge()
	var inverse := Layout.facing(viewer).inverse()
	for pose in _hand_slots.values():
		edge = maxf(edge, (inverse * pose.origin).z + Layout.LONG)
	return edge

func _slot_at_drag(point: Vector2) -> int:
	var best := -1
	var nearest := INF
	var row := Rect2()
	var first := true
	for slot in _hand_slots:
		var bounds := _screen_bounds(_hand_slots[slot])
		row = bounds if first else row.merge(bounds)
		first = false
		var distance := absf(bounds.get_center().x - point.x)
		if distance < nearest:
			nearest = distance
			best = int(slot)
	return best if not first and row.grow(maxf(row.size.y, 30.0)).has_point(point) else -1

func _above_discard_line(point: Vector2) -> bool:
	if _hand_slots.is_empty(): return false
	var top := INF
	var height := 0.0
	var selected_id := int(hand_order.get("selected_id", -1))
	var used_unselected := false
	for slot in _hand_slots:
		if selected_id >= 0 and tiles.has(selected_id) and int(tiles[selected_id].get_meta("hand_index", -1)) == int(slot):
			continue
		used_unselected = true
		var bounds := _screen_bounds(_hand_slots[slot])
		top = minf(top, bounds.position.y)
		height = maxf(height, bounds.size.y)
	if not used_unselected:
		for pose in _hand_slots.values():
			var bounds := _screen_bounds(pose)
			top = minf(top, bounds.position.y)
			height = maxf(height, bounds.size.y)
	return point.y < top - height * 0.16

func _slot_at(point: Vector2) -> int:
	var best := -1
	var nearest := INF
	for slot in _hand_slots:
		var t: Transform3D = _hand_slots[slot]
		var bounds := Rect2()
		var first := true
		for i in 8:
			var corner := camera.unproject_position(t * TILE_BOUNDS.get_endpoint(i))
			bounds = Rect2(corner, Vector2.ZERO) if first else bounds.expand(corner)
			first = false
		var bottom_center := Vector2(bounds.get_center().x, bounds.end.y)
		var tolerance: float = custom_profile.data.get("hand_tolerance", HAND_TOLERANCE) if custom_profile else HAND_TOLERANCE
		var scaled := Rect2(bottom_center + (bounds.position - bottom_center) * tolerance, bounds.size * tolerance)
		var distance := bounds.get_center().distance_squared_to(point)
		if scaled.has_point(point) and distance < nearest:
			best = int(slot)
			nearest = distance
	return best

func _cancel_press() -> void:
	if _hold:
		_hold.kill()
	_press_id = -1
	_press_play_prompt = -1
	_press_began_stable = false
	_press_was_selected = false
	_pointer = -2
	_dragging = false
	_discard_dragging = false
	_drag_from_hold = false
	_hold_drag_moved = false
	_last_drag_slot = -1
	_blank_moved = false
	_set_discard_drag_hint(false, false)

func _set_discard_drag_hint(active: bool, ready: bool) -> void:
	if active == _drag_hint_active and ready == _drag_hint_ready:
		return
	_drag_hint_active = active
	_drag_hint_ready = ready
	discard_drag_state_changed.emit(active, ready)

func _live_playable(id: int, finishing_drag: bool = false) -> bool:
	var prompt := int(view.get("prompt_id", -1))
	if prompt < 0 or not can_play_hand(finishing_drag):
		return false
	if _press_play_prompt >= 0 and _press_play_prompt != prompt:
		return false
	return view.get("choices", {}).get("discard_ids", []).has(id)

func can_play_hand(finishing_drag: bool = false) -> bool:
	return not view.get("choices", {}).get("discard_ids", []).is_empty() and own_hand_stable(finishing_drag)

func own_hand_stable(finishing_drag: bool = false) -> bool:
	if (_dragging and not finishing_drag) or (_opening and _opening.tracks.has(viewer)):
		return false
	for key in _motions:
		var tween: Tween = _motions[key]
		if tween.has_meta("hand_travel") and tiles[key].get_meta("seat", -1) == viewer and not (finishing_drag and tween.has_meta("drag_preview")):
			return false
	return true

func _update_hand_stability() -> void:
	var stable := own_hand_stable()
	if stable != _hand_was_stable:
		_hand_was_stable = stable
		hand_stability_changed.emit()

func _press(point: Vector2, index: int, double: bool) -> bool:
	if _pointer != -2 or not is_visible_in_tree():
		return false
	var id := tile_at(point)
	if id < 0:
		if double:
			var wall := _pick(point, true)
			if wall >= 0:
				wall_center_requested.emit(int(layout.slots.slot_info(wall).seat))
				return true
			return false
		if not _blank_at(point):
			return false
	_pointer = index
	_press_id = id
	_press_point = point
	_pointer_point = point
	if id < 0:
		return true
	_press_play_prompt = int(view.get("prompt_id", -1))
	_press_began_stable = own_hand_stable()
	_press_was_selected = hand_order.get("selected_id", -1) == id
	if not _press_began_stable:
		return true
	_hold = create_tween()
	_hold.tween_interval(HOLD_SECONDS)
	_hold.tween_callback(func():
		if _press_id >= 0:
			_drag_from_hold = true
			_start_drag(false))
	return true

func _start_drag(discard: bool) -> void:
	if _hold: _hold.kill()
	_discard_dragging = discard
	_dragging = not discard
	_last_drag_slot = -1
	var initial = _held_point(_press_point)
	_carry_offset = tiles[_press_id].position - Vector3(initial) + Vector3.UP * 0.45 if initial != null and tiles.has(_press_id) else Vector3.ZERO
	if initial != null and tiles.has(_press_id):
		tiles[_press_id].position = Vector3(initial) + _carry_offset
		_destinations.erase(_press_id)
	if discard: _set_discard_drag_hint(true, false)
	if _dragging: drag_started.emit(_press_id)

func _motion(point: Vector2) -> void:
	_pointer_point = point
	if _press_id < 0:
		if point.distance_to(_press_point) > _tap_slop(): _blank_moved = true
		return
	if not _dragging and not _discard_dragging:
		var delta := point - _press_point
		if delta.length() <= _tap_slop(): return
		if not own_hand_stable(): return
		var playable := _live_playable(_press_id)
		if delta.y < -_tap_slop() * 0.75 and absf(delta.y) >= absf(delta.x) * 0.72 and playable:
			_start_drag(true)
		elif absf(delta.x) > absf(delta.y) * 0.72:
			_start_drag(false)
		elif delta.y < -_tap_slop() * 0.75 and playable:
			_start_drag(true)
		else:
			if _hold: _hold.kill()
			return
	if _drag_from_hold and not _hold_drag_moved:
		_hold_drag_moved = point.distance_to(_press_point) > _tap_slop()
		if not _hold_drag_moved:
			return
	if _dragging and not _above_discard_line(point):
		var slot := _slot_at_drag(point)
		if slot >= 0 and slot != _last_drag_slot:
			_last_drag_slot = slot
			drag_slot_changed.emit(slot)
	var rise := _press_point.y - point.y
	var hint_active := ((_discard_dragging and rise > 0.0) or (
		_dragging and rise >= maxf(24.0, _tap_slop() * 1.5))) and _live_playable(_press_id, _dragging)
	_set_discard_drag_hint(hint_active, hint_active and (_over_discard_line(point) or _upward_discard_flick(point)))
	if tiles.has(_press_id):
		var position_on_table = _held_point(point)
		if position_on_table != null:
			tiles[_press_id].position = Vector3(position_on_table) + _carry_offset + Vector3.UP * (0.22 if _drag_hint_ready else 0.0)
			_destinations.erase(_press_id)
			if _dragging:
				var local: Vector3 = Layout.facing(viewer).inverse() * tiles[_press_id].position
				hand_drag_position.emit([clampf(local.x, -table_edge(), table_edge()), clampf(local.z, -table_edge(), table_edge())])

func _over_discard_line(point: Vector2) -> bool:
	if _above_discard_line(point):
		return true
	var plane_hit = _world_point(point, 0.0)
	return plane_hit != null and is_discard_point(Vector3(plane_hit))

func _upward_discard_flick(point: Vector2) -> bool:
	var rise := _press_point.y - point.y
	var sideways := absf(point.x - _press_point.x)
	return (_discard_dragging and rise >= maxf(34.0, _tap_slop() * 2.4) and rise >= sideways * 0.45) or (
		not _dragging and rise >= maxf(32.0, _tap_slop() * 2.2) and rise >= sideways * 0.65)

func _release(point: Vector2) -> void:
	var id := _press_id
	var traveled := point.distance_to(_press_point)
	if id < 0:
		var tapped := not _blank_moved and traveled <= _tap_slop() and _blank_at(point)
		_cancel_press()
		if tapped: blank_tapped.emit()
		return
	var dragged := _dragging
	var discard_dragged := _discard_dragging
	var can_play := _live_playable(id, dragged)
	var discard := can_play and (((dragged or discard_dragged) and _over_discard_line(point)) or _upward_discard_flick(point))
	var within_tap_slop := traveled <= _tap_slop()
	var held_tap := dragged and _drag_from_hold and not _hold_drag_moved and within_tap_slop and _last_drag_slot == -1 and not discard
	var tapped := _press_began_stable and can_play and within_tap_slop and (held_tap or (not dragged and not discard_dragged))
	var confirms := held_tap and _press_was_selected
	var slot := -1 if discard or held_tap else _slot_at_drag(point)
	_cancel_press()
	_settling_id = id
	if dragged: drag_finished.emit(slot)
	if discard: swipe_discard.emit(id)
	elif tapped:
		# Starting a sort drag clears the selection, so carry it through a stationary hold tap.
		_hold_tap_confirms = confirms
		tile_clicked.emit(id)
		_hold_tap_confirms = false
	if dragged or discard_dragged: _render(true)
	_settling_id = -1

func is_discard_point(point: Vector3) -> bool:
	if not custom_profile:
		return maxf(absf(point.x),absf(point.z)) < Layout.WALL_RADIUS-Layout.LONG*0.5
	# Each wall's inner edge is a boundary of the shared physical play area.
	for seat in 4:
		var found:=false
		for key in custom_profile.region_keys(seat,"wall"):
			var row:Dictionary=custom_profile.data.regions[key]
			if not row.visible:continue
			found=true
			var local:Vector3=custom_profile.region_pose(seat,"wall",key).affine_inverse()*point
			if local.z>=-float(row.depth)-0.001:return false
		if not found:return false
	return true

## Same physical boundaries as swipe-discard, retained even when a wall has been consumed.
func play_area_polygon() -> PackedVector2Array:
	var edge:=table_edge()
	var poly:=PackedVector2Array([Vector2(-edge,-edge),Vector2(edge,-edge),Vector2(edge,edge),Vector2(-edge,edge)])
	for seat in 4:
		var boundaries: Array=[]
		if custom_profile:
			for key in custom_profile.region_keys(seat,"wall"):
				if custom_profile.data.regions[key].visible:boundaries.append({"pose":custom_profile.region_pose(seat,"wall",key),"depth":custom_profile.data.regions[key].depth})
		else:boundaries.append({"pose":Layout.pose(seat,Vector3(0,0,Layout.WALL_RADIUS),0,0),"depth":Layout.LONG*0.5})
		if boundaries.is_empty():return PackedVector2Array()
		for boundary in boundaries:
			var clipped:=PackedVector2Array()
			if poly.is_empty():return poly
			var inverse:Transform3D=boundary.pose.affine_inverse()
			for index in poly.size():
				var a:=poly[index];var b:=poly[(index+1)%poly.size()]
				var da:float=(inverse*Vector3(a.x,0,a.y)).z+float(boundary.depth)
				var db:float=(inverse*Vector3(b.x,0,b.y)).z+float(boundary.depth)
				if da<=0:clipped.append(a)
				if (da<=0)!=(db<=0):clipped.append(a.lerp(b,da/(da-db)))
			poly=clipped
	return poly

func _unhandled_input(event: InputEvent) -> void:
	var consumed := false
	if event is InputEventScreenTouch and event.pressed:
		consumed = _press(event.position, event.index, event.double_tap)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		consumed = _press(event.position, -1, event.double_click)
	if consumed:
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# Finish a captured drag even when the finger ends above a HUD element.
	if _pointer == -2:
		return
	if event is InputEventScreenDrag and event.index == _pointer:
		_motion(event.position)
	elif event is InputEventMouseMotion and _pointer == -1:
		_motion(event.position)
	elif event is InputEventScreenTouch and not event.pressed and event.index == _pointer:
		if event.canceled:
			if _dragging:
				drag_finished.emit(-1)
			_cancel_press()
			_render(true)
		else:
			_release(event.position)
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _pointer == -1:
		_release(event.position)
	else:
		return
	get_viewport().set_input_as_handled()

func _planned_pose(placement: Dictionary, fallback: Transform3D, seat: int, kind: String) -> Transform3D:
	if placement.is_empty():
		layout_conflict.emit(seat, kind)
		return fallback
	return placement.pose

func _refresh_wall_pose_cache(offsets:Array) -> void:
	var signature:=[custom_profile,offsets.duplicate()]
	if custom_profile:
		for seat in 4:
			for key in custom_profile.region_keys(seat,"wall"):
				signature.append(custom_profile.data.regions[key].duplicate(true))
	if signature!=_wall_pose_signature:
		_wall_pose_signature=signature
		_wall_pose_cache.clear()

func _wall_pose(id: int, offsets: Array, height: int = -1) -> Transform3D:
	if custom_profile and height<0 and _wall_pose_cache.has(id):return _wall_pose_cache[id]
	var original := layout.wall_pose(id, offsets, height)
	if not custom_profile: return original
	var slot: Dictionary = layout.slots.slot_info(id)
	var layer := 1 - int(slot.layer) if height < 0 else height
	var result: Dictionary = region_placement.indexed(slot.seat, "wall", int(slot.column), Layout.WIDTH, Layout.LONG, (layer + 0.5) * Layout.THICK, PI if height < 0 else 0.0, 14 if int(slot.seat) % 2 else 13, true)
	# Centering is a display translation only; it never alters wall identity or draw order.
	if not result.is_empty() and offsets.size() == 4:
		result.pose.origin -= result.pose.basis.orthonormalized().x * float(offsets[slot.seat])
	var pose:=_planned_pose(result, original, slot.seat, "wall")
	if height<0:_wall_pose_cache[id]=pose
	return pose

func table_edge() -> float:
	return float(custom_profile.data.table_side) * 0.5 if custom_profile else Layout.EDGE
