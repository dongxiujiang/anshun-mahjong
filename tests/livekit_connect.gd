extends SceneTree
## Manual integration probe: joins the test room through the real Nginx path.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var http := HTTPRequest.new()
	root.add_child(http)
	var err := http.request("https://mj.dongxiu.fun/livekit-token?room=9999&identity=seat3&name=probe")
	if err != OK:
		print("token request error=", err)
		quit(2)
		return
	var result = await http.request_completed
	print("token result=", result[0], " code=", result[1])
	if result[1] != 200:
		print("body=", result[3].get_string_from_utf8())
		quit(3)
		return
	var data = JSON.parse_string(result[3].get_string_from_utf8())
	var room := LiveKitRoom.new()
	var connected := [false]
	room.connected.connect(func(): connected[0] = true; print("LIVEKIT_CONNECTED"))
	room.connection_failed.connect(func(error): print("LIVEKIT_FAILED=", error))
	room.connect_to_room(str(data.get("url", "")), str(data.get("token", "")), {})
	for i in 100:
		await create_timer(0.1).timeout
		if connected[0]:
			break
	print("connected=", connected[0], " state=", room.get_connection_state())
	room.disconnect_from_room()
	await create_timer(0.5).timeout
	quit(0 if connected[0] else 4)
