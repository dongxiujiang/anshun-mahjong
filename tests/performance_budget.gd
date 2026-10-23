extends SceneTree
## Coarse performance guardrails for hot paths. The limits are intentionally
## generous for CI; the measured values are printed so regressions are visible.
const H := preload("res://tests/test_harness.gd")
const SESSIONS := preload("res://scripts/core/NetworkSessionStore.gd")
const REPLAY := preload("res://scripts/core/RoundReplay.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _round_fixture() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261023)
	r.build_players(0)
	r.phase = RoundState.Phase.PLAYING
	r.current_turn = 0
	r.awaiting = true
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	r.players[0].concealed = ["wan1", "wan2", "wan3", "wan2", "wan3", "wan4", "tong3", "tong4", "tong5", "tiao3", "tiao4", "tiao5", "wan9", "tiao8"]
	r.players[0].just_drew = "tiao8"
	r.players[0].first_turn_done = true
	return r

func _run() -> void:
	var round := _round_fixture()
	var started := Time.get_ticks_usec()
	for i in 100:
		var state := round.serialize_for_seat(i % 4)
		state.audio_events = state.audio_events.filter(func(event): return int(event.id) > 0)
	var serialize_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("[performance] serialize100_ms=", serialize_ms)
	t.expect(serialize_ms < 3000.0, "100 per-seat serializations stay under 3s")

	var net: NetGameNode = NetGameNode.new()
	var old := {"players": [{"score": 1, "discards": ["wan1"]}], "revision": 1, "round_meta": {"winner": 0}}
	var new := {"players": [{"score": 3, "discards": ["wan1", "wan2"]}], "revision": 2, "round_meta": {"winner": 1}}
	started = Time.get_ticks_usec()
	for i in 500:
		var ops: Array = []
		net._build_state_delta(old, new, [], ops)
		var copy: Dictionary = old.duplicate(true)
		if not net._apply_state_delta(copy, ops):
			t.expect(false, "delta patch applies")
			break
		if copy != new:
			t.expect(false, "delta patch reconstructs state")
			break
	var delta_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("[performance] delta500_ms=", delta_ms)
	t.expect(delta_ms < 2000.0, "500 delta build/apply cycles stay under 2s")
	net.free()

	started = Time.get_ticks_usec()
	var replay_ms := 0.0
	for i in 100:
		REPLAY.fingerprint(round)
	replay_ms = (Time.get_ticks_usec() - started) / 1000.0
	print("[performance] fingerprint100_ms=", replay_ms)
	t.expect(replay_ms < 1500.0, "100 replay fingerprints stay under 1.5s")

	var ai := AiPlayer.new()
	ai.use_mcts = false
	started = Time.get_ticks_usec()
	var decision: Dictionary = ai.decide_turn(round, 0)
	var ai_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("[performance] ai_turn_ms=", ai_ms, " discard=", decision.get("discard", ""))
	t.expect(ai_ms < 3000.0, "one bounded AI turn stays under 3s")
	t.expect(round.legal_turn_options(0).discards.has(str(decision.get("discard", ""))), "bounded AI chooses a legal discard")

	var path := "res://build/performance_budget/session.cfg"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var session := {"host": "127.0.0.1", "port": 7594, "number": "001234",
		"name": "性能", "player_name": "玩家", "token": "b".repeat(64), "online": true}
	started = Time.get_ticks_usec()
	for i in 20:
		if SESSIONS.write_session(path, session) != OK or SESSIONS.read_session(path) != session:
			t.expect(false, "session store round-trip")
			break
	var session_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("[performance] session20_ms=", session_ms)
	t.expect(session_ms < 2000.0, "20 encrypted session round-trips stay under 2s")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".session"))

	await H.quit_cleanly(self, t.finish("performance_budget"))
