extends RefCounted

const Room := preload("res://src/session/RoomSession.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")
const VoicePacks := preload("res://src/audio/VoicePacks.gd")
const TableTheme := preload("res://src/presentation/TableTheme.gd")
const DEFAULTS := {
	"nickname": "牌友",
	"avatar": 1,
	"draw_style": "a",
	"suit_order": ["wan", "tiao", "tong"],
	"hand_priority": "multiple",
	"novice": false,
	"teaching_enabled": false,
	"smart_hints": true,
	"table_theme": "jade_classic",
	"tile_back": "jade",
	"music": false,
	"microphone": false,
	"voice_enabled": true,
	"voice_pack": "luoxiaohei",
	"effects_enabled": true,
	"music_volume": 0.8,
	"voice_volume": 0.8,
	"effects_volume": 0.8,
	"microphone_gain": 0.8,
	"speaker_gain": 0.8,
	"difficulty": "low",
	"quality": "detail",
	"power_save": false,
	"quality_manual": false,
	"directory_url": "",
	"update_manifest_url": "",
	"discard_seconds": 10,
	"response_seconds": 5,
}

var _path: String
var transient:=false
var _profile := DEFAULTS.duplicate(true)
var _player_id := ""
var _ticket := {}
var _profile_complete := false


func _init(path: String = "user://dongxiu-preferences-v1.cfg") -> void:
	_path = path
	var saved := ConfigFile.new()
	if saved.load(path) == OK and saved.get_value("format", "version", 0) == 1:
		for key in DEFAULTS:
			var value = saved.get_value("profile", key, DEFAULTS[key])
			if _valid(key, value):
				_profile[key] = value
		var identity = saved.get_value("private", "player_id", "")
		if identity is String and identity.length() == 64 and identity.is_valid_hex_number():
			_player_id = identity
		var ticket = saved.get_value("private", "resume", {})
		if ticket is Dictionary and _valid_ticket(ticket):
			_ticket = ticket
		var previously_set: bool = not _ticket.is_empty() or _profile.nickname != DEFAULTS.nickname or _profile.avatar != DEFAULTS.avatar
		_profile_complete = saved.get_value("format", "profile_complete", previously_set) == true
	if _player_id.is_empty():
		_ticket.clear()
		_player_id = Crypto.new().generate_random_bytes(32).hex_encode()
		_write(_profile, _ticket, _profile_complete)


func profile() -> Dictionary:
	return _profile.duplicate(true)


func player_id() -> String:
	return _player_id


func profile_complete() -> bool:
	return _profile_complete


func save_profile(nickname: String, avatar: int) -> bool:
	if not _valid("nickname", nickname) or not _valid("avatar", avatar):
		return false
	var next := _profile.duplicate(true)
	next.merge({"nickname": nickname, "avatar": avatar}, true)
	if not _write(next, _ticket, true):
		return false
	_profile = next
	_profile_complete = true
	return true


func update(changes: Dictionary) -> bool:
	var next := _profile.duplicate(true)
	for key in changes:
		if not key is String or not _valid(key, changes[key]):
			return false
		next[key] = changes[key]
	if not _write(next, _ticket, _profile_complete):
		return false
	_profile = next.duplicate(true)
	return true


func remember_room(ticket: Dictionary) -> bool:
	if not _valid_ticket(ticket) or not _write(_profile, ticket, _profile_complete):
		return false
	_ticket = ticket.duplicate(true)
	return true


func remembered_room() -> Dictionary:
	return _ticket.duplicate(true)


func _write(profile_values: Dictionary, ticket: Dictionary, profile_complete: bool) -> bool:
	if transient:return true
	if _player_id.is_empty():
		return false
	var file := ConfigFile.new()
	file.set_value("format", "version", 1)
	file.set_value("format", "profile_complete", profile_complete)
	for key in profile_values:
		file.set_value("profile", key, profile_values[key])
	file.set_value("private", "player_id", _player_id)
	file.set_value("private", "resume", ticket)
	var temporary := _path + ".tmp"
	if file.save(temporary) != OK:
		return false
	if DirAccess.rename_absolute(temporary, _path) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return true


static func _valid(key: String, value) -> bool:
	match key:
		"nickname":
			return value is String and Room.is_valid_nickname(value)
		"avatar":
			return value is int and value in range(1, VoicePacks.ORDER.size()+1)
		"draw_style":
			return value in ["a", "b", "random"]
		"suit_order":
			return value is Array and value.size() == 3 and Catalog.SUITS.all(func(suit): return value.has(suit))
		"hand_priority":
			return value in ["multiple", "pattern"]
		"novice", "music", "microphone", "voice_enabled", "effects_enabled", "teaching_enabled", "smart_hints", "power_save", "quality_manual":
			return value is bool
		"table_theme":
			return value is String and TableTheme.TABLE_THEMES.has(value)
		"tile_back":
			return value is String and TableTheme.TILE_BACKS.has(value)
		"music_volume", "voice_volume", "effects_volume", "microphone_gain", "speaker_gain":
			return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= 0.0 and value <= 1.0
		"voice_pack":
			return value is String and VoicePacks.ORDER.has(value)
		"difficulty":
			return value in ["low", "medium", "high"]
		"quality":
			return value in ["smooth", "detail"]
		"directory_url", "update_manifest_url":
			return value is String and value.length() <= 320
		"discard_seconds", "response_seconds":
			return value is int and value >= 1 and value <= 120
	return false


static func _valid_ticket(ticket: Dictionary) -> bool:
	if ticket.is_empty():
		return true
	for key in ["room_instance_id", "room_number", "member_token", "address", "mode"]:
		if not ticket.get(key) is String or ticket[key].is_empty():
			return false
	if ticket.has("directory_url") and not _valid("directory_url", ticket.directory_url):
		return false
	var port = ticket.get("port")
	return ticket.mode == "online" and port is int and port > 0 and port <= 65535
