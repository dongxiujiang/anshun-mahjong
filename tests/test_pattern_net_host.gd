extends SceneTree
## 联机测试牌型双端验证：主机端。
const PATTERNS := preload("res://scripts/core/TestPatterns.gd")

func _initialize() -> void:
	print("[host] initialize")
	call_deferred("_run")

func _mark(text: String) -> void:
	var f := FileAccess.open("res://build/pattern-net-result.txt", FileAccess.WRITE)
	if f != null: f.store_line(text); f.close()

func _run() -> void:
	print("[host] run")
	_mark("host-start")
	var net := NetGameNode.new()
	root.add_child(net)
	if not net.host(false, true, 7513, "7313", "测试牌型主机"):
		print("[host] host failed")
		quit(1)
		return
	net.set_ready(true)
	var deadline := Time.get_ticks_msec() + 12000
	while (not net.all_ready() or net._human_seats().size() < 2) and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(1.0).timeout
	if not net.start_net_game(20261026):
		print("[host] start failed")
		quit(1)
		return
	await create_timer(1.0).timeout
	net.propose_test_pattern("ready")
	deadline = Time.get_ticks_msec() + 10000
	while net.game != null and net.game.test_pattern != "ready" and Time.get_ticks_msec() < deadline:
		await process_frame
	if net.game == null or net.game.test_pattern != "ready":
		print("[host] pattern not applied")
		_mark("host-failed-pattern")
		quit(1)
		return
	await create_timer(0.5).timeout
	var hand: Array = net.game.players[0].concealed
	var expected := PATTERNS.hand("ready")
	var subset := true
	for card in expected:
		if not hand.has(card):
			subset = false
			break
	print("[host] applied pattern hand=%d expected=%d phase=%d" % [hand.size(), expected.size(), net.game.phase])
	if not subset:
		quit(1)
		return
	print("[host] passed")
	_mark("host-passed")
	quit(0)




