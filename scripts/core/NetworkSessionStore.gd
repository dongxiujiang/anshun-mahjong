extends RefCounted
## Only successful client joins are resumable. A room number alone is not an identity.
const STORE := preload("res://scripts/core/UserSettingsStore.gd")

static func valid(session: Dictionary) -> bool:
	for key in ["host", "number", "token", "player_name"]:
		if not session.get(key) is String or session[key].is_empty(): return false
	if not NetGameNode.valid_room_number(session.number): return false
	if session.host.length() > 253 or session.player_name.length() > 16: return false
	if not session.get("port") is int or session.port < 1 or session.port > 65535: return false
	if session.token.length() != 64 or not session.token.is_valid_hex_number(false): return false
	return true

static func _session_key() -> PackedByteArray:
	# Encryption at rest for the app-private user:// directory. This is not a
	# hardware-backed secret; it keeps bearer tokens out of plaintext config
	# dumps and backups that copy network.cfg without its companion file.
	return (str(OS.get_unique_id()) + "|" + OS.get_name() + "|anshun-resume-v1").sha256_buffer()

static func _encrypted_path(path: String) -> String:
	return path + ".session"

static func read_session(path: String) -> Dictionary:
	var encrypted := _encrypted_path(path)
	if FileAccess.file_exists(encrypted):
		var file := FileAccess.open_encrypted(encrypted, FileAccess.READ, _session_key())
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				# JSON numbers are floats; restore the integer port before
				# validating the session schema.
				parsed["port"] = int(parsed.get("port", 0))
				if valid(parsed): return parsed.duplicate(true)
	# Migration path for sessions written by older versions.
	var config := STORE.read_config(path)
	var session = config.get_value("resume", "session", {})
	return session.duplicate(true) if session is Dictionary and valid(session) else {}

static func write_session(path: String, session: Dictionary) -> Error:
	if not session.is_empty() and not valid(session): return ERR_INVALID_DATA
	var config := STORE.read_config(path)
	# Do not persist the bearer token in the plaintext ConfigFile. The token
	# lives only in the encrypted companion file; non-secret fields remain for
	# migration and diagnostics.
	var stored := session.duplicate(true)
	if not stored.is_empty(): stored["token"] = ""
	config.set_value("resume", "session", stored)
	var error := STORE.write_config(config, path)
	if error != OK: return error
	error = config.save(path + ".bak")
	if error != OK: return error
	var encrypted := _encrypted_path(path)
	if session.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(encrypted))
		return OK
	var tmp := encrypted + ".tmp"
	var file := FileAccess.open_encrypted(tmp, FileAccess.WRITE, _session_key())
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(session))
	file.close()
	var target := ProjectSettings.globalize_path(encrypted)
	DirAccess.remove_absolute(target)
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), target)
