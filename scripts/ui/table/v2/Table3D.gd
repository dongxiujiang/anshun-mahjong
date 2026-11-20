extends Control
## Real meshes mirror the existing presentation timeline; RoundState stays authoritative.
const G = preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const MODEL_PATH := "res://res/models/mahjong3d/"
# Flat top rim of tiles.glb, inside the beveled shell.
const TILE_FACE_HALF := Vector2(0.4472395, 0.5665705)
const TILE_FACE_HEIGHT := 0.31
var view: Control
var viewport: SubViewport
var camera: Camera3D
var world: Node3D
var table_model: Node3D
var tile_nodes := {}
var dice_nodes := {}
var _meshes := {}
var _sources := {}
var _signatures := {}
var _rects := {}
var _opponent_hand_slots := {}
var _dice_normals: Dictionary
var _pressed: TileView
var _press_at := Vector2.ZERO
var _pointer := -1
var _changed := true
var opponent_hand_scale := 1.0
var _own_hand_pitch := deg_to_rad(63)
var discard_marker: MeshInstance3D
var _marker_source_id := 0
var _marker_blocked := false
var geometry_revision := 0
var _own_exposed_layout_key := 0
var _own_placed_context := []
var _own_placed_poses := {}
var _own_exposed_targets := {}
var _own_exposed_origins := {}
var _own_exposed_previous := {}
var _own_exposed_left_hand := Rect2()

func clear_own_exposed_flight() -> void:
	if _own_exposed_targets.is_empty(): return
	_own_exposed_targets.clear()
	_own_exposed_origins.clear()
	_own_exposed_previous.clear()
	_own_exposed_layout_key = 0

func _ready() -> void:
	name = "Table3D"
	add_to_group("table_3d")
	size = G.DESIGN_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_priority = 90
	viewport = SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.positional_shadow_atlas_size = 0
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var picture := TextureRect.new()
	picture.texture = viewport.get_texture()
	picture.size = size
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.show_behind_parent = true
	add_child(picture)
	world = Node3D.new()
	viewport.add_child(world)
	discard_marker = MeshInstance3D.new()
	var pointer_mesh := CylinderMesh.new()
	pointer_mesh.top_radius = 0.0
	pointer_mesh.bottom_radius = 0.23
	pointer_mesh.height = 0.55
	pointer_mesh.radial_segments = 3
	discard_marker.mesh = pointer_mesh
	discard_marker.rotation.x = PI
	discard_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pointer_material := StandardMaterial3D.new()
	pointer_material.albedo_color = Color("#ee6344")
	pointer_material.roughness = 0.4
	discard_marker.material_override = pointer_material
	discard_marker.hide()
	world.add_child(discard_marker)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 54, 61)
	camera.look_at(Vector3.ZERO)
	camera.fov = 18.6
	camera.near = 0.1
	camera.far = 200
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#09251c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#e6eadc")
	environment.environment.ambient_light_energy = 0.35
	world.add_child(environment)
	var surround := MeshInstance3D.new()
	var surround_mesh := PlaneMesh.new()
	surround_mesh.size = Vector2(140, 140)
	surround.mesh = surround_mesh
	surround.position.y = -4.4
	surround.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surround_material := ShaderMaterial.new()
	surround_material.shader = load(MODEL_PATH + "room.gdshader")
	surround.material_override = surround_material
	world.add_child(surround)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-62, -25, 0)
	light.light_color = Color("#fff2db")
	light.light_energy = 0.72
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 140
	light.shadow_bias = 0.02
	world.add_child(light)
	for file in ["tiles", "dice"]:
		var library = load(MODEL_PATH + file + ".glb").instantiate()
		for child in library.find_children("*", "MeshInstance3D"):
			_meshes[String(child.name)] = child.mesh
		library.free()
	var tile_material := ShaderMaterial.new()
	tile_material.shader = load(MODEL_PATH + "tile.gdshader")
	tile_material.set_shader_parameter("artwork", load(MODEL_PATH + "mahJong.png"))
	tile_material.set_shader_parameter("engraving", load(MODEL_PATH + "mahJong_NORM.png"))
	for key in _meshes:
		if key not in ["red", "black"]:
			_meshes[key].surface_set_material(0, tile_material)
	_dice_normals = JSON.parse_string(FileAccess.get_file_as_string(MODEL_PATH + "models.json")).dice_face_normals
	var table = load(MODEL_PATH + "table.glb").instantiate()
	table_model = table
	table.scale = Vector3(1.64, 1, 1.25)
	table.position.z = -1.0
	for mesh in table.find_children("*", "MeshInstance3D"):
		var material := ShaderMaterial.new()
		material.shader = load(MODEL_PATH + ("felt.gdshader" if mesh.name == "felt" else "wood.gdshader"))
		if mesh.name == "felt":
			var noise := FastNoiseLite.new()
			noise.seed = 81
			noise.frequency = 0.6
			var texture := NoiseTexture2D.new()
			texture.width = 256
			texture.height = 256
			texture.generate_mipmaps = true
			texture.noise = noise
			texture.changed.connect(func(): _changed = true)
			material.set_shader_parameter("fibers", texture)
		mesh.material_override = material
	world.add_child(table)
	sync_tiles()
	RenderingServer.frame_pre_draw.connect(_sync_before_draw)

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var started: bool = view != null and view.native_settlement_started()
	_own_hand_pitch = move_toward(_own_hand_pitch, 0.0, deg_to_rad(63) * delta / 0.28) if started else deg_to_rad(63)
	if started and GameConfig.tile_motion_seconds() == 0.0: _own_hand_pitch = 0.0

func _sync_before_draw() -> void:
	# Tweens can recycle tile sources after _process; mirror their final state.
	if is_visible_in_tree():
		sync_tiles()
		view._layout_arrangement_controls()
		view._layout_meld_badges()

func _at_height(screen: Vector2, height: float) -> Vector3:
	var pixel := screen / size * Vector2(viewport.size)
	var origin := camera.project_ray_origin(pixel)
	var direction := camera.project_ray_normal(pixel)
	return origin + direction * ((height - origin.y) / direction.y)

func _pixel_scale(screen: Vector2, width: float) -> float:
	return _at_height(screen + Vector2(width * 0.5, 0), 0).distance_to(
		_at_height(screen - Vector2(width * 0.5, 0), 0))

func _wall_flip_landing(index: int, factor: float, world_unit: float, width_fit: float) -> Transform3D:
	var segment: Dictionary = view._wall_segment_for_index(index)
	var side: int = view._wall_screen_seat(int(segment.seat))
	var center: Vector2 = view.wall_center_for_index(index | 1)
	if side == 1: center.y -= 28.0
	var row_offset := 0.0
	if side in [0, 2]:
		row_offset = (center.y - G.CENTER.y) * world_unit
		center.y = G.CENTER.y
	var along_scale := lerpf(0.79, 1.09, center.y / size.y) * lerpf(0.58, 1.0, width_fit)
	center.x = G.CENTER.x + (center.x - G.CENTER.x) * along_scale
	var layers := 2 if index % 2 == 0 else 1
	var stack_offset := Vector3(0.0, 0.62 * factor * layers, row_offset)
	var basis := Basis(Vector3.UP, -G.wall_angle(side)).scaled(Vector3.ONE * factor)
	return Transform3D(basis, _at_height(center, 0.31 * factor + 0.03) + stack_offset)

func _ordinary_position(center: Vector2, seat: int, factor: float, world_unit: float, width_fit: float) -> Vector3:
	var row_offset := 0.0
	if G.relative_seat(view.human_seat, seat) in [1, 3]:
		row_offset = (center.y - G.CENTER.y) * world_unit * 0.95
		center.y = G.CENTER.y
	else:
		var first_y := G.ordinary_slot_center(seat, 0, view.human_seat).y
		var step_y := G.ordinary_slot_center(seat, 10, view.human_seat).y - first_y
		# Adjacent rows touch in world space, including the flight's final pose.
		row_offset = (center.y - first_y) / absf(step_y) * 1.34 * factor
		center.y = first_y
	var along_scale := lerpf(0.79, 1.09, center.y / size.y) * lerpf(0.58, 1.0, width_fit)
	center.x = G.CENTER.x + (center.x - G.CENTER.x) * along_scale
	var position := _at_height(center, 0.31 * factor + 0.03) + Vector3(0, 0, row_offset)
	if G.relative_seat(view.human_seat, seat) in [0, 2]:
		# Pack horizontal rows in model units, independent of perspective and pixel gaps.
		var slot_step := G.TILE_BASE.x * G.ORDINARY_UNIT + G.TILE_GAP
		position.x = (center.x - G.CENTER.x) / along_scale / slot_step * factor * 0.98
	return position

func can_keep_north_exposed(specs: Array, obstacles: Dictionary[Rect2, Dictionary]) -> bool:
	var width_fit := minf(1.0, G.DESIGN_SIZE.aspect() / Vector2(viewport.size).aspect())
	var world_unit := _pixel_scale(G.CENTER, 1.0) * width_fit
	var wall_factor := world_unit * G.TILE_BASE.x * G.WALL_UNIT
	var river_factor := world_unit * G.TILE_BASE.x * G.ORDINARY_UNIT
	var tile_bounds: AABB = _meshes["wan1"].get_aabb()
	for spec in specs:
		var prefix := "red-meld" if Tiles.is_chicken(spec.tile) else "meld"
		var key := "%s:%d:%d:%d" % [prefix, spec.seat, spec.meld_index, spec.meld_slot] if spec.meld_index >= 0 \
			else "red-discard:%d:%d" % [spec.seat, spec.discard_id]
		var source: TileView = view._render_tiles.get(key)
		if not is_instance_valid(source): return false
		var id := source.get_instance_id()
		var tile: MeshInstance3D = tile_nodes.get(id)
		if not is_instance_valid(tile) or not tile.visible: return false
		var face := _exposed_printed_bounds([id]) if source.face_up else _project_mesh(tile)
		var volume := (tile.transform * tile.mesh.get_aabb()).grow(-0.001)
		var footprint: Rect2 = spec.rect.grow(-0.05)
		for area in obstacles:
			if not footprint.intersects(area): continue
			var block: Dictionary = obstacles[area]
			var pose: Transform3D
			if block.has("wall_index"):
				# Use the stack's real pose one layer below the reveal landing.
				pose = _wall_flip_landing(block.wall_index, wall_factor, world_unit, width_fit)
				pose.origin.y -= 0.62 * wall_factor
				pose.basis *= Basis(Vector3.RIGHT, PI)
			else:
				var center := G.ordinary_slot_center(block.seat, block.slot, view.human_seat, block.count)
				var rel := G.relative_seat(view.human_seat, block.seat)
				var basis := Basis(Vector3.UP, PI / 2.0 if rel == 1 else -PI / 2.0)
				pose = Transform3D(basis.scaled(Vector3.ONE * river_factor),
					_ordinary_position(center, block.seat, river_factor, world_unit, width_fit))
			if volume.intersects(pose * tile_bounds) or face.intersects(_project_bounds(tile_bounds, pose)): return false
	return true

func _fit_viewport() -> void:
	# The Android HUD fills the safe area nonuniformly. The camera texture must
	# instead share the phone's actual aspect ratio or circles become ovals.
	var pixels := size * get_global_transform_with_canvas().get_scale().abs()
	if pixels.x < 1 or pixels.y < 1: return
	var aspect := pixels.x / pixels.y
	var render_scale := minf(1.0, minf(2560.0 / pixels.x, 1440.0 / pixels.y))
	var target := Vector2i((pixels * render_scale).round())
	if viewport.size == target: return
	viewport.size = target
	# Full-row voice buttons and the two near-badge lane changes bound the
	# verified aspect intervals. At 20:9 the eighth chicken limits a short hand.
	var width_at_1080 := 1080.0 * target.x / target.y
	var clear_rows := (width_at_1080 >= 2000 and width_at_1080 <= 2187) \
		or (width_at_1080 >= 2209 and width_at_1080 <= 2414) \
		or (width_at_1080 >= 2461 and width_at_1080 <= 3000)
	opponent_hand_scale = 1.036 if clear_rows else 1.0
	table_model.scale.x = 1.64 * aspect / G.DESIGN_SIZE.aspect()
	_signatures.clear()
	_changed = true

func _new_mesh(source: Control, mesh: Mesh, collection: Dictionary) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	world.add_child(node)
	var id := source.get_instance_id()
	collection[id] = node
	_sources[id] = weakref(source)
	return node

func sync_tiles() -> void:
	if view == null or viewport == null: return
	_fit_viewport()
	var settled: bool = view.round != null and view.round.phase == RoundState.Phase.SETTLED
	var settlement_started: bool = view.native_settlement_started()
	if settlement_started: clear_own_exposed_flight()
	var seen := {}
	var moved: Array[MeshInstance3D] = []
	var latest: TileView = null
	var board_inverse := view.get_global_transform().affine_inverse()
	var width_fit := minf(1.0, G.DESIGN_SIZE.aspect() / Vector2(viewport.size).aspect())
	var world_unit := _pixel_scale(G.CENTER, 1.0) * width_fit
	var touch_height: float = view.minimum_touch_height()
	var own_hand_bottom: float = view.settlement_hand_bottom() if settlement_started else size.y - 6.0
	var settlement_panel: Rect2 = view._native_settlement.get_rect() if settlement_started and is_instance_valid(view._native_settlement) else Rect2()
	var visual_session: String = view.round._presentation.session if view.round != null else ""
	var own_layout_state := [viewport.size, settled, touch_height, view.human_seat, visual_session, settlement_panel]
	var own_meld_key := hash(view.round.players[view.human_seat].melds) if view.round != null else 0
	var own_travel := 1.0
	for id in _own_exposed_origins:
		var moving = _sources[id].get_ref() if _sources.has(id) else null
		if is_instance_valid(moving) and moving.get_parent() == view._deal_layer:
			own_travel = 1.0 - pow(1.0 - clampf(moving.flight_progress, 0.0, 1.0), 3.0)
			break
	var flip_view: TileView = view._settlement_flip_view
	var flip_card: String = view._native_flip_tile() if is_instance_valid(flip_view) else ""
	for layer in [view._wall_layer, view._discard_layer, view._red_layer, view._meld_layer,
			view._deal_layer] + view.hand_boxes + view.draw_boxes:
		for source in layer.get_children():
			if not source is TileView: continue
			var id: int = source.get_instance_id()
			seen[id] = true
			source.presentation_3d = true
			var masked: bool = source.tile == "hidden0"
			var face_up: bool = source.face_up and not masked
			var flipping_wall: bool = source == flip_view
			var key: String = source.tile if face_up and source.tile != "" else "wan1"
			# Its printed surface can become visible as the selected tile turns onto its edge.
			if flipping_wall and flip_card != "": key = flip_card
			var node: MeshInstance3D = tile_nodes.get(id)
			if node == null: node = _new_mesh(source, _meshes[key], tile_nodes)
			var xf: Transform2D = board_inverse * source.get_global_transform()
			var kind := str(source.get_meta("new_kind", ""))
			var wall_index := int(source.get_meta("wall_ring_index", -1)) if kind == "wall" else -1
			var wall_flip: bool = wall_index >= 0 and wall_index == view._settlement_flip_index
			var hand := kind in ["hand", "draw"]
			var own_hand: bool = hand and source.standing_back_view == -1
			var own_exposed: bool = kind in ["meld", "red"] and int(source.get_meta("v2_seat", -1)) == view.human_seat
			if not settled and source.latest_highlight and source.is_visible_in_tree() and kind in ["ordinary", "red"] and int(source.get_meta("meld_index", -1)) < 0:
				latest = source
			var signature := hash([key, source.face_up, xf, source.size, source.is_visible_in_tree(),
				source.modulate, source.self_modulate, source.standing_back_view, kind, source.flight_pitch, source.flight_progress,
				source.z_index, source.highlight, source.latest_highlight, source.ai_teach_highlight,
				source.get_meta("flight_origin_offset_3d", Vector3.ZERO), source.get_meta("ordinary_flight_3d", {}), source.get_meta("claimed_flight_origin_3d", Transform3D.IDENTITY), source.get_meta("v2_draw_flight", false), source.get_meta("meld_room_3d", {}),
				source.get_parent().get_instance_id(),
				source.get_meta("charge_chicken", false), source.get_meta("gold_chicken", false),
				source.get_meta("v2_charge", false), source.get_meta("kong_offset_2d", Vector2.ZERO), source.get_meta("kong_offset_3d", Vector2.ZERO), settlement_started if own_exposed else settled, settlement_started, _own_hand_pitch if own_hand else 0.0,
				source.get_meta("v2_draw_reserve", 1.0) if own_hand else 1.0, own_hand_bottom if own_hand else 0.0,
				own_meld_key if kind in ["meld", "red"] and int(source.get_meta("v2_seat", -1)) == view.human_seat else 0,
				own_travel if _own_exposed_targets.has(id) else 1.0, view._wall_raise if kind == "wall" else 1.0])
			if wall_flip:
				signature = hash([signature, view._settlement_flip_support, view._settlement_flip_travel])
			if source.get_parent() != view._deal_layer and (own_hand or (kind in ["meld", "red"] and int(source.get_meta("v2_seat", -1)) == view.human_seat)):
				own_layout_state.append([id, signature])
			if kind == "wall" and view._wall_screen_seat(int(view._wall_segment_for_index(wall_index).get("seat", 0))) in [1, 2]:
				own_layout_state.append([id, signature])
			if source.get_parent() != view._deal_layer and kind in ["ordinary", "meld", "red", "hand", "draw"] and not (int(source.get_meta("v2_seat", -1)) == view.human_seat and kind != "ordinary"):
				# Only spatial obstacle changes invalidate this cache; highlights do not.
				own_layout_state.append([id, xf, source.size, source.is_visible_in_tree(), kind, source.face_up, source.standing_back_view, source.flight_pitch])
			if _signatures.get(id) == signature: continue
			_signatures[id] = signature
			moved.append(node)
			_changed = true
			node.mesh = _meshes[key]
			node.visible = source.is_visible_in_tree() and source.modulate.a > 0.01
			if not node.visible: continue
			var center: Vector2 = xf * (source.size / 2.0)
			var source_center := center
			var scale_2d := xf.get_scale().abs()
			var angle := -xf.get_rotation()
			var pitch := 0.0 if face_up else PI
			if own_hand: pitch = _own_hand_pitch if settled else deg_to_rad(63)
			elif hand and not face_up: pitch = PI / 2.0
			if source.flight_pitch >= 0: pitch = source.flight_pitch
			# Masked network events may outlive the snapshot that reveals the hands.
			if masked: pitch = PI / 2.0 if hand else PI
			var wall_upper := false
			var side_wall := false
			if kind == "wall":
				wall_upper = wall_index % 2 == 0
				var side: int = view._wall_screen_seat(int(view._wall_segment_for_index(wall_index).get("seat", 0)))
				side_wall = side in [0, 2]
				if wall_upper: center -= G.wall_upper_offset(side)
				if side == 1: center.y -= 28.0
				# The flip is a physical rotation, not a shrinking cardboard sprite.
				if flipping_wall:
					pitch = acos(clampf(scale_2d.y / maxf(scale_2d.x, 0.001), 0, 1))
					if not source.face_up: pitch = PI - pitch
			# Uniform world scales preserve the source model's 1 : 1.34 : 0.62 shape.
			# A single physical baseline gives near and far rows their natural parallax.
			var rel := G.relative_seat(view.human_seat, int(source.get_meta("v2_seat", view.human_seat)))
			var charge_outward := Vector2.ZERO
			if kind == "red" and bool(source.get_meta("v2_charge", false)):
				charge_outward = [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT][rel]
				# Project through the same upright row center, then align the actual model edge.
				center -= charge_outward * (source.size.y * scale_2d.y - source.size.x * scale_2d.x) / 2.0
			var kong_offset := Vector2.ZERO
			if kind in ["meld", "red"] and int(source.get_meta("meld_index", -1)) >= 0:
				# Pack a kong in model units; sprite spacing changes with the camera and aspect.
				center -= Vector2(source.get_meta("kong_offset_2d", Vector2.ZERO))
				kong_offset = source.get_meta("kong_offset_3d", Vector2.ZERO)
			var side_hand: bool = hand and source.standing_back_view in [1, 3]
			var motion := float(source.flight_progress)
			var flight := motion if source.get_parent() == view._deal_layer else -1.0
			var draw_flight: bool = flight >= 0.0 and bool(source.get_meta("v2_draw_flight", false))
			var hand_blend := (smoothstep(0.0, 0.75, flight) if draw_flight else 1.0 - smoothstep(0.0, 0.75, flight)) if flight >= 0.0 else 1.0
			var side_row: bool = side_wall or (side_hand and (flight < 0.0 or draw_flight)) or (kind in ["meld", "red"] and rel in [1, 3] and flight < 0.0)
			if rel == 0 and kind in ["meld", "red"] and center.y < G.HAND_BOTTOM - G.TILE_BASE.y * G.OWN_UNIT:
				center.y -= 72.0 if settlement_started else 12.0
			var near_fit := lerpf(1.0, width_fit, 0.55)
			var side_unit := 1.07 if face_up else 1.30
			var weight := lerpf(1.0, 1.04 * near_fit / width_fit * 1.02 if own_hand else (side_unit if side_hand else 1.0), hand_blend)
			var factor: float = world_unit * source.size.x * scale_2d.x * weight
			var row_offset := 0.0
			if side_row:
				var along_row := center.y - G.CENTER.y
				if side_hand:
					# Strip the old sprite's baked-in slant; projection gives this line its angle.
					center.x -= along_row * 0.105 * (1 if source.standing_back_view == 1 else -1) * hand_blend
				var row_spacing := side_unit * 0.95 if side_hand else (0.95 if kind in ["ordinary", "red", "meld"] else 1.0)
				row_offset = along_row * world_unit * row_spacing * (hand_blend if side_hand else 1.0)
				center.y = lerpf(center.y, G.CENTER.y, hand_blend) if side_hand else G.CENTER.y
			var converge := lerpf(0.79, 1.09, center.y / size.y)
			var along_scale := converge * lerpf(0.58, 1.0, width_fit)
			var row_x := center.x
			var row_anchor := G.CENTER.x
			if own_hand:
				var draw_gap := 24.0 if kind == "draw" else 0.0
				# A merged fourteen-tile row no longer reserves space for a separate draw.
				var reserve_draw := float(source.get_meta("v2_draw_reserve", 1.0)) if not settlement_started else 1.0
				var own_scale := 1.13 * near_fit * 1.02
				along_scale = lerpf(along_scale, own_scale, hand_blend)
				row_anchor += ((-64.0 * reserve_draw + draw_gap) * own_scale - 46.0 * reserve_draw) * hand_blend
				center.y += 32.0 * hand_blend
			center.x = row_anchor + (row_x - G.CENTER.x) * along_scale
			if side_hand: center.y -= 112.0 * hand_blend
			var height := (1.34 * absf(sin(pitch)) + 0.62 * absf(cos(pitch))) * factor / 2.0 + 0.03
			var position_3d := _at_height(center, height)
			position_3d.z += row_offset
			if kind == "ordinary": position_3d = _ordinary_position(source_center, int(source.get_meta("v2_seat")), factor, world_unit, width_fit)
			position_3d += Vector3(kong_offset.x, 0, kong_offset.y) * factor
			position_3d += Vector3(charge_outward.x, 0, charge_outward.y) * ((TILE_FACE_HALF.y - TILE_FACE_HALF.x) * factor)
			if flight >= 0.0:
				position_3d.y += factor * (1.0 - pow(absf(flight * 2.0 - 1.0), 2.0)) * (1.75 if side_hand else 0.9)
			elif motion >= 0.0:
				position_3d.y += factor * (1.0 - motion) * 0.38
			if kind == "wall":
				if wall_upper or (source.face_up and not wall_flip): position_3d.y += 0.62 * factor
				if flipping_wall: position_3d.y += sin(pitch) * factor * 0.35
				position_3d.y -= (1.0 - view._wall_raise) * 1.26 * factor
			var basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, pitch)
			node.transform = Transform3D(basis.scaled(Vector3.ONE * factor), position_3d)
			if wall_flip and view._settlement_flip_support >= 0:
				var travel: float = view._settlement_flip_travel if flipping_wall else float(face_up)
				if travel > 0.0:
					var landing := _wall_flip_landing(view._settlement_flip_support, world_unit * source.size.x, world_unit, width_fit)
					node.transform = node.transform.interpolate_with(landing, travel)
					node.position.y += 3.2 * travel * (1.0 - travel) * factor
			var ordinary_flight: Dictionary = source.get_meta("ordinary_flight_3d", {})
			if flight >= 0.0 and not ordinary_flight.is_empty():
				var target_center: Vector2 = source_center if flight >= 1.0 else ordinary_flight.target
				var target_factor: float = world_unit * ordinary_flight.width
				var target_position := _ordinary_position(target_center, int(source.get_meta("v2_seat")), target_factor, world_unit, width_fit)
				var target_basis := Basis(Vector3.UP, -float(ordinary_flight.angle)).scaled(Vector3.ONE * target_factor)
				var travel: float = Tween.interpolate_value(0.0, 1.0, clampf(flight, 0.0, 1.0), 1.0, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
				node.transform = Transform3D(ordinary_flight.origin).interpolate_with(Transform3D(target_basis, target_position), travel)
				node.position.y += node.basis.get_scale().x * (1.0 - pow(absf(flight * 2.0 - 1.0), 2.0)) * 0.9
			if own_hand and (flight < 0.0 or draw_flight):
				# The same bottom edge is used by landed hands and their incoming flights.
				for _step in 2:
					center.y += (own_hand_bottom - _project_mesh(node).end.y) * hand_blend
					node.position = _at_height(center, height)
			if hand and not side_hand and (flight < 0.0 or draw_flight):
				var step: float = (source.size.x + G.TILE_GAP) * along_scale
				var normal_step := _at_height(center + Vector2(step, 0), height).x - node.position.x
				if normal_step > factor * 0.98:
					var anchor := _at_height(Vector2(row_anchor, center.y), height).x
					node.position.x = lerpf(node.position.x, lerpf(anchor, node.position.x, factor * 0.98 / normal_step), hand_blend)
			if flight >= 0.0 and ordinary_flight.is_empty():
				node.position += Vector3(source.get_meta("flight_origin_offset_3d", Vector3.ZERO)) * (1.0 - smoothstep(0.0, 1.0, flight))
			if side_hand or (source.get_parent() == view._deal_layer and flight < 0.0):
				# Include flights before their destination hand metadata is assigned.
				for _step in 3:
					var bounds := _project_mesh(node)
					var shift := maxf(8.0 - bounds.position.x, 0.0) + minf(size.x - 8.0 - bounds.end.x, 0.0)
					if is_zero_approx(shift): break
					var screen := camera.unproject_position(node.position) / Vector2(viewport.size) * size
					node.position += _at_height(screen + Vector2(shift, 0), height) - _at_height(screen, height)
			_opponent_hand_slots.erase(id)
			if hand and rel != 0 and opponent_hand_scale > 1.0 and ordinary_flight.is_empty():
				_opponent_hand_slots[id] = _project_mesh(node)
				# Keep the physical outer edge and base fixed. A shared tangent anchor
				# scales the row spacing and the separate draw together.
				var box: AABB = node.transform * node.mesh.get_aabb()
				var pivot := Vector3(0, box.position.y, box.position.z)
				if rel != 2:
					pivot = Vector3(box.end.x if rel == 1 else box.position.x, box.position.y, 2.0)
				var multiplier := lerpf(1.0, opponent_hand_scale, hand_blend)
				node.position = pivot + (node.position - pivot) * multiplier
				node.basis = node.basis.scaled(Vector3.ONE * multiplier)
			if rel == 0 and kind in ["meld", "red"]:
				node.set_meta("exposed_transform", node.transform)
			if _own_exposed_targets.has(id):
				if flight >= 0.0 and _own_exposed_origins.has(id):
					var travel := 1.0 - pow(1.0 - clampf(flight, 0.0, 1.0), 3.0)
					node.position = Vector3(_own_exposed_origins[id]).lerp(_own_exposed_targets[id].origin, travel)
					node.position.y += factor * (1.0 - pow(absf(flight * 2.0 - 1.0), 2.0)) * 0.9
				elif source.get_parent() != view._deal_layer:
					node.transform = Transform3D(_own_exposed_previous.get(id, _own_exposed_targets[id])).interpolate_with(_own_exposed_targets[id], own_travel)
			if flight >= 0.0 and source.has_meta("claimed_flight_origin_3d"):
				var travel := 1.0 - pow(1.0 - clampf(flight, 0.0, 1.0), 3.0)
				node.transform = Transform3D(source.get_meta("claimed_flight_origin_3d")).interpolate_with(node.transform, travel)
			var room: Dictionary = source.get_meta("meld_room_3d", {})
			if not room.is_empty():
				var progress := float(room.progress)
				node.transform = Transform3D(room.origin).interpolate_with(room.target, progress)
				node.position.y += float(room.get("lift", 0.0)) * 4.0 * progress * (1.0 - progress)
			_rects[id] = _project_mesh(node)
	for source in [view._dice_red, view._dice_white]:
		if not is_instance_valid(source): continue
		var id: int = source.get_instance_id()
		seen[id] = true
		source.presentation_3d = true
		var node: MeshInstance3D = dice_nodes.get(id)
		var color := "red" if source == view._dice_red else "black"
		if node == null: node = _new_mesh(source, _meshes[color], dice_nodes)
		var signature := hash([source.value, source.position, source.scale, source.rotation, source.visible, source.roll_progress, source.roll_lift])
		if _signatures.get(id) == signature: continue
		_changed = true
		_signatures[id] = signature
		moved.append(node)
		node.visible = source.is_visible_in_tree()
		var coords: Array = _dice_normals[color][str(source.value)]
		var normal := Vector3(coords[0], coords[1], coords[2])
		var center: Vector2 = source.position + source.size / 2.0
		var factor := _pixel_scale(center, source.size.x * source.scale.x) / 0.8
		var remaining := pow(1.0 - float(source.roll_progress), 2.3)
		var direction := 1.0 if color == "red" else -1.0
		var basis := Basis(Vector3.FORWARD, direction * TAU * remaining) * Basis(Vector3.RIGHT, TAU * 2.0 * remaining)
		basis *= Basis(Vector3.UP, -source.rotation) * Basis(Quaternion(normal, Vector3.UP))
		var support := 0.4 * (absf(basis.x.y) + absf(basis.y.y) + absf(basis.z.y))
		node.transform = Transform3D(basis.scaled(Vector3.ONE * factor),
			_at_height(center, support * factor + 0.04) + Vector3.UP * factor * float(source.roll_lift))
	if is_instance_valid(view._dice_shadow): view._dice_shadow.hide()
	for collection in [tile_nodes, dice_nodes]:
		for id in collection.keys():
			if seen.has(id): continue
			collection[id].queue_free()
			collection.erase(id)
			var source = _sources[id].get_ref()
			if is_instance_valid(source): source.presentation_3d = false
			_sources.erase(id)
			_signatures.erase(id)
			_rects.erase(id)
			_opponent_hand_slots.erase(id)
			_changed = true
	var own_layout_key := hash(own_layout_state)
	if own_layout_key != _own_exposed_layout_key:
		_own_exposed_layout_key = own_layout_key
		if _own_exposed_targets.is_empty():
			_clear_own_exposed_faces(moved, own_hand_bottom if settlement_started else INF, settlement_panel)
	_update_discard_marker(latest)
	if _changed:
		geometry_revision += 1
		# frame_pre_draw runs after the normal transform flush.
		for node in moved:
			node.force_update_transform()
		discard_marker.force_update_transform()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		queue_redraw()
		_changed = false

func _clear_own_exposed_faces(moved: Array[MeshInstance3D], settlement_bottom: float = INF, settlement_panel: Rect2 = Rect2()) -> void:
	var groups := {}
	var pieces := {}
	var hand := Rect2()
	var walls := {}
	var wall_and_hand_tiles: Array[Rect2] = []
	var obstacles: Array[Rect2] = []
	var left_hand := Rect2()
	for id in tile_nodes:
		var source = _sources[id].get_ref()
		var node: MeshInstance3D = tile_nodes[id]
		if not is_instance_valid(source) or not node.visible: continue
		if source.get_parent() == view._deal_layer: continue
		if source.has_meta("meld_room_3d"): return
		var kind := str(source.get_meta("new_kind", ""))
		var seat := int(source.get_meta("v2_seat", -1))
		if kind in ["ordinary", "meld", "red", "hand", "draw"] and not (seat == view.human_seat and kind != "ordinary"):
			var obstacle: Rect2 = _opponent_hand_slots[id] if _opponent_hand_slots.has(id) else _project_mesh(node)
			obstacles.append(obstacle)
			if kind in ["hand", "draw"] and obstacle.get_center().x < size.x * 0.25:
				left_hand = left_hand.merge(obstacle) if left_hand.has_area() else obstacle
		if kind == "wall":
			var segment: Dictionary = view._wall_segment_for_index(int(source.get_meta("wall_ring_index", 0)))
			var side: int = view._wall_screen_seat(int(segment.get("seat", 0)))
			var wall_bounds := _project_mesh(node)
			wall_and_hand_tiles.append(wall_bounds)
			walls[side] = walls[side].merge(wall_bounds) if walls.has(side) else wall_bounds
		if seat == view.human_seat and kind in ["hand", "draw"]:
			var bounds := _project_mesh(node)
			wall_and_hand_tiles.append(bounds)
			hand = hand.merge(bounds) if hand.has_area() else bounds
		if seat == view.human_seat and kind in ["meld", "red"]:
			var meld_index := int(source.get_meta("meld_index", -1))
			var melds: Array = view.round.players[view.human_seat].melds
			var shape = melds[meld_index].duplicate(true) if meld_index >= 0 and meld_index < melds.size() else null
			pieces[[view._render_key(source), source.tile, source.face_up, shape]] = id
			node.transform = node.get_meta("exposed_transform", node.transform)
			_rects[id] = _project_mesh(node)
			var meld := int(source.get_meta("meld_index", -1))
			var key := "meld%d" % meld if meld >= 0 else "red%d" % id
			if not groups.has(key): groups[key] = []
			groups[key].append(id)
	if groups.is_empty() or not hand.has_area():
		_own_placed_poses.clear()
		return
	_own_exposed_left_hand = left_hand
	# Use the owner's event order, independent of node pooling and card values.
	var order: Array = groups.keys()
	order.sort_custom(func(a, b): return _own_group_order(groups[a]) > _own_group_order(groups[b]))
	# Missing walls leave real free space beside the hand. The old sprite wall
	# rectangles are not projected geometry and must not act as phantom obstacles.
	var group_height := 0.0
	for ids in groups.values(): group_height = maxf(group_height, _exposed_printed_bounds(ids).size.y)
	var free_top := maxf(size.y * 0.6, hand.position.y - group_height * 2.0 - 24.0)
	var near_wall: Rect2 = walls.get(1, Rect2(Vector2(G.CENTER.x, free_top), Vector2.ZERO))
	var side_wall: Rect2 = walls.get(2, Rect2(Vector2(left_hand.end.x, free_top), Vector2.ZERO))
	var bottom := minf(minf(G.TABLE_BOUNDS.end.y, size.y - view.minimum_touch_height() - 6.0), settlement_bottom)
	var beside := Rect2(Vector2(2.0, maxf(near_wall.end.y, side_wall.end.y) + 6.0), Vector2.ZERO)
	beside.size = Vector2(hand.position.x - 2.0 - beside.position.x, bottom - beside.position.y)
	var corner := Rect2(Vector2(side_wall.end.x + 6.0, near_wall.position.y + 2.0), Vector2.ZERO)
	corner.size = Vector2(near_wall.position.x - 6.0 - corner.position.x, hand.position.y - 2.0 - corner.position.y)
	var context := [view.round._presentation.session, view.human_seat, viewport.size,
		camera.global_transform, camera.get_camera_projection(), bottom]
	for seat in 4: obstacles.append(view._seat_hud_rect(seat))
	if settlement_panel.has_area(): obstacles.append(settlement_panel)
	var placed := false
	if context == _own_placed_context and pieces.size() == _own_placed_poses.size():
		var blockers: Array[Rect2] = obstacles + wall_and_hand_tiles
		# Keep the last landing through the final flight. New public pieces still get packed.
		if view.round.phase == RoundState.Phase.SETTLED and not view.native_settlement_started(): blockers.clear()
		placed = _restore_own_placement(pieces, bottom, blockers)
	if not placed:
		placed = _pack_centered_own_exposed(groups, order, hand.position.y - 8.0, obstacles + wall_and_hand_tiles)
	var areas := [beside, corner]
	if settlement_bottom != INF:
		# The flat revealed hand occupies the near center. The right-hand end of
		# the same strip can hold the public groups when the side wall fills the left.
		var right := maxf(G.CENTER.x, hand.end.x + 6.0)
		areas.append(Rect2(right, beside.position.y, size.x - right - 8.0, beside.size.y))
		obstacles.append_array(wall_and_hand_tiles)
	obstacles.sort_custom(func(a, b): return a.position.x > b.position.x)
	# Where the left player's hand spans the entire strip, anchor below it to
	# our hand instead of following the wall or the opponent's separate draw.
	if beside.end.x <= left_hand.end.x:
		var aligned := beside
		aligned.position.y = maxf(beside.position.y, hand.position.y - 6.0)
		aligned.size.y = bottom - aligned.position.y
		areas.push_front(aligned)
	for area: Rect2 in areas:
		if placed: break
		for key in order:
			for id in groups[key]: tile_nodes[id].transform = tile_nodes[id].get_meta("exposed_transform")
		placed = _pack_own_exposed(groups, order, area, obstacles)
	if not placed:
		# The open ends of the near wall can fit a complete row just above the hand.
		var above := Rect2(2.0, near_wall.position.y, size.x - 10.0, hand.position.y - 6.0 - near_wall.position.y)
		for key in order:
			for id in groups[key]: tile_nodes[id].transform = tile_nodes[id].get_meta("exposed_transform")
		var above_obstacles: Array = obstacles if settlement_bottom != INF else obstacles + wall_and_hand_tiles
		above_obstacles.sort_custom(func(a, b): return a.position.x > b.position.x)
		placed = _pack_own_exposed(groups, order, above, above_obstacles, true)
	if not placed:
		for key in order:
			for id in groups[key]: tile_nodes[id].transform = tile_nodes[id].get_meta("exposed_transform")
		placed = _pack_own_exposed(groups, order, beside, obstacles, true)
	if not placed:
		for key in order:
			for id in groups[key]: tile_nodes[id].transform = tile_nodes[id].get_meta("exposed_transform")
		push_error("自己碰杠和鸡牌近侧空间不足，禁止移到桌心: %s / %s" % [beside, corner])
	_own_placed_context = context
	_own_placed_poses.clear()
	if placed:
		for key in pieces: _own_placed_poses[key] = tile_nodes[pieces[key]].transform
	_changed = true
	for key in order:
		for id in groups[key]:
			_rects[id] = _project_mesh(tile_nodes[id])
			if not moved.has(tile_nodes[id]): moved.append(tile_nodes[id])

func _own_group_order(ids: Array) -> float:
	var source: TileView = _sources[ids[0]].get_ref()
	var index := int(source.get_meta("meld_index", -1))
	if index >= 0:
		var meld: Dictionary = view.round.players[view.human_seat].melds[index]
		return float(meld.get("formed_at", meld.get("after_discard", 0))) * 2.0 + index * 0.001
	return float(source.get_meta("discard_id", 0)) * 2.0 + 1.0

func _pack_centered_own_exposed(groups: Dictionary, reverse_order: Array, bottom: float, obstacles: Array[Rect2], row_width: float = 0.0) -> bool:
	if row_width == 0.0: row_width = size.x - 540.0
	for ids in groups.values():
		for id in ids: tile_nodes[id].transform = tile_nodes[id].get_meta("exposed_transform")
	var rows: Array = [[]]
	var spans: Array[float] = [0.0]
	var heights: Array[float] = [0.0]
	var order := reverse_order.duplicate()
	order.reverse()
	for key in order:
		var bounds := _exposed_printed_bounds(groups[key])
		var row := rows.size() - 1
		if spans[row] + bounds.size.x > row_width and not rows[row].is_empty():
			rows.append([])
			spans.append(0.0)
			heights.append(0.0)
			row += 1
		rows[row].append(key)
		spans[row] += bounds.size.x + 6.0
		heights[row] = maxf(heights[row], bounds.size.y + 8.0)
	var total_height := 0.0
	for height in heights: total_height += height
	for shift in [0.0, 24.0, 48.0, 72.0]:
		for key in order:
			for id in groups[key]: tile_nodes[id].transform = tile_nodes[id].get_meta("exposed_transform")
		var top: float = bottom - total_height - float(shift)
		var fits := true
		for row in rows.size():
			var cursor := Vector2(G.CENTER.x + (spans[row] - 6.0) / 2.0, top)
			var deepest = rows[row][0]
			for key in rows[row]:
				if _exposed_printed_bounds(groups[key]).size.y > _exposed_printed_bounds(groups[deepest]).size.y:
					deepest = key
			_position_exposed_group(groups[deepest], cursor, INF)
			var hand_edge := _own_exposed_hand_edge(groups[deepest])
			for i in range(rows[row].size() - 1, -1, -1):
				var ids: Array = groups[rows[row][i]]
				var bounds := _position_exposed_group(ids, cursor, hand_edge)
				for obstacle in obstacles:
					if bounds.grow(-0.5).intersects(obstacle): fits = false
				cursor.x = bounds.position.x - 6.0
			top += heights[row]
		if fits: return true
	var hud: Rect2 = view._seat_hud_rect(view.human_seat)
	var clear_width := (G.CENTER.x - hud.end.x - 12.0) * 2.0
	if clear_width > 0.0 and clear_width < row_width - 1.0:
		return _pack_centered_own_exposed(groups, reverse_order, bottom, obstacles, clear_width)
	return false

func _restore_own_placement(pieces: Dictionary, bottom: float, obstacles: Array[Rect2]) -> bool:
	# Keep the last legal landing when an ordinary draw/discard frees space.
	var area := Rect2(0.0, 0.0, size.x, bottom).grow(0.2)
	for key in pieces:
		var id: int = pieces[key]
		var node: MeshInstance3D = tile_nodes[id]
		if not _own_placed_poses.has(key) or not node.basis.is_equal_approx(_own_placed_poses[key].basis): return false
		node.transform = _own_placed_poses[key]
		var bounds := _exposed_printed_bounds([id])
		if not area.encloses(bounds): return false
		for obstacle in obstacles:
			if bounds.intersects(obstacle): return false
	return true

func _pack_own_exposed(groups: Dictionary, order: Array, area: Rect2, obstacles: Array[Rect2], bottom_up: bool = false) -> bool:
	if area.size.x <= 0.0 or area.size.y <= 0.0: return false
	var cursor := Vector2(area.end.x, area.end.y - 6.0 if bottom_up else area.position.y)
	var row_height := 0.0
	var hand_edge := INF
	for key in order:
		var ids: Array = groups[key]
		var bounds := _position_own_exposed_row(ids, cursor, obstacles, bottom_up, hand_edge)
		if bounds.position.x == -INF and row_height == 0.0 and not bottom_up:
			cursor.y = maxf(cursor.y, _own_exposed_left_hand.end.y + 6.0)
			bounds = _position_own_exposed_row(ids, cursor, obstacles, bottom_up)
		if bounds.position.x < area.position.x and row_height > 0.0:
			cursor.y += (row_height + 6.0) * (-1.0 if bottom_up else 1.0)
			cursor.x = area.end.x
			row_height = 0.0
			hand_edge = INF
			bounds = _position_own_exposed_row(ids, cursor, obstacles, bottom_up)
		if bounds.position.x < area.position.x - 0.2 or bounds.position.y < area.position.y - 0.2 or bounds.end.y > area.end.y + 0.2:
			return false
		cursor.x = bounds.position.x - 6.0
		row_height = maxf(row_height, bounds.size.y)
		hand_edge = _own_exposed_hand_edge(ids)
	return true

func _own_exposed_hand_edge(ids: Array) -> float:
	var edge := -INF
	for id in ids:
		var node: MeshInstance3D = tile_nodes[id]
		var center := node.transform * Vector3(0.0, TILE_FACE_HEIGHT, 0.0)
		var half := absf(node.basis.x.z) * TILE_FACE_HALF.x + absf(node.basis.z.z) * TILE_FACE_HALF.y
		edge = maxf(edge, center.z + half)
	return edge

func _position_own_exposed_row(ids: Array, cursor: Vector2, obstacles: Array[Rect2], bottom_up: bool, hand_edge: float = INF) -> Rect2:
	if is_finite(hand_edge):
		return _position_exposed_group_clear(ids, cursor, obstacles, hand_edge)
	var top := cursor
	if bottom_up: top.y -= _exposed_printed_bounds(ids).size.y
	var bounds := _position_exposed_group_clear(ids, top, obstacles)
	if bottom_up:
		top.y += cursor.y - bounds.end.y
		bounds = _position_exposed_group_clear(ids, top, obstacles)
	return bounds

func _position_exposed_group_clear(ids: Array, right_top: Vector2, obstacles: Array[Rect2], hand_edge: float = INF) -> Rect2:
	var bounds := _position_exposed_group(ids, right_top, hand_edge)
	# A charge continuing an existing row can use gaps outside the individual tiles.
	# The bounding box of the entire side hand also covers empty felt near its end.
	var starts_row := not is_finite(hand_edge)
	if starts_row and bounds.intersects(_own_exposed_left_hand):
		bounds.position.x = -INF
		return bounds
	for obstacle in obstacles:
		if not bounds.intersects(obstacle): continue
		right_top.x = obstacle.position.x - 6.0
		bounds = _position_exposed_group(ids, right_top, hand_edge)
		if starts_row and bounds.intersects(_own_exposed_left_hand):
			bounds.position.x = -INF
			return bounds
	return bounds

func _position_exposed_group(ids: Array, right_top: Vector2, hand_edge: float) -> Rect2:
	var align_hand_edge := is_finite(hand_edge)
	if align_hand_edge:
		var shift_z := hand_edge - _own_exposed_hand_edge(ids)
		for id in ids: tile_nodes[id].position.z += shift_z
	var bounds := _exposed_printed_bounds(ids)
	for _step in 4:
		var anchor: MeshInstance3D = tile_nodes[ids[0]]
		var screen := camera.unproject_position(anchor.position) / Vector2(viewport.size) * size
		var shift := right_top - Vector2(bounds.end.x, bounds.position.y)
		if align_hand_edge: shift.y = 0.0
		var delta := _at_height(screen + shift, anchor.position.y) - _at_height(screen, anchor.position.y)
		for id in ids: tile_nodes[id].position += delta
		bounds = _exposed_printed_bounds(ids)
	return bounds

func _exposed_printed_bounds(ids: Array) -> Rect2:
	var bounds := Rect2()
	var first := true
	for id in ids:
		var node: MeshInstance3D = tile_nodes[id]
		for x in [-0.45, 0.45]:
			for z in [-0.60, 0.60]:
				var point := camera.unproject_position(node.transform * Vector3(x, 0.31, z)) / Vector2(viewport.size) * size
				bounds = Rect2(point, Vector2.ZERO) if first else bounds.expand(point)
				first = false
	return bounds

func _update_discard_marker(source: TileView) -> void:
	var source_id := source.get_instance_id() if is_instance_valid(source) else 0
	var blocked: bool = view.native_actions_pending()
	# Occlusion only changes when a mesh, latest discard, or presentation queue changes.
	if not _changed and source_id == _marker_source_id and blocked == _marker_blocked: return
	_marker_source_id = source_id
	_marker_blocked = blocked
	var show_marker: bool = is_instance_valid(source) and tile_nodes.has(source.get_instance_id()) and tile_nodes[source.get_instance_id()].visible
	if show_marker:
		show_marker = source.get_parent() != view._deal_layer and not blocked and pick_tile(project_tile(source).get_center(), false) == source
	if discard_marker.visible != show_marker:
		discard_marker.visible = show_marker
		_changed = true
	if not show_marker: return
	var node: MeshInstance3D = tile_nodes[source.get_instance_id()]
	var factor := node.basis.get_scale().x
	var bounds := project_tile(source)
	# New rows grow outwards; this edge stays clear of the preceding printed row.
	var outward: Vector2 = [Vector2.DOWN, Vector2.RIGHT, Vector2.UP, Vector2.LEFT][G.relative_seat(view.human_seat, int(source.get_meta("v2_seat")))]
	var edge := bounds.get_center() + bounds.size * outward / 2.0
	var height := node.position.y + factor
	var at := _at_height(edge + outward * 20.0, height)
	var direction := (_at_height(edge, height) - at).normalized()
	var marker_transform := Transform3D(Basis(Quaternion(Vector3.UP, direction)).scaled(Vector3.ONE * factor), at)
	if not discard_marker.transform.is_equal_approx(marker_transform):
		discard_marker.transform = marker_transform
		_changed = true

func _project_mesh(node: MeshInstance3D) -> Rect2:
	return _project_bounds(node.mesh.get_aabb(), node.transform)

func _project_bounds(box: AABB, pose: Transform3D) -> Rect2:
	var result := Rect2()
	for i in 8:
		var point := camera.unproject_position(pose * box.get_endpoint(i)) / Vector2(viewport.size) * size
		result = Rect2(point, Vector2.ZERO) if i == 0 else result.expand(point)
	return result

# Badges and exposed groups are anchored to the permanent layout slots. Reading
# and picking the physical tile still uses the enlarged mesh.
func tile_layout_slot(tile: TileView) -> Rect2:
	return _opponent_hand_slots.get(tile.get_instance_id(), project_tile(tile))

func project_tile(tile: TileView) -> Rect2:
	return _rects.get(tile.get_instance_id(), Rect2())

func pick_tile(point: Vector2, interactive_only: bool = true) -> TileView:
	var pixel := point / size * Vector2(viewport.size)
	var from := camera.project_ray_origin(pixel)
	var to := from + camera.project_ray_normal(pixel) * 100.0
	var selected: TileView = null
	var distance := INF
	for id in tile_nodes:
		var source = _sources[id].get_ref()
		var node: MeshInstance3D = tile_nodes[id]
		if not is_instance_valid(source) or (interactive_only and not source.interactive) or not node.visible: continue
		var inverse := node.transform.affine_inverse()
		var intersection: Variant = node.mesh.get_aabb().intersects_segment(inverse * from, inverse * to)
		if intersection == null: continue
		var at := from.distance_squared_to(node.transform * intersection)
		if at < distance:
			distance = at
			selected = source
	return selected

func _gui_input(event: InputEvent) -> void:
	var touch := event is InputEventScreenTouch
	var mouse: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	var motion := event is InputEventScreenDrag or event is InputEventMouseMotion
	if not touch and not mouse and not motion: return
	if mouse and OS.has_feature("android"): return
	var pointer: int = event.index if touch or event is InputEventScreenDrag else -2
	if (touch or mouse) and event.pressed:
		if _pointer != -1: return
		_pressed = pick_tile(event.position)
		if _pressed == null: return
		_pointer = pointer
		_press_at = event.position
	if not is_instance_valid(_pressed):
		_pointer = -1
		return
	if _pointer != pointer: return
	var forwarded: InputEvent = event.duplicate()
	forwarded.position = _pressed.size / 2.0 + event.position - _press_at
	if (touch or mouse) and not event.pressed and pick_tile(event.position) != _pressed:
		forwarded.position = Vector2(-1000, -1000)
	_pressed.gui_input.emit(forwarded)
	if (touch or mouse) and not event.pressed:
		_pressed = null
		_pointer = -1
	accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_pressed = null
		_pointer = -1

func _draw() -> void:
	for id in tile_nodes:
		var source = _sources[id].get_ref()
		if not is_instance_valid(source) or not tile_nodes[id].visible: continue
		var color := Color.TRANSPARENT
		if source.highlight: color = Color("#f2ce72")
		if source.ai_teach_highlight: color = Color("#5ad4ff")
		if color.a > 0: draw_rect(project_tile(source).grow(2), color, false, 3)
		var badge := "金" if source.get_meta("gold_chicken", false) else ""
		if badge != "":
			var center := project_tile(source).position + Vector2(12, 12)
			draw_circle(center, 15, Color("#9c6e28"))
			draw_string(TileView._font(), center + Vector2(-10, 7), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#fff7dc"))
