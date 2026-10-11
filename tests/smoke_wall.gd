extends SceneTree
## 冒烟测试：牌组108张、牌墙环布局、破墙、起手发牌（庄14 他家13）
## 运行： godot --headless --script res://tests/smoke_wall.gd

const H := preload("res://tests/test_harness.gd")

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	print("[smoke_wall] 开始")

	# 1) 牌组
	var deck := TileSetFactory.create_deck()
	t.expect(deck.size() == 108, "牌数应为108, 实际 %d" % deck.size())
	t.expect(_count_tile(deck, "wan1") == 4, "wan1应为4张")
	t.expect(_count_tile(deck, "tiao1") == 4, "tiao1应为4张")
	t.expect(_count_tile(deck, "tong8") == 4, "tong8应为4张")
	print("[ok] 牌组 108 张, 每值4张; 一条=%d 八筒=%d" % [_count_tile(deck, "tiao1"), _count_tile(deck, "tong8")])

	# 2) 洗牌+环布局
	var built := WallBuilder.setup(rng)
	var ring: Array = built["ring"]
	var wall := WallRing.new(ring)
	t.expect(ring.size() == 108, "环布局应为108张, 实际 %d" % ring.size())
	print("[ok] 环布局 ring=%d seg=%s" % [ring.size(), str(wall.SEG.keys())])

	# 3) 各骰子破墙点应在段内且>=0
	for d in [1, 2, 3, 4, 5, 6]:
		var b := WallRing.compute_break(d)
		var ok := b >= 0 and b < 108
		print("  die=%d -> break=%d ok=%s" % [d, b, ok])
		t.expect(ok, "骰子%d 破墙点越界: %d" % [d, b])

	run_deal_simulation(wall, 4)

	quit(t.finish("smoke_wall"))

func run_deal_simulation(wall: WallRing, die: int) -> void:
	wall.set_head(WallRing.compute_break(die))
	# 起手：庄->下家->对家->上家, 每轮4张, 3轮=12张
	var hands := {0: [], 1: [], 2: [], 3: []}
	var seats := [0, 1, 2, 3]
	for _round in 3:
		for seat in seats:
			for _j in 4:
				var tile := wall.draw_head()
				t.expect(tile != "", "发牌不应为空")
				hands[seat].append(tile)
	# 每人再摸1张 -> 13
	for seat in seats:
		hands[seat].append(wall.draw_head())
	t.expect(hands[0].size() == 13 and hands[1].size() == 13 and hands[2].size() == 13 and hands[3].size() == 13,
		"起手应各13张, 实际 %s" % str([hands[0].size(), hands[1].size(), hands[2].size(), hands[3].size()]))
	# 庄家首回合"摸一张打一张"：摸到第14张
	hands[0].append(wall.draw_head())
	t.expect(hands[0].size() == 14, "庄家首回合应摸成14张, 实际 %d" % hands[0].size())
	print("[ok] 起手: 庄=%d 下家=%d 对家=%d 上家=%d (庄首回合摸成14) 剩余=%d" % [hands[0].size(), hands[1].size(), hands[2].size(), hands[3].size(), wall.remaining])

	# 尾补杠测试：从牌尾摸一张
	var tail := wall.draw_tail()
	t.expect(tail != "", "尾补杠应有牌")
	print("[ok] 尾补杠摸到 [%s], 剩余=%d" % [tail, wall.remaining])

func _count_tile(arr: Array, tile: String) -> int:
	var n := 0
	for item in arr:
		if item == tile:
			n += 1
	return n
