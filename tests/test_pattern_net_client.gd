extends SceneTree
## 联机测试牌型双端验证：客户端投票。

func _initialize() -> void:
	print("[client] initialize")
	call_deferred("_run")

func _mark(text: String) -> void:
	var f := FileAccess.open("res://build/pattern-net-result.txt", FileAccess.WRITE)
	if f != null: f.store_line(text); f.close()

func _run() -> void:
	print("[client] run")
	_mark("client-start")
	var net := NetGameNode.new()
	root.add_child(net)
	net.room_ready.connect(func(_seat): net.set_ready(true))
	net.lobby_updated.connect(func():
		var vote: Dictionary = net.lobby.get("test_vote", {})
		if vote.is_empty() or net.my_seat < 0: return
		var yes: Array = vote.get("yes", [])
		if net.my_seat in yes: return
		print("[client] voting yes for ", vote.get("pattern", ""))
		net.answer_test_vote(true))
	_mark("client-before-connect")
	if not net.client("127.0.0.1", 7513, "7313", "测试牌型客户端"):
		_mark("client-connect-failed")
		print("[client] connect failed")
		quit(1)
		return
	_mark("client-connected")
	var deadline := Time.get_ticks_msec() + 20000
	var initial_session := ""
	while Time.get_ticks_msec() < deadline:
		if net.game != null and net.game.players.size() == 4:
			if initial_session == "":
				initial_session = net.game.audio_session
			elif net.game.audio_session != initial_session:
				print("[client] observed restarted round")
				await create_timer(0.5).timeout
				print("[client] passed")
				_mark("client-passed")
				quit(0)
				return
		await process_frame
	print("[client] pattern timeout")
	quit(1)



