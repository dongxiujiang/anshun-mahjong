extends RefCounted
## 杠的基础付款人与杠内鸡分分别计算，明杠基础费只针对来源玩家。
const CFG := preload("res://scripts/autoload/GameConfig.gd")
const PAY := preload("res://scripts/core/PaymentLedger.gd")

static func pay(round, deltas: Array, transfers: Array, called: Array, items: Array, flip: String, is_draw: bool) -> void:
	var related: Array = Tiles.flip_related(flip)
	for receiver in 4:
		if not called[receiver] or receiver == int(round.round_meta.get("burn_chicken_seat", -1)):
			continue
		for meld in round.players[receiver].melds:
			if meld.get("robbed", false) or meld.kind not in ["kong", "add_kong"]:
				continue
			var tile := str(meld.get("tile", ""))
			var source := int(meld.get("from_seat", -1))
			var own_kong: bool = meld.kind == "add_kong" or meld.get("concealed", false)
			var kind_name: String = "加杠" if meld.kind == "add_kong" else ("暗杠" if meld.get("concealed", false) else "明杠")
			var payers: Array = []
			for payer in 4:
				if payer == receiver or (is_draw and called[payer]):
					continue
				if own_kong or payer == source:
					payers.append(payer)
			var chicken_value := 0.0
			var flip_value := 0.0
			if receiver != round.round_meta.get("burn_chicken_seat", -1):
				if Tiles.is_chicken(tile):
					# 冲锋鸡被杠后按普通鸡每张2分计，明杠放牌者另付杠分4。
					chicken_value = CFG.SCORE_CALL_CHICKEN * 4.0
					if not is_draw:
						chicken_value *= CFG.SCORE_FLIP_DOUBLE if tile in related else 1.0
				elif not is_draw and tile in related:
					flip_value = CFG.SCORE_FLIP_CHICKEN * 4.0
			for payer in payers:
				PAY.transfer(deltas, transfers, payer, receiver, CFG.SCORE_DRAW_KONG, ("查叫" if is_draw else "") + kind_name)
			var chicken_payers: Array = []
			for payer in 4:
				# 胡牌局杠内鸡已纳入完整鸡分两两比较；只在流局查叫时单独补付。
				if is_draw and payer != receiver and not called[payer] and chicken_value > 0:
					PAY.transfer(deltas, transfers, payer, receiver, chicken_value, "杠中鸡")
					chicken_payers.append(payer)
			if is_draw and payers.is_empty() and chicken_payers.is_empty():
				continue
			var tiles: Array = []
			for _index in 4:
				tiles.append(tile)
			var base: float = CFG.SCORE_DRAW_KONG if not payers.is_empty() else 0.0
			var own_amount := chicken_value + flip_value + (base if own_kong else 0.0)
			items[receiver].append({"kind": "kong", "label": kind_name, "tile": tile, "tiles": tiles,
				"amount": base + chicken_value + flip_value, "base_amount": base,
				"chicken_amount": chicken_value, "flip_amount": flip_value, "own_amount": own_amount,
				"kong_kind": RoundState.KongKind.ADD_KONG if meld.kind == "add_kong" else (RoundState.KongKind.CONCEALED if own_kong else RoundState.KongKind.EXPOSED),
				"from_seat": source, "owner": receiver, "payers": payers, "chicken_payers": chicken_payers, "draw": is_draw, "note": ""})
	# 未叫牌杠家的杠组不计正分：个人分只扣一次“杠基础 + 杠中鸡”，
	# 再按流水向每位叫牌者逐家补付杠中鸡。
	for owner in 4:
		if called[owner] or owner == int(round.round_meta.get("burn_chicken_seat", -1)):
			continue
		for meld in round.players[owner].melds:
			if meld.get("robbed", false) or meld.kind not in ["kong", "add_kong"]:
				continue
			var tile := str(meld.get("tile", ""))
			var chicken_value := 0.0
			var flip_value := 0.0
			if Tiles.is_chicken(tile):
				chicken_value = CFG.SCORE_CALL_CHICKEN * 4.0
				if not is_draw and tile in related:
					chicken_value *= CFG.SCORE_FLIP_DOUBLE
			elif not is_draw and tile in related:
				flip_value = CFG.SCORE_FLIP_CHICKEN * 4.0
			var base_value: float = CFG.SCORE_DRAW_KONG
			var own_amount := -(base_value + chicken_value + flip_value)
			items[owner].append({"kind": "kong", "label": ("加杠" if meld.kind == "add_kong" else ("暗杠" if meld.get("concealed", false) else "明杠")),
				"tile": tile, "tiles": [tile, tile, tile, tile], "amount": -own_amount,
				"base_amount": base_value, "chicken_amount": chicken_value, "flip_amount": flip_value,
				"own_amount": own_amount, "kong_kind": RoundState.KongKind.ADD_KONG if meld.kind == "add_kong" else (RoundState.KongKind.CONCEALED if meld.get("concealed", false) else RoundState.KongKind.EXPOSED),
				"from_seat": int(meld.get("from_seat", -1)), "payers": [], "chicken_payers": [],
				"draw": is_draw, "note": "未叫牌杠主只计一次负分"})
			if chicken_value > 0.0:
				for receiver in 4:
					if called[receiver] and receiver != int(round.round_meta.get("burn_chicken_seat", -1)):
						PAY.transfer(deltas, transfers, owner, receiver, chicken_value, "未叫牌杠中鸡")
