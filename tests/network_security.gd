extends SceneTree
## Split from the protocol helper test: checks the authority-issued reconnect
## credential, encrypted client storage, heartbeat surface and delta failures.
const H := preload("res://tests/test_harness.gd")
const SESSIONS := preload("res://scripts/core/NetworkSessionStore.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var first := NetGameNode.new_resume_token()
	var second := NetGameNode.new_resume_token()
	t.expect(first.length() == 64 and first.is_valid_hex_number(false), "authority token is 32 random bytes in hex")
	t.expect(first != second, "authority issues distinct reconnect tokens")
	t.expect(NetGameNode.HEARTBEAT_INTERVAL_MS == 5000, "heartbeat interval is five seconds")
	t.expect(NetGameNode.HEARTBEAT_TIMEOUT_MS == 15000, "heartbeat timeout is fifteen seconds")

	var path := "res://build/network_security/session.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var session := {"host": "127.0.0.1", "port": 7594, "number": "001234",
		"name": "安全", "player_name": "玩家", "token": first, "online": true}
	t.expect(SESSIONS.write_session(path, session) == OK, "session with authority token writes")
	t.expect(SESSIONS.read_session(path) == session, "session with authority token round-trips")
	t.expect(not FileAccess.get_file_as_string(path).contains(first), "plaintext config excludes the token")
	var encrypted_file := FileAccess.open(path + ".session", FileAccess.READ)
	t.expect(encrypted_file != null and encrypted_file.get_length() > 0, "encrypted companion is populated")
	if encrypted_file != null: encrypted_file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".session"))

	var net: NetGameNode = NetGameNode.new()
	var old := {"rows": [1, 2], "map": {"a": 1}, "drop": true}
	var new := {"rows": [1, 2, 3], "map": {"a": 2, "b": 3}}
	var ops: Array = []
	net._build_state_delta(old, new, [], ops)
	var copy: Dictionary = old.duplicate(true)
	t.expect(net._apply_state_delta(copy, ops), "delta applies after removal/append")
	t.expect(copy == new, "delta restores complete state")
	t.expect(not net._apply_state_delta(copy, [["s", ["rows", 99], 1]]), "invalid delta path is rejected")
	net.free()

	var bad := {"host": "127.0.0.1", "port": "7594", "number": "001234",
		"name": "x", "player_name": "x", "token": first}
	t.expect(not SESSIONS.valid(bad), "string port is rejected by session schema")
	bad.port = 7594
	bad.token = "z".repeat(64)
	t.expect(not SESSIONS.valid(bad), "non-hex token is rejected")
	await H.quit_cleanly(self, t.finish("network_security"))
