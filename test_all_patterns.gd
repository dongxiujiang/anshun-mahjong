extends Node

const RuleEngine := preload("res://scripts/core/RuleEngine.gd")
const ScoringEngine := preload("res://scripts/core/ScoringEngine.gd")
const RoundState := preload("res://scripts/core/RoundState.gd")
const PlayerState := preload("res://scripts/core/PlayerState.gd")
const Tiles := preload("res://scripts/core/Tiles.gd")

var test_cases := []
var output_dir := "user://test_screenshots/"

func _ready() -> void:
	var dir := DirAccess.open("user://")
	if not dir.dir_exists("test_screenshots"):
		dir.make_dir("test_screenshots")
	
	_generate_all_test_cases()
	print("生成了 %d 个测试用例" % test_cases.size())
	
	for i in test_cases.size():
		var test_case: Dictionary = test_cases[i]
		print("处理测试 %d/%d: %s" % [i + 1, test_cases.size(), test_case.name])
		var round := _create_test_round(test_case)
		var result := ScoringEngine.settle(round)
		_generate_description(test_case, result)
	
	print("所有说明文档已生成完毕！")
	print("输出目录：", OS.get_user_data_dir(), "/test_screenshots/")
	get_tree().quit()

func _generate_all_test_cases() -> void:
	test_cases.append({
		"name": "01_小七对_自摸",
		"concealed": ["wan1", "wan1", "wan2", "wan2", "wan3", "wan3", "wan4", "wan4", "wan5", "wan5", "wan6", "wan6", "wan7", "wan7"],
		"melds": [],
		"win_tile": "wan7",
		"self_draw": true,
		"description": "小七对自摸，赢家每家收24分"
	})
	
	test_cases.append({
		"name": "02_小七对_点炮",
		"concealed": ["tiao1", "tiao1", "tiao2", "tiao2", "tiao3", "tiao3", "tiao4", "tiao4", "tiao5", "tiao5", "tiao6", "tiao6", "tiao7", "tiao7"],
		"melds": [],
		"win_tile": "tiao7",
		"self_draw": false,
		"discard_seat": 1,
		"description": "小七对点炮，放炮者支付24分"
	})
	
	test_cases.append({
		"name": "03_龙七对_自摸",
		"concealed": ["wan1", "wan1", "wan1", "wan1", "wan2", "wan2", "wan3", "wan3", "wan4", "wan4", "wan5", "wan5", "wan6", "wan6"],
		"melds": [],
		"win_tile": "wan6",
		"self_draw": true,
		"description": "龙七对自摸（四张万1），赢家每家收44分"
	})
	
	test_cases.append({
		"name": "04_龙七对_点炮",
		"concealed": ["tong1", "tong1", "tong2", "tong2", "tong2", "tong2", "tong3", "tong3", "tong4", "tong4", "tong5", "tong5", "tong6", "tong6"],
		"melds": [],
		"win_tile": "tong6",
		"self_draw": false,
		"discard_seat": 2,
		"description": "龙七对点炮（四张筒2），放炮者支付44分"
	})
	
	test_cases.append({
		"name": "05_大对子_自摸",
		"concealed": ["wan1", "wan1", "wan2", "wan2", "wan2", "wan3", "wan3", "wan3", "wan4", "wan4", "wan4", "wan5", "wan5", "wan5"],
		"melds": [],
		"win_tile": "wan1",
		"self_draw": true,
		"description": "大对子自摸，赢家每家收14分"
	})
	
	test_cases.append({
		"name": "06_大对子_点炮",
		"concealed": ["tiao2", "tiao2", "tiao3", "tiao3", "tiao3", "tiao4", "tiao4", "tiao4", "tiao5", "tiao5", "tiao5", "tiao6", "tiao6", "tiao6"],
		"melds": [],
		"win_tile": "tiao2",
		"self_draw": false,
		"discard_seat": 3,
		"description": "大对子点炮，放炮者支付14分"
	})
	
	test_cases.append({
		"name": "07_大对子单吊_自摸",
		"concealed": ["wan1", "wan1", "wan2", "wan2", "wan2", "wan3", "wan3", "wan3", "wan4", "wan4", "wan4", "wan5", "wan5", "wan5"],
		"melds": [],
		"win_tile": "wan1",
		"self_draw": true,
		"description": "大对子单吊自摸，赢家每家收24分"
	})
	
	test_cases.append({
		"name": "08_清一色_自摸",
		"concealed": ["wan1", "wan1", "wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan7", "wan7", "wan8", "wan8", "wan8"],
		"melds": [],
		"win_tile": "wan8",
		"self_draw": true,
		"description": "清一色（万）自摸，赢家每家收24分"
	})
	
	test_cases.append({
		"name": "09_清一色_点炮",
		"concealed": ["tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tiao7", "tiao8", "tiao9", "tiao9", "tiao9", "tiao7", "tiao7", "tiao7"],
		"melds": [],
		"win_tile": "tiao7",
		"self_draw": false,
		"discard_seat": 1,
		"description": "清一色（条）点炮，放炮者支付24分"
	})
	
	test_cases.append({
		"name": "10_清大对_自摸",
		"concealed": ["tong1", "tong1", "tong2", "tong2", "tong2", "tong3", "tong3", "tong3", "tong4", "tong4", "tong4", "tong5", "tong5", "tong5"],
		"melds": [],
		"win_tile": "tong1",
		"self_draw": true,
		"description": "清大对（筒）自摸，赢家每家收34分"
	})
	
	test_cases.append({
		"name": "11_清大对_点炮",
		"concealed": ["wan1", "wan1", "wan2", "wan2", "wan2", "wan3", "wan3", "wan3", "wan4", "wan4", "wan4", "wan5", "wan5", "wan5"],
		"melds": [],
		"win_tile": "wan1",
		"self_draw": false,
		"discard_seat": 2,
		"description": "清大对（万）点炮，放炮者支付34分"
	})
	
	test_cases.append({
		"name": "12_清大对单吊_自摸",
		"concealed": ["tiao1", "tiao1", "tiao2", "tiao2", "tiao2", "tiao3", "tiao3", "tiao3", "tiao4", "tiao4", "tiao4", "tiao5", "tiao5", "tiao5"],
		"melds": [],
		"win_tile": "tiao1",
		"self_draw": true,
		"description": "清大对单吊（条）自摸，赢家每家收44分"
	})
	
	test_cases.append({
		"name": "13_清七对_自摸",
		"concealed": ["wan1", "wan1", "wan2", "wan2", "wan3", "wan3", "wan4", "wan4", "wan5", "wan5", "wan6", "wan6", "wan7", "wan7"],
		"melds": [],
		"win_tile": "wan7",
		"self_draw": true,
		"description": "清七对（万）自摸，赢家每家收44分"
	})
	
	test_cases.append({
		"name": "14_清七对_点炮",
		"concealed": ["tong1", "tong1", "tong2", "tong2", "tong3", "tong3", "tong4", "tong4", "tong5", "tong5", "tong6", "tong6", "tong7", "tong7"],
		"melds": [],
		"win_tile": "tong7",
		"self_draw": false,
		"discard_seat": 3,
		"description": "清七对（筒）点炮，放炮者支付44分"
	})
	
	test_cases.append({
		"name": "15_清单吊_自摸",
		"concealed": ["wan1", "wan1", "wan1", "wan2", "wan2", "wan2", "wan3", "wan3", "wan3", "wan4", "wan4", "wan4", "wan5", "wan5"],
		"melds": [],
		"win_tile": "wan5",
		"self_draw": true,
		"description": "清单吊（万）自摸，赢家每家收54分"
	})
	
	test_cases.append({
		"name": "16_清单吊_点炮",
		"concealed": ["tiao2", "tiao2", "tiao2", "tiao3", "tiao3", "tiao3", "tiao4", "tiao4", "tiao4", "tiao5", "tiao5", "tiao5", "tiao6", "tiao6"],
		"melds": [],
		"win_tile": "tiao6",
		"self_draw": false,
		"discard_seat": 1,
		"description": "清单吊（条）点炮，放炮者支付54分"
	})
	
	test_cases.append({
		"name": "17_清龙对_自摸",
		"concealed": ["tong1", "tong1", "tong1", "tong1", "tong2", "tong2", "tong3", "tong3", "tong4", "tong4", "tong5", "tong5", "tong6", "tong6"],
		"melds": [],
		"win_tile": "tong6",
		"self_draw": true,
		"description": "清龙对（筒，四张筒1）自摸，赢家每家收64分"
	})
	
	test_cases.append({
		"name": "18_清龙对_点炮",
		"concealed": ["wan2", "wan2", "wan2", "wan2", "wan3", "wan3", "wan4", "wan4", "wan5", "wan5", "wan6", "wan6", "wan7", "wan7"],
		"melds": [],
		"win_tile": "wan7",
		"self_draw": false,
		"discard_seat": 2,
		"description": "清龙对（万，四张万2）点炮，放炮者支付64分"
	})
	
	test_cases.append({
		"name": "19_报听胡牌_自摸",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9", "tiao1", "tiao2", "tiao3", "tong1", "tong1"],
		"melds": [],
		"win_tile": "tong1",
		"self_draw": true,
		"ready": true,
		"description": "报听后自摸，赢家每家收24分（含自摸基础4分）"
	})
	
	test_cases.append({
		"name": "20_报听胡牌_点炮",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tong1", "tong1"],
		"melds": [],
		"win_tile": "tong1",
		"self_draw": false,
		"discard_seat": 3,
		"ready": true,
		"description": "报听后点炮，放炮者支付24分"
	})
	
	test_cases.append({
		"name": "21_干扣_自摸",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tiao7", "tong2", "tong2"],
		"melds": [],
		"win_tile": "tong2",
		"self_draw": true,
		"no_chicken": true,
		"description": "干扣自摸（无鸡牌），赢家每家收14分"
	})
	
	test_cases.append({
		"name": "22_大干扣_自摸",
		"concealed": ["wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tiao7", "tong2", "tong2"],
		"melds": [],
		"win_tile": "tong2",
		"self_draw": true,
		"all_no_chicken": true,
		"description": "大干扣自摸（四家均无鸡牌），赢家每家收24分"
	})
	
	test_cases.append({
		"name": "23_杠开_自摸",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong1", "tong1"],
		"melds": [{"kind": "kong", "tile": "tiao1", "concealed": true}],
		"win_tile": "tong1",
		"self_draw": true,
		"kong_draw": true,
		"description": "杠开自摸（杠后摸牌胡），每家额外+5分"
	})
	
	test_cases.append({
		"name": "24_海底捞_自摸",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tong1", "tong1"],
		"melds": [],
		"win_tile": "tong1",
		"self_draw": true,
		"last_four": true,
		"description": "海底捞自摸（最后四张牌），每家额外+5分"
	})
	
	test_cases.append({
		"name": "25_抢杠胡",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tong1", "tong1"],
		"melds": [],
		"win_tile": "tong1",
		"self_draw": false,
		"robbed_kong": true,
		"discard_seat": 1,
		"description": "抢杠胡，被抢杠者支付12分基础分"
	})
	
	test_cases.append({
		"name": "26_杀报",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tong1", "tong1"],
		"melds": [],
		"win_tile": "tong1",
		"self_draw": false,
		"discard_seat": 2,
		"ready": true,
		"discarder_ready": true,
		"description": "报听者打出被胡（杀报），额外承担24分"
	})
	
	test_cases.append({
		"name": "27_普通胡_自摸",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tong1", "tong1"],
		"melds": [],
		"win_tile": "tong1",
		"self_draw": true,
		"description": "普通胡牌自摸，基础分4分"
	})
	
	test_cases.append({
		"name": "28_普通胡_点炮",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tong1", "tong1"],
		"melds": [],
		"win_tile": "tong1",
		"self_draw": false,
		"discard_seat": 1,
		"description": "普通胡牌点炮，无基础分，只比较鸡分"
	})
	
	test_cases.append({
		"name": "29_暗杠后点炮_未叫牌",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tong1", "tong1"],
		"melds": [],
		"win_tile": "tong1",
		"self_draw": false,
		"discard_seat": 3,
		"kong_discard": true,
		"discarder_called": false,
		"description": "暗杠后放炮（未叫牌），放炮者支付21分基础分"
	})
	
	test_cases.append({
		"name": "30_加杠后点炮_已叫牌",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao1", "tiao2", "tiao3", "tiao4", "tiao5", "tiao6", "tong1", "tong1"],
		"melds": [],
		"win_tile": "tong1",
		"self_draw": false,
		"discard_seat": 2,
		"kong_discard": true,
		"discarder_called": true,
		"description": "加杠后放炮（已叫牌），放炮者支付17分基础分"
	})
	
	test_cases.append({
		"name": "31_有碰杠_自摸",
		"concealed": ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tong1", "tong1"],
		"melds": [
			{"kind": "pung", "tile": "tiao1"},
			{"kind": "kong", "tile": "tiao2", "concealed": false}
		],
		"win_tile": "tong1",
		"self_draw": true,
		"description": "带碰和杠的普通胡牌自摸"
	})
	
	test_cases.append({
		"name": "32_清大对单吊_杠开",
		"concealed": ["wan1", "wan1", "wan2", "wan2", "wan2", "wan3", "wan3", "wan3", "wan4", "wan4", "wan4", "wan5", "wan5", "wan5"],
		"melds": [],
		"win_tile": "wan1",
		"self_draw": true,
		"kong_draw": true,
		"description": "清大对单吊+杠开，每家收44+5=49分"
	})
	
	test_cases.append({
		"name": "33_清龙对_海底捞",
		"concealed": ["tong1", "tong1", "tong1", "tong1", "tong2", "tong2", "tong3", "tong3", "tong4", "tong4", "tong5", "tong5", "tong6", "tong6"],
		"melds": [],
		"win_tile": "tong6",
		"self_draw": true,
		"last_four": true,
		"description": "清龙对+海底捞，每家收64+5=69分"
	})

func _create_test_round(test_case: Dictionary) -> RoundState:
	var round := RoundState.new()
	
	for i in 4:
		var player := PlayerState.new()
		player.seat = i
		player.concealed = []
		player.melds = []
		player.discards = []
		player.discard_count = 0
		player.ready = false
		round.players.append(player)
	
	var winner := 0
	round.players[winner].concealed = test_case.concealed.duplicate()
	round.players[winner].melds = test_case.get("melds", []).duplicate(true)
	round.players[winner].ready = test_case.get("ready", false)
	
	if not test_case.get("self_draw", true):
		var discard_seat: int = test_case.get("discard_seat", 1)
		if test_case.get("discarder_ready", false):
			round.players[discard_seat].ready = true
		if test_case.get("discarder_called", false):
			round.players[discard_seat].concealed = ["wan1", "wan2", "wan3"]
	
	round.round_meta = {
		"winner": winner,
		"winners": [winner],
		"dealer_seat": 0,
		"self_draw": test_case.get("self_draw", true),
		"win_tile": test_case.get("win_tile", ""),
		"robbed_kong": test_case.get("robbed_kong", false),
		"flip_tile": "",
		"chicken_multiplier": 1
	}
	
	if not test_case.get("self_draw", true):
		round.round_meta["discard_seat"] = test_case.get("discard_seat", 1)
	
	if test_case.get("kong_draw", false):
		round.round_meta["kong_draw_seat"] = winner
	
	if test_case.get("last_four", false):
		round.round_meta["last_four_self_draw_seat"] = winner
	
	if test_case.get("kong_discard", false):
		round.last_discard = {
			"after_kong": true,
			"seat": test_case.get("discard_seat", 1),
			"tile": test_case.get("win_tile", "")
		}
	
	return round

func _generate_description(test_case: Dictionary, result: Dictionary) -> void:
	var filename: String = test_case.name + ".txt"
	var filepath: String = output_dir + filename
	
	var content := ""
	content += "=".repeat(60) + "\n"
	content += "测试案例：%s\n" % test_case.name
	content += "=".repeat(60) + "\n\n"
	
	content += "【基本信息】\n"
	content += "牌型说明：%s\n\n" % test_case.description
	
	content += "【手牌】\n"
	content += "暗牌：%s\n" % str(test_case.concealed)
	if test_case.has("melds") and not test_case.melds.is_empty():
		content += "明牌："
		for meld in test_case.melds:
			var kind_name := "碰" if meld.kind == "pung" else "杠"
			content += "%s(%s) " % [kind_name, meld.tile]
		content += "\n"
	content += "胡牌：%s\n\n" % test_case.get("win_tile", "")
	
	content += "【胡牌方式】\n"
	if test_case.get("self_draw", true):
		content += "方式：自摸\n"
	else:
		var discard_seat: int = test_case.get("discard_seat", -1)
		var seat_names := ["庄家", "下家", "对家", "上家"]
		content += "方式：点炮\n"
		content += "放炮者：%s（座位%d）\n" % [seat_names[discard_seat], discard_seat]
	
	var special_flags := []
	if test_case.get("ready", false):
		special_flags.append("报听")
	if test_case.get("kong_draw", false):
		special_flags.append("杠开")
	if test_case.get("last_four", false):
		special_flags.append("海底捞")
	if test_case.get("robbed_kong", false):
		special_flags.append("抢杠胡")
	if test_case.get("discarder_ready", false):
		special_flags.append("杀报")
	if test_case.get("kong_discard", false):
		var called: bool = test_case.get("discarder_called", false)
		special_flags.append("杠后放炮（%s）" % ("叫牌" if called else "未叫牌"))
	if test_case.get("no_chicken", false):
		special_flags.append("干扣")
	if test_case.get("all_no_chicken", false):
		special_flags.append("大干扣")
	
	if not special_flags.is_empty():
		content += "特殊标记：%s\n" % ", ".join(special_flags)
	content += "\n"
	
	content += "【结算结果】\n"
	if result.has("lines"):
		for line in result.lines:
			content += "%s\n" % line
	content += "\n"
	
	content += "【分数变动】\n"
	var deltas: Array = result.get("deltas", [0.0, 0.0, 0.0, 0.0])
	var seat_names := ["庄家", "下家", "对家", "上家"]
	for i in 4:
		var sign := "+" if deltas[i] >= 0 else ""
		content += "%s：%s%.0f\n" % [seat_names[i], sign, deltas[i]]
	content += "\n"
	
	if result.has("transfers") and not result.transfers.is_empty():
		content += "【详细流水】\n"
		for transfer in result.transfers:
			var from: int = transfer.get("from", -1)
			var to: int = transfer.get("to", -1)
			var amount: float = transfer.get("amount", 0.0)
			var reason: String = transfer.get("reason", "")
			content += "%s → %s：%.0f（%s）\n" % [seat_names[from], seat_names[to], amount, reason]
		content += "\n"
	
	content += "=".repeat(60) + "\n"
	
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		print("已生成说明文档：%s" % filepath)
	else:
		push_error("无法创建文件：%s" % filepath)
