extends SceneTree

const Main := preload("res://scenes/Main.tscn")
const Settings := preload("res://src/app/AppSettings.gd")
const Client := preload("res://src/network/GameClient.gd")
const Bar := preload("res://src/app/StatusTelemetryBar.gd")
const Round := preload("res://src/domain/Round.gd")
const Catalog := preload("res://src/domain/TileCatalog.gd")
const Retire := preload("res://tests/AudioRetirement.gd")

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL telemetry: " + note)


func _run() -> void:
	# 1. Pure formatting & color tier checks
	var lan_fast := Bar.format_network({"active": true, "mode": "online", "state": "connected", "rtt_ms": 8})
	check(lan_fast.text == "服务器 8ms" and lan_fast.color == Bar.COLOR_GOOD, "low latency formatting and green tier")
	var srv_med := Bar.format_network({"active": true, "mode": "online", "state": "connected", "rtt_ms": 95})
	check(srv_med.text == "服务器 95ms" and srv_med.color == Bar.COLOR_WARN, "Online medium latency formatting and gold tier")
	var srv_high := Bar.format_network({"active": true, "mode": "online", "state": "connected", "rtt_ms": 210})
	check(srv_high.text == "服务器 210ms" and srv_high.color == Bar.COLOR_BAD, "Online high latency formatting and red tier")
	var srv_conn := Bar.format_network({"active": true, "mode": "online", "state": "connecting", "rtt_ms": -1})
	check(srv_conn.text == "服务器 连接中" and srv_conn.color == Bar.COLOR_WARN, "Connecting state formatting")
	var lan_rec := Bar.format_network({"active": true, "mode": "online", "state": "reconnecting", "rtt_ms": -1})
	check(lan_rec.text == "服务器 重连中" and lan_rec.color == Bar.COLOR_RECONNECT, "Reconnecting state formatting")
	var srv_disc := Bar.format_network({"active": true, "mode": "online", "state": "disconnected", "rtt_ms": -1})
	check(srv_disc.text == "服务器 已断开" and srv_disc.color == Bar.COLOR_DISCONNECTED, "Disconnected state formatting")

	# 2. Live ENet RTT measurement via GameClient.connection_metrics()
	var client := Client.new()
	root.add_child(client)
	check(not client.connection_metrics().active, "Idle client reports inactive network metrics")
	var authority := Client.new()
	root.add_child(authority)
	check(authority.start_server("8866", 0), "independent authority starts for RTT test")
	check(client.connect_room("127.0.0.1", authority.local_port, {"nickname":"测延迟", "player_id":"telemetry-player", "room_number":"8866"}), "online client connects")
	var got_rtt := false
	for _step in 30:
		await create_timer(0.05).timeout
		var m := client.connection_metrics()
		if m.active and m.mode == "online" and m.state == "connected" and int(m.rtt_ms) >= 0:
			got_rtt = true
			break
	check(got_rtt, "Live ENet peer reports a measured RTT, including sub-ms loopback rounding to zero")
	client._reset()
	authority._reset()
	authority.queue_free()
	client.queue_free()

	# 3. Main HUD visibility & multi-resolution zero-overlap geometry check
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var cfg := "user://telemetry-test-%d.cfg" % Time.get_ticks_usec()
	var app := Main.instantiate()
	app.table_play_only = true
	app._settings = Settings.new(cfg)
	app._settings.save_profile("遥测玩家", 2)
	viewport.add_child(app)
	for _i in 6:
		await process_frame

	check(not app._telemetry_bar.visible, "Telemetry bar stays hidden on lobby/connect screen")

	var rs := Round.new()
	rs.start(0, 4, 2, Catalog.values(541))
	rs.begin_dealer_turn()
	var snap := rs.snapshot_for(0)
	var members := []
	for seat in 4:
		members.append({"nickname": ["遥测玩家", "贵阳老友", "花溪雀友", "屯堡牌王"][seat], "score": 200, "ai_id": -1, "connected": true, "player_id": "t-" + str(seat), "avatar": seat + 1})
	app._mode = "solo"
	app._round_projection = snap
	app._view = {"seat": 0, "room": {"room_instance_id": "tel", "round_number": 1, "seats": members, "mode": "solo"}, "round": snap}
	app._table.viewer = 0
	app._table.apply_view(snap)
	app._show("play")
	app._refresh_hud()
	for _i in 4:
		await process_frame

	check(app._telemetry_bar.visible, "Telemetry bar is visible during play")
	check(app._telemetry_bar._fps_label.text.ends_with(" FPS"), "Telemetry bar renders FPS text")
	check(not app._telemetry_bar._net_row.visible, "Solo mode hides network latency row")

	# Simulate online server active telemetry across all 4 target resolutions
	app._telemetry_bar.configure(true, func(): return {"active": true, "mode": "online", "state": "connected", "rtt_ms": 34})
	for res in [Vector2i(1280, 720), Vector2i(1600, 1000), Vector2i(1602, 720), Vector2i(2670, 1200)]:
		viewport.size = res
		app.size = Vector2(res)
		for _i in 4:
			await process_frame
		app._telemetry_bar.refresh_now()
		for _i in 2:
			await process_frame
		var bar_rect: Rect2 = app._telemetry_bar.get_global_rect()
		var safe_rect: Rect2 = app._safe.get_global_rect()
		var top_badge_rect: Rect2 = app._identities[2].get_global_rect()
		var right_badge_rect: Rect2 = app._identities[1].get_global_rect()
		check(app._telemetry_bar._net_row.visible and app._telemetry_bar._net_label.text == "服务器 34ms", "Online label renders at %s" % [res])
		check(safe_rect.grow(1.0).encloses(bar_rect), "Telemetry bar stays inside safe area at %s (bar=%s safe=%s)" % [res, bar_rect, safe_rect])
		check(not bar_rect.grow(2.0).intersects(top_badge_rect), "Telemetry bar never touches top player badge at %s (bar=%s top=%s)" % [res, bar_rect, top_badge_rect])
		check(not bar_rect.grow(2.0).intersects(right_badge_rect), "Telemetry bar never touches right player badge at %s (bar=%s right=%s)" % [res, bar_rect, right_badge_rect])
		if res.x < 1360:
			check(app._telemetry_bar._compact_layout, "Narrow viewport %s uses compact 2-line telemetry stack" % [res])
		else:
			check(not app._telemetry_bar._compact_layout, "Wide viewport %s uses single-line telemetry bar" % [res])

	await Retire.release_app(app, self)
	viewport.free()
	DirAccess.remove_absolute(cfg)
	print("Telemetry bar: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
