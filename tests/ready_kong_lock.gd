extends SceneTree
## 报听后的行为锁定：
##   1. 手牌不能改，只能打刚摸到的牌
##   2. 不能碰、不能明杠、不能暗杠、不能加杠
##   3. 未过胡时可以自摸、胡别人弃牌、抢杠；过胡后本局只能自摸
##   4. 非报听玩家杠后弃牌，被报听玩家胡牌（杠后放炮，结算按报听算）
##
## 对应 RoundState.gd:554,1006,1020 与 LegalActions.gd:9,106,110,148。

const H := preload("res://tests/test_harness.gd")
const ACTIONS := preload("res://scripts/core/LegalActions.gd")

var t := H.new()

const TENPAI := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8",
	"wan9", "tong2", "tong3", "tong4", "tong5"]
const JUNK := ["wan1", "wan4", "wan7", "wan9", "tong1", "tong3", "tong5",
	"tong7", "tong9", "tiao2", "tiao5", "tiao8", "tiao9"]
const JUNK2 := ["wan2", "wan5", "wan6", "tong2", "tong4", "tong7", "tong9",
	"tiao3", "tiao6", "tiao9", "wan9", "tong1", "tong3"]
const JUNK3 := ["wan3", "wan6", "wan8", "tong3", "tong5", "tong9", "tiao2",
	"tiao7", "tiao9", "wan2", "wan8", "tong6", "tong1"]


func _initialize() -> void:
	call_deferred("_run")


func _fixture() -> RoundState:
	var game := RoundState.new()
	game.set_rng_seed(20261102)
	game.build_players(0)
	game.controllers = [null, null, null, null]
	game.wall = WallRing.new(TileSetFactory.create_deck())
	game.wall.set_head(0)
	game.phase = RoundState.Phase.PLAYING
	game.players[1].concealed = JUNK.duplicate()
	game.players[2].concealed = JUNK2.duplicate()
	game.players[3].concealed = JUNK3.duplicate()
	return game


func _run() -> void:
	_test_hand_locked()
	_test_no_pong_or_kong()
	_test_can_win_and_rob()
	_test_post_kong_discard()
	await H.quit_cleanly(self, t.finish("ready_kong_lock"))


func _test_hand_locked() -> void:
	var ready_round := _fixture()
	ready_round.players[0].concealed = TENPAI.duplicate()
	ready_round.players[0].ready = true
	ready_round.players[0].just_drew = "wan9"
	var ready_options: Dictionary = ACTIONS.turn_options(ready_round, 0)
	t.expect(ready_options.discards == ["wan9"], "报听后只能打刚摸到的牌")
	t.expect(ready_options.kong_declares.is_empty() and ready_options.add_kong.is_empty(),
		"报听后不提供任何杠选项")

	var free_round := _fixture()
	free_round.players[0].concealed = TENPAI.duplicate()
	free_round.players[0].just_drew = "wan9"
	var free_options: Dictionary = ACTIONS.turn_options(free_round, 0)
	t.expect(free_options.discards.size() > 1, "没报听可以打任意牌")


func _test_no_pong_or_kong() -> void:
	var round := _fixture()
	round.players[0].concealed = ["wan5", "wan5", "wan5", "wan6", "wan7", "wan8",
		"tong1", "tong2", "tong3", "tiao1", "tiao2", "tiao3", "wan9"]
	round.players[0].ready = true
	var meld: Dictionary = ACTIONS.response_options(round, 0, 1, "wan5",
		RoundState.ResponseStage.MELD)
	t.expect(not meld.can_pong, "报听后不能碰别人打出的牌")
	t.expect(not meld.can_kong, "报听后不能明杠别人打出的牌")

	var free_round := _fixture()
	free_round.players[0].concealed = ["wan5", "wan5", "wan5", "wan6", "wan7", "wan8",
		"tong1", "tong2", "tong3", "tiao1", "tiao2", "tiao3", "wan9"]
	var free_meld: Dictionary = ACTIONS.response_options(free_round, 0, 1, "wan5",
		RoundState.ResponseStage.MELD)
	t.expect(free_meld.can_pong and free_meld.can_kong, "没报听可以碰、可以明杠")


func _test_can_win_and_rob() -> void:
	var round := _fixture()
	round.players[0].concealed = TENPAI.duplicate()
	round.players[0].ready = true

	var win: Dictionary = ACTIONS.response_options(round, 0, 1, "tong5",
		RoundState.ResponseStage.WIN)
	t.expect(win.can_win, "报听后可以胡别人打出的牌")
	t.expect(not win.can_pong, "报听后不能碰")

	var rob: Dictionary = ACTIONS.response_options(round, 0, 1, "tong5",
		RoundState.ResponseStage.ROB)
	t.expect(rob.rob_kong and rob.can_win, "报听后可以抢杠")


func _test_post_kong_discard() -> void:
	var round := _fixture()
	# 报听者听六万，大对子：幺鸡2 一万3 二筒3 四条3 六万2
	round.players[0].concealed = ["tiao1", "tiao1", "wan1", "wan1", "wan1",
		"tong2", "tong2", "tong2", "tiao4", "tiao4", "tiao4", "wan6", "wan6", "wan6"]
	round.players[0].ready = true
	round.players[1].melds = [{"kind": "add_kong", "tile": "wan6", "from_seat": -1, "concealed": false}]
	round.players[1].discards = ["wan6"]
	round.last_discard = {"after_kong": true, "kong_kind": RoundState.KongKind.ADD_KONG, "tile": "wan6"}
	round.round_meta.merge({"winner": 0, "winners": [0], "self_draw": false,
		"discard_seat": 1, "win_tile": "wan6", "flip_tile": "tiao6",
		"burn_chicken_seat": 1, "burn_chicken_reason": "after_kong_discard"}, true)
	var result: Dictionary = ScoringEngine.settle(round)
	# 放炮者(未叫)：21 杠后放炮 + 20 报听 + 14 大对子 + 4 鸡分差 = 59
	# 另外两家：各付 4 鸡分差
	t.expect(result.deltas == [67.0, -59.0, -4.0, -4.0],
		"报听者胡杠后弃牌：期望 [67,-59,-4,-4]，实际 %s" % str(result.deltas))
	var base_paid := false
	for tr in result.transfers:
		if int(tr.from) == 1 and int(tr.to) == 0 \
			and str(tr.reason) == "点炮基础分（未叫牌）" and float(tr.amount) == 21.0:
			base_paid = true
	t.expect(base_paid, "杠后放炮按未叫牌 21 分")
