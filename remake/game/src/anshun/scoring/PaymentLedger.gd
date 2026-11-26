extends RefCounted

var _burned_seat: int
var _transfers: Array = []
var items: Array = [[], [], [], []]

func _init(burned_seat: int) -> void:
	_burned_seat = burned_seat

func register(item: Dictionary, opponents: Array) -> void:
	if not opponents.is_empty():
		var row := item.duplicate()
		row["opponents"] = opponents.duplicate()
		items[item.owner].append(row)

## 入账时保留单倍项目。credit 与 offset 分别是这对玩家结算中的加项和抵扣。
func transfer(payer: int, receiver: int, reason: String, credit: Array, offset: Array = []) -> void:
	if payer == receiver or receiver == _burned_seat:
		return
	var sources: Array = []
	var total := 0.0
	for item in credit:
		var source: Dictionary = item.duplicate()
		source["contribution"] = absf(item.amount)
		total += source.contribution
		sources.append(source)
	for item in offset:
		var source: Dictionary = item.duplicate()
		source["contribution"] = -absf(item.amount)
		total += source.contribution
		sources.append(source)
	if total > 0.0:
		_transfers.append({"from": payer, "to": receiver, "reason": reason, "unit_amount": total, "sources": sources})

func award(payers: Array, receiver: int, amount: float, label: String, kind: String, details: Dictionary = {}) -> void:
	if amount <= 0.0 or payers.is_empty() or receiver == _burned_seat:
		return
	var item := _fee(receiver, amount, label, kind, details)
	register(item, payers)
	for payer in payers:
		transfer(payer, receiver, label, [item])

func charge(payer: int, recipients: Array, amount: float, label: String, kind: String, details: Dictionary = {}) -> void:
	var payees := recipients.filter(func(seat): return seat != _burned_seat)
	if amount <= 0.0 or payees.is_empty():
		return
	var item := _fee(payer, -amount, label, kind, details)
	register(item, payees)
	for receiver in payees:
		transfer(payer, receiver, label, [item])

func _fee(owner: int, amount: float, label: String, kind: String, details: Dictionary) -> Dictionary:
	var item := {"owner": owner, "amount": amount, "label": label, "kind": kind, "tiles": [], "tile_ids": []}
	item.merge(details, true)
	return item

func result(multiplier: int) -> Dictionary:
	var transfers: Array = []
	var deltas := [0.0, 0.0, 0.0, 0.0]
	for row in _transfers:
		var transfer_row: Dictionary = row.duplicate()
		var amount: float = row.unit_amount * multiplier
		transfer_row["amount"] = amount
		deltas[row.from] -= amount
		deltas[row.to] += amount
		transfers.append(transfer_row)
	return {"transfers": transfers, "pairwise": pairwise_payments(transfers), "deltas": deltas, "items": items, "multiplier": multiplier}

static func pairwise_payments(transfers: Array) -> Array:
	var matrix := [[0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0]]
	for entry in transfers:
		matrix[entry.to][entry.from] += entry.amount
		matrix[entry.from][entry.to] -= entry.amount
	return matrix
