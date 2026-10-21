extends SceneTree
## 暗杠只在“开局四张”或“本次摸到第四张”的弃牌前开放；
## 选择弃牌后，本局不能再暗杠这张牌。明杠/加杠保持原规则。

func _initialize() -> void:
	call_deferred("_run")

func _fixture() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261021)
	r.build_players(0)
	r.phase = RoundState.Phase.PLAYING
	r.wall = WallRing.new(TileSetFactory.create_deck())
	r.wall.set_head(0)
	var p: PlayerState = r.players[0]
	p.concealed = ["wan1", "wan1", "wan1", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tiao1", "tiao2"]
	p.just_drew = "tiao2"
	p.first_turn_done = false
	return r

func _run() -> void:
	var ok := true
	var r := _fixture()
	var p: PlayerState = r.players[0]
	ok = ok and r.legal_turn_options(0).kong_declares.has("wan1")
	# 选择过牌/弃牌，失去开局暗杠窗口。
	p.first_turn_done = true
	p.just_drew = ""
	ok = ok and not r.legal_turn_options(0).kong_declares.has("wan1")
	# 本回合摸到第四张：窗口打开。
	p.concealed = ["wan1", "wan1", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "tiao1", "tiao2", "tiao3", "wan1"]
	p.just_drew = "wan1"
	ok = ok and r.legal_turn_options(0).kong_declares.has("wan1")
	# 弃牌后窗口关闭。
	p.just_drew = ""
	ok = ok and not r.legal_turn_options(0).kong_declares.has("wan1")
	# 加杠不受这个窗口限制。
	p.concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tiao1", "tiao2", "tiao3", "tiao4", "tong1"]
	p.melds = [{"kind": "pung", "tile": "wan1"}]
	p.first_turn_done = true
	p.just_drew = "tong1"
	ok = ok and r.legal_turn_options(0).add_kong.has("wan1")
	print("[concealed_kong_window] ", "passed" if ok else "FAILED")
	quit(0 if ok else 1)
