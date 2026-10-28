extends SceneTree
## 逐题算分回归：与产品一对一核对过的 52 个局面。
## 每条都写在名字里，失败时能直接看出是哪道题。
##
## 运行：
##   Godot_v4.7.2-stable_win64.exe --headless --path <项目> \
##       --script res://tests/scoring_chat_cases.gd

const H := preload("res://tests/test_harness.gd")
const CHICKEN := preload("res://scripts/core/ChickenScoring.gd")
const CFG := preload("res://scripts/autoload/GameConfig.gd")
const WIN := preload("res://scripts/core/WinScoring.gd")

var t := H.new()

const JUNK := ["wan1", "wan4", "wan7", "wan9", "tong1", "tong3",
	"tong5", "tong7", "tong9", "tiao2", "tiao5", "tiao8", "tiao9"]
const JUNK2 := ["wan2", "wan5", "wan6", "tong2", "tong4", "tong7",
	"tong9", "tiao3", "tiao6", "tiao9", "wan9", "tong1", "tong3"]
const JUNK3 := ["wan3", "wan6", "wan8", "tong3", "tong5", "tong9",
	"tiao2", "tiao7", "tiao9", "wan2", "wan8", "tong6", "tong1"]
const WAIT_HAND := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
	"tiao2", "tiao3", "tiao4", "tong1", "tong2", "tong3", "wan9"]


func _initialize() -> void:
	call_deferred("_run")


func _round() -> RoundState:
	var r := RoundState.new()
	r.set_rng_seed(20261029)
	r.build_players(0)
	r.controllers = [null, null, null, null]
	r.phase = RoundState.Phase.PLAYING
	r.players[1].concealed = JUNK.duplicate()
	r.players[2].concealed = JUNK2.slice(0, 13)
	r.players[3].concealed = JUNK3.slice(0, 13)
	return r


## 鸡分题：叫牌看收入，没叫看欠账。杠基础分按产品口径计入。
func _chicken(name: String, hand: Array, flip: String, answer: int,
		melds: Array = [], discards: Array = [], called: bool = true,
		charge: bool = false, burn: bool = false) -> void:
	var r := _round()
	r.players[0].concealed = hand.duplicate()
	r.players[0].melds = melds.duplicate(true)
	r.players[0].discards = discards.duplicate()
	r.players[0].discard_ids = range(discards.size())
	r.players[0].ready = called
	if charge and not discards.is_empty():
		r.round_meta.merge({"charge_chickens": {discards[0]: {"owner": 0,
			"location": "discard", "discard_id": 0}}}, true)
	if burn:
		r.round_meta.merge({"burn_chicken_seat": 0}, true)
	var kong_total := 0
	for meld in melds:
		if str(meld.get("kind", "")) in ["kong", "add_kong"]:
			var own: bool = meld.get("kind", "") == "add_kong" or bool(meld.get("concealed", false))
			# 明杠的 4 分只由放杠者付，单玩家口径里不计；暗杠/加杠才是三家各付。
			if own:
				kong_total += 4
	var profile: Dictionary = CHICKEN.chicken_profile(r, 0, flip)
	var value := int(float(profile.get("total", 0.0)))
	if called:
		value += kong_total
	else:
		# 未叫者暗杠/加杠：杠基础 4 + 杠中鸡（幺鸡 8 / 金 16）向后补付。
		var kong_chicken := 0
		for meld in melds:
			if str(meld.get("kind", "")) in ["kong", "add_kong"]:
				var own: bool = meld.get("kind", "") == "add_kong" or bool(meld.get("concealed", false))
				if own and Tiles.is_chicken(str(meld.get("tile", ""))):
					kong_chicken += 16 if str(meld.get("tile", "")) in Tiles.flip_related(flip) else 8
		value = -(kong_total + kong_chicken + int(float(profile.get("discard_debt", 0.0))) \
			+ int(float(profile.get("pung_debt", 0.0))))
	if burn:
		value = 0
	t.expect(value == answer, "%s：期望 %d，实际 %d" % [name, answer, value])


## 牌型题
func _pattern(name: String, hand: Array, melds: Array, win_tile: String,
		label: String, score: float) -> void:
	var pattern := RuleEngine.hand_pattern(hand, melds, win_tile)
	t.expect(bool(pattern.get("win", false)), "%s：这手牌不成立" % name)
	var info: Dictionary = WIN._pattern_info(pattern)
	var got := str(info.get("label", ""))
	var scored := float(info.get("score", 0.0))
	t.expect(got == label and is_equal_approx(scored, score),
		"%s：期望 %s %d，实际 %s %d" % [name, label, int(score), got, int(scored)])


## 结算题
func _settle(name: String, builder: Callable, expected: Array) -> void:
	var r := _round()
	builder.call(r)
	var result: Dictionary = ScoringEngine.settle(r)
	t.expect(result.deltas == expected,
		"%s：期望 %s，实际 %s" % [name, str(expected), str(result.deltas)])


func _run() -> void:
	_test_chicken()
	_test_patterns()
	_test_settlements()
	await H.quit_cleanly(self, t.finish("scoring_chat_cases"))


func _test_chicken() -> void:
	_chicken("1 叫牌 幺鸡3+八筒2", ["tiao1", "tiao1", "tiao1", "wan1", "wan2", "wan3",
		"wan4", "wan5", "wan6", "tong8", "tong8", "tiao2", "tiao3"], "tong5", 10)
	_chicken("2 同上翻一条金鸡", ["tiao1", "tiao1", "tiao1", "wan1", "wan2", "wan3",
		"wan4", "wan5", "wan6", "tong8", "tong8", "tiao2", "tiao3"], "tiao1", 17)
	_chicken("3 打出冲锋幺鸡", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7",
		"wan8", "wan9", "tong2", "tong3", "tong4", "tong8"], "tong6", 6,
		[], ["tiao1"], true, true)
	_chicken("4 碰幺鸡", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tong8", "tong8",
		"tiao2", "tiao3"], "tong6", 10, [{"kind": "pung", "tile": "tiao1", "from_seat": 2}])
	_chicken("5 暗杠幺鸡含杠基础", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"tong8", "tong8", "tiao2", "tiao3"], "tong6", 16,
		[{"kind": "kong", "tile": "tiao1", "from_seat": -1, "concealed": true}])
	_chicken("6 手里八筒1 翻九筒金鸡", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong2", "tong3", "tong4", "tong8"], "tong9", 4)
	_chicken("7 手里五筒3 翻五筒", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong5", "tong5", "tong5", "tong2"], "tong5", 3)
	_chicken("8 没叫 手里有鸡", ["tiao1", "tiao1", "tiao1", "wan1", "wan4", "wan7",
		"tong1", "tong4", "tong8", "tong8", "tiao5", "tiao8", "wan9"], "tong5", 0,
		[], [], false)
	_chicken("9 没叫 打出冲锋幺鸡", ["wan1", "wan4", "wan7", "tong1", "tong4", "tiao5",
		"tiao8", "wan9", "tong2", "tong5", "tong9", "wan2", "tiao7"], "tong5", -4,
		[], ["tiao1"], false, true)
	_chicken("10 碰幺鸡 翻一条", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"tong8", "tong8", "tiao2", "tiao3"], "tiao1", 17,
		[{"kind": "pung", "tile": "tiao1", "from_seat": 2}])
	_chicken("11 暗杠八筒 翻九筒", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong2"], "tong9", 20,
		[{"kind": "kong", "tile": "tong8", "from_seat": -1, "concealed": true}])
	_chicken("12 没叫 碰幺鸡", ["wan1", "wan4", "wan7", "tong1", "tong4", "tiao5",
		"tiao8", "wan9", "tong2", "tong5"], "tiao6", -6,
		[{"kind": "pung", "tile": "tiao1", "from_seat": 2}], [], false)
	_chicken("13 没叫 打出普通幺鸡", ["tiao1", "tiao1", "tong8", "wan1", "wan4", "wan7",
		"tong1", "tong4", "tiao5", "tiao8", "wan9", "tong2", "tong5"], "tiao6", -2,
		[], ["tiao1"], false)
	_chicken("14 打出冲锋八筒+普通幺鸡", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong2", "tong3", "tong4", "tong5"], "tiao4", 6,
		[], ["tong8", "tiao1"], true, true)
	_chicken("15 手里八筒2 翻八筒", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong2", "tong3", "tong8", "tong8"], "tong8", 8)
	_chicken("16 碰八筒 翻八筒", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong5"], "tong8", 12,
		[{"kind": "pung", "tile": "tong8", "from_seat": 2}])
	_chicken("17 烧鸡归零", ["tiao1", "tiao1", "tiao1", "wan1", "wan2", "wan3", "wan4",
		"wan5", "wan6", "tong8", "tong8", "tiao2", "tiao3"], "tong6", 0,
		[], [], true, false, true)
	_chicken("18 同17 不烧鸡", ["tiao1", "tiao1", "tiao1", "wan1", "wan2", "wan3", "wan4",
		"wan5", "wan6", "tong8", "tong8", "tiao2", "tiao3"], "tong6", 10)
	_chicken("19 幺鸡在顺子 单张八筒", ["tiao1", "tiao2", "tiao3", "wan1", "wan2", "wan3",
		"wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tong8"], "tong8", 6)
	_chicken("20 幺鸡对子 翻五筒", ["tiao1", "tiao1", "tong5", "tong6", "wan1", "wan2",
		"wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9"], "tong5", 6)
	_chicken("21 暗杠五筒 翻五筒", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong2"], "tong5", 8,
		[{"kind": "kong", "tile": "tong5", "from_seat": -1, "concealed": true}])
	_chicken("22 打出冲锋+普通幺鸡", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong2", "tong3", "tong4", "tong5"], "tiao6", 6,
		[], ["tiao1", "tiao1"], true, true)
	_chicken("23 没叫 碰幺鸡+冲锋八筒", ["wan1", "wan4", "wan7", "tong1", "tong4",
		"tiao5", "tiao8", "wan9", "tong2", "tong5"], "tiao6", -10,
		[{"kind": "pung", "tile": "tiao1", "from_seat": 2}], ["tong8"], false, true)
	_chicken("24 手里八筒3 翻七筒", ["tong8", "tong8", "tong8", "wan1", "wan2", "wan3",
		"wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tong2"], "tong7", 12)
	_chicken("25 打出的冲锋幺鸡被翻中", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong2", "tong3", "tong4", "tong5"], "tiao2", 8,
		[], ["tiao1"], true, true)
	_chicken("26 打出的普通幺鸡被翻中", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong2", "tong3", "tong4", "tong5"], "tiao2", 4,
		[], ["tiao1"], true, false)
	_chicken("27 明杠幺鸡", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7",
		"wan8", "wan9", "tong2"], "tiao6", 8,
		[{"kind": "kong", "tile": "tiao1", "from_seat": 2, "concealed": false}])
	_chicken("28 没叫 暗杠幺鸡", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
		"wan7", "wan8", "wan9", "tong2"], "tiao6", -12,
		[{"kind": "kong", "tile": "tiao1", "from_seat": -1, "concealed": true}], [], false)
	_chicken("29 手里八筒+碰幺鸡+冲锋八筒", ["wan1", "wan2", "wan3", "wan4", "wan5",
		"wan6", "wan7", "wan8", "wan9", "tong8"], "tiao6", 12,
		[{"kind": "pung", "tile": "tiao1", "from_seat": 2}], ["tong8"], true, true)


func _test_patterns() -> void:
	_pattern("31 大对子", ["wan1", "wan1", "wan1", "tong2", "tong2", "tong2", "tiao4",
		"tiao4", "tiao4", "wan6", "wan6", "wan6", "tong9", "tong9"], [], "wan6", "大对子", 14.0)
	_pattern("32 大对子单吊", ["tong9", "tong9"], [
		{"kind": "pung", "tile": "wan1"}, {"kind": "pung", "tile": "tong2"},
		{"kind": "pung", "tile": "tiao4"}, {"kind": "pung", "tile": "wan6"}],
		"tong9", "大对子单吊", 24.0)
	_pattern("33 小七对", ["wan1", "wan1", "wan2", "wan2", "tong3", "tong3", "tong4",
		"tong4", "tiao5", "tiao5", "tiao6", "tiao6", "wan9", "wan9"], [], "wan9", "小七对", 24.0)
	_pattern("34 龙七对", ["wan1", "wan1", "wan1", "wan1", "wan2", "wan2", "tong3",
		"tong3", "tong4", "tong4", "tiao5", "tiao5", "tiao6", "tiao6"], [], "wan1", "龙七对", 44.0)
	_pattern("35 清一色", ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7",
		"wan8", "wan9", "wan2", "wan3", "wan4", "wan9", "wan9"], [], "wan9", "清一色", 24.0)
	_pattern("36 清大对", ["wan1", "wan1", "wan1", "wan2", "wan2", "wan2", "wan3",
		"wan3", "wan3", "wan4", "wan4", "wan4", "wan9", "wan9"], [], "wan4", "清大对", 34.0)
	_pattern("37 清七对", ["wan1", "wan1", "wan2", "wan2", "wan3", "wan3", "wan4",
		"wan4", "wan5", "wan5", "wan6", "wan6", "wan9", "wan9"], [], "wan9", "清七对", 44.0)


func _test_settlements() -> void:
	_settle("38 报听自摸大对子八筒2", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan1", "wan1", "wan1", "tong2", "tong2", "tong2",
			"tiao4", "tiao4", "tiao4", "wan6", "wan6", "wan6", "tong8", "tong8"]
		r.players[0].ready = true
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true,
			"flip_tile": "tong5"}, true), [114.0, -38.0, -38.0, -38.0])
	_settle("39 报听点炮大对子幺鸡2", func(r: RoundState) -> void:
		r.players[0].concealed = ["tiao1", "tiao1", "wan1", "wan1", "wan1", "tong2",
			"tong2", "tong2", "tiao4", "tiao4", "tiao4", "wan6", "wan6", "wan6"]
		r.players[0].ready = true
		r.players[1].discards = ["wan6"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "wan6", "flip_tile": "tong5"}, true),
		[46.0, -38.0, -4.0, -4.0])
	_settle("41 抢杠胡", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan7", "wan8", "wan9", "wan1", "wan2", "wan3",
			"tong4", "tong5", "tong6", "tiao2", "tiao3", "tiao4", "tong9", "tong9"]
		r.players[1].melds = [{"kind": "pung", "tile": "wan9", "from_seat": 2, "robbed": true}]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"robbed_kong": true, "discard_seat": 1, "win_tile": "wan9",
			"flip_tile": "tiao6"}, true), [12.0, -12.0, 0.0, 0.0])
	_settle("42 杠后放炮放炮者已叫", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
			"tong1", "tong2", "tong3", "tiao2", "tiao3", "tiao4", "tong9", "tong9"]
		r.players[1].concealed = WAIT_HAND.duplicate()
		r.players[1].discards = ["wan5"]
		r.last_discard = {"after_kong": true, "kong_kind": RoundState.KongKind.ADD_KONG, "tile": "wan5"}
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "wan5", "flip_tile": "tiao6",
			"burn_chicken_seat": 1, "burn_chicken_reason": "after_kong_discard"}, true),
		[17.0, -17.0, 0.0, 0.0])
	_settle("43 杠后放炮放炮者没叫", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
			"tong1", "tong2", "tong3", "tiao2", "tiao3", "tiao4", "tong9", "tong9"]
		r.players[1].discards = ["wan5"]
		r.last_discard = {"after_kong": true, "kong_kind": RoundState.KongKind.ADD_KONG, "tile": "wan5"}
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "wan5", "flip_tile": "tiao6",
			"burn_chicken_seat": 1, "burn_chicken_reason": "after_kong_discard"}, true),
		[21.0, -21.0, 0.0, 0.0])
	_settle("44 通行证胡牌+暗杠", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
			"tong4", "tong5", "tong6", "tiao2", "tiao2"]
		r.players[0].melds = [{"kind": "kong", "tile": "tong1", "from_seat": -1, "concealed": true}]
		r.players[1].discards = ["tiao2"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "tiao2", "flip_tile": "tiao6"}, true),
		[16.0, -8.0, -4.0, -4.0])
	_settle("45 杀报", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
			"tong1", "tong2", "tong3", "tiao2", "tiao3", "tiao4", "tong9", "tong9"]
		r.players[1].concealed = WAIT_HAND.duplicate()
		r.players[1].ready = true
		r.players[1].discards = ["wan5"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
			"discard_seat": 1, "win_tile": "wan5", "flip_tile": "tiao9"}, true),
		[24.0, -24.0, 0.0, 0.0])
	_settle("46 大干扣", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
			"tong1", "tong2", "tong3", "tiao2", "tiao3", "tiao4", "tong9", "tong9"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true,
			"flip_tile": "tiao9"}, true), [72.0, -24.0, -24.0, -24.0])
	_settle("47 干扣 另一家叫牌有鸡", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
			"tong1", "tong2", "tong3", "tiao2", "tiao3", "tiao4", "tong9", "tong9"]
		r.players[1].concealed = ["tiao1", "tiao1", "tiao1", "tong2", "tong2", "tong2",
			"tiao4", "tiao4", "tiao4", "wan6", "wan6", "wan6", "wan9"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true,
			"flip_tile": "tiao6"}, true), [36.0, 4.0, -20.0, -20.0])
	_settle("48 杠开自摸 带暗杠", func(r: RoundState) -> void:
		r.players[0].concealed = ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6",
			"tong4", "tong5", "tong6", "tiao2", "tiao2"]
		r.players[0].melds = [{"kind": "kong", "tile": "tong1", "from_seat": -1, "concealed": true}]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true,
			"kong_draw_seat": 0, "flip_tile": "tiao9"}, true), [39.0, -13.0, -13.0, -13.0])
	_settle("49 海底自摸 幺鸡3", func(r: RoundState) -> void:
		r.players[0].concealed = ["tiao1", "tiao1", "tiao1", "wan1", "wan2", "wan3",
			"wan4", "wan5", "wan6", "tong4", "tong5", "tong6", "tong9", "tong9"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true,
			"last_four_self_draw_seat": 0, "flip_tile": "tiao6"}, true),
		[45.0, -15.0, -15.0, -15.0])
	_settle("50 流局四家都叫", func(r: RoundState) -> void:
		for seat in 4:
			r.players[seat].concealed = WAIT_HAND.duplicate()
		r.round_meta.merge({"winner": -1, "winners": [], "self_draw": false,
			"flip_tile": ""}, true), [0.0, 0.0, 0.0, 0.0])
	_settle("51 流局只我叫 座位1打过冲锋幺鸡", func(r: RoundState) -> void:
		r.players[0].concealed = WAIT_HAND.duplicate()
		r.players[1].discards = ["tiao1"]
		r.round_meta.merge({"winner": -1, "winners": [], "self_draw": false,
			"flip_tile": "",
			"charge_chickens": {"tiao1": {"owner": 1, "location": "discard", "discard_id": 0}}}, true),
		[16.0, -8.0, -4.0, -4.0])
	_settle("52 倍率2", func(r: RoundState) -> void:
		r.players[0].concealed = ["tiao1", "tiao1", "tiao1", "wan1", "wan2", "wan3",
			"wan4", "wan5", "wan6", "tong4", "tong5", "tong6", "tong9", "tong9"]
		r.round_meta.merge({"winner": 0, "winners": [0], "self_draw": true,
			"flip_tile": "tiao6", "chicken_multiplier": 2}, true),
		[60.0, -20.0, -20.0, -20.0])
