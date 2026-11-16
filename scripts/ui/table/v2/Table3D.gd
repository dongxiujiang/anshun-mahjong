extends Control
## Real meshes mirror the existing presentation timeline; RoundState stays authoritative.
const G = preload("res://scripts/ui/table/v2/TableV2Geometry.gd")
const MODEL_PATH := "res://res/models/mahjong3d/"
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
var _dice_normals: Dictionary
var _pressed: TileView
var _press_at := Vector2.ZERO
var _pointer := -1
var _changed := true
var _own_hand_pitch := deg_to_rad(63)
var discard_marker: MeshInstance3D

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
	var settled: bool = view != null and view.round != null and view.round.phase == RoundState.Phase.SETTLED
	_own_hand_pitch = move_toward(_own_hand_pitch, 0.0, deg_to_rad(63) * delta / 0.28) if settled else deg_to_rad(63)
	if settled and GameConfig.tile_motion_seconds() == 0.0: _own_hand_pitch = 0.0

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
	var seen := {}
	var latest: TileView = null
	var board_inverse := view.get_global_transform().affine_inverse()
	var width_fit := minf(1.0, G.DESIGN_SIZE.aspect() / Vector2(viewport.size).aspect())
	var world_unit := _pixel_scale(G.CENTER, 1.0) * width_fit
	for layer in [view._wall_layer, view._discard_layer, view._red_layer, view._meld_layer,
			view._deal_layer] + view.hand_boxes + view.draw_boxes:
		for source in layer.get_children():
			if not source is TileView: continue
			var id: int = source.get_instance_id()
			seen[id] = true
			source.presentation_3d = true
			var masked: bool = source.tile == "hidden0"
			var face_up: bool = source.face_up and not masked
			var key: String = source.tile if face_up and source.tile != "" else "wan1"
			var node: MeshInstance3D = tile_nodes.get(id)
			if node == null: node = _new_mesh(source, _meshes[key], tile_nodes)
			var xf: Transform2D = board_inverse * source.get_global_transform()
			var kind := str(source.get_meta("new_kind", ""))
			var hand := kind in ["hand", "draw"]
			var own_hand: bool = hand and source.standing_back_view == -1
			if not settled and source.latest_highlight and source.is_visible_in_tree() and kind in ["ordinary", "red"] and int(source.get_meta("meld_index", -1)) < 0:
				latest = source
			var signature := hash([key, source.face_up, xf, source.size, source.is_visible_in_tree(),
				source.modulate, source.self_modulate, source.standing_back_view, kind, source.flight_pitch, source.flight_progress,
				source.z_index, source.highlight, source.latest_highlight, source.ai_teach_highlight,
				source.score_highlight, source.get_parent().get_instance_id(),
				source.get_meta("charge_chicken", false), source.get_meta("gold_chicken", false),
				source.get_meta("v2_charge", false), source.get_meta("kong_offset_2d", Vector2.ZERO), source.get_meta("kong_offset_3d", Vector2.ZERO), settled, settlement_started, _own_hand_pitch if own_hand else 0.0,
				source.get_meta("v2_draw_reserve", 1.0) if own_hand else 1.0])
			if _signatures.get(id) == signature: continue
			_signatures[id] = signature
			_changed = true
			node.mesh = _meshes[key]
			node.visible = source.is_visible_in_tree() and source.modulate.a > 0.01
			if not node.visible: continue
			var center: Vector2 = xf * (source.size / 2.0)
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
				var index := int(source.get_meta("wall_ring_index", 1))
				wall_upper = index % 2 == 0
				var side: int = view._wall_screen_seat(int(view._wall_segment_for_index(index).get("seat", 0)))
				side_wall = side in [0, 2]
				if wall_upper: center -= G.wall_upper_offset(side)
				if side == 1: center.y -= 28.0
				# The flip is a physical rotation, not a shrinking cardboard sprite.
				if source == view._settlement_flip_view:
					pitch = acos(clampf(scale_2d.y / maxf(scale_2d.x, 0.001), 0, 1))
					if not source.face_up: pitch = PI - pitch
			# Uniform world scales preserve the source model's 1 : 1.34 : 0.62 shape.
			# A single physical baseline gives near and far rows their natural parallax.
			var rel := G.relative_seat(view.human_seat, int(source.get_meta("v2_seat", view.human_seat)))
			var kong_offset := Vector2.ZERO
			if kind in ["meld", "red"] and int(source.get_meta("meld_index", -1)) >= 0:
				# Pack a kong in model units; sprite spacing changes with the camera and aspect.
				center -= Vector2(source.get_meta("kong_offset_2d", Vector2.ZERO))
				kong_offset = source.get_meta("kong_offset_3d", Vector2.ZERO)
			var side_hand: bool = hand and source.standing_back_view in [1, 3]
			var motion := float(source.flight_progress)
			var flight := motion if source.get_parent() == view._deal_layer else -1.0
			var hand_blend := 1.0 if flight < 0.0 else 1.0 - smoothstep(0.0, 0.75, flight)
			var side_row: bool = side_wall or (side_hand and flight < 0.0) or (kind in ["meld", "red", "ordinary"] and rel in [1, 3] and flight < 0.0)
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
					center.x -= along_row * 0.105 * (1 if source.standing_back_view == 1 else -1)
				var row_spacing := side_unit * 0.95 if side_hand else (0.95 if kind in ["ordinary", "red", "meld"] else 1.0)
				row_offset = along_row * world_unit * row_spacing
				center.y = G.CENTER.y
			elif kind == "ordinary":
				var seat := int(source.get_meta("v2_seat"))
				var first_y := G.ordinary_slot_center(seat, 0, view.human_seat).y
				var step_y := G.ordinary_slot_center(seat, 10, view.human_seat).y - first_y
				# Adjacent rows touch in world space, so the nearer row hides the far tile's base.
				row_offset = (center.y - first_y) / absf(step_y) * 1.34 * world_unit * source.size.x * scale_2d.x
				center.y = first_y
			var converge := lerpf(0.79, 1.09, center.y / size.y)
			var along_scale := converge * lerpf(0.58, 1.0, width_fit)
			var row_x := center.x
			var row_anchor := G.CENTER.x
			if own_hand:
				var draw_gap := 24.0 if kind == "draw" else 0.0
				# A merged fourteen-tile row no longer reserves space for a separate draw.
				var reserve_draw := float(source.get_meta("v2_draw_reserve", 1.0)) if not settled else 1.0
				var own_scale := 1.13 * near_fit * 1.02
				along_scale = lerpf(along_scale, own_scale, hand_blend)
				row_anchor += ((-64.0 * reserve_draw + draw_gap) * own_scale - 46.0 * reserve_draw) * hand_blend
				center.y += 32.0 * hand_blend
			center.x = row_anchor + (row_x - G.CENTER.x) * along_scale
			if side_hand: center.y -= 112.0 * hand_blend
			var height := (1.34 * absf(sin(pitch)) + 0.62 * absf(cos(pitch))) * factor / 2.0 + 0.03
			var position_3d := _at_height(center, height)
			position_3d.z += row_offset
			position_3d += Vector3(kong_offset.x, 0, kong_offset.y) * factor
			if flight >= 0.0:
				position_3d.y += factor * (1.0 - pow(absf(flight * 2.0 - 1.0), 2.0)) * (1.75 if side_hand else 0.9)
			elif motion >= 0.0:
				position_3d.y += factor * (1.0 - motion) * 0.38
			if kind == "wall":
				if wall_upper or source.face_up: position_3d.y += 0.62 * factor
				if source == view._settlement_flip_view: position_3d.y += sin(pitch) * factor * 0.35
			var basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, pitch)
			node.transform = Transform3D(basis.scaled(Vector3.ONE * factor), position_3d)
			if own_hand and flight < 0.0:
				# The taller online controls must clear the printed faces at settlement.
				for _step in 2:
					center.y += size.y - (68.0 if settled else 60.0) - _project_mesh(node).end.y
					node.position = _at_height(center, height)
			if hand and not side_hand and flight < 0.0:
				var step: float = (source.size.x + G.TILE_GAP) * along_scale
				var normal_step := _at_height(center + Vector2(step, 0), height).x - node.position.x
				if normal_step > factor * 0.98:
					var anchor := _at_height(Vector2(row_anchor, center.y), height).x
					node.position.x = lerpf(anchor, node.position.x, factor * 0.98 / normal_step)
			if side_hand or (source.get_parent() == view._deal_layer and flight < 0.0):
				# Include flights before their destination hand metadata is assigned.
				for _step in 3:
					var bounds := _project_mesh(node)
					var shift := maxf(8.0 - bounds.position.x, 0.0) + minf(size.x - 8.0 - bounds.end.x, 0.0)
					if is_zero_approx(shift): break
					var screen := camera.unproject_position(node.position) / Vector2(viewport.size) * size
					node.position += _at_height(screen + Vector2(shift, 0), height) - _at_height(screen, height)
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
			_changed = true
	_update_discard_marker(latest)
	if _changed:
		# frame_pre_draw runs after the normal transform flush.
		for node in tile_nodes.values() + dice_nodes.values() + [discard_marker]:
			node.force_update_transform()
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		queue_redraw()
		_changed = false

func _update_discard_marker(source: TileView) -> void:
	var show_marker: bool = is_instance_valid(source) and tile_nodes.has(source.get_instance_id()) and tile_nodes[source.get_instance_id()].visible
	if show_marker:
		show_marker = source.get_parent() != view._deal_layer and not view.native_actions_pending() and pick_tile(project_tile(source).get_center(), false) == source
	if discard_marker.visible != show_marker:
		discard_marker.visible = show_marker
		_changed = true
	if not show_marker: return
	var node: MeshInstance3D = tile_nodes[source.get_instance_id()]
	var factor := node.basis.get_scale().x
	var bounds := project_tile(source)
	var at := _at_height(Vector2(bounds.get_center().x, bounds.position.y - 20.0), node.position.y + factor)
	if not discard_marker.position.is_equal_approx(at) or not discard_marker.scale.is_equal_approx(Vector3.ONE * factor):
		discard_marker.position = at
		discard_marker.scale = Vector3.ONE * factor
		_changed = true

func _project_mesh(node: MeshInstance3D) -> Rect2:
	var box := node.mesh.get_aabb()
	var result := Rect2()
	for i in 8:
		var point := camera.unproject_position(node.transform * box.get_endpoint(i)) / Vector2(viewport.size) * size
		result = Rect2(point, Vector2.ZERO) if i == 0 else result.expand(point)
	return result

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
		if source.score_highlight: color = Color("#f9d66b")
		if color.a > 0: draw_rect(project_tile(source).grow(2), color, false, 3)
		var badge := "金" if source.get_meta("gold_chicken", false) else ""
		if badge != "":
			var center := project_tile(source).position + Vector2(12, 12)
			draw_circle(center, 15, Color("#9c6e28"))
			draw_string(TileView._font(), center + Vector2(-10, 7), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#fff7dc"))
