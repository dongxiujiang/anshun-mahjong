extends SceneTree
## 房主主动退出后，剩余真人必须接任房主。

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var net := NetGameNode.new()
	net.name = "HostTransferNet"
	root.add_child(net)
	net.room_number = "654321"
	net.host_mode = true
	net._owner_peer = 1
	net._members = {
		1: {"name": "房主", "ready": false, "wants_dealer": false, "resume_token": ""},
		2: {"name": "客人", "ready": false, "wants_dealer": false, "resume_token": ""},
	}
	net._peer_seat = {1: 0, 2: 1}
	net._seat_peer = {0: 1, 1: 2, 2: -1, 3: -1}
	net._ctrl_hint = {0: "remote", 1: "remote", 2: "auto", 3: "auto"}
	net._on_peer_disconnected(1)
	var ok: bool = net._owner_peer == 2 and not net._members.has(1) and not net._peer_seat.has(1)
	ok = ok and int(net.lobby.get("owner", -1)) == 2
	var reconnect := NetGameNode.new()
	reconnect.name = "OwnerReservationNet"
	root.add_child(reconnect)
	reconnect.room_number = "654322"
	reconnect.host_mode = true
	reconnect._owner_peer = 1
	reconnect._members = {
		1: {"name": "房主", "ready": false, "wants_dealer": false, "resume_token": "owner-token"},
		2: {"name": "客人", "ready": false, "wants_dealer": false, "resume_token": ""},
	}
	reconnect._peer_seat = {1: 0, 2: 1}
	reconnect._seat_peer = {0: 1, 1: 2, 2: -1, 3: -1}
	reconnect._ctrl_hint = {0: "remote", 1: "remote", 2: "auto", 3: "auto"}
	reconnect._on_peer_disconnected(1)
	ok = ok and bool(reconnect._orphaned[0].get("owner", false))
	reconnect._orphaned[0]["until"] = 0
	reconnect._process(0)
	ok = ok and reconnect._owner_peer == 2
	reconnect.queue_free()
	net.queue_free()
	await process_frame
	print("[host_transfer] ", "passed" if ok else "FAILED")
	quit(0 if ok else 1)
