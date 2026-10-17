extends RefCounted
## 付款流水是唯一账本；净变化和玩家间矩阵都从同一流水产生。
const CFG := preload("res://scripts/autoload/GameConfig.gd")

static func transfer(deltas: Array, transfers: Array, payer: int, receiver: int, amount: float, reason: String) -> void:
	if payer not in range(4) or receiver not in range(4) or payer == receiver or amount <= 0:
		return
	deltas[payer] -= amount
	deltas[receiver] += amount
	transfers.append({"from": payer, "to": receiver, "amount": amount, "reason": reason})

static func pay_win(deltas: Array, transfers: Array, winner: int, meta: Dictionary, amount: float, reason: String) -> void:
	if meta.get("self_draw", false):
		for seat in 4:
			if seat != winner:
				transfer(deltas, transfers, seat, winner, amount, reason)
	else:
		transfer(deltas, transfers, int(meta.get("discard_seat", -1)), winner, amount, reason)

static func pay_uncalled(deltas: Array, transfers: Array, called: Array, discard_points: Array, add_huang_fee: bool = false) -> void:
	# 荒牌时每个未叫者还要向每个叫牌者补 4 分基础分。
	for payer in 4:
		if called[payer]:
			continue
		for receiver in 4:
			if called[receiver]:
				var amount := float(discard_points[payer]) + float(discard_points[receiver])
				if add_huang_fee:
					amount += CFG.SCORE_SELF_DRAW
				transfer(deltas, transfers, payer, receiver, amount, "荒牌包鸡")

static func pairwise_payments(transfers: Array) -> Array:
	var matrix: Array = [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
	for transfer in transfers:
		var payer := int(transfer.get("from", -1))
		var receiver := int(transfer.get("to", -1))
		if payer not in range(4) or receiver not in range(4) or payer == receiver:
			continue
		var amount := float(transfer.get("amount", 0.0))
		matrix[receiver][payer] += amount
		matrix[payer][receiver] -= amount
	return matrix

static func relative_payments(matrix: Array, seat: int) -> Array:
	var out: Array = []
	for offset in [3, 2, 1]:
		out.append(matrix[seat][posmod(seat + offset, 4)])
	return out

static func compare_chickens(deltas: Array, transfers: Array, called: Array, points: Array) -> void:
	# 胡牌局：叫牌者按完整鸡分，未叫牌者以出牌鸡负分参与。
	# 包括手中、碰杠、保留出牌鸡和翻鸡；杠基础分及胡牌费用另按付款人收取。
	for first in 4:
		for second in range(first + 1, 4):
			# 两名未叫牌玩家之间不互相结算；未叫牌只向叫牌玩家
			# 补付自己的出牌鸡和对方应得的鸡分差。
			if not called[first] and not called[second]:
				continue
			var first_points: float = float(points[first])
			var second_points: float = float(points[second])
			var difference: float = first_points - second_points
			if difference > 0: transfer(deltas, transfers, second, first, difference, "鸡分差额")
			elif difference < 0: transfer(deltas, transfers, first, second, -difference, "鸡分差额")
