extends SceneTree
## 冒烟测试：RuleEngine 判胡/番型/听牌、Shanten 向听数
## 运行： godot --headless --script res://tests/smoke_logic.gd

const H := preload("res://tests/test_harness.gd")

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[smoke_logic] 开始")
	var melds: Array = []

	# 1) 平胡 win
	var ping := ["wan1","wan2","wan3","wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","wan5","wan5"]
	t.expect(_win(ping, melds), "平胡应胡")
	var p := RuleEngine.analyze(ping, melds)
	t.expect(p.normal and not p.seven_pairs and not p.all_triplets, "平胡番型判定错误")  # 该手全万=清一色,flush为真
	print("[ok] 平胡识别: normal=%s sp=%s trips=%s flush=%s" % [p.normal, p.seven_pairs, p.all_triplets, p.flush])

	# 2) 小七对 win
	var sp := ["wan1","wan1","wan2","wan2","wan3","wan3","tiao4","tiao4","tiao5","tiao5","tong6","tong6","tong7","tong7"]
	t.expect(_win(sp, melds), "小七对应胡")
	var p2 := RuleEngine.analyze(sp, melds)
	t.expect(p2.seven_pairs, "小七对番型未识别")
	print("[ok] 小七对识别")

	# 3) 大队子（全刻）
	var dt := ["wan1","wan1","wan1","wan2","wan2","wan2","wan3","wan3","wan3","wan4","wan4","wan4","wan5","wan5"]
	t.expect(_win(dt, melds), "大队子应胡")
	var p3 := RuleEngine.analyze(dt, melds)
	t.expect(p3.all_triplets, "大队子番型未识别")
	print("[ok] 大队子识别")

	# 4) 清一色（平胡单门）
	var flush := ["wan1","wan2","wan3","wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","wan5","wan5"]
	var p4 := RuleEngine.analyze(flush, melds)
	t.expect(p4.flush and p4.normal, "清一色番型未识别")
	print("[ok] 清一色识别")

	# 5) 听牌：123 456 789 + 55 + 24万 -> 等 3万
	var tenpai := ["wan1","wan2","wan3","wan4","wan5","wan6","wan7","wan8","wan9","wan5","wan5","wan2","wan4"]
	t.expect(RuleEngine.is_tenpai(tenpai, melds), "应听牌")
	var waits := RuleEngine.waiting_tiles(tenpai, melds)
	t.expect("wan3" in waits, "应等wan3: " + str(waits))
	print("[ok] 听牌等待=%s" % str(waits))

	# 6) 向听数：该听牌手 -> 0
	t.expect(Shanten.shanten(tenpai, melds) == 0, "听牌手向听数应为0, 实际 %d" % Shanten.shanten(tenpai, melds))
	# 乱牌 -> 大
	var messy := ["wan1","wan1","wan2","wan3","tiao5","tiao6","tong8","tong8","wan9","tiao1","tiao3","tong2","tong4"]
	var s := Shanten.shanten(messy, melds)
	print("[ok] 乱牌向听数=%d (应>0)" % s)
	t.expect(s > 0, "乱牌向听数应大于0, 实际 %d" % s)

	quit(t.finish("smoke_logic"))

func _win(concealed: Array, melds: Array) -> bool:
	return RuleEngine.analyze(concealed, melds).win
