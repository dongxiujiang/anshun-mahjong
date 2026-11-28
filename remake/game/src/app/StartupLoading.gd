extends Control
## Keep the loading page visible until resources and the first table frames are ready.
const UI = preload("res://src/app/AppTheme.gd")
const Packs = preload("res://src/audio/VoicePacks.gd")
const EFFECTS := ["charge_chicken", "chicken_ping", "coin_roll", "dice_roll", "discard", "meld_slam", "ready_chime", "tile_draw", "tile_select", "tile_slide", "ui_click", "win_fanfare"]
var retained: Array[Resource] = []
var progress := ProgressBar.new()
var caption := Label.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = UI.BACKDROP
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 22)
	center.add_child(content)
	var title := UI.label("东秀麻将", 38, UI.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	progress.custom_minimum_size = Vector2(280, 12)
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", UI.card(Color("#203e32"), 6, 0))
	progress.add_theme_stylebox_override("fill", UI.card(UI.GOLD, 6, 0))
	content.add_child(progress)
	caption.text = "正在准备牌桌…"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color", UI.MUTED)
	content.add_child(caption)

func update_stage(amount: float, text: String) -> void:
	progress.value = clampf(amount, progress.value, 100.0)
	caption.text = text

func load_resources() -> bool:
	var paths: Array[String] = ["res://assets/tiles/classic/tile_meshes.res", "res://assets/tiles/classic/mahJong.png", "res://assets/tiles/classic/mahJong_NORM.png", "res://assets/audio/music/table.mp3"]
	for pack in Packs.ORDER:
		paths.append("res://assets/characters/voice-portraits-v1/" + pack + ".png")
	for effect in EFFECTS:
		paths.append("res://assets/audio/effects/" + effect + ".wav")
	for path in paths:
		if ResourceLoader.load_threaded_request(path) != OK:
			caption.text = "资源加载失败，请重新打开游戏"
			return false
	while not paths.is_empty():
		var amount := float(retained.size())
		for path in paths.duplicate():
			var loaded: Array = []
			var state := ResourceLoader.load_threaded_get_status(path, loaded)
			if state == ResourceLoader.THREAD_LOAD_FAILED or state == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				caption.text = "资源加载失败，请重新打开游戏"
				return false
			if state == ResourceLoader.THREAD_LOAD_LOADED:
				retained.append(ResourceLoader.load_threaded_get(path))
				paths.erase(path)
				amount += 1.0
			elif not loaded.is_empty():
				amount += float(loaded[0])
		update_stage(55.0 * amount / float(paths.size() + retained.size()), "正在加载牌桌与音效…")
		if paths.is_empty(): break
		await get_tree().process_frame
	return true
