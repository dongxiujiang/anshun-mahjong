extends SceneTree

const RoomSession = preload("res://src/session/RoomSession.gd")

var _failures: int = 0


func _initialize() -> void:
	_test_nicknames_and_seats()
	_test_ready_round_and_accounts()
	_test_replacement_during_round()
	_test_room_deadline()
	_test_recovery_credentials()
	_test_retired_connections()
	_test_in_room_profile()
	if _failures == 0:
		print("Room session tests passed")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _test_nicknames_and_seats() -> void:
	for nickname in ["A", "东秀甲a12", "𠀀", "é٣"]:
		_check(RoomSession.is_valid_nickname(nickname), "Valid nickname: %s" % nickname)
	for nickname in ["", "甲乙丙丁戊己庚", " 东", "东!", "😀", "A\n", "カ"]:
		_check(not RoomSession.is_valid_nickname(nickname), "Invalid nickname: %s" % nickname)

	var room := RoomSession.new("0123")
	_check(room.join("bad", "错误!", "cx", 0).is_empty(), "Invalid nickname cannot claim a seat")
	var first := room.join("first", "同名", "c1", 0)
	_check(first.get("seat") == 1, "First entrant sits south")
	_check(room.move_to_empty_seat("c1", 3, 0), "First entrant can choose north in preparation")
	_check(room.join("first", "别人", "cx", 0).is_empty(), "Existing identity cannot join a second time")
	_check(room.join("second", "同名", "c1", 0).is_empty(), "Connection cannot claim another identity")
	_check(room.join("second", "同名", "c2", 0).get("seat") == 1, "South is reused after a manual move")
	_check(room.join("third", "同名", "c3", 0).get("seat") == 0, "East is next")
	_check(room.join("fourth", "同名", "c4", 0).get("seat") == 2, "West is last when north is already taken")
	_check(not room.move_to_empty_seat("c2", 3, 0), "A human seat cannot be claimed")
	_check(room.disconnect_human("c1", 0), "Disconnect preserves the seat")
	_check(not room.move_to_empty_seat("c2", 3, 0), "An offline human seat cannot be claimed")
	_check(room.join("fifth", "新来", "c5", 0).is_empty(), "Offline humans retain their place in a full room")

	var default_room := RoomSession.new("0123")
	var expected: Array[int] = [1, 0, 3, 2]
	for index in expected.size():
		var id := str(index)
		_check(default_room.join(id, "同名", id, 0).get("seat") == expected[index], "Default seat order")
	for occupant in default_room.snapshot(0).get("seats"):
		_check(occupant.get("score") == 200, "First entrants start with 200 each")


func _test_in_room_profile() -> void:
	var room := RoomSession.new("profile")
	var ticket := room.join("first", "甲", "c1", 0)
	for in_round in [false, true]:
		if in_round:
			_check(room.set_ready("c1", true, 0) and room.start_round(0, 1), "Profile restrictions also apply after starting")
		var before := room.snapshot(0)
		for forbidden in [{"nickname": "乙"}, {"avatar": 2}, {"nickname": "乙", "voice_pack": "huaqiang"}]:
			_check(room.set_player_profile("c1", forbidden, 0) == -1, "Room members cannot change nickname or appearance")
			_check(room.snapshot(0) == before, "A rejected mixed profile cannot partially change the room")
		_check(room.set_player_profile("c1", {"nickname": "甲", "avatar": 1}, 0) == 0, "Same identity fields are safe to repeat")
		var resumed := room.resume(ticket.room_instance_id, "first", ticket.member_token, "c1", 0, {"nickname": "绕过", "avatar": 10})
		_check(not resumed.is_empty() and room.snapshot(0) == before, "Same-connection recovery cannot bypass in-room identity restrictions")
	_check(room.set_player_profile("c1", {"voice_pack": "huaqiang", "suit_order": ["tong", "tiao", "wan"], "novice": true}, 0) == 1, "Sound and hand preferences remain editable in a room")
	var occupant: Dictionary = room.snapshot(0).seats[1]
	_check(occupant.nickname == "甲" and occupant.avatar == 1 and occupant.voice_pack == "huaqiang", "Preferences preserve the player's identity")
	_check(room.set_player_profile("c1", {"voice_pack": "huaqiang", "suit_order": ["tong", "tiao", "wan"], "novice": true}, 0) == 0, "All allowed preferences were applied")


func _test_ready_round_and_accounts() -> void:
	var room := RoomSession.new("score")
	var ticket := room.join("playing", "甲", "c1", 1)
	_check(room.snapshot(1).get("phase") == RoomSession.Phase.FIRST_PREPARATION, "First preparation is the initial phase")
	_check(not room.start_round(1, 0), "An unready human prevents the start")
	_check(room.set_ready("c1", true, 1), "A connected human can be ready in preparation")
	_check(room.start_round(1, 0), "A ready human can start with AI seats")
	_check(room.snapshot(1).get("phase") == RoomSession.Phase.IN_ROUND, "Round marked in progress")
	_check(not room.set_ready("c1", false, 1), "Readiness cannot change in a round")
	_check(not room.move_to_empty_seat("c1", 3, 1), "Seat cannot move in a round")
	_check(not room.finish_round(1, [7, 19, -13, -11], 1, 2), "Reject imbalanced settlement")
	_check(room.finish_round(1, [7, 19, -13, -13], 1, 2), "Apply settlement and determine next dealer")
	_check(not room.finish_round(1, [7, 19, -13, -13], 1, 2), "A duplicate settlement cannot be applied twice")
	var result := room.snapshot(2)
	_check(result.get("phase") == RoomSession.Phase.BETWEEN_ROUNDS, "Settlement opens inter-round preparation")
	var before: Array = result.get("seats")
	_check(not before[1].get("ready"), "Next preparation starts unready")
	_check(room.move_to_empty_seat("c1", 0, 3), "Human can take an AI seat between rounds")
	var after: Dictionary = room.snapshot(3)
	var seats: Array = after.get("seats")
	_check(seats[0].get("player_id") == "playing" and seats[0].get("score") == 219, "Human score follows their identity")
	_check(seats[1].get("ai_id") == before[0].get("ai_id") and seats[1].get("score") == 207, "Target AI keeps its identity and score")
	_check(seats[2].get("score") == 187 and seats[3].get("score") == 187, "Unaffected seat balances stay put")
	_check(after.get("next_dealer_seat") == 0, "The next dealer follows the moved player")
	_check(room.disconnect_human("c1", 4), "Close the original client")
	var recovered := room.resume(ticket.room_instance_id, "playing", ticket.member_token, "c2", 5)
	_check(recovered.get("seat") == 0 and recovered.get("seats", [])[0].get("score") == 219, "Reopening restores the latest seat and score")
	_check(room.set_ready("c2", true, 5) and room.start_round(5), "Ready player can start the next round")
	_check(room.snapshot(5).get("dealer_seat") == 0, "Next round uses the selected dealer")
	_check(not room.finish_round(1, [7, 19, -13, -13], 1, 5), "Old settlement cannot apply to a later round")
	_check(room.finish_round(2, [220, -220, 0, 0], 1, 5), "Next dealer can be an AI and its balance can go below zero")
	_check(room.move_to_empty_seat("c2", 1, 5), "Human can swap with the AI dealer")
	_check(room.snapshot(5).get("next_dealer_seat") == 0, "The AI retains its next-dealer identity after being moved")
	var ai_dealer: Dictionary = room.snapshot(5).get("seats")[0]
	_check(ai_dealer.get("score") == -13, "The negative AI balance follows the AI")
	var joined := room.join("new", "乙", "cx", 6)
	_check(joined.get("seat") == 0 and joined.get("replaced_ai_id") == ai_dealer.get("ai_id"), "The newcomer can replace the AI dealer in preparation")
	var next := room.snapshot(6)
	_check(next.get("next_dealer_seat") == 0 and next.get("seats")[0].get("score") == -13, "The newcomer inherits the pending dealer role and negative balance")
	_check(room.move_to_empty_seat("cx", 3, 6), "The new dealer can move to an empty seat")
	_check(room.snapshot(6).get("next_dealer_seat") == 3, "The inherited dealer role now follows the member")


func _test_replacement_during_round() -> void:
	var room := RoomSession.new("replacement")
	var original := room.join("original", "甲", "c1", 0)
	_check(room.set_ready("c1", true, 0) and room.start_round(0, 1), "A human starts with empty AI seats")
	_check(room.finish_round(1, [-220, 220, 0, 0], 0, 1), "An AI becomes dealer with a negative balance")
	_check(room.set_ready("c1", true, 2) and room.start_round(2), "The next round uses the AI dealer")
	_check(room.disconnect_human("c1", 3), "The original human seat remains reserved")
	var before := room.snapshot(300002)
	var newcomer := room.join("newcomer", "新来", "c2", 300002)
	_check(newcomer.get("joined") == true and newcomer.get("seat") == 0, "A newcomer can take the AI dealer one millisecond before expiry")
	_check(newcomer.get("replaced_ai_id") == before.get("seats")[0].get("ai_id"), "The ticket identifies the AI that was replaced")
	var after := room.snapshot(300003)
	_check(after.get("phase") == RoomSession.Phase.IN_ROUND and after.get("round_number") == before.get("round_number"), "Replacement keeps the same active round")
	_check(after.get("dealer_seat") == 0 and after.get("seats")[0].get("player_id") == "newcomer", "The newcomer becomes controller of the current dealer seat")
	_check(after.get("seats")[0].get("score") == -20 and after.get("seats")[0].get("ai_id") == -1, "The newcomer inherits the AI balance without a duplicate account")
	_check(after.get("seats")[1].get("score") == 420 and after.get("seats")[1].get("player_id") == "original", "The offline human retains their seat and balance")
	_check(room.resume(original.room_instance_id, "original", original.member_token, "c3", 300004).get("seat") == 1, "The offline human can still recover their reserved seat")

	var expired := RoomSession.new("expired-during-round")
	expired.join("original", "甲", "c1", 0)
	_check(expired.set_ready("c1", true, 0) and expired.start_round(0, 0), "A round starts with the AI seated as dealer")
	_check(expired.disconnect_human("c1", 1), "The last human disconnects during the round")
	_check(expired.join("newcomer", "新来", "c2", 300001).is_empty(), "Even an available AI seat cannot be filled at expiry")
	_check(expired.join("newcomer", "新来", "c2", 300002).is_empty(), "Closing the room is final")


func _test_room_deadline() -> void:
	var room := RoomSession.new("deadline")
	var first := room.join("first", "甲", "c1", 0)
	var second := room.join("second", "乙", "c2", 0)
	_check(room.disconnect_human("c1", 1), "First player disconnects")
	_check(room.is_open(900000), "One remaining human keeps the room active")
	_check(room.recoverable_seat(first.room_instance_id, "first", first.member_token, 900000) == 1, "Personal time offline does not matter")
	_check(room.set_ready("c2", true, 900000) and room.start_round(900000, 0), "AI can cover a disconnected player")
	_check(room.disconnect_human("c2", 900010), "Last player disconnects")
	_check(not room.disconnect_human("c2", 900011), "A duplicate disconnect cannot restart the deadline")
	_check(room.finish_round(1, [0, 0, 0, 0], 0, 1190000), "The authority can finish a round during the grace period")
	_check(room.recoverable_seat(second.room_instance_id, "second", second.member_token, 1200009) == 0, "Recoverable one millisecond before the room deadline")
	_check(room.recoverable_seat(first.room_instance_id, "first", "wrong", 1200009) == -1, "An invalid probe cannot renew the room")
	_check(room.recoverable_seat(first.room_instance_id, "first", first.member_token, 1200010) == -1, "At five minutes the old room offers no restore")
	_check(room.resume(first.room_instance_id, "first", first.member_token, "c3", 1200010).is_empty(), "The exact deadline cannot be raced by a restore")
	_check(room.join("third", "丙", "c3", 1200010).is_empty(), "The exact deadline cannot be raced by a new entrant")
	_check(room.snapshot(1200011).is_empty(), "Closed room publishes no active snapshot")
	_check(room.seat_for_connection("c2", 1200011) == -1, "Closed rooms authorize no connection")

	var renewed := RoomSession.new("renewed")
	var ticket := renewed.join("first", "甲", "c1", 1)
	_check(renewed.disconnect_human("c1", 10), "First empty interval starts")
	_check(not renewed.resume(ticket.room_instance_id, "first", ticket.member_token, "c2", 300009).is_empty(), "Human returns before the first deadline")
	_check(renewed.is_open(600000), "The old deadline was cleared")
	_check(renewed.disconnect_human("c2", 600001), "Second empty interval starts")
	_check(not renewed.join("second", "乙", "c3", 900000).is_empty(), "A new human can also clear the deadline")
	_check(renewed.is_open(900001), "New human keeps the room active")
	_check(renewed.disconnect_human("c3", 900002), "Third empty interval starts")
	_check(renewed.is_open(1200001) and not renewed.is_open(1200002), "A fresh five-minute deadline starts for the last disconnection")


func _test_recovery_credentials() -> void:
	var room := RoomSession.new("same-code")
	var first := room.join("first", "同名", "c1", 0)
	var second := room.join("second", "同名", "c2", 0)
	_check(room.seat_for_connection("c1", 0) == 1 and room.seat_for_connection("c2", 0) == 0, "Authority maps connected clients to their actual seats")
	_check(room.seat_for_connection("", 0) == -1 and room.seat_for_connection("unknown", 0) == -1, "Empty and unknown connection IDs have no seat")
	_check(room.set_ready("c1", true, 0), "First human is ready")
	_check(not room.start_round(0, 1), "Another connected unready human prevents the start")
	_check(room.set_ready("c2", true, 0) and room.start_round(0, 1), "Both humans ready start the round")
	_check(room.disconnect_human("c1", 1), "Reconnect target disconnects")
	_check(room.resume(first.room_instance_id, "first", "", "c3", 2).is_empty(), "Missing member token cannot restore")
	_check(room.resume(first.room_instance_id, "first", second.member_token, "c3", 2).is_empty(), "Another member's token cannot restore the target")
	_check(room.resume(first.room_instance_id, "同名", first.member_token, "c3", 2).is_empty(), "Matching nickname cannot restore")
	_check(room.resume(first.room_instance_id, "first", first.member_token, "c2", 2).is_empty(), "Resume cannot steal another member's connection")
	var recovered := room.resume(first.room_instance_id, "first", first.member_token, "c3", 2)
	_check(recovered.get("seat") == 1, "Matching instance, identity and token restore membership")
	_check(recovered.get("phase") == RoomSession.Phase.IN_ROUND and recovered.get("dealer_seat") == 1, "Reopening during a round returns the current round and dealer")
	_check(not room.disconnect_human("c1", 3), "A stale connection cannot disconnect the recovered member")
	_check(not str(room.snapshot(3)).contains(first.member_token), "Room snapshots never expose recovery credentials")
	var moved_connection := room.resume(first.room_instance_id, "first", first.member_token, "c4", 4)
	_check(moved_connection.get("seat") == 1 and room.seat_for_connection("c4", 4) == 1, "Replacing an active connection grants the new connection the seat")
	_check(room.seat_for_connection("c3", 4) == -1, "Replacing an active connection revokes the old one")
	_check(room.finish_round(1, [0, 0, 0, 0], 1, 5), "The room returns to preparation")
	_check(not room.set_ready("c3", true, 5) and not room.move_to_empty_seat("c3", 3, 5), "The replaced connection cannot prepare or move")
	_check(room.move_to_empty_seat("c4", 3, 5) and room.seat_for_connection("c4", 5) == 3, "The new connection follows the current member seat")

	var replacement := RoomSession.new("same-code")
	var current := replacement.join("first", "同名", "new-c1", 0)
	_check(first.room_instance_id != current.room_instance_id, "Reused room code gets a different instance identity")
	_check(replacement.resume(first.room_instance_id, "first", first.member_token, "new-c2", 3).is_empty(), "Reused room code cannot restore the old member")
	_check(replacement.resume(first.room_instance_id, "first", current.member_token, "new-c2", 3).is_empty(), "Correct member token in the wrong instance is rejected")
	_check(replacement.resume(current.room_instance_id, "first", first.member_token, "new-c2", 3).is_empty(), "An old token in the correct new instance is rejected")


func _test_retired_connections() -> void:
	var room := RoomSession.new("retired")
	var ticket := room.join("player", "甲", "old-connection", 0)
	var instance_id: String = ticket.room_instance_id
	var token: String = ticket.member_token
	_check(room.set_ready("old-connection", true, 0), "The first connection sets ready")
	var restored := room.resume(instance_id, "player", token, "current-connection", 1)
	_check(restored.get("seat") == ticket.get("seat"), "A fresh connection can replace an active one")
	var current_snapshot := room.snapshot(1)
	_check(room.resume(instance_id, "player", token, "current-connection", 2) == restored, "A duplicate valid resume on the current connection is idempotent")
	_check(room.join("other", "乙", "old-connection", 3).is_empty(), "A replaced connection cannot join as another player")
	_check(room.resume(instance_id, "player", token, "old-connection", 3).is_empty(), "A replaced connection cannot resume with valid original credentials")
	_check(room.seat_for_connection("current-connection", 3) == ticket.seat and room.snapshot(3) == current_snapshot, "Stale requests preserve the active connection and state")
	_check(not str(room.snapshot(3)).contains("old-connection"), "The public snapshot omits retired connection IDs")

	_check(room.disconnect_human("current-connection", 10), "The last connection disconnects")
	_check(room.resume(instance_id, "player", "wrong", "fresh-connection", 11).is_empty(), "A fresh connection still requires a valid token")
	_check(room.resume(instance_id, "player", token, "current-connection", 12).is_empty(), "The disconnected ID cannot restore the room")
	_check(room.join("other", "乙", "current-connection", 12).is_empty(), "The disconnected ID cannot join a fresh seat")
	_check(room.resume(instance_id, "player", token, "fresh-connection", 300009).get("seat") == ticket.seat, "Fresh ID and original token can recover before expiry")
	_check(room.is_open(300010), "A successful fresh recovery clears the previous deadline")
	_check(room.disconnect_human("fresh-connection", 300020), "Another final disconnection starts a new interval")
	_check(room.resume(instance_id, "player", token, "fresh-connection", 600019).is_empty(), "Repeating the newest retired ID cannot clear the new deadline")
	_check(room.join("other", "乙", "old-connection", 600019).is_empty(), "An earlier retired ID still cannot join")
	_check(room.is_open(600019) and not room.is_open(600020), "Replays never extend the five-minute empty interval")
