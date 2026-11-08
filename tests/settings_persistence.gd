extends SceneTree
const H := preload("res://tests/test_harness.gd")
const STORE := preload("res://scripts/core/UserSettingsStore.gd")
const GAME := "res://scripts/autoload/GameConfig.gd"
const AUDIO := "res://scripts/autoload/AudioManager.gd"
const CHOICES := {"ai_speed": "0.80", "animation_speed": "fast", "tile_animation_seconds": 0.7, "settlement_speed": "0.60"}
var t := H.new()
var directory := "res://build/settings_persistence/%d" % OS.get_process_id()

func _initialize() -> void: call_deferred("_run")

func _game(path: String):
	var config = ResourceLoader.load(GAME, "", ResourceLoader.CACHE_MODE_IGNORE).new()
	config.settings_path = path
	config.persist_settings = true
	root.add_child(config)
	return config

func _audio(path: String):
	var audio = ResourceLoader.load(AUDIO, "", ResourceLoader.CACHE_MODE_IGNORE).new()
	audio.settings_path = path
	audio.persist_settings = true
	root.add_child(audio)
	return audio

func _test_defaults_and_recovery() -> void:
	var path := directory + "/validation.cfg"
	var config = _game(path)
	t.expect(config.ai_speed == "0.80" and config.tile_animation_seconds == 0.20 and config.settlement_speed == "0.70", "new installation uses short durations")
	t.expect(not config.score_details_enabled, "new installation defaults to score details off")
	t.expect(not FileAccess.file_exists(path), "loading missing settings never writes defaults")
	config.set_settlement_speed("slow")
	t.expect(STORE.read_config(path).get_value("game", "settlement_speed") == "1.00", "explicitly choosing the current default is still saved for future upgrades")
	config.set_ai_speed("medium")
	config.set_ai_speed("slow")
	t.expect(FileAccess.file_exists(path + ".bak"), "saving keeps previous complete settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var recovered = _game(path)
	t.expect(recovered.ai_speed == "1.00", "interrupted primary rename recovers the previous complete settings")
	recovered.set_ai_speed("slow")
	t.expect(STORE.read_config(path).get_value("game", "ai_speed") == "1.00", "recovered settings can be saved again")
	var data := STORE.read_config(path)
	data.set_value("future", "keep", "from-newer-version")
	data.set_value("game", "draw_animation_speed", {"invalid": true})
	data.set_value("game", "discard_animation_speed", "obsolete")
	data.set_value("game", "settlement_speed", "fast")
	data.erase_section_key("game", "animation_speed")
	data.erase_section_key("game", "score_details_enabled")
	data.erase_section_key("game", "tile_animation_seconds")
	data.save(path)
	data.set_value("game", "ai_speed", "1.26")
	data.set_value("game", "tile_animation_seconds", 1.75)
	data.set_value("game", "settlement_speed", "1.45")
	data.save(path)
	var migrated = _game(path)
	t.expect(migrated.ai_speed == "1.00" and migrated.tile_animation_seconds == 1.0 and migrated.settlement_speed == "1.00", "old durations above the new range clamp to one second")
	migrated.free()
	data.set_value("game", "ai_speed", "slow")
	data.set_value("game", "settlement_speed", "fast")
	data.erase_section_key("game", "tile_animation_seconds")
	data.save(path)
	var digest := FileAccess.get_sha256(path)
	var loaded = _game(path)
	t.expect(loaded.ai_speed == "1.00" and loaded.settlement_speed == "0.80", "valid choices survive invalid neighboring fields")
	t.expect(loaded.tile_animation_seconds == 0.20, "invalid legacy animation preference falls back to the default")
	t.expect(loaded.animation_speed == "standard", "a newly added setting uses its default")
	t.expect(not loaded.score_details_enabled, "older settings default to score details off")
	loaded.set_ai_speed("invalid")
	t.expect(FileAccess.get_sha256(path) == digest, "loading and invalid selections do not rewrite the saved file")
	loaded.set_tile_animation_seconds(0.40)
	t.expect(STORE.read_config(path).get_value("future", "keep") == "from-newer-version", "saving preserves unfamiliar settings for updates and rollback")
	config.free()
	recovered.free()
	loaded.free()
	var audio_path := directory + "/legacy_audio.cfg"
	data = ConfigFile.new()
	data.set_value("music", "volume", 0.28)
	data.set_value("voice", "volume", 0.9)
	data.set_value("voice", "enabled", false)
	data.set_value("effects", "volume", "invalid")
	data.set_value("effects", "enabled", "invalid")
	data.set_value("voice", "preview_seat", 99)
	data.set_value("voice", "seat_packs", JSON.stringify(["usagi", "lubenwei", "weilong", "xiaohei"]))
	data.set_value("future", "keep", 27)
	data.save(audio_path)
	digest = FileAccess.get_sha256(audio_path)
	var audio = _audio(audio_path)
	t.expect(is_equal_approx(audio.volumes.music, 0.28), "legacy music preference is not replaced by a new default")
	t.expect(is_equal_approx(audio.volumes.voice, 0.9) and audio.enabled.voice, "legacy voice volume survives upgrade and obsolete mute flag is ignored")
	t.expect(is_equal_approx(audio.volumes.effects, 0.65) and audio.enabled.effects, "invalid audio fields use safe individual defaults")
	t.expect(audio.preview_voice_seat == 0, "invalid preview selection falls back")
	t.expect(audio.seat_voice_packs == ["luoxiaohei", "wuyuanzhao", "wangye", "nvyou"], "old default seat voices migrate to the new mapping")
	t.expect(FileAccess.get_sha256(audio_path) == digest, "startup reads old audio settings without modifying the file")
	audio.set_volume("effects", 0.43)
	t.expect(STORE.read_config(audio_path).get_value("future", "keep") == 27, "audio saves preserve unknown future settings")
	audio.free()

func _test_controls() -> void:
	var config = root.get_node("GameConfig")
	var audio = root.get_node("AudioManager")
	config.settings_path = directory + "/ui_game.cfg"
	audio.settings_path = directory + "/ui_audio.cfg"
	config.persist_settings = true
	audio.persist_settings = true
	var settings = load("res://scripts/ui/SoundSettings.gd").new()
	settings.table_mode = true
	root.add_child(settings)
	t.expect(settings.score_details_button.text == "详细展示：关闭", "settings show the default off state")
	settings.score_details_button.pressed.emit()
	t.expect(settings.score_details_button.text == "详细展示：开启", "settings show the enabled state")
	var reloaded = _game(config.settings_path)
	t.expect(reloaded.score_details_enabled, "enabled score details survive reloading settings")
	reloaded.free()
	settings.tile_speed_slider.value = 0.7
	t.expect(is_equal_approx(STORE.read_config(config.settings_path).get_value("game", "tile_animation_seconds"), 0.7), "tile duration is saved while settings is open")
	settings.settlement_speed_slider.value = 0.40
	t.expect(STORE.read_config(config.settings_path).get_value("game", "settlement_speed") == "0.40", "settlement step duration is saved while settings is open")
	settings.sliders.voice.value = 37
	var saved := STORE.read_config(audio.settings_path)
	t.expect(is_equal_approx(saved.get_value("voice", "volume"), 0.37), "volume slider saves immediately")
	t.expect(saved.get_value("voice", "enabled") == true, "obsolete voice mute flag is ignored when saving")
	t.expect(settings.get("voice_selector") == null, "legacy voice selector removed")
	settings.free()
	settings = load("res://scripts/ui/SoundSettings.gd").new()
	settings.table_mode = true
	root.add_child(settings)
	t.expect(settings.sliders.voice.value == 37, "reopened settings reflect saved choices")
	var game_hash := FileAccess.get_sha256(config.settings_path)
	var audio_hash := FileAccess.get_sha256(audio.settings_path)
	settings.persist_changes = false
	settings.tile_speed_slider.value = 0.0
	settings.settlement_speed_slider.value = 2.0
	settings.score_details_button.pressed.emit()
	t.expect(not config.score_details_enabled and settings.score_details_button.text == "详细展示：关闭", "settings can turn score details off again")
	settings.sliders.voice.value = 19
	settings.close()
	t.expect(FileAccess.get_sha256(config.settings_path) == game_hash and FileAccess.get_sha256(audio.settings_path) == audio_hash, "preview/test controls cannot overwrite saved preferences")
	settings.free()
	config.persist_settings = false
	audio.persist_settings = false

func _child(mode: String) -> void:
	if mode == "patch":
		t.expect(ProjectSettings.load_resource_pack(directory + "/new-defaults.pck", true), "mount updated defaults from a real PCK")
		var defaults = ResourceLoader.load(GAME, "", ResourceLoader.CACHE_MODE_IGNORE).new()
		t.expect(defaults.ai_speed == "slow" and defaults.settlement_speed == "standard", "updated script defaults really differ from the installed version")
		defaults.free()
	var config = _game(directory + "/restart_game.cfg")
	var audio = _audio(directory + "/restart_audio.cfg")
	if mode == "write":
		for key in CHOICES: config.call("set_" + key, CHOICES[key])
		for channel in audio.CHANNELS:
			audio.set_volume(channel, {"music": 0.28, "voice": 0.9, "effects": 0.43}[channel])
			audio.set_enabled(channel, channel == "effects")
		audio.set_preview_voice_seat(2)
		t.expect(FileAccess.file_exists(config.settings_path) and FileAccess.file_exists(audio.settings_path), "preferences saved before closing the settings panel or exiting")
	else:
		for key in CHOICES:
			var actual = config.get(key)
			t.expect(is_equal_approx(actual, CHOICES[key]) if actual is float else actual == CHOICES[key], mode + " restores " + key + " at startup")
		for channel in audio.CHANNELS:
			t.expect(is_equal_approx(audio.volumes[channel], {"music": 0.28, "voice": 0.9, "effects": 0.43}[channel]), mode + " restores volume " + channel)
			var expected_enabled: bool = channel in ["voice", "effects"]
			t.expect(audio.enabled[channel] == expected_enabled, mode + " ignores obsolete switch " + channel)
		t.expect(audio.preview_voice_seat == 2, mode + " restores last preview voice")
	config.free()
	audio.free()
	quit(t.finish("settings_persistence_child"))

func _run_child(mode: String) -> void:
	var output: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/settings_persistence.gd", "--", "--settings-child=" + mode, "--settings-directory=" + directory])
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	var log := "".join(output)
	var file := FileAccess.open(directory + "/" + mode + ".log", FileAccess.WRITE)
	file.store_string(log)
	file.close()
	t.expect(code == 0 and log.contains("[settings_persistence_child] passed") and not log.contains("ERROR:"), "separate process " + mode + " succeeds: " + log if code != 0 or log.contains("ERROR:") else "separate process " + mode + " restores settings")

func _test_restart_and_patch() -> void:
	_run_child("write")
	var game_hash := FileAccess.get_sha256(directory + "/restart_game.cfg")
	var audio_hash := FileAccess.get_sha256(directory + "/restart_audio.cfg")
	_run_child("read")
	var game_source := FileAccess.get_file_as_string(GAME).replace('var ai_speed := "0.80"', 'var ai_speed := "slow"').replace('var settlement_speed := "0.70"', 'var settlement_speed := "standard"')
	var audio_source := FileAccess.get_file_as_string(AUDIO).replace('{"music": 0.12, "voice": 0.8, "effects": 0.65}', '{"music": 0.5, "voice": 0.5, "effects": 0.5}')
	var pack := PCKPacker.new()
	t.expect(pack.pck_start(directory + "/new-defaults.pck") == OK, "create preference upgrade fixture")
	for entry in [[GAME, game_source], [AUDIO, audio_source]]:
		var path := directory + "/" + str(entry[0]).get_file()
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(entry[1])
		file.close()
		t.expect(pack.add_file(entry[0], path) == OK, "pack new defaults for " + entry[0])
	t.expect(pack.flush() == OK, "finish real PCK fixture")
	_run_child("patch")
	_run_child("read") # rollback to original code must also retain preferences
	t.expect(FileAccess.get_sha256(directory + "/restart_game.cfg") == game_hash, "restart, hot update and rollback never rewrite saved game preferences")
	t.expect(FileAccess.get_sha256(directory + "/restart_audio.cfg") == audio_hash, "restart, hot update and rollback never rewrite saved audio preferences")

func _run() -> void:
	var mode := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--settings-directory="): directory = arg.trim_prefix("--settings-directory=")
		if arg.begins_with("--settings-child="): mode = arg.trim_prefix("--settings-child=")
	if mode != "":
		_child(mode)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	t.expect(root.get_node("GameConfig").SETTINGS_PATH.begins_with("user://") and root.get_node("AudioManager").SETTINGS_PATH.begins_with("user://"), "preferences are outside update packages and versioned download folders")
	_test_defaults_and_recovery()
	_test_controls()
	_test_restart_and_patch()
	quit(t.finish("settings_persistence"))

