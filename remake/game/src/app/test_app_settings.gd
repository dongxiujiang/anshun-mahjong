extends SceneTree

const Settings := preload("res://src/app/AppSettings.gd")

var _failures := 0


func _initialize() -> void:
	var directory := "user://preferences-test-" + Crypto.new().generate_random_bytes(8).hex_encode()
	_check(DirAccess.make_dir_absolute(directory) == OK)
	var path := directory.path_join("settings.cfg")
	var settings := Settings.new(path)
	var defaults := settings.profile()
	var identity := settings.player_id()
	_check(identity.length() == 64)
	_check(not settings.profile_complete() and not Settings.new(path).profile_complete())
	_check(defaults.draw_style == "a" and defaults.suit_order == ["wan", "tiao", "tong"])
	_check(defaults.hand_priority == "multiple" and not defaults.novice and not defaults.music and not defaults.microphone)
	_check(not settings.update({"nickname": "太长的昵称不得截断", "avatar": 3}))
	_check(not settings.update({"suit_order": ["tong", "tong", "wan"]}))
	_check(not settings.update({"difficulty": "unknown"}))
	_check(settings.profile() == defaults)
	_check(settings.update({"nickname": "晚风1", "difficulty": "high", "suit_order": ["tong", "tiao", "wan"], "draw_style": "random", "novice": true}))
	_check(not settings.profile_complete() and not settings.save_profile("错误!", 5))
	var ticket := {"room_instance_id": "room-instance", "room_number": "0042", "address": "127.0.0.1",
		"port": 7600, "mode": "lan", "member_token": "local-ticket"}
	_check(settings.remember_room(ticket))
	var reopened := Settings.new(path)
	_check(reopened.player_id() == identity and reopened.remembered_room() == ticket)
	_check(not reopened.profile_complete() and reopened.save_profile("晚风1", 5))
	_check(Settings.new(path).profile_complete() and Settings.new(path).remembered_room() == ticket)
	_check(reopened.profile().nickname == "晚风1" and reopened.profile().difficulty == "high")
	_check(reopened.profile().suit_order == ["tong", "tiao", "wan"] and reopened.profile().novice)
	_check(reopened.remember_room({}) and Settings.new(path).remembered_room().is_empty())
	var old := ConfigFile.new()
	_check(old.load(path) == OK)
	old.erase_section_key("format", "profile_complete")
	_check(old.save(path) == OK and Settings.new(path).profile_complete())
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("AppSettings test failures: %d" % _failures)
	quit(_failures)


func _check(condition: bool) -> void:
	if condition:
		return
	_failures += 1
	push_error("AppSettings assertion failed")
