extends SceneTree
const H := preload("res://tests/test_harness.gd")
const STORE := preload("res://scripts/core/UserSettingsStore.gd")
const GAME := "res://scripts/autoload/GameConfig.gd"
const AUDIO := "res://scripts/autoload/AudioManager.gd"
const CHOICES := {"ai_speed": "medium", "animation_speed": "fast", "draw_animation_speed": "slow", "discard_animation_speed": "fast", "settlement_speed": "detail"}
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
	t.expect(config.ai_speed == "medium" and config.draw_animation_speed == "fast" and config.discard_animation_speed == "fast" and config.settlement_speed == "standard", "new installation uses defaults")
	t.expect(not FileAccess.file_exists(path), "loading missing settings never writes defaults")
	config.set_settlement_speed("slow")
	t.expect(STORE.read_config(path).get_value("game", "settlement_speed") == "slow", "explicitly choosing the current default is still saved for future upgrades")
	config.set_ai_speed("medium")
	config.set_ai_speed("slow")
	t.expect(FileAccess.file_exists(path + ".bak"), "saving keeps previous complete settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var recovered = _game(path)
	t.expect(recovered.ai_speed == "medium", "interrupted primary rename recovers the previous complete settings")
	recovered.set_ai_speed("slow")
	t.expect(STORE.read_config(path).get_value("game", "ai_speed") == "slow", "recovered settings can be saved again")
	var data := STORE.read_config(path)
	data.set_value("future", "keep", "from-newer-version")
	data.set_value("game", "draw_animation_speed", {"invalid": true})
	data.set_value("game", "discard_animation_speed", "obsolete")
	data.set_value("game", "settlement_speed", "detail")
	data.erase_section_key("game", "animation_speed")
	data.save(path)
	var digest := FileAccess.get_sha256(path)
	var loaded = _game(path)
	t.expect(loaded.ai_speed == "slow" and loaded.settlement_speed == "detail", "valid choices survive invalid neighboring fields")
	t.expect(loaded.draw_animation_speed == "fast" and loaded.discard_animation_speed == "fast", "invalid type and obsolete key fall back individually")
	t.expect(loaded.animation_speed == "standard", "a newly added setting uses its default")
	loaded.set_ai_speed("invalid")
	t.expect(FileAccess.get_sha256(path) == digest, "loading and invalid selections do not rewrite the saved file")
	loaded.set_discard_animation_speed("fast")
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
	data.set_value("future", "keep", 27)
	data.save(audio_path)
	digest = FileAccess.get_sha256(audio_path)
	var audio = _audio(audio_path)
	t.expect(is_equal_approx(audio.volumes.music, 0.28), "legacy music preference is not replaced by a new default")
	t.expect(is_equal_approx(audio.volumes.voice, 0.9) and not audio.enabled.voice, "legacy voice volume and mute survive upgrade")
	t.expect(is_equal_approx(audio.volumes.effects, 0.65) and audio.enabled.effects, "invalid audio fields use safe individual defaults")
	t.expect(audio.preview_voice_seat == 0, "invalid preview selection falls back")
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
	for pair in [["draw", "slow"], ["discard", "fast"], ["settlement", "detail"]]:
		settings.get(pair[0] + "_speed_buttons")[pair[1]].pressed.emit()
		var key: String = pair[0] + ("_speed" if pair[0] == "settlement" else "_animation_speed")
		t.expect(STORE.read_config(config.settings_path).get_value("game", key) == pair[1], "UI choice saved immediately while panel is still open: " + key)
	settings.sliders.music.value = 37
	settings.switches.voice.button_pressed = false
	settings.voice_selector.item_selected.emit(3)
	var saved := STORE.read_config(audio.settings_path)
	t.expect(is_equal_approx(saved.get_value("music", "volume"), 0.37), "volume slider saves immediately")
	t.expect(not saved.get_value("voice", "enabled"), "sound switch saves immediately")
	t.expect(saved.get_value("voice", "preview_seat") == 3, "last preview voice is remembered without changing players' voices")
	settings.free()
	settings = load("res://scripts/ui/SoundSettings.gd").new()
	settings.table_mode = true
	root.add_child(settings)
	t.expect(settings.voice_selector.selected == 3 and settings.sliders.music.value == 37, "reopened settings reflect saved choices")
	var game_hash := FileAccess.get_sha256(config.settings_path)
	var audio_hash := FileAccess.get_sha256(audio.settings_path)
	settings.persist_changes = false
	settings.draw_speed_buttons.instant.pressed.emit()
	settings.discard_speed_buttons.instant.pressed.emit()
	settings.settlement_speed_buttons.instant.pressed.emit()
	settings.sliders.music.value = 19
	settings.voice_selector.item_selected.emit(1)
	settings.close()
	t.expect(FileAccess.get_sha256(config.settings_path) == game_hash and FileAccess.get_sha256(audio.settings_path) == audio_hash, "preview/test controls cannot overwrite saved preferences")
	settings.free()
	config.persist_settings = false
	audio.persist_settings = false

func _child(mode: String) -> void:
	if mode == "patch":
		t.expect(ProjectSettings.load_resource_pack(directory + "/new-defaults.pck", true), "mount updated defaults from a real PCK")
		var defaults = ResourceLoader.load(GAME, "", ResourceLoader.CACHE_MODE_IGNORE).new()
		t.expect(defaults.ai_speed == "slow" and defaults.settlement_speed == "instant", "updated script defaults really differ from the installed version")
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
		for key in CHOICES: t.expect(config.get(key) == CHOICES[key], mode + " restores " + key + " at startup")
		for channel in audio.CHANNELS:
			t.expect(is_equal_approx(audio.volumes[channel], {"music": 0.28, "voice": 0.9, "effects": 0.43}[channel]), mode + " restores volume " + channel)
			t.expect(audio.enabled[channel] == (channel == "effects"), mode + " restores switch " + channel)
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
	var game_source := FileAccess.get_file_as_string(GAME).replace('var ai_speed := "medium"', 'var ai_speed := "slow"').replace('var settlement_speed := "standard"', 'var settlement_speed := "instant"')
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
