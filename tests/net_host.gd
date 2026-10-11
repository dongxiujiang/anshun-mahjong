extends SceneTree
## 联机传输测试·主机：全AI打到底，广播同步；客户端回执后退出。
## 需与 net_client.gd 配对运行（先主机后客户端）。

func _initialize() -> void:
	_run()

func _run() -> void:
	var net := NetGameNode.new()
	net.name = "Net"
	root.add_child(net)
	net.host(true, true, 7510)
	print("[host] 主机启动，等待客户端 2 秒后开局")
	await create_timer(2.0).timeout
	net.start_net_game()
	print("[host] 本局进行中/已结算")
	var elapsed := 0.0
	while not net.ack_flag and elapsed < 25.0:
		await process_frame
		elapsed += 0.016
	if net.ack_flag:
		print("[host] 收到客户端回执: ", net.ack_text)
		quit(0)
	print("[host] 超时未收到回执")
	quit(1)