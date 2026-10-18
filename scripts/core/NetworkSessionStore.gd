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

static func read_session(path: String) -> Dictionary:
	var config := STORE.read_config(path)
	var session = config.get_value("resume", "session", {})
	return session.duplicate(true) if session is Dictionary and valid(session) else {}

static func write_session(path: String, session: Dictionary) -> Error:
	if not session.is_empty() and not valid(session): return ERR_INVALID_DATA
	var config := STORE.read_config(path)
	config.set_value("resume", "session", session)
	var error := STORE.write_config(config, path)
	if error != OK: return error
	# A cleared/replaced credential must not reappear from an older backup.
	# Keep the same recoverable session in both copies, including its tombstone.
	return config.save(path + ".bak")
