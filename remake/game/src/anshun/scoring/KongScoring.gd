extends RefCounted

const CFG := preload("res://src/anshun/scoring/RulesConfig.gd")
const Rules := preload("res://src/anshun/scoring/KongRules.gd")
const Chicken := preload("res://src/anshun/scoring/ChickenScoring.gd")
const Ledger := preload("res://src/anshun/scoring/PaymentLedger.gd")

static func settle(ledger: Ledger, players: Array, called: Array, draw: bool) -> void:
	for owner in 4:
		for meld in players[owner].melds:
			if meld.kind not in ["kong", "add_kong"] or meld.get("robbed", false):
				continue
			var kind := Rules.kind(meld)
			var source := int(meld.get("from_seat", -1))
			var opponents: Array = []
			for seat in 4:
				if seat == owner or (kind == "exposed" and seat != source):
					continue
				if (called[owner] and (not draw or not called[seat])) or (not called[owner] and called[seat]):
					opponents.append(seat)
			var name: String = {"exposed": "明杠", "concealed": "暗杠", "add_kong": "加杠"}[kind]
			var tiles := [meld.tile, meld.tile, meld.tile, meld.tile]
			var details := {"kong_kind": kind, "from_seat": source, "tiles": tiles, "tile_ids": Chicken.meld_ids(meld, 4)}
			if called[owner]:
				ledger.award(opponents, owner, CFG.SCORE_DRAW_KONG, ("查叫" if draw else "") + name, "kong_base", details)
			else:
				ledger.charge(owner, opponents, CFG.SCORE_DRAW_KONG, "未叫牌杠分", "kong_base", details)
