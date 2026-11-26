extends RefCounted

enum Phase { FIRST_PREPARATION, IN_ROUND, BETWEEN_ROUNDS }

const Packs := preload("res://src/audio/VoicePacks.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")
const MahjongNames := preload("res://src/domain/MahjongNames.gd")
const ROOM_GRACE_MS: int = 5 * 60 * 1000
const INITIAL_SCORE: int = 200
const SEAT_ORDER: Array[int] = [1, 0, 3, 2] # South, east, north, west.
const _TOKEN_BYTES: int = 32

var _room_number: String
var _room_instance_id: String
var _seats: Array[Dictionary] = []
var _retired_connections: Dictionary[String, bool] = {}
var _auto_play_connections := {}
var _phase: Phase = Phase.FIRST_PREPARATION
var _round_number: int = 0
var _dealer_seat: int = -1
var _next_dealer_seat: int = -1
var _close_at_ms: int = -1
var _closed: bool = false
var _crypto := Crypto.new()
var _owner_player_id := ""
var _owner_token_hash := PackedByteArray()


func _init(room_number: String) -> void:
	_room_number = room_number
	_room_instance_id = _crypto.generate_random_bytes(_TOKEN_BYTES).hex_encode()
	_closed = _room_instance_id.is_empty()
	var ai_names := MahjongNames.pick_unique(4)
	for seat in 4:
		_seats.append(_ai_seat(seat, INITIAL_SCORE, ai_names[seat]))


static func _ai_seat(seat: int, score: int = INITIAL_SCORE, nickname: String = "") -> Dictionary:
	var chosen := nickname if not nickname.is_empty() else MahjongNames.pick_one()
	return {
			"ai_id": seat,
			"player_id": "",
			"nickname": chosen,
			"avatar": 1,
			"voice_pack": Packs.ORDER[seat],
			"suit_order": Catalog.SUITS,
			"hand_priority": "multiple",
			"novice": false,
			"score": score,
			"ready": false,
			"connection_id": "",
			"token_hash": PackedByteArray(),
		}


func _seat_nicknames(skip_seat: int = -1) -> Array:
	var used := []
	for idx in _seats.size():
		if idx == skip_seat:
			continue
		var nick := str(_seats[idx].get("nickname", ""))
		if not nick.is_empty():
			used.append(nick)
	return used


func _dedupe_ai_nicknames() -> void:
	var seen := {}
	for occupant in _seats:
		if int(occupant.get("ai_id", -1)) < 0:
			var human_nick := str(occupant.get("nickname", ""))
			if not human_nick.is_empty():
				seen[human_nick] = true
	for occupant in _seats:
		if int(occupant.get("ai_id", -1)) >= 0:
			var nick := str(occupant.get("nickname", ""))
			if nick.is_empty() or seen.has(nick):
				nick = MahjongNames.pick_one(seen.keys())
				occupant.nickname = nick
			seen[nick] = true


static func is_valid_nickname(nickname: String) -> bool:
	var pattern := RegEx.create_from_string(
		"\\A(?:(?=[\\p{Han}\\p{Latin}])\\p{L}|\\p{Nd}|〇){1,6}\\z"
	)
	return pattern.search(nickname) != null


# The authority supplies monotonic milliseconds and a unique ID per connection.
func is_open(now_ms: int) -> bool:
	if _close_at_ms >= 0 and now_ms >= _close_at_ms:
		_closed = true
	return not _closed


func seat_for_connection(connection_id: String, now_ms: int) -> int:
	if not is_open(now_ms):
		return -1
	return _find_seat("connection_id", connection_id)


# A new member takes control of an AI seat's current account. Send the ticket only to its member.
func reserve_owner(token_hash: PackedByteArray) -> void:
	_owner_token_hash = token_hash.duplicate()


func join(player_id: String, nickname: String, connection_id: String, now_ms: int, profile: Dictionary = {}, owner_token: String = "", requested_seat: int = -1) -> Dictionary:
	if not is_open(now_ms):
		return {}
	if player_id.is_empty() or _find_seat("player_id", player_id) != -1:
		return {}
	if requested_seat != -1 and not _valid_seat(requested_seat):
		return {}
	if connection_id.is_empty() or _retired_connections.has(connection_id) or _find_seat("connection_id", connection_id) != -1:
		return {}
	profile = profile.duplicate(true)
	profile.nickname = nickname
	profile.merge({"avatar": 1, "voice_pack": Packs.DEFAULT})
	if not _valid_profile(profile):
		return {}
	var claiming := not owner_token.is_empty()
	if claiming and (_owner_token_hash.is_empty() or not _crypto.constant_time_compare(_owner_token_hash, owner_token.sha256_buffer())):
		return {}
	for seat in SEAT_ORDER:
		if requested_seat != -1 and seat != requested_seat:
			continue
		if not _owner_token_hash.is_empty() and ((claiming and seat != 1) or (not claiming and seat == 1)):
			continue
		var occupant := _seats[seat]
		if not occupant.player_id.is_empty():
			continue
		var token := _crypto.generate_random_bytes(_TOKEN_BYTES).hex_encode()
		if token.is_empty():
			return {}
		var replaced_ai_id: int = occupant.ai_id
		occupant.ai_id = -1
		occupant.player_id = player_id
		occupant.merge(profile, true)
		occupant.connection_id = connection_id
		occupant.token_hash = token.sha256_buffer()
		_dedupe_ai_nicknames()
		if claiming:
			_owner_token_hash.clear()
			_owner_player_id = player_id
		elif _owner_player_id.is_empty() and _owner_token_hash.is_empty():
			_owner_player_id = player_id
		_close_at_ms = -1
		return {
			"joined": true,
			"room_number": _room_number,
			"room_instance_id": _room_instance_id,
			"seat": seat,
			"player_id": player_id,
			"member_token": token,
			"replaced_ai_id": replaced_ai_id,
		}
	return {}


func disconnect_human(connection_id: String, now_ms: int) -> bool:
	if not is_open(now_ms):
		return false
	var seat := _find_seat("connection_id", connection_id)
	if seat == -1:
		return false
	_retired_connections[connection_id] = true
	_auto_play_connections.erase(connection_id)
	_seats[seat].connection_id = ""
	_seats[seat].ready = false
	if _seats[seat].player_id == _owner_player_id:
		_transfer_owner(seat)
	for occupant in _seats:
		if not occupant.connection_id.is_empty():
			return true
	_close_at_ms = now_ms + ROOM_GRACE_MS
	return true


func _transfer_owner(from_seat: int) -> void:
	_owner_player_id = ""
	for step in range(1, 4):
		var seat := posmod(from_seat - step, 4)
		if not _seats[seat].connection_id.is_empty():
			_owner_player_id = _seats[seat].player_id
			return


func leave_human(connection_id: String, now_ms: int) -> bool:
	var seat := seat_for_connection(connection_id, now_ms)
	if seat < 0 or not disconnect_human(connection_id, now_ms):
		return false
	var score: int = _seats[seat].score
	_seats[seat] = _ai_seat(seat, score, MahjongNames.pick_one(_seat_nicknames(seat)))
	if _seats.all(func(occupant): return occupant.player_id.is_empty()):
		_closed = true
	return true


func recoverable_seat(instance_id: String, player_id: String, token: String, now_ms: int) -> int:
	if not is_open(now_ms) or instance_id != _room_instance_id or token.length() != _TOKEN_BYTES * 2:
		return -1
	var seat := _find_seat("player_id", player_id)
	if seat == -1 or not _crypto.constant_time_compare(_seats[seat].token_hash, token.sha256_buffer()):
		return -1
	return seat


func resume(instance_id: String, player_id: String, token: String, connection_id: String, now_ms: int, profile: Dictionary = {}) -> Dictionary:
	var seat := recoverable_seat(instance_id, player_id, token, now_ms)
	if seat == -1 or connection_id.is_empty() or _retired_connections.has(connection_id) or not _valid_profile(profile):
		return {}
	var connected_seat := _find_seat("connection_id", connection_id)
	if connected_seat != -1 and connected_seat != seat:
		return {}
	if connected_seat == -1:
		var previous_id: String = _seats[seat].connection_id
		if not previous_id.is_empty():
			_retired_connections[previous_id] = true
			_auto_play_connections.erase(previous_id)
		_seats[seat].connection_id = connection_id
		_close_at_ms = -1
		_seats[seat].merge(profile.duplicate(true), true)
		if _owner_player_id.is_empty() and _owner_token_hash.is_empty():
			_owner_player_id = player_id
	var state := snapshot(now_ms)
	state["seat"] = seat
	return state


# -1 rejects the request, 0 is unchanged, and 1 publishes a new profile.
func set_player_profile(connection_id: String, profile: Dictionary, now_ms: int) -> int:
	var seat := seat_for_connection(connection_id, now_ms)
	if seat == -1 or not _valid_profile(profile):
		return -1
	var occupant := _seats[seat]
	for key in ["nickname", "avatar"]:
		if profile.has(key) and profile[key] != occupant[key]:
			return -1
	for key in profile:
		if profile[key] != occupant[key]:
			occupant.merge(profile.duplicate(true), true)
			return 1
	return 0


static func _valid_profile(profile: Dictionary) -> bool:
	for key in profile:
		var value: Variant = profile[key]
		match key:
			"nickname":
				if not value is String or not is_valid_nickname(value): return false
			"avatar":
				if not value is int or value < 1 or value > Packs.ORDER.size(): return false
			"voice_pack":
				if not value is String or not Packs.ORDER.has(value): return false
			"suit_order":
				if not value is Array or value.size() != Catalog.SUITS.size() or not Catalog.SUITS.all(func(suit): return value.has(suit)): return false
			"hand_priority":
				if not value is String or value not in ["multiple", "pattern"]: return false
			"novice":
				if not value is bool: return false
			_:
				return false
	return true


func hand_preferences(seat: int) -> Dictionary:
	var occupant := _seats[seat]
	return {"suit_order": occupant.suit_order.duplicate(), "hand_priority": occupant.hand_priority,
		"novice": occupant.novice}


# A grant belongs to the authenticated connection and the round named by its request.
func set_auto_play(connection_id: String, instance: String, number: int, enabled: bool, now_ms: int) -> int:
	if _phase != Phase.IN_ROUND or instance != _room_instance_id or number != _round_number or seat_for_connection(connection_id, now_ms) < 0:
		return -1
	if _auto_play_connections.has(connection_id) == enabled:
		return 0
	if enabled:
		_auto_play_connections[connection_id] = true
	else:
		_auto_play_connections.erase(connection_id)
	return 1


func set_ready(connection_id: String, ready: bool, now_ms: int) -> bool:
	if not is_open(now_ms) or _phase == Phase.IN_ROUND:
		return false
	var seat := _find_seat("connection_id", connection_id)
	if seat == -1:
		return false
	_seats[seat].ready = ready
	return true


func move_to_empty_seat(connection_id: String, destination: int, now_ms: int) -> bool:
	if not is_open(now_ms) or _phase == Phase.IN_ROUND or not _valid_seat(destination):
		return false
	var source := _find_seat("connection_id", connection_id)
	if source == -1 or not _seats[destination].player_id.is_empty():
		return false
	var ai := _seats[destination]
	_seats[destination] = _seats[source]
	_seats[source] = ai
	if _next_dealer_seat == source:
		_next_dealer_seat = destination
	elif _next_dealer_seat == destination:
		_next_dealer_seat = source
	return true


func start_round(now_ms: int, first_dealer_seat: int = -1) -> bool:
	if not is_open(now_ms) or _phase == Phase.IN_ROUND or not _owner_token_hash.is_empty():
		return false
	var dealer := first_dealer_seat if _phase == Phase.FIRST_PREPARATION else _next_dealer_seat
	if not _valid_seat(dealer):
		return false
	var has_connected_human := false
	for occupant in _seats:
		if occupant.connection_id.is_empty():
			continue
		if not occupant.ready:
			return false
		has_connected_human = true
	if not has_connected_human:
		return false
	_round_number += 1
	_dealer_seat = dealer
	_next_dealer_seat = -1
	_phase = Phase.IN_ROUND
	return true


func finish_round(round_number: int, deltas: Array[int], next_dealer_seat: int, now_ms: int) -> bool:
	if not is_open(now_ms) or _phase != Phase.IN_ROUND or round_number != _round_number:
		return false
	if deltas.size() != 4 or not _valid_seat(next_dealer_seat):
		return false
	var balance: int = 0
	for delta in deltas:
		balance += delta
	if balance != 0:
		return false
	for seat in 4:
		_seats[seat].score += deltas[seat]
		_seats[seat].ready = false
	_dealer_seat = -1
	_next_dealer_seat = next_dealer_seat
	_phase = Phase.BETWEEN_ROUNDS
	_auto_play_connections.clear()
	return true


func snapshot(now_ms: int) -> Dictionary:
	if not is_open(now_ms):
		return {}
	var seats: Array[Dictionary] = []
	for occupant in _seats:
		seats.append({
			"ai_id": occupant.ai_id,
			"player_id": occupant.player_id,
			"nickname": occupant.nickname,
			"avatar": occupant.avatar,
			"voice_pack": occupant.voice_pack,
			"score": occupant.score,
			"ready": occupant.ready,
			"connected": not occupant.connection_id.is_empty(),
			"auto_play": _auto_play_connections.has(occupant.connection_id),
		})
	return {
		"room_number": _room_number,
		"room_instance_id": _room_instance_id,
		"owner_player_id": _owner_player_id,
		"phase": _phase,
		"round_number": _round_number,
		"dealer_seat": _dealer_seat,
		"next_dealer_seat": _next_dealer_seat,
		"seats": seats,
	}


func _find_seat(key: String, value: String) -> int:
	if not value.is_empty():
		for seat in 4:
			if _seats[seat][key] == value:
				return seat
	return -1


static func _valid_seat(seat: int) -> bool:
	return seat >= 0 and seat < 4

## Server-local authentication snapshot for the private online voice signer.
func directory_auth_state(now_ms: int) -> Dictionary:
	if not is_open(now_ms):
		return {}
	var members := []
	for seat in _seats.size():
		var member := _seats[seat]
		if not member.connection_id.is_empty():
			members.append({"seat": seat, "connected": true, "token_sha256": member.token_hash.hex_encode()})
	return {"room_instance_id": _room_instance_id, "members": members}


## 权威端全量导出：包含成员身份、累计分、庄家与关闭计时；连接 ID 属本进程，不导出。
func export_authority() -> Dictionary:
	var seats: Array = []
	for occupant in _seats:
		seats.append(occupant.duplicate(true))
		seats.back().connection_id = ""
	return {"room_number": _room_number, "room_instance_id": _room_instance_id,
		"phase": _phase, "round_number": _round_number, "dealer_seat": _dealer_seat,
		"next_dealer_seat": _next_dealer_seat, "close_at_ms": _close_at_ms, "closed": _closed,
		"owner_token_hash": _owner_token_hash.duplicate(),
		"seats": seats}


func restore_authority(state: Dictionary) -> bool:
	if state.get("seats") is not Array or state.seats.size() != 4:
		return false
	if not state.get("room_instance_id") is String or state.room_instance_id.length() < 16:
		return false
	var restored: Array[Dictionary] = []
	for row in state.seats:
		if not row is Dictionary:
			return false
		restored.append(row.duplicate(true))
	_room_number = str(state.get("room_number", ""))
	_room_instance_id = str(state.room_instance_id)
	_phase = int(state.get("phase", Phase.FIRST_PREPARATION))
	_round_number = int(state.get("round_number", 0))
	_dealer_seat = int(state.get("dealer_seat", -1))
	_next_dealer_seat = int(state.get("next_dealer_seat", -1))
	_close_at_ms = int(state.get("close_at_ms", -1))
	_closed = bool(state.get("closed", false))
	_owner_token_hash = state.get("owner_token_hash", PackedByteArray()).duplicate()
	# All transport connections must authenticate again after a process takeover.
	_owner_player_id = ""
	_seats = restored
	_retired_connections.clear()
	_auto_play_connections.clear()
	# 新进程分配新连接 ID，成员恢复经 resume() 凭 player_id + member_token 重新绑定。
	for occupant in _seats:
		occupant.connection_id = ""
	return true


## 接管后单调时钟原点不同，把 5 分钟关闭计时平移到新权威的时钟。
func rebase_close_at(delta_ms: int) -> void:
	if _close_at_ms >= 0:
		_close_at_ms += delta_ms
