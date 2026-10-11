extends Node
## 联机传输测试·主机（正式场景启动，多人网络可用）

func _ready() -> void:
	_run()

func _run() -> void:
	var net := NetGameNode.new()
	net.name = "Net"
	add_child(net)
	net.host(true, true, 7510)
	print("[host] 主机启动，等待客户端 2 秒后开局")
	await get_tree().create_timer(2.0).timeout
	net.start_net_game()
	print("[host] 本局进行中/已结算")
	var t := 0.0
	while not net.ack_flag and t < 25.0:
		await get_tree().process_frame
		t += 0.016
	if net.ack_flag:
		print("[host] 收到客户端回执: ", net.ack_text)
		print("[host] 通过")
		get_tree().quit(0)
	else:
		print("[host] 超时未收到回执")
		get_tree().quit(1)