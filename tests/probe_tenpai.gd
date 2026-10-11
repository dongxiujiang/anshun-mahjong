extends SceneTree
## 统计：随机14张手牌中，"打掉一张后即听牌"的比例（用于判断首手报听的天然概率）。

func _initialize() -> void:
	_run()
	quit(0)

func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var n := 3000
	var hit := 0
	for _i in n:
		var deck := TileSetFactory.create_deck()
		deck = TileSetFactory.shuffle(deck, rng)
		var hand: Array = []
		for k in 14:
			hand.append(deck[k])
		# 是否存在一张，打掉后 13 张听牌
		var ok := false
		for t in hand.duplicate():
			var h2: Array = hand.duplicate()
			h2.erase(t)
			if RuleEngine.is_tenpai(h2, []):
				ok = true
				break
		if ok: hit += 1
	print("随机14张中「打1张即听牌」的比例: %d/%d = %.2f%%" % [hit, n, 100.0 * hit / n])