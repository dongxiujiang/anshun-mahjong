class_name WallBuilder
## 把洗好的 108 张牌一次分配到庄家视角的四段牌墙。

static func build_ring(shuffled_deck: Array, dealer_seat: int = 0, dealer_layout: bool = true) -> Dictionary:
	var ring: Array = []
	var seg_counts: Array = []
	var segments: Array = []
	for segment in WallRing.segments_for_dealer(dealer_seat, dealer_layout).values():
		seg_counts.append(segment.len)
		segments.append(segment)
	var idx := 0
	for seg in 4:
		var n: int = seg_counts[seg]
		var slice: Array = []
		for _i in n:
			slice.append(shuffled_deck[idx])
			idx += 1
		if int(segments[seg].seat) in [1, 2]:
			var reversed: Array = []
			for col in range(n / 2 - 1, -1, -1):
				reversed.append(slice[col * 2])
				reversed.append(slice[col * 2 + 1])
			slice = reversed
		ring.append_array(slice)
	return {
		"ring": ring,
		"seg_counts": seg_counts,
	}

## 直接一步：create_deck -> shuffle -> build_ring，返回 {deck, ring}
static func setup(rng: RandomNumberGenerator, dealer_seat: int = 0, dealer_layout: bool = true) -> Dictionary:
	var deck := TileSetFactory.create_deck()
	deck = TileSetFactory.shuffle(deck, rng)
	var built := build_ring(deck, dealer_seat, dealer_layout)
	built["deck"] = deck
	return built
