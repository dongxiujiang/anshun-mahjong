extends RefCounted
## 付款流水是唯一账本；净变化和玩家间矩阵都从同一流水产生。

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

static func pay_uncalled(deltas: Array, transfers: Array, called: Array, discard_points: Array) -> void:
	for payer in 4:
		if called[payer]:
			continue
		for receiver in 4:
			if called[receiver]:
				transfer(deltas, transfers, payer, receiver, discard_points[receiver], "未叫牌补打出鸡")

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
	for first in 4:
		for second in range(first + 1, 4):
			if not called[first] or not called[second]: continue
			var difference: float = points[first] - points[second]
			if difference > 0: transfer(deltas, transfers, second, first, difference, "鸡分差额")
			elif difference < 0: transfer(deltas, transfers, first, second, -difference, "鸡分差额")
