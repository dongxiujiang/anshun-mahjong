class_name WallBuilder
## 把一副洗好的 108 张牌布局成牌墙环（与 WallRing.SEG 边界一致）。
## 分段砖数：对家28(seg0) 下家26(seg1) 庄家28(seg2) 上家26(seg3)。

static func build_ring(shuffled_deck: Array) -> Dictionary:
	var ring: Array = []
	var seg_counts: Array = [28, 26, 28, 26]
	var idx := 0
	for seg in 4:
		var n: int = seg_counts[seg]
		var slice: Array = []
		for _i in n:
			slice.append(shuffled_deck[idx])
			idx += 1
		ring.append_array(slice)
	return {
		"ring": ring,
		"seg_counts": seg_counts,
	}

## 直接一步：create_deck -> shuffle -> build_ring，返回 {deck, ring}
static func setup(rng: RandomNumberGenerator) -> Dictionary:
	var deck := TileSetFactory.create_deck()
	deck = TileSetFactory.shuffle(deck, rng)
	var built := build_ring(deck)
	built["deck"] = deck
	return built