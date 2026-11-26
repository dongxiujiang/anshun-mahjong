extends SceneTree

const Voice := preload("res://src/audio/VoiceController.gd")

class Client extends Node:
	signal view_changed(view: Dictionary)
	signal session_ended(reason: String)
	signal voice_connection_ended()
	signal voice_packet_received(packet: PackedByteArray)
	signal voice_stream_reset(seat: int)
	var view := {}
	var ticket := {"room_instance_id": "lan-a", "member_token": "private-token-not-in-preferences"}
	func waiting_for_foreground_view(): return false

	func show_view(state: Dictionary) -> void:
		view = state
		view_changed.emit(state)

var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "user://test-muted-speakers-%d.cfg" % Time.get_ticks_usec()
	var voice := Voice.new(path)
	var client := Client.new()
	root.add_child(voice);root.add_child(client)
	voice.bind_client(client)
	var errors := []
	voice.speaker_preference_failed.connect(func(message):errors.append(message))
	var me := _person("local", "自己")
	var a := _person("target-a", "同名")
	var b := _person("target-b", "同名")
	var ai := {"ai_id": 3, "player_id": "", "nickname": "人机", "connected": false}
	client.show_view(_view("lan-a", "lan", [me,a,b,ai]))
	check(voice.set_speaker_enabled(1,false,"target-a"), "name entry can mute an authenticated remote identity")
	check(not voice.speaker_enabled(1) and voice.speaker_enabled(2) and not voice._backend.speaker_enabled(1), "same-name peers have separate preferences and actual LAN playback")
	client.show_view(_view("lan-a", "lan", [me,b,a,ai]))
	check(voice.speaker_enabled(1) and not voice.speaker_enabled(2), "mute follows the person after a seat change")
	check(not voice.set_speaker_enabled(1,false,"target-a") and voice.speaker_enabled(1), "held name context cannot mute a new seat occupant")
	var renamed := a.duplicate();renamed.nickname="新名字";renamed.avatar=9
	client.show_view(_view("lan-a", "lan", [me,b,renamed,ai]))
	check(not voice.speaker_enabled(2), "profile changes do not remove the identity's mute")
	client.session_ended.emit("left");client.show_view({})
	check(not voice.speaker_enabled_for("target-a"), "leaving preserves local listening preferences")
	client.show_view(_view("online-b", "online", [me,renamed,ai,b]))
	check(not voice.speaker_enabled(1) and voice.speaker_enabled(3), "the same identity stays muted across room and mode changes")
	check(voice.set_speaker_enabled(3,false,"target-b"), "another listener preference can be changed without a live online SDK")
	var file:=ConfigFile.new()
	check(file.load(path)==OK and file.get_value("voice","muted")==PackedStringArray(["target-a","target-b"]), "disk contains only selected muted identities")
	check(not FileAccess.get_file_as_string(path).contains(client.ticket.member_token), "listening preferences never store room credentials")
	var reopened:=Voice.new(path);root.add_child(reopened);reopened.bind_client(client)
	check(not reopened.speaker_enabled(1) and not reopened.speaker_enabled(3), "a fresh controller reloads mute preferences")
	check(voice.set_speaker_enabled(1,true,"target-a") and voice.speaker_enabled(1) and not voice.speaker_enabled(3), "restoring one voice leaves another muted")
	voice._mute_path=path.path_join("unwritable.cfg")
	check(not voice.set_speaker_enabled(1,false,"target-a") and voice.speaker_enabled(1) and errors.back().contains("未能保存"), "failed persistence leaves actual listening unchanged and reports the failure")
	check(not voice.set_speaker_enabled(0,false,"local") and not voice.set_speaker_enabled(2,false), "self and AI cannot be muted through remote listening")
	for node in [voice,reopened,client]:node.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	print("Speaker settings: %d checks, %d failures" % [_checks,_failures])
	quit(1 if _failures else 0)

func _person(player_id:String,nickname:String) -> Dictionary:
	return {"player_id":player_id,"nickname":nickname,"ai_id":-1,"connected":true,"avatar":1}

func _view(instance:String,mode:String,seats:Array) -> Dictionary:
	return {"seat":0,"room":{"room_number":"1234","room_instance_id":instance,"mode":mode,"seats":seats}}

func check(ok:bool,description:String) -> void:
	_checks+=1
	if not ok:
		_failures+=1
		printerr(description)
