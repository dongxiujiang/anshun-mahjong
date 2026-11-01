extends SceneTree
## 四人示例局：校验牌数、叫牌状态与引擎算分。

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var r := RoundState.new()
	r.set_rng_seed(20261101)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING

	# 座位0：报听，大对子，胡座位1 打出的六万
	r.players[0].concealed = ["tiao1", "tiao1", "wan1", "wan1", "wan1", "tong2", "tong2",
		"tong2", "tiao4", "tiao4", "tiao4", "wan6", "wan6", "wan6"]
	r.players[0].ready = true

	# 座位1：报听并放炮；八筒两张
	r.players[1].concealed = ["wan2", "wan2", "wan2", "tong3", "tong3", "tong3",
		"tiao5", "tiao5", "tiao5", "wan7", "wan7", "tong8", "tong8"]
	r.players[1].ready = true
	r.players[1].discards = ["wan6"]

	# 座位2：没叫；明杠八条（放杠者座位3）
	r.players[2].concealed = ["wan3", "wan3", "tiao9", "tiao9", "tong1", "tong1",
		"tiao6", "tiao7", "wan5", "wan5"]
	r.players[2].melds = [{"kind": "kong", "tile": "tiao8", "from_seat": 3, "concealed": false}]

	# 座位3：没叫；是座位2 明杠的放杠者
	r.players[3].concealed = ["wan9", "wan9", "tiao3", "tiao3", "tiao3", "tong5",
		"tong5", "tong5", "tong6", "tong6", "tong7", "tong7", "tiao2"]

	r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
		"discard_seat": 1, "win_tile": "wan6", "flip_tile": "tong8"}, true)

	var result: Dictionary = ScoringEngine.settle(r)
	print("叫牌：", result.called)
	print("鸡分：", result.points)
	print("净分：", result.deltas)
	for t in result.transfers:
		print("  %d → %d  %s  %.0f" % [int(t.from), int(t.to), str(t.reason), float(t.amount)])
	quit()
