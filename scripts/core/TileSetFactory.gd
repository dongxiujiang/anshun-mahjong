class_name TileSetFactory
## 生成一整副 108 张麻将：wan/tiao/tong × 1-9 × 4 张，返回 Array[String]。

static func create_deck() -> Array:
	var deck: Array = []
	for s in Tiles.SUITS:
		for r in Tiles.RANKS:
			# 4 张同值
			for _i in 4:
				deck.append(Tiles.val(s, r))
	return deck

## 洗牌（费雪-耶茨），RandomNumberGenerator 传入便于测试复现
static func shuffle(deck: Array, rng: RandomNumberGenerator) -> Array:
	var a := deck.duplicate()
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a