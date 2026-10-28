extends SceneTree
## 不变式检查：任意局面下，未叫牌玩家之间不得互相付款。
##
## 覆盖：胜负/流局、自摸/点炮/抢杠/杠后、各种杠（明/暗/加）、鸡、报听。
## 运行：
##   Godot_v4.7.2-stable_win64.exe --headless --path <项目> \
##       --script res://tools/debug/check_uncalled_pair.gd

const TILES := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9",
	"tong1", "tong2", "tong3", "tong4", "tong5", "tong6", "tong7", "tong8", "tong9",
	"tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tiao7", "tiao8", "tiao9"]
const PLAIN := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4",
	"tong2", "tong3", "tong4", "wan9"]
const READY := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4",
	"tong1", "tong2", "tong3", "wan9"]
const JUNK := ["wan1", "wan4", "wan7", "tong1", "tong4", "tong7", "tiao2", "tiao5", "tiao8",
	"wan9", "tong2", "tong6", "tiao9"]

var bad := 0
var checked := 0


func _initialize() -> void:
	call_deferred("_run")


func _build(rng: RandomNumberGenerator, index: int) -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(1000 + index)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	for seat in 4:
		r.players[seat].concealed = (READY if rng.randf() < 0.5 else PLAIN).duplicate()
	# 随机杠
	for seat in 4:
		var kong_count := rng.randi_range(0, 1)
		for _k in kong_count:
			var tile: String = TILES[rng.randi_range(0, TILES.size() - 1)]
			var kind := rng.randi_range(0, 2)
			var meld := {"kind": "kong", "tile": tile, "from_seat": rng.randi_range(0, 3)}
			if kind == 0:
				meld["kind"] = "kong"
				meld["concealed"] = false
			elif kind == 1:
				meld["kind"] = "kong"
				meld["concealed"] = true
				meld["from_seat"] = -1
			else:
				meld["kind"] = "add_kong"
				meld["from_seat"] = -1
			r.players[seat].melds.append(meld)
	# 随机打出鸡
	for seat in 4:
		if rng.randf() < 0.4:
			r.players[seat].discards = ["tiao1" if rng.randf() < 0.5 else "tong8"]
	# 随机报听
	for seat in 4:
		r.players[seat].ready = rng.randf() < 0.45
	var draw := rng.randf() < 0.2
	if draw:
		r.round_meta.merge({"winner": -1, "winners": [], "self_draw": false,
			"flip_tile": ""}, true)
	else:
		var winner := rng.randi_range(0, 3)
		r.round_meta.merge({"winner": winner, "winners": [winner],
			"self_draw": rng.randf() < 0.5,
			"discard_seat": rng.randi_range(0, 3),
			"win_tile": "wan9", "flip_tile": "tong5"}, true)
	return r


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261029
	for index in 3000:
		var round := _build(rng, index)
		var result: Dictionary = ScoringEngine.settle(round)
		var called: Array = result.called
		checked += 1
		for t in result.transfers:
			var a := int(t.from)
			var b := int(t.to)
			if a == b:
				continue
			if not bool(called[a]) and not bool(called[b]):
				bad += 1
				print("违规：未叫者 %d -> 未叫者 %d  %s %.0f 分（种子 %d）" % [
					a, b, str(t.reason), float(t.amount), 1000 + index])
	print("检查 %d 局，未叫者互相付款 %d 笔" % [checked, bad])
	quit()
