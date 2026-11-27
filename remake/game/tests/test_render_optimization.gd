extends SceneTree
const Art = preload("res://src/presentation/TileArt.gd")
const Table = preload("res://src/presentation/TableView.gd")
const Settings = preload("res://src/app/AppSettings.gd")
const SettingsPanel = preload("res://src/app/SettingsPanel.gd")
const Main = preload("res://scenes/Main.tscn")
const AudioRetirement = preload("res://tests/AudioRetirement.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL render: ", message)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	Art.apply_quality("smooth")
	Art.material(true)
	var materials = [Art._visible_material, Art._hidden_material, Art._match_highlight_material, Art._chicken_glow_material, Art._hint_glow_material]
	var params = []
	for mat in materials:
		params.append([mat.get_shader_parameter("green"), mat.get_shader_parameter("ivory"), mat.get_shader_parameter("glow_amount")])
		check(mat.shader == Art.RESIN_SMOOTH, "smooth shader after lazy initialization")
	Art.apply_quality("detail")
	for i in materials.size():
		var mat = materials[i]
		check(mat.shader == Art.RESIN, "detail shader")
		check([mat.get_shader_parameter("green"), mat.get_shader_parameter("ivory"), mat.get_shader_parameter("glow_amount")] == params[i], "parameters preserved")
	Art.apply_quality("smooth")
	for i in materials.size():
		check(materials[i].shader == Art.RESIN_SMOOTH and [materials[i].get_shader_parameter("green"), materials[i].get_shader_parameter("ivory"), materials[i].get_shader_parameter("glow_amount")] == params[i], "smooth parameters preserved")
	var table = Table.new(false)
	root.add_child(table)
	await process_frame
	check(table.get_children().all(func(child): return not child is ReflectionProbe), "no reflection probe")
	check(table._key_light.directional_shadow_max_distance <= 45.0, "shadow distance")
	for zone in ["wall", "discard", "hand", "meld", "chicken"]:
		table._place(999, "wan1", Transform3D.IDENTITY, zone, false)
		var expected = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if zone in ["wall", "discard"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		check(table.tiles[999].cast_shadow == expected, "shadow for " + zone)
	table.queue_free()
	await process_frame
	var path = "user://render-optimization-%d.cfg" % Time.get_ticks_usec()
	var settings = Settings.new(path)
	check(settings.update({"power_save": true, "quality_manual": true}), "save boolean settings")
	var loaded = Settings.new(path)
	check(loaded.profile().power_save and loaded.profile().quality_manual, "persist boolean settings")
	check(not loaded.update({"power_save": 1}) and not loaded.update({"quality_manual": "yes"}), "reject invalid boolean settings")
	var panel = SettingsPanel.new()
	root.add_child(panel)
	panel.build(loaded.profile(), true)
	check(panel.values().power_save and panel._fields.power_save is CheckButton, "power save toggle")
	panel.queue_free()
	await process_frame
	var app = Main.instantiate()
	app._settings = loaded
	root.add_child(app)
	await process_frame
	app._apply_quality("smooth")
	check(app._board_world.msaa_3d == Viewport.MSAA_DISABLED and app._table.camera.environment.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED, "smooth disables msaa and bg reflection")
	app._apply_quality("detail")
	check(app._board_world.msaa_3d == Viewport.MSAA_2X and app._table.camera.environment.reflected_light_source == Environment.REFLECTION_SOURCE_BG, "detail enables 2x msaa and bg reflection")
	loaded.update({"quality": "detail", "quality_manual": false, "power_save": false})
	var low = [25.0, 28.0, 26.0, 29.0, 27.0, 28.0]
	check(app._evaluate_auto_quality(low, true) and loaded.profile().quality == "smooth", "low fps downgrade")
	loaded.update({"quality": "detail", "quality_manual": true})
	check(not app._evaluate_auto_quality(low, true) and loaded.profile().quality == "detail", "manual quality retained")
	loaded.update({"quality_manual": false})
	check(not app._evaluate_auto_quality([58.0, 60.0, 59.0, 60.0, 58.0, 60.0], true), "healthy fps retained")
	check(not app._evaluate_auto_quality(low, false), "desktop retained")
	loaded.update({"power_save": true})
	check(not app._evaluate_auto_quality(low, true), "power saving does not trigger downgrade")
	app._apply_power_save(true)
	check(Engine.max_fps == 30, "power saving limits fps")
	app._apply_power_save(false)
	check(Engine.max_fps == 0, "normal fps is unlimited")
	await AudioRetirement.release_app(app, self)
	Engine.max_fps = 0
	DirAccess.remove_absolute(path)
	print("Render optimization: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

