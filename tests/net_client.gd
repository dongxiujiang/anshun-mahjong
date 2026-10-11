extends SceneTree
## 联机传输测试·客户端：连接主机，接收结算同步，回执并退出。

const H := preload("res://tests/test_harness.gd")

var t := H.new()

func _initialize() -> void:
	_run()

func _run() -> void:
	var net := NetGameNode.new()
	net.name = "Net"
	root.add_child(net)
	net.client("127.0.0.1", 7510)
	print("[client] 尝试连接主机 7510 ...")
	var elapsed := 0.0
	while elapsed < 20.0:
		await process_frame
		elapsed += 0.016
		if net.game != null and net.game.phase == "settled":
			print("[client] 收到结算同步 winner=%d 牌守恒=%s" % [net.game.round_meta.winner, str(_conserved(net.game))])
			t.expect(_conserved(net.game), "客户端渲染牌应守恒")
			net.rpc_id(1, "ack", "settled-ok winner=%d" % net.game.round_meta.winner)
			await create_timer(0.6).timeout
			quit(t.finish("net_client"))
			return
	t.expect(false, "20 秒内未收到结算同步")
	quit(t.finish("net_client"))

func _conserved(r) -> bool:
	var n := 0
	for ps in r.players:
		n += ps.concealed.size() + ps.discards.size()
		for m in ps.melds:
			n += 3 if m.kind == "pung" else 4
	for s in 4:
		n += int(r.wall_remain.get(s, 0))
	return n == 108