extends RefCounted
## User preferences live outside the application/PCK. Keep one previous file
## so an interrupted save can be recovered without resetting every preference.

static func read_config(path: String) -> ConfigFile:
	for candidate in [path, path + ".bak"]:
		var config := ConfigFile.new()
		if config.load(candidate) == OK: return config
	return ConfigFile.new()

static func write_config(config: ConfigFile, path: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if error != OK: return error
	error = config.save(path + ".tmp")
	if error != OK: return error
	if FileAccess.file_exists(path):
		# Never replace a recoverable backup with an unreadable primary file.
		var previous := ConfigFile.new()
		if previous.load(path) == OK:
			if FileAccess.file_exists(path + ".bak"):
				error = DirAccess.remove_absolute(absolute + ".bak")
				if error != OK: return error
			error = DirAccess.rename_absolute(absolute, absolute + ".bak")
		else:
			error = DirAccess.remove_absolute(absolute)
		if error != OK: return error
	return DirAccess.rename_absolute(absolute + ".tmp", absolute)
