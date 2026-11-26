extends SceneTree

const Round = preload("res://src/domain/Round.gd")
const Catalog = preload("res://src/domain/TileCatalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_exhaust_wall()
	_same_window()
	_three_winners()
	_ready_lock()
	_concealed_kong()
	_exposed_kong()
	_post_kong_discard()
	_pass_until_discard()
	_winning_chicken(false)
	_winning_chicken(true)
	_last_draw_win(52)
	_last_draw_win(55)
	_rob_kong(true)
	_rob_kong(false)
	print("Round: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func _tiles(spec: String) -> Array:
	var values := []
	for group in spec.split(" ", false):
		var suit: String = {"w": "wan", "t": "tiao", "b": "tong"}[group.left(1)]
		for rank in group.substr(1):
			values.append(suit + rank)
	return values

## 只安排牌墙，不改玩家或响应状态。用剩余真实牌填满空槽并经过正式发牌入口。
func _game(hands: Dictionary = {}, draws: String = "", tails: String = "", late_draws: Dictionary = {}):
	var fixed := {}
	var opening := 10 # 南庄红5：北墙第6列上，逻辑索引10。
	for seat in hands:
		var offset := posmod(1 - int(seat), 4)
		var values := _tiles(hands[seat])
		for i in values.size():
			var at := 48 + offset if i == 12 else (i / 4) * 16 + offset * 4 + i % 4
			fixed[(opening + at) % 108] = values[i]
	var nexts := _tiles(draws)
	for i in nexts.size():
		fixed[(opening + 52 + i) % 108] = nexts[i]
	for offset in late_draws:
		fixed[(opening + 52 + offset) % 108] = late_draws[offset]
	var ends := _tiles(tails)
	for i in ends.size():
		fixed[posmod(opening - 2 - 2 * (i / 2) + i % 2, 108)] = ends[i]
	var pool := Catalog.values(8427)
	for value in fixed.values():
		check(pool.has(value), "fixture has more than four " + value)
		pool.erase(value)
	var deck := []
	for id in 108:
		deck.append(fixed[id] if fixed.has(id) else pool.pop_back())
	var r = Round.new()
	check(r.start(1, 5, 2, deck), "valid complete deck must start")
	check(r.wall.remaining == 56 and r.players.all(func(p): return p.hand.size() == 13), "four hands of thirteen first")
	check(r.begin_dealer_turn() and r.turn == 1 and r.wall.remaining == 55, "separate dealer draw")
	return r

func _pass_all(r) -> void:
	if r.phase == "response":
		check(r.expire_responses(r.prompt_id), "resolve outstanding responses")

func _discard(r, id: int = -1, ready: bool = false) -> void:
	var opts: Dictionary = r.choices(r.turn)
	var selected := id
	if selected == -1:
		selected = r.players[r.turn].draw_id
		if selected < 0:
			selected = opts.discard_ids[0]
	check(r.submit(r.turn, r.prompt_id, "ready" if ready else "discard", selected), "legal discard at seat %s" % r.turn)

func _conserved(r) -> bool:
	var all: Array = r.wall.occupied_slots()
	for p in r.players:
		all.append_array(p.hand)
		all.append_array(p.discards)
		for meld in p.melds:
			all.append_array(meld.tile_ids)
	if r.phase == "settled" and not r.round_meta.self_draw and not r.round_meta.winners.is_empty():
		all.append(r.round_meta.win_tile_id)
	all.sort()
	return all == range(108)

func _exhaust_wall() -> void:
	var r = _game()
	var before: Array = r.players.duplicate(true)
	var version: int = r.prompt_id
	check(not r.submit(1, version - 1, "discard", r.players[1].draw_id), "reject stale prompt")
	check(not r.submit(0, version, "discard", r.players[1].draw_id), "reject wrong seat")
	check(not r.submit(1, version, "discard", -80), "reject foreign ID")
	check(before == r.players and r.prompt_id == version, "failed requests change nothing")
	for _step in 120:
		if r.phase == "settled":
			break
		_discard(r)
		_pass_all(r)
		check(_conserved(r), "conservation after draw or discard")
	check(r.phase == "settled" and r.wall.remaining == 0 and r.round_meta.flip_wall_index == -1, "empty wall draw has no flip")
	check(r.settlement_facts().round_meta.winner == -1, "draw projects no winner")

func _same_window() -> void:
	var r = _game({0: "w555", 3: "w1112344678999"}, "w5")
	var id: int = r.players[1].draw_id
	_discard(r, id)
	var window: int = r.prompt_id
	check(r.choices(0).actions.has("kong") and r.choices(3).actions.has("win"), "exposed kong and win in same window")
	check(r.submit(0, window, "kong") and r.phase == "response", "first response only records intent")
	check(not r.submit(0, window, "pass") and r.players[0].melds.is_empty(), "no editing or premature kong")
	var remaining: int = r.wall.remaining
	check(r.submit(3, window, "win"), "accept later win")
	_pass_all(r)
	check(r.round_meta.winners == [3] and r.players[0].melds.is_empty(), "hu outranks kong")
	check(r.wall.remaining == remaining and r.round_meta.flip_wall_index == r.wall.peek_head(), "flip and voided kong consume no tile")
	check(_conserved(r), "winning ID remains unique")

func _three_winners() -> void:
	var r = _game({0: "w1122334456677", 3: "t112233445566 w5", 2: "b112233445566 w5"}, "w5")
	var id: int = r.players[1].draw_id
	_discard(r, id)
	var window: int = r.prompt_id
	for seat in [2, 3, 0]:
		check(r.choices(seat).actions.has("win") and r.submit(seat, window, "win"), "all three winners can choose")
	check(r.round_meta.winners == [0, 3, 2], "winner order independent of arrival")
	for seat in r.round_meta.winners:
		var row: Dictionary = r.settlement_facts().players[seat]
		check(row.concealed_ids.back() == id and not r.players[seat].hand.has(id), "projection shares source, owns no duplicate")
	check(_conserved(r), "three winners reference one physical tile")

func _ready_lock() -> void:
	var r = _game({1: "w123456789 t45 b55"}, "b2 b123 w1 b456 t3 w234 t6")
	var seat := 1
	var declared: int = r.players[seat].draw_id
	check(r.choices(seat).ready_ids.has(declared), "first normal draw and thirteen in tenpai")
	_discard(r, declared, true)
	var fixed: Array = r.players[seat].ready_ids.duplicate()
	for cycle in 3:
		_pass_all(r)
		for _other in 3:
			_discard(r)
			_pass_all(r)
		check(r.phase == "ready_draw", "ready draw waits for animation")
		var drawn: int = r.players[seat].draw_id
		var old_id: int = fixed[0]
		check(not r.submit(seat, r.prompt_id, "discard", old_id), "old matching tile cannot be substituted")
		check(r.finish_draw_animation(seat, r.prompt_id), "ready animation finishes once")
		if cycle == 0:
			check(r.players[seat].discards.has(drawn) and r.players[seat].hand == fixed, "auto discard newly drawn duplicate")
		elif cycle == 1:
			check(r.choices(seat).actions == ["self_win", "pass"] and r.expire_responses(r.prompt_id), "self-win timeout equals pass")
			check(r.players[seat].pass_win and r.players[seat].hand == fixed, "declining self draw permanently restricts ron")
		else:
			check(r.submit(seat, r.prompt_id, "self_win"), "a later self draw on another wait still wins")
	check(r.round_meta.self_draw and _conserved(r), "ready self draw keeps thirteen and winning draw")

func _concealed_kong() -> void:
	var r = _game({1: "w9999"}, "t2", "b7")
	var id: int = r.choices(1).concealed_kong_ids[0]
	var tail: int = r.wall.tail_index
	check(r.submit(1, r.prompt_id, "concealed_kong", id), "concealed kong available after draw")
	check(r.players[1].draw_id == tail and r.choices(1).ready_ids.is_empty(), "kong draws tail and disqualifies ready")
	check(r.snapshot_for(1).players[1].melds[0].tile == "wan9" and not r.snapshot_for(0).players[1].melds[0].has("tile_ids"), "opponent cannot identify concealed kong")
	_discard(r)
	check(not r.snapshot_for(0).players[1].melds[0].has("tile"), "first discard remains hidden")
	_pass_all(r)
	for _other in 3:
		_discard(r)
		_pass_all(r)
	_discard(r)
	check(r.snapshot_for(0).players[1].melds[0].tile == "wan9", "second successful discard reveals kong")
	check(_conserved(r), "concealed kong conserves all IDs")
	var declined = _game({1: "w9999"}, "t2")
	_discard(declined)
	_pass_all(declined)
	for _other in 3:
		_discard(declined)
		_pass_all(declined)
	check(declined.players[1].dark_locked.has("wan9") and declined.choices(1).concealed_kong_ids.all(func(tile_id): return declined.wall.value(tile_id) != "wan9"), "declined kong cannot return")

func _rob_kong(take_win: bool) -> void:
	var r = _game({0: "w55", 3: "w46 t111222 b33344", 2: "w46 t333444 b55566"}, "w5 b789 w5")
	_discard(r)
	check(r.submit(0, r.prompt_id, "pong"), "source meld formed from discard")
	_pass_all(r)
	check(r.turn == 0 and r.players[0].draw_id == -1 and r.choices(0).discard_ids.all(func(id): return r.wall.value(id) != "wan5"), "pong skips draw and forbids same-value discard")
	_discard(r)
	_pass_all(r)
	for _other in 3:
		_discard(r)
		_pass_all(r)
	var fourth: int = r.players[0].draw_id
	var stock: int = r.wall.remaining
	var tail: int = r.wall.tail_index
	check(r.choices(0).add_kong_ids == [fourth] and r.submit(0, r.prompt_id, "add_kong", fourth), "only newly drawn fourth tile offered")
	check(r.phase == "response" and r.wall.remaining == stock and r.players[0].melds[0].kind == "pung", "pending add-kong has no side effects")
	if take_win:
		var window: int = r.prompt_id
		check(r.submit(2, window, "win") and r.submit(3, window, "win"), "two robbers submit")
		_pass_all(r)
		check(r.round_meta.winners == [3, 2] and r.round_meta.burn_chicken_seat == 0 and r.round_meta.robbed_kong, "multi-rob burns source")
		check(r.wall.remaining == stock and r.players[0].melds[0].tile_ids.size() == 3, "rob keeps original pong, no replacement")
	else:
		_pass_all(r)
		check(r.players[0].melds[0].kind == "add_kong" and r.players[0].draw_id == tail and r.wall.remaining == stock - 1, "all pass then complete and draw")
		check(r.players[3].pass_win and r.players[2].pass_win, "passing eligible rob locks each seat")
		_discard(r)
		_pass_all(r)
		check(r.turn == 3 and r.players[3].pass_win, "ordinary draw does not clear passed win")
		_discard(r)
		check(not r.players[3].pass_win, "successful discard clears ordinary lock")
	check(_conserved(r), "rob window conserves all physical IDs")

func _exposed_kong() -> void:
	var r = _game({0: "w555 t123456 b234 b1"}, "w5", "b1")
	var source: int = r.players[1].draw_id
	_discard(r)
	check(r.submit(0, r.prompt_id, "kong"), "claim exposed kong")
	_pass_all(r)
	var meld: Dictionary = r.players[0].melds[0]
	check(meld.source_id == source and meld.from_seat == 1 and meld.tile_ids.size() == 4 and not meld.concealed, "exposed kong retains supplier and all four tiles")
	check(r.submit(0, r.prompt_id, "self_win"), "replacement tile wins")
	check(r.round_meta.kong_draw_seat == 0 and r.round_meta.burn_chicken_seat == -1 and _conserved(r), "replacement bonus without burn")

func _post_kong_discard() -> void:
	var r = _game({1: "w9999", 0: "b68 t111222 w33344"}, "t2", "b7")
	check(r.submit(1, r.prompt_id, "concealed_kong", r.choices(1).concealed_kong_ids[0]), "declare dark kong")
	_discard(r)
	check(r.submit(0, r.prompt_id, "win"), "ordinary mixed hand gets post-dark-kong passport")
	_pass_all(r)
	check(r.round_meta.burn_chicken_reason == "after_kong_discard" and r.last_discard.kong_kind == "concealed" and r.round_meta.discard_seat == 1, "precise post-kong settlement source")
	r = _game({0: "w555", 3: "b68 t111222 w33344"}, "w5", "b7")
	_discard(r)
	check(r.submit(0, r.prompt_id, "kong"), "exposed kong for negative passport example")
	_pass_all(r)
	_discard(r)
	check(not r.choices(3).get("actions", []).has("win") and r.last_discard.kong_kind == "exposed", "exposed kong discard is ordinary")

func _pass_until_discard() -> void:
	var r = _game({2: "w3434545667899"}, "w54")
	_discard(r)
	var options: Array = r.choices(2).actions
	check(options.has("win") and options.has("pong"), "one seat offered both eligible options")
	_pass_all(r)
	check(r.players[2].pass_win and r.players[2].pass_pong == ["wan5"], "timeout locks eligible win and corresponding pong value")
	_discard(r)
	check(r.submit(2, r.prompt_id, "pong"), "other value remains claimable")
	_pass_all(r)
	check(r.turn == 2 and r.players[2].pass_win and r.players[2].pass_pong == ["wan5"], "pong itself clears neither lock")
	check(not r.submit(2, r.prompt_id, "discard", -22) and r.players[2].pass_win, "rejected discard does not clear locks")
	_discard(r)
	check(not r.players[2].pass_win and r.players[2].pass_pong.is_empty(), "successful direct post-pong discard clears both locks")

func _winning_chicken(later: bool) -> void:
	var r = _game({0: "w112233 t445566 b8"}, "b8 t234 b8")
	var first: int = r.players[1].draw_id
	_discard(r)
	if later:
		_pass_all(r)
		for _other in 3:
			_discard(r)
			_pass_all(r)
		_discard(r)
	var id: int = r.last_discard.tile_id
	check(r.submit(0, r.prompt_id, "win"), "win on chicken")
	_pass_all(r)
	var meta: Dictionary = r.round_meta
	var charge: Dictionary = meta.charge_chickens.tong8
	if later:
		check(charge.owner == 1 and charge.discard_id == first and charge.location == "discard", "first charge retained by discarder")
		check(meta.resolved_chicken_discards == [{"owner": 1, "tile": "tong8", "charge": false, "discard_id": id}], "later chicken has exactly one resolved source entry")
	else:
		check(charge.owner == 0 and charge.discard_id == first and charge.location == "hand", "first winning chicken loses charge and transfers")
		check(meta.resolved_chicken_discards.is_empty(), "first winning chicken confers no discard debt")
	check(r.settlement_facts().players[0].concealed_ids.back() == id and _conserved(r), "winner scores the exact chicken tile")

func _last_draw_win(offset: int) -> void:
	var seat := posmod(1 - offset, 4)
	var r = _game({seat: "w123456789 t45 b55"}, "", "", {offset: "tiao3"})
	for _step in offset:
		_discard(r)
		_pass_all(r)
	var remaining: int = r.wall.remaining
	check(r.turn == seat and r.submit(seat, r.prompt_id, "self_win"), "late-wall self draw")
	check(r.round_meta.last_four_self_draw_seat == seat and r.round_meta.kong_draw_seat == -1, "last four self draw without kong bonus")
	check(r.round_meta.flip_wall_index == r.wall.peek_head() and r.wall.remaining == remaining, "late flip reads next or remains empty")
	check(_conserved(r), "last draw win conserves stock")
