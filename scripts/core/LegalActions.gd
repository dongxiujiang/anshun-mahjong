extends RefCounted
## 只判断规则，不修改牌局；UI、AI 和权威提交共用相同的选项。

static func turn_options(round, seat: int) -> Dictionary:
	var options := {"self_win": false, "discards": [], "kong_declares": [], "add_kong": [], "ready_discards": []}
	if seat < 0 or seat >= round.players.size(): return options
	var player: PlayerState = round.players[seat]
	options.self_win = player.just_drew != "" and RuleEngine.analyze(player.concealed, player.melds).win
	if player.ready:
		if player.just_drew != "" and player.concealed.has(player.just_drew): options.discards.append(player.just_drew)
		return options
	for tile in Tiles.to_counts(player.concealed).keys():
		if tile != player.forbidden_discard_tile:
			options.discards.append(tile)
	if round._wall_count() > 0:
		for tile in options.discards:
			if Tiles.count(player.concealed, tile) >= 4: options.kong_declares.append(tile)
		for meld in player.melds:
			if meld.kind == "pung" and player.concealed.has(meld.tile) and not options.add_kong.has(meld.tile): options.add_kong.append(meld.tile)
	if ready_window(player):
		for tile in options.discards:
			var after := player.concealed.duplicate()
			after.erase(tile)
			if RuleEngine.is_tenpai(after, player.melds): options.ready_discards.append(tile)
	return options

static func ready_window(player: PlayerState) -> bool:
	return not player.ready and not player.first_turn_done and player.just_drew != "" and player.melds.all(func(meld): return meld.kind == "kong" and meld.get("concealed", false))

static func valid_turn(options: Dictionary, player: PlayerState, decision: Dictionary) -> bool:
	var dark: Variant = decision.get("kong_declares", [])
	var added: Variant = decision.get("add_kong", [])
	if not dark is Array or not added is Array: return false
	# 同一次提交只选择一种主动作；保留旧控制器附带的备用弃牌字段。
	var categories := int(bool(decision.get("self_win", false))) + int(not dark.is_empty()) + int(not added.is_empty())
	if categories > 1: return false
	if categories > 0 and bool(decision.get("ready", false)): return false
	if decision.get("self_win", false): return options.self_win
	if not dark.is_empty(): return dark.size() == 1 and options.kong_declares.has(dark[0])
	if not added.is_empty(): return added.size() == 1 and options.add_kong.has(added[0])
	var tile: Variant = decision.get("discard", player.just_drew if player.ready else "")
	if not tile is String or not options.discards.has(tile): return false
	var discard_index := int(decision.get("discard_index", -1))
	if discard_index >= 0:
		if discard_index >= player.concealed.size() or str(player.concealed[discard_index]) != tile:
			return false
	return not bool(decision.get("ready", false)) or options.ready_discards.has(tile)

static func response_options(round, seat: int, source: int, tile: String, stage: int) -> Dictionary:
	var options := {"can_win": false, "can_pong": false, "can_kong": false, "rob_kong": stage == RoundState.ResponseStage.ROB}
	if seat < 0 or seat >= round.players.size() or source == seat or tile == "": return options
	var player: PlayerState = round.players[seat]
	options.can_win = can_win_on_discard(round, seat, source, tile, stage)
	options.can_pong = stage == RoundState.ResponseStage.MELD and not player.ready and not player.passed_pong_tiles.has(tile) and Tiles.count(player.concealed, tile) >= 2
	options.can_kong = stage == RoundState.ResponseStage.MELD and not player.ready and round._wall_count() > 0 and Tiles.count(player.concealed, tile) >= 3
	return options

static func valid_response(options: Dictionary, decision: Dictionary) -> bool:
	var action: Variant = decision.get("action", "pass")
	return action is String and (action == "pass" or bool(options.get({"win": "can_win", "pong": "can_pong", "kong": "can_kong"}.get(action, "invalid"), false)))

static func has_self_kong(player: PlayerState) -> bool:
	return player.melds.any(func(meld): return meld.kind == "add_kong" or (meld.kind == "kong" and meld.get("concealed", false)))

static func can_win_on_discard(round, seat: int, source: int, tile: String, stage: int) -> bool:
	if seat < 0 or seat >= round.players.size() or source == seat: return false
	var player: PlayerState = round.players[seat]
	if player.passed_win_until_draw:
		return false
	if not RuleEngine.can_win_on(player.concealed, player.melds, tile): return false
	if stage == RoundState.ResponseStage.ROB or player.ready: return true
	if source >= 0 and source < round.players.size() and round.players[source].ready: return true
	# 暗杠、加杠补牌后打出的牌都开放抢胡，并由结算统一标记烧鸡。
	if bool(round.last_discard.get("after_kong", false)): return true
	var combined := player.concealed.duplicate()
	combined.append(tile)
	var pattern := RuleEngine.analyze(combined, player.melds)
	return bool(pattern.get("all_triplets", false) or pattern.get("flush", false)
		or pattern.get("seven_pairs", false) or RuleEngine.special_pattern_key(pattern) != ""
		or has_self_kong(player))
