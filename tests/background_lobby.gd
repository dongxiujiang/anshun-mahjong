extends SceneTree
## 连接仍在、应用进入后台时，大厅快照必须继续使用 _members 中的成员信息。

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var net := NetGameNode.new()
	net.name = "BackgroundLobbyNet"
	root.add_child(net)
	net.room_number = "123456"
	net.room_name = "后台测试"
	net.host_mode = true
	net._owner_peer = 1
	net._members = {1: {"name": "后台玩家", "ready": false, "wants_dealer": false, "resume_token": "token"}}
	net._peer_seat = {1: 0}
	net._seat_peer = {0: 1, 1: -1, 2: -1, 3: -1}
	net._ctrl_hint = {0: "remote", 1: "auto", 2: "auto", 3: "auto"}
	net._background_until = {0: Time.get_ticks_msec() + 30000}
	net._publish_lobby()
	var seat: Dictionary = net.lobby.get("seats", [])[0] if net.lobby.get("seats", []).size() > 0 else {}
	var ok: bool = not seat.is_empty() and str(seat.get("name", "")) == "后台玩家" and bool(seat.get("disconnected", false))
	net.queue_free()
	await process_frame
	print("[background_lobby] ", "passed" if ok else "FAILED")
	quit(0 if ok else 1)
