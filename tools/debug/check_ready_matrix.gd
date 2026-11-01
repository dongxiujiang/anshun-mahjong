extends SceneTree
## 穷举报听相关的结算分支，打印每家净分和逐笔转账。
##
## 只包含真实对局能出现的组合：报听者不能暗杠/加杠（RoundState.gd:1006,1020），
## 所以「被抢杠者报听」「杠后放炮的放炮者报听」不可能出现，这里不列。

const PLAIN := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tong1", "tong2",
	"tong3", "tiao2", "tiao3", "tiao4", "tong9", "tong9"]
const PATTERN := ["wan1", "wan1", "wan1", "tong2", "tong2", "tong2", "tiao4", "tiao4",
	"tiao4", "wan6", "wan6", "wan6", "tong9", "tong9"]
const JUNK := ["wan1", "wan4", "wan7", "wan9", "tong1", "tong3", "tong4", "tong7",
	"tiao5", "tiao8", "wan2", "wan8", "tiao9"]
const JUNK2 := ["wan2", "wan5", "wan6", "tong2", "tong5", "tong9", "tiao3", "tiao6",
	"tiao9", "wan9", "tong1", "tong3", "tiao7"]
const JUNK3 := ["wan3", "wan6", "wan8", "tong3", "tong5", "tong7", "tiao2", "tiao7",
	"tiao9", "wan2", "wan8", "tong6", "tong1"]


func _initialize() -> void:
	call_deferred("_run")


func _round() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261101)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	r.players[1].concealed = JUNK.duplicate()
	r.players[2].concealed = JUNK2.duplicate()
	r.players[3].concealed = JUNK3.duplicate()
	return r


func _case(name: String, build: Callable) -> void:
	var r := _round()
	build.call(r)
	var result: Dictionary = ScoringEngine.settle(r)
	var cells: PackedStringArray = []
	for t in result.transfers:
		cells.append("%d→%d %s %.0f" % [int(t.from), int(t.to), str(t.reason), float(t.amount)])
	print("%-40s | 净分 %s | %s" % [name, str(result.deltas), "；".join(cells)])


func _run() -> void:
	_case("A1 报听自摸·无牌型", func(r: RoundState) -> void:
		r.players[0].concealed = PLAIN.duplicate()
		r.players[0].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true, "flip_tile": "tiao9"}, true))
	_case("A2 报听自摸·有牌型", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		r.players[0].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true, "flip_tile": "tiao9"}, true))
	_case("A3 报听点炮·无牌型", func(r: RoundState) -> void:
		r.players[0].concealed = PLAIN.duplicate()
		r.players[0].ready = true
		r.players[1].discards = ["wan6"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "wan6", "flip_tile": "tiao9"}, true))
	_case("A4 报听点炮·有牌型", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		r.players[0].ready = true
		r.players[1].discards = ["wan6"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "wan6", "flip_tile": "tiao9"}, true))
	_case("A5 报听抢杠·无牌型", func(r: RoundState) -> void:
		r.players[0].concealed = PLAIN.duplicate()
		r.players[0].ready = true
		r.players[1].melds = [{"kind": "pung", "tile": "wan6", "from_seat": 2, "robbed": true}]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"robbed_kong": true, "discard_seat": 1, "win_tile": "wan6", "flip_tile": "tiao9"}, true))
	_case("A6 报听杠后放炮·无牌型", func(r: RoundState) -> void:
		r.players[0].concealed = PLAIN.duplicate()
		r.players[0].ready = true
		r.players[1].discards = ["wan6"]
		r.last_discard = {"after_kong": true, "kong_kind": RoundState.KongKind.ADD_KONG, "tile": "wan6"}
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "wan6", "flip_tile": "tiao9",
			"burn_chicken_seat": 1}, true))
	_case("B1 自摸·座位1报听（杀报）", func(r: RoundState) -> void:
		r.players[0].concealed = PLAIN.duplicate()
		r.players[1].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true, "flip_tile": "tiao9"}, true))
	_case("B2 自摸·座位1、2都报听", func(r: RoundState) -> void:
		r.players[0].concealed = PLAIN.duplicate()
		r.players[1].ready = true
		r.players[2].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true, "flip_tile": "tiao9"}, true))
	_case("B3 点炮·放炮者报听（杀报）", func(r: RoundState) -> void:
		r.players[0].concealed = PLAIN.duplicate()
		r.players[1].ready = true
		r.players[1].discards = ["wan6"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "wan6", "flip_tile": "tiao9"}, true))
	_case("B4 点炮·放炮者报听且有牌型", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		r.players[1].ready = true
		r.players[1].discards = ["wan6"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "wan6", "flip_tile": "tiao9"}, true))
	_case("C1 双方都报听·点炮", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		r.players[0].ready = true
		r.players[1].ready = true
		r.players[1].discards = ["wan6"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "wan6", "flip_tile": "tiao9"}, true))
	_case("C2 赢家报听·另有他报听·自摸", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		r.players[0].ready = true
		r.players[2].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true, "flip_tile": "tiao9"}, true))
	_case("D1 报听自摸·倍率2", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		r.players[0].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true,
			"flip_tile": "tiao9", "chicken_multiplier": 2}, true))
	_case("E1 报听自摸·赢家烧鸡", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		r.players[0].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true,
			"flip_tile": "tiao9", "burn_chicken_seat": 0}, true))
	_case("F1 流局·只有座位0报听", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
			"tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]
		r.players[0].ready = true
		r.round_meta.merge({"winner": -1, "winners": [], "self_draw": false, "flip_tile": ""}, true))
	_case("F2 流局·座位0报听且听牌型", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan1", "wan1", "wan1", "wan2", "wan2", "wan2",
			"wan3", "wan3", "wan3", "wan9", "wan9", "wan9", "wan5"]
		r.players[0].ready = true
		r.round_meta.merge({"winner": -1, "winners": [], "self_draw": false, "flip_tile": ""}, true))
	_case("B6 自摸有牌型·座位1报听", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		r.players[1].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true, "flip_tile": "tiao9"}, true))
	_case("B7 自摸有牌型·三家都报听", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		for seat in [1, 2, 3]:
			r.players[seat].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true, "flip_tile": "tiao9"}, true))
	_case("A7 报听自摸·杠开", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		r.players[0].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true,
			"kong_draw_seat": 0, "flip_tile": "tiao9"}, true))
	_case("A8 报听抢杠·有牌型", func(r: RoundState) -> void:
		r.players[0].concealed = PATTERN.duplicate()
		r.players[0].ready = true
		r.players[1].melds = [{"kind": "pung", "tile": "wan6", "from_seat": 2, "robbed": true}]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"robbed_kong": true, "discard_seat": 1, "win_tile": "wan6", "flip_tile": "tiao9"}, true))
	_case("B8 自摸无牌型有鸡·座位1报听", func(r: RoundState) -> void:
		r.players[0].concealed = ["tiao1", "tiao1", "tiao1", "wan1", "wan2", "wan3",
			"wan4", "wan5", "wan6", "tong4", "tong5", "tong6", "tong9", "tong9"]
		r.players[1].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true, "flip_tile": "tiao6"}, true))
	quit()
