extends RefCounted
## The approved existing artwork and its original UVs are shared by the table and settlement icons.
const ROOT := "res://assets/tiles/classic/"
const RESIN = preload("res://src/presentation/TileResin.gdshader")
const RESIN_SMOOTH = preload("res://src/presentation/TileResinSmooth.gdshader")
const Themes = preload("res://src/presentation/TableTheme.gd")

static var _meshes := {}
static var _faces := {}
static var _faces_sideways := {}
static var _artwork: Texture2D
static var _engraving: Texture2D
static var _artwork_image: Image
static var _visible_material: ShaderMaterial
static var _hidden_material: ShaderMaterial
static var _match_highlight_material: ShaderMaterial
static var _chicken_glow_material: ShaderMaterial
static var _hint_glow_material: ShaderMaterial
static var _tile_back_id := "jade"
static var _quality := "detail"


static func _load_library() -> void:
	if not _meshes.is_empty():
		return
	var library: MeshLibrary = load(ROOT + "tile_meshes.res")
	_artwork = load(ROOT + "mahJong.png")
	_engraving = load(ROOT + "mahJong_NORM.png")
	_visible_material = ShaderMaterial.new()
	_visible_material.shader = RESIN
	_visible_material.set_shader_parameter("printed", true)
	_visible_material.set_shader_parameter("artwork", _artwork)
	_visible_material.set_shader_parameter("engraving", _engraving)
	_hidden_material = _visible_material.duplicate()
	_hidden_material.set_shader_parameter("printed", false)
	# 池化高亮材质（GL Compatibility 移动端零开销、零驱动限制）
	_match_highlight_material = _visible_material.duplicate()
	_match_highlight_material.set_shader_parameter("glow_amount", 0.58)
	_match_highlight_material.set_shader_parameter("glow_color", Color("#ffd870"))
	_chicken_glow_material = _visible_material.duplicate()
	_chicken_glow_material.set_shader_parameter("glow_amount", 0.92)
	_chicken_glow_material.set_shader_parameter("glow_color", Color("#ffae2b"))
	_hint_glow_material = _visible_material.duplicate()
	_hint_glow_material.set_shader_parameter("glow_amount", 0.42)
	_hint_glow_material.set_shader_parameter("glow_color", Color("#7ef0bd"))
	apply_back_theme(_tile_back_id)
	apply_quality(_quality)
	for item in library.get_item_list():
		var value := library.get_item_name(item)
		_meshes[value] = library.get_item_mesh(item)


static func apply_quality(value: String) -> void:
	_quality = "detail" if value == "detail" else "smooth"
	for mat in [_visible_material, _hidden_material, _match_highlight_material, _chicken_glow_material, _hint_glow_material]:
		if mat == null:
			continue
		var params := {}
		for key in ["artwork", "printed", "ivory", "green", "glow_amount", "glow_color"]:
			params[key] = mat.get_shader_parameter(key)
		mat.shader = RESIN if _quality == "detail" else RESIN_SMOOTH
		for key in params:
			if params[key] != null:
				mat.set_shader_parameter(key, params[key])
		if _quality == "detail":
			mat.set_shader_parameter("engraving", _engraving)


static func apply_back_theme(id: String) -> void:
	_tile_back_id = id if Themes.TILE_BACKS.has(id) else "jade"
	if _visible_material == null:
		return
	var spec: Dictionary = Themes.tile_back_data(_tile_back_id)
	for mat in [_visible_material, _hidden_material, _match_highlight_material, _chicken_glow_material, _hint_glow_material]:
		if mat != null:
			mat.set_shader_parameter("green", spec.back)
			mat.set_shader_parameter("ivory", spec.ivory)


static func mesh(value: String) -> Mesh:
	_load_library()
	return _meshes.get(value, _meshes.wan1)


static func material(printed: bool) -> ShaderMaterial:
	_load_library()
	return _visible_material if printed else _hidden_material


static func highlight_material(kind: String) -> ShaderMaterial:
	_load_library()
	match kind:
		"match": return _match_highlight_material
		"chicken": return _chicken_glow_material
		"hint": return _hint_glow_material
		_: return _visible_material


static func face(value: String) -> Texture2D:
	_load_library()
	if _faces.has(value):
		return _faces[value]
	if not _meshes.has(value) or _artwork == null:
		return null
	# 按需延迟提取单张牌面 UV，大幅缩短冷启动耗时
	var tile_mesh: Mesh = _meshes[value]
	var data: Array = tile_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = data[Mesh.ARRAY_TEX_UV]
	var low := Vector2.ONE
	var high := Vector2.ZERO
	for i in vertices.size():
		if vertices[i].y > 0.30 and normals[i].y > 0.95 and uv[i].y < 0.73:
			low = low.min(uv[i])
			high = high.max(uv[i])
	var atlas := AtlasTexture.new()
	atlas.atlas = _artwork
	atlas.region = Rect2(low * _artwork.get_size(), (high - low) * _artwork.get_size())
	atlas.filter_clip = true
	_faces[value] = atlas
	return atlas


static func face_sideways(value: String) -> Texture2D:
	if _faces_sideways.has(value):
		return _faces_sideways[value]
	var upright := face(value) as AtlasTexture
	if upright == null or _artwork == null:
		return null
	if _artwork_image == null:
		_artwork_image = _artwork.get_image()
		if _artwork_image != null and _artwork_image.is_compressed():
			_artwork_image.decompress()
	if _artwork_image == null:
		return upright
	var region := Rect2i(upright.region.position.floor(), upright.region.size.ceil()).intersection(Rect2i(Vector2i.ZERO, _artwork_image.get_size()))
	if region.size.x <= 0 or region.size.y <= 0:
		return upright
	var sub := _artwork_image.get_region(region)
	sub.rotate_90(COUNTERCLOCKWISE)
	var tex := ImageTexture.create_from_image(sub)
	_faces_sideways[value] = tex
	return tex
