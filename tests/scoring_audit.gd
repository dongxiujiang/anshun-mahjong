extends SceneTree
## 新规则审计：以 3,472 个确定性组合验证结算不变式、牌型优先级和付款守恒。
const H := preload("res://tests/test_harness.gd")
const ORACLE := preload("res://tests/settlement_oracle.gd")
var t := H.new()
var cases := 0

const PLAIN := ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "tiao2", "tiao3", "tiao4", "tong2", "tong3", "tong4", "wan9", "wan9"]
const BIG := ["wan1","wan1","wan1","wan2","wan2","wan2","tong3","tong3","tong3","tiao4","tiao4","tiao4","wan9","wan9"]
const SEVEN := ["tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao4","tiao4","tiao5","tiao5","tiao6","tiao6","tiao9","tiao9"]
const DRAGON := ["tiao1","tiao1","tiao1","tiao1","tiao2","tiao2","tiao3","tiao3","tiao5","tiao5","tiao7","tiao7","tiao9","tiao9"]
const FLUSH := ["tiao1","tiao2","tiao3","tiao1","tiao2","tiao3","tiao4","tiao5","tiao6","tiao7","tiao8","tiao9","tiao5","tiao5"]
const CLEAN_BIG := ["tiao1","tiao1","tiao1","tiao2","tiao2","tiao2","tiao4","tiao4","tiao4","tiao6","tiao6","tiao6","tiao9","tiao9"]
const CLEAN_SINGLE := ["tiao1","tiao2","tiao3","tiao2","tiao3","tiao4","tiao4","tiao5","tiao6","tiao7","tiao8","tiao9","tiao9","tiao9"]
const WAIT := ["wan1","wan2","wan3","wan4","wan5","wan6","tiao2","tiao3","tiao4","tong1","tong2","tong3","wan9"]

func _initialize() -> void: call_deferred("_run")

func fixture() -> RoundState:
	var r := RoundState.new(); r.build_players(0); r.controllers = [null, null, null, null]; r.phase = RoundState.Phase.PLAYING; r.wall = WallRing.new(TileSetFactory.create_deck()); r.wall.set_head(0); return r

func check_result(r: RoundState, label: String) -> void:
	var first := ScoringEngine.settle(r)
	ORACLE.check(r, first, t, label)
	t.expect(ScoringEngine.settle(r) == first, "%s: 结算无副作用" % label)
	cases += 1

func _run() -> void:
	# 3,072 个胡牌组合覆盖10种牌型、四赢家、四来源、报听、流局倍率和出牌鸡。
	for winner in 4:
		for source in 4:
			for ready_mask in 16:
				for variant in 12:
					var r := fixture()
					var hands: Array = [PLAIN, BIG, SEVEN, DRAGON, FLUSH, CLEAN_BIG, BIG, CLEAN_SINGLE, SEVEN, DRAGON, CLEAN_SINGLE, PLAIN]
					var win_tiles: Array = ["wan9", "wan9", "tiao9", "tiao9", "tiao1", "tiao1", "wan9", "tiao9", "tiao9", "tiao9", "tiao9", "wan9"]
					var hand: Array = hands[variant]
					r.players[winner].concealed = hand.duplicate()
					for seat in 4:
						if seat != winner and bool(ready_mask & (1 << seat)):
							r.players[seat].concealed = WAIT.duplicate()
						r.players[seat].ready = bool(ready_mask & (1 << seat))
						if posmod(seat + variant, 3) == 0:
							r.players[seat].discards = ["tiao1"]
							r.players[seat].discard_ids = [0]
							r.round_meta.charge_chickens["tiao1"] = {"owner": seat, "location": "discard", "discard_id": 0}
					r.round_meta.chicken_multiplier = 2 if variant % 2 else 1
					r.round_meta.winner = winner
					r.round_meta.winners = [winner]
					r.round_meta.self_draw = source == winner
					r.round_meta.discard_seat = source if source != winner else -1
					r.round_meta.win_tile = str(win_tiles[variant])
					r.round_meta.flip_tile = "tiao1" if variant % 2 else "wan5"
					check_result(r, "win-%d-%d-%d-%d" % [winner, source, ready_mask, variant])
	# 荒牌跨叫/未叫组合，以及保留出牌鸡和三类杠付款人。
	for mask in 16:
		var r := fixture(); r.round_meta.winner = -1
		for seat in 4:
			r.players[seat].concealed = WAIT.duplicate() if bool(mask & (1 << seat)) else []
			if seat % 2 == 0:
				r.players[seat].discards = ["tiao1"]
				r.players[seat].discard_ids = [0]
				r.round_meta.charge_chickens["tiao1"] = {"owner": seat, "location": "discard", "discard_id": 0}
		check_result(r, "draw-%d" % mask)
	for kind in ["kong", "concealed", "add_kong"]:
		for source in 4:
			for mask in 16:
				for multiplier in [1, 2]:
					var r := fixture()
					r.players[0].concealed = WAIT.duplicate()
					r.players[0].melds = [{"kind": "add_kong" if kind == "add_kong" else "kong", "tile": "tiao1", "from_seat": source, "concealed": kind == "concealed"}]
					for seat in 4:
						if bool(mask & (1 << seat)): r.players[seat].concealed = WAIT.duplicate()
					r.round_meta.chicken_multiplier = multiplier
					r.round_meta.winner = -1 if mask % 2 == 0 else 0
					if r.round_meta.winner == 0:
						r.players[0].concealed.append("wan9")
						r.round_meta.self_draw = true
						r.round_meta.winners = [0]
					check_result(r, "kong-%s-%d-%d-x%d" % [kind, source, mask, multiplier])
	print("[scoring_audit] independently checked settlements: %d" % cases)
	print("[scoring_audit] 3,072 winner cases, 16 draw cases and 384 kong cases")
	quit(t.finish("scoring_audit"))
