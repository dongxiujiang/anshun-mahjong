extends SceneTree
## 加杠只在本回合摸到第 4 张时开放；碰掉可明杠的牌后本局锁定该牌。

func _initialize() -> void:
	call_deferred("_run")

func _round() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261021)
	r.build_players(0)
	r.phase = RoundState.Phase.PLAYING
	r.current_turn = 0
	r.awaiting = true
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	var p: PlayerState = r.players[0]
	p.first_turn_done = true
	p.concealed = ["wan9", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "tiao1", "tiao2", "tiao3", "tiao4", "tong1"]
	p.melds = [{"kind": "pung", "tile": "wan9"}]
	p.just_drew = "wan9"
	return r

func _run() -> void:
	var r := _round()
	var p: PlayerState = r.players[0]
	var ok: bool = r.legal_turn_options(0).add_kong.has("wan9")
	p.just_drew = ""
	ok = ok and not r.legal_turn_options(0).add_kong.has("wan9")
	p.just_drew = "wan9"
	p.add_kong_locked_tiles = ["wan9"]
	ok = ok and not r.legal_turn_options(0).add_kong.has("wan9")

	var pong := RoundState.new()
	pong.set_rng_seed(20261021)
	pong.build_players(0)
	pong.phase = RoundState.Phase.PLAYING
	pong.current_turn = 1
	pong.awaiting = true
	pong.wall = WallRing.new(TileSetFactory.create_deck())
	pong.wall.set_head(0)
	pong.players[0].concealed = ["wan9", "wan9", "wan9", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "tiao1", "tiao2"]
	pong.players[1].discards = ["wan9"]
	pong.players[1].discard_ids = [0]
	pong.last_discard = {"seat": 1, "tile": "wan9"}
	pong._awaiting_response = {"seat": 0, "disc_seat": 1, "tile": "wan9", "stage": RoundState.ResponseStage.MELD}
	pong._pending_responders = [0]
	pong._response_stage = RoundState.ResponseStage.MELD
	ok = ok and pong.submit_response(0, "wan9", {"action": "pong"})
	ok = ok and pong.players[0].add_kong_locked_tiles.has("wan9")
	ok = ok and not pong.legal_turn_options(0).add_kong.has("wan9")

	print("[add_kong_window] ", "passed" if ok else "FAILED")
	quit(0 if ok else 1)
