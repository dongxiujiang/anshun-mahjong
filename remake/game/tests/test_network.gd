extends SceneTree

const Client = preload("res://src/network/GameClient.gd")
const Record = preload("res://src/session/RoundRecord.gd")
const Order = preload("res://src/presentation/HandOrder.gd")
const Table = preload("res://src/presentation/TableView.gd")
var checks := 0
var failures := 0
var raw_ms := 1000
var nodes: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func client(label: String):
	var value := Client.new()
	# This protocol fixture has no renderer; explicitly report its simulated completion.
	value.view_changed.connect(func(state):
		if state.has("presentation"):value.finish_presentation.call_deferred(state.presentation))
	value.name = label
	root.add_child(value)
	nodes.append(value)
	return value

func until(predicate: Callable, limit: int = 3000) -> bool:
	for step in limit:
		if predicate.call(): return true
		await process_frame
		OS.delay_msec(1)
	return false

func _run() -> void:
	var room_mode := "lan" if "--lan" in OS.get_cmdline_user_args() else "online"
	var server = client("AuthorityEndpoint")
	check(server.start_server("123456", 0, {"difficulty": "low", "ai_delay_ms": 2,
		"presentation_ms": {"dealt": 10, "turn": 5, "response": 5, "ready_draw": 5}}, room_mode), "real UDP service starts")
	server._host.clock_msec = func(): return raw_ms
	check(server.local_port > 0, "ephemeral ENet port available")
	var south = client("SouthEndpoint")
	var east = client("EastEndpoint")
	var preference := {"suit_order": ["tong", "tiao", "wan"], "hand_priority": "pattern", "novice": true}
	var profile_s := {"player_id": "test-south", "nickname": "南家", "room_number": "123456", "draw_style": "b", "avatar": 10, "voice_pack": "nvyou"}
	profile_s.merge(preference)
	var profile_e := {"player_id": "test-east", "nickname": "东家", "room_number": "123456", "avatar": 6, "voice_pack": "wangye"}
	profile_s.mode = room_mode
	profile_e.mode = room_mode
	check(south.connect_room("127.0.0.1", server.local_port, profile_s), "south connects")
	check(await until(func(): return not south.view.is_empty()), "south receives authenticated private view over RPC")
	check(east.connect_room("127.0.0.1", server.local_port, profile_e), "east connects")
	check(await until(func(): return not east.view.is_empty()), "east receives authenticated private view over RPC")
	if south.view.is_empty() or east.view.is_empty():
		await finish()
		return
	check(server._host != null and south._host == null and east._host == null, "only the independent server owns a game authority")
	check(south._standby_state.is_empty() and east._standby_state.is_empty() and south._backup_private == null and east._backup_private == null, "independent server endpoints receive no authority replica or backup key")
	check(south.view.seat == 1 and east.view.seat == 0, "network join follows south then east")
	check(south.ticket.member_token != east.ticket.member_token, "each seat gets private recovery credential")
	check(await until(func(): return south.view.room.seats[0].avatar == 6), "both players' join profiles reach the other endpoint")
	var original: Dictionary = east.view.room.seats[1].duplicate()
	var east_member: Dictionary = east.view.room.seats[0].duplicate()
	var displaced_ai: Dictionary = east.view.room.seats[3].duplicate()
	var authority_room = server._host._session._room
	check(authority_room.hand_preferences(1) == preference, "trusted opening hand preferences are available before the first deal")
	check(preference.keys().all(func(key): return not original.has(key)), "private hand preferences stay out of public player profiles")
	check(original.nickname == "南家" and original.avatar == 10 and original.voice_pack == "nvyou", "public profile contains the selected nickname, avatar and sound")
	check(not original.has("token_hash") and not original.has("member_token") and not original.has("connection_id") and not str(east.view).contains(south.ticket.member_token), "public view does not contain another member's credential")
	check(displaced_ai.avatar == 1 and displaced_ai.voice_pack != east.view.room.seats[2].voice_pack, "AI profiles have valid stable defaults")
	check(south.move_to_empty_seat(3), "authenticated player requests an empty seat")
	check(await until(func(): return south.view.seat == 3 and east.view.room.seats[3] == original), "player profile follows the person to the new seat")
	check(authority_room.hand_preferences(3) == preference, "private hand preferences also follow the person")
	check(east.view.room.seats[1] == displaced_ai, "displaced AI profile follows the AI identity")
	check(south.move_to_empty_seat(1), "player can return to the prior seat")
	check(await until(func(): return south.view.seat == 1 and east.view.room.seats[1] == original), "both clients agree on the restored position")
	var saved: Dictionary = south.ticket.duplicate(true)
	var instance: String = saved.room_instance_id
	south.set_ready(true)
	east.set_ready(true)
	south.start_first_round()
	check(await until(func(): return south.view.room.get("preparing", false) or server._host._prepare_at >= 0), "both ready start cancellable preparation")
	east.set_ready(false)
	check(await until(func(): return server._host._prepare_at == -1), "remote unready cancels countdown")
	east.set_ready(true)
	await until(func(): return server._host._prepare_at >= 0)
	raw_ms += 3001
	check(await until(func(): return south.view.round.phase == "dealt", 12000), "real dice settles and real private deal reaches peers")
	check(south.view.round.players[1].hand.size() == 13 and south.view.round.players[0].hand.is_empty(), "south never receives east concealed tile values")
	check(east.view.round.players[0].hand.size() == 13 and east.view.round.players[1].hand.is_empty(), "east never receives south concealed tile values")
	check(south.view.round.deal_styles == ["a", "b", "a", "a"] and east.view.round.deal_styles == south.view.round.deal_styles, "same individual deal motions on both real clients")
	await _verify_auto_play_controls(server, south, east)
	east_member = east.view.room.seats[0].duplicate()
	var hand := Order.new()
	hand.set_suit_order(preference.suit_order)
	hand.sync_hand(instance, 1, south.view.round.prompt_id, south.view.round.players[1].hand)
	var moving: int = hand.view().slots[5]
	var lookup: Dictionary = south.view.round.players[1].display.own_keys
	var moving_key: String = lookup[str(moving)]
	var observer := Table.new()
	root.add_child(observer)
	observer.apply_view(east.view.round)
	var physical: Node3D = observer.tiles[moving_key]
	hand.begin_drag(moving)
	hand.move_gap(2)
	var preview := hand.view()
	preview.drag_position = [2.25, 9.0]
	check(south.set_hand_display(preview), "drag travels through authenticated reliable ENet")
	check(await until(func(): return east.view.round.players[1].display.dragged == moving_key), "opponent sees same dragged back")
	observer.apply_view(east.view.round)
	observer._render(false)
	check(observer.tiles[moving_key] == physical and physical.position.is_equal_approx(Table.Layout.facing(1) * Vector3(2.25, 1.9, 9.0)), "same physical node follows world position from the other camera")
	check(east.view.round.players[1].hand.is_empty() and not east.view.round.players[1].display.has("own_keys"), "moving back reveals neither hand faces nor hidden ID lookup")
	hand.commit_drag(2)
	south.set_hand_display(hand.view())
	var final_keys: Array = hand.view().slots.map(func(id): return lookup[str(id)])
	check(await until(func(): return east.view.round.players[1].display.slots == final_keys and east.view.round.players[1].display.dragged == ""), "committed slot order reaches observer")
	var invalid := hand.view()
	invalid.slots[0] = invalid.slots[1]
	south.set_hand_display(invalid)
	for frame in 8:
		await process_frame
		OS.delay_msec(1)
	check(east.view.round.players[1].display.slots == final_keys, "forged duplicate ID cannot alter shared arrangement")
	observer.free()
	var before_ids: Array = south.view.round.players[1].hand.duplicate(true)
	var port: int = server.local_port
	south._reset() # Simulate an unexpected app loss, not an explicit room departure.
	check(await until(func(): return server._host._connections.size() == 1), "network disconnect releases connection without ending room")
	var profile_recovered := profile_s.duplicate()
	profile_recovered.merge({"nickname": "归来", "avatar": 9, "voice_pack": "wenrou"}, true)
	check(south.connect_room("127.0.0.1", port, profile_recovered, saved), "closed app credential reconnects")
	check(await until(func(): return not south.view.is_empty()), "recovery restored view")
	check(south.view.room.room_instance_id == instance and south.view.seat == 1 and south.view.round.players[1].hand == before_ids, "recovery preserves exact identity and physical hand")
	check(south.view.round.players[1].display.slots == final_keys and south.view.round.players[1].display.manual, "manual order survives connection replacement")
	check(await until(func(): return east.view.room.seats[1].nickname == "归来"), "authenticated recovery propagates the latest saved profile")
	check(south.view.room.seats[1].avatar == 9 and east.view.room.seats[1].voice_pack == "wenrou" and east.view.room.seats[0] == east_member, "restored appearance and voice belong to the original authenticated player")
	await _verify_live_profile(server, south, east)
	await _presence_transitions(server, south, east)
	var delegated_prompt: int = south.view.round.prompt_id
	check(south.set_auto_play(true) and await until(func(): return east.view.room.seats[1].auto_play and south.view.room.seats[1].auto_play), "remote human delegates subsequent legal actions to the authority")
	var cancel_sent := false
	var sent := {}
	var finished := false
	for frame in 26000:
		raw_ms += 10
		await process_frame
		OS.delay_msec(1)
		if not cancel_sent and south.view.round.prompt_id != delegated_prompt and south.view.round.phase != "settled":
			cancel_sent = south.set_auto_play(false)
		for peer in [south, east]:
			if peer.view.is_empty() or peer.view.room.seats[peer.view.seat].auto_play: continue
			var round_view: Dictionary = peer.view.round
			var options: Dictionary = round_view.get("choices", {})
			if options.is_empty(): continue
			var key := str(peer.name) + ":" + str(round_view.prompt_id)
			if sent.has(key): continue
			var action := "pass" if options.actions.has("pass") else ("self_win" if options.actions.has("self_win") else "discard")
			var id: int = options.discard_ids[0] if action == "discard" else -1
			if peer.submit(round_view.prompt_id, action, id): sent[key] = true
		if south.view.round.phase == "settled" and east.view.round.phase == "settled":
			finished = true
			break
	check(finished, "two live ENet clients complete actual match with AI players")
	if finished:
		check(south.view.settlement.scores == east.view.settlement.scores, "both clients receive same authoritative settlement")
		var record: Dictionary = server._host.last_completed_record()
		check(record.inputs.any(func(event): return event.get("type") == "submit" and event.get("seat") == 1 and event.get("prompt_id") == delegated_prompt), "delegated human made a real decision before timeout without a client action")
		check(Record.replay(record).ok, "network-submitted round fully replays")
	var bad = client("WrongRoomEndpoint")
	var ended := []
	bad.session_ended.connect(func(reason): ended.append(reason))
	bad.connect_room("127.0.0.1", port, {"player_id": "outsider", "nickname": "来客", "room_number": "999999"})
	check(await until(func(): return not ended.is_empty()), "wrong-room handshake rejected")
	check(bad.view.is_empty() and server._host._connections.size() == 2, "rejected handshake never acquires game information or seat")
	if finished:
		await _concurrent_departures(server, south, east, room_mode)
	await finish()

func _concurrent_departures(server, south, east, room_mode: String) -> void:
	var members := [south, east]
	for index in 2:
		var guest = client("AdditionalEndpoint" + str(index))
		guest.connect_room("127.0.0.1", server.local_port, {"mode": room_mode, "room_number": "123456",
			"player_id": "guest-" + str(index), "nickname": "来客" + str(index)})
		check(await until(func(): return not guest.view.is_empty()), "additional player actually joins over ENet")
		members.append(guest)
	for member in members: member.set_ready(true)
	members[0].start_first_round()
	check(await until(func(): return server._host._prepare_at >= 0), "four authenticated players ready for next round")
	raw_ms += 1001
	if not await until(func(): return members.all(func(member): return member.view.round.phase == "dealt"), 12000):
		check(false, "four live endpoints reach the same new deal")
		return
	var dealer: int = south.view.round.dealer
	var survivor
	var returning_profile := {}
	var returning_ticket := {}
	var private_hand := []
	for member in members:
		if member.view.seat == dealer:
			survivor = member
		else:
			if member.view.seat == (dealer + 2) % 4:
				returning_profile = member._profile.duplicate(true)
				returning_ticket = member.ticket.duplicate(true)
				private_hand = member.view.round.players[member.view.seat].hand.duplicate(true)
			member._reset() # These simultaneous losses are later recovered with their tickets.
			member.queue_free()
			nodes.erase(member)
	check(await until(func(): return survivor.view.room.seats.filter(func(seat): return seat.connected).size() == 1), "same-frame departure of three endpoints preserves the fourth connection")
	raw_ms += 11
	check(await until(func(): return survivor.view.round.phase == "turn"), "survivor receives a new prompt after simultaneous disconnects")
	raw_ms += 6
	if not await until(func(): return not survivor.view.round.choices.is_empty()):
		check(false, "surviving dealer can play after its animation")
		return
	var id: int = survivor.view.round.choices.discard_ids[0]
	survivor.submit(survivor.view.round.prompt_id, "discard", id)
	check(await until(func(): return survivor.view.round.players[dealer].discards.size() == 1), "surviving endpoint makes a real accepted discard")
	var back = client("ReturningEndpoint")
	back.set_application_away(true)
	back.connect_room("127.0.0.1", server.local_port, returning_profile, returning_ticket)
	check(await until(func(): return not back.view.is_empty()), "former peer reauthenticates using its original private ticket")
	if not back.view.is_empty():
		check(back.view.room.seats[back.view.seat].away and back.view.room.seats[back.view.seat].connected and back.waiting_for_foreground_view(), "a recovery handshake in background preserves occupancy and starts away")
		back.set_application_away(false)
		check(await until(func(): return not back.waiting_for_foreground_view() and not survivor.view.room.seats[back.view.seat].away), "recovered member returns after the latest current-room snapshot")
		check(back.view.room.room_instance_id == returning_ticket.room_instance_id and back.view.seat == returning_ticket.seat and back.view.round.players[back.view.seat].hand == private_hand, "restored endpoint keeps its exact seat and concealed hand")
		check(back.view.round.players[dealer].discards == survivor.view.round.players[dealer].discards and back.view.round.players[dealer].hand.is_empty(), "returning endpoint sees the new play and only its own private tiles")

func _verify_auto_play_controls(server, south, east) -> void:
	var original: Dictionary = south.view.room.seats[1].duplicate()
	var game: Dictionary = south.view.round.duplicate(true)
	var instance: String = south.ticket.room_instance_id
	check(south.set_auto_play(true) and await until(func(): return south.view.room.seats[1].auto_play and east.view.room.seats[1].auto_play), "explicit opt-in reaches both real endpoints")
	var delegated := original.duplicate()
	delegated.auto_play = true
	check(east.view.room.seats[1] == delegated and not east.view.room.seats[0].auto_play and south.view.round == game, "delegation keeps the same authenticated player, occupied seat, assets, points and cards")
	east._command({"kind": "auto_play", "instance": instance, "round": 1, "seat": 1, "enabled": false})
	var other: String = server._peer_connections[east._api.get_unique_id()]
	check(await until(func(): return server._last_requests.get(other) == east._request_id) and server._host.public_room().seats[1].auto_play, "another live connection cannot cancel the owner's permission by supplying its seat number")
	var old_request: int = south._request_id
	south.set_auto_play(true)
	south.set_auto_play(false)
	check(await until(func(): return not south.view.room.seats[1].auto_play and not east.view.room.seats[1].auto_play), "both endpoints observe explicit cancellation")
	south.client_request.rpc_id(1, {"kind": "auto_play", "instance": instance, "round": 1, "enabled": true, "request_id": old_request})
	for packet in [{"instance": "other", "round": 1, "enabled": true}, {"instance": instance, "round": 2, "enabled": true}, {"instance": instance, "round": 1, "enabled": 1}]:
		packet.kind = "auto_play"
		south._command(packet)
	var conn: String = server._peer_connections[south._api.get_unique_id()]
	check(await until(func(): return server._last_requests.get(conn) == south._request_id), "authority consumed stale, duplicate and malformed test packets")
	check(server._host.public_room().seats[1] == original and south.view.round == game, "replayed opt-in, another room, another round and invalid flag cannot re-enable or change the deal")

func _presence_transitions(server, owner, observer) -> void:
	var instance: String = owner.ticket.room_instance_id
	var seat: int = owner.view.seat
	var prompt: int = owner.view.round.prompt_id
	var tile: int = owner.view.round.choices.discard_ids[0]
	var before: Dictionary = owner.view.round.duplicate(true)
	var timer: Dictionary = owner.view.clock.duplicate(true)
	owner.set_application_away(true)
	check(owner.waiting_for_foreground_view() and not owner.submit(prompt, "discard", tile), "background blocks input immediately, before ENet notification returns")
	check(await until(func(): return observer.view.room.seats[seat].away), "connected background seat becomes away on the other live endpoint")
	var member: Dictionary = observer.view.room.seats[seat]
	check(member.connected and member.player_id == owner.ticket.player_id and member.ai_id < 0 and not observer.view.room.seats[observer.view.seat].away, "away is per member and keeps the connected, occupied seat")
	observer.set_application_away(true)
	check(await until(func(): return observer.view.room.seats[observer.view.seat].away) and server._host._session.is_open(raw_ms + 300001), "all connected humans in background do not trigger the last-disconnect room deadline")
	observer.set_application_away(false)
	await until(func(): return not observer.waiting_for_foreground_view())
	var conn: String = server._peer_connections[owner._api.get_unique_id()]
	check(not server._host.submit(conn, instance, 1, prompt, "discard", tile), "hidden manual action also fails at authority")
	observer._command({"kind": "presence", "instance": instance, "revision": 123, "seat": seat, "away": false})
	observer._command({"kind": "presence", "instance": "old-instance", "revision": 124, "away": true})
	var other: String = server._peer_connections[observer._api.get_unique_id()]
	check(await until(func(): return server._last_requests.get(other) == observer._request_id) and server._host.connection_away(conn) and not server._host.connection_away(other), "another seat and a stale room cannot change the member's presence")
	var observed := []
	var examine := func(v: Dictionary):
		if not v.presence.needs_ack or owner._application_away: return
		observed.append(owner.waiting_for_foreground_view() and server._host.connection_away(conn) and not owner.submit(prompt, "discard", tile))
		if observed.size() == 1:
			owner.set_application_away(true)
			owner._command({"kind": "foreground_received", "instance": instance, "revision": v.presence.revision})
	owner.view_changed.connect(examine)
	owner.set_application_away(false)
	check(owner.waiting_for_foreground_view(), "resuming cannot use a cached foreground view")
	check(await until(func(): return observed.size() == 1 and owner.view.presence.revision == owner._presence_revision), "a second background transition overtakes the first pending foreground receipt")
	check(server._host.connection_away(conn) and observer.view.room.seats[seat].away, "retired foreground receipt cannot reactivate an away player")
	owner.set_application_away(false)
	check(await until(func(): return not owner.waiting_for_foreground_view() and not observer.view.room.seats[seat].away), "authority reopens after receipt of the fresh private view")
	owner.view_changed.disconnect(examine)
	check(observed == [true, true] and timer == owner.view.clock and before == owner.view.round, "both pending foreground snapshots blocked play without resetting prompt, timer or tiles")

func _verify_live_profile(server, south, east) -> void:
	raw_ms += 10
	check(await until(func(): return south.view.round.phase == "turn"), "profile test reaches a live dealer turn")
	raw_ms += 5
	check(await until(func(): return south.view.get("clock", {}).get("phase", "") == "countdown"), "profile test reaches the dealer's live timer")
	var round_before: Dictionary = south.view.round.duplicate(true)
	var clock_before: Dictionary = south.view.get("clock", {}).duplicate(true)
	var east_member: Dictionary = east.view.room.seats[0].duplicate()
	var original: Dictionary = east.view.room.seats[1].duplicate()
	check(south.set_player_profile({"nickname": "东家", "avatar": 2, "voice_pack": "huaqiang"}), "client sends an identity change for authority validation")
	check(await until(func(): return server._last_requests.values().has(south._request_id)), "authority receives the attempted in-room identity change")
	check(server._host.public_room().seats[1] == original, "authority rejects in-room nickname and appearance changes atomically")
	south._command({"kind": "hello", "protocol": Client.Protocol.PROTOCOL_VERSION, "variant": Client.Protocol.VARIANT_ID, "rules": Client.Protocol.RULES_VERSION, "ticket": south.ticket, "profile": {"nickname": "绕过", "avatar": 10}})
	check(await until(func(): return server._last_requests.values().has(south._request_id)), "authority receives repeated authenticated hello")
	check(server._host.public_room().seats[1] == original, "repeated hello cannot bypass in-room identity restrictions")
	var changed := {"voice_pack": "huaqiang"}
	check(south.set_player_profile(changed), "connected player changes sound in the current round")
	check(await until(func(): return south.view.room.seats[1].voice_pack == "huaqiang" and east.view.room.seats[1].voice_pack == "huaqiang"), "new sound reaches both clients without reconnecting")
	var current: Dictionary = east.view.room.seats[1].duplicate()
	check(current.nickname == original.nickname and current.avatar == original.avatar and current.player_id == original.player_id, "sound preference leaves nickname and appearance unchanged")
	check(current.score == original.score and east.view.room.seats[0] == east_member and south.view.round == round_before and south.view.clock == clock_before, "editing profile changes neither scores, other players, dealer, hand, nor timer")
	for invalid_profile in [{"nickname": "甲乙丙丁戊己庚", "avatar": 3}, {"voice_pack": "../outside", "avatar": 3}, {"avatar": 11}, {"avatar": true}, {"nickname": "甲!"}, {"seat": 0, "nickname": "冒充"}, {"player_id": "test-east", "avatar": 3}, {"suit_order": ["tong", "tong", "wan"], "avatar": 3}]:
		south._command({"kind": "player_profile", "profile": invalid_profile})
	check(south.set_player_profile(changed), "identical profile is safe to repeat")
	south.client_request.rpc_id(1, {"kind": "player_profile", "request_id": south._request_id, "profile": {"nickname": "旧值"}})
	check(await until(func(): return server._last_requests.values().has(south._request_id)), "authority receives the entire reliable request sequence")
	await process_frame
	check(east.view.room.seats[1] == current and east.view.room.seats[0] == east_member, "forged profile fields and repeated transport requests leave both identities intact")

func finish() -> void:
	for value in nodes: value.queue_free()
	await process_frame
	await process_frame
	print("Network: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
