extends RefCounted

## 选庄与牌谱核验共用的候选。抽签只在真实权威结算执行一次。
static func candidates(scored: Dictionary, current: int) -> Array[int]:
	if scored.all_called_draw:
		return [current]
	var win: bool = not scored.winners.is_empty()
	var eligible: Array[int] = []
	for seat in 4:
		if (win and not scored.winners.has(seat)) or (not win and scored.called[seat]):
			continue
		if not eligible.is_empty():
			var difference: float = scored.deltas[seat] - scored.deltas[eligible[0]]
			if difference != 0.0:
				if (difference > 0.0) != win:
					continue
				eligible.clear()
		eligible.append(seat)
	return eligible
