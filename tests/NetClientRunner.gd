extends Node
## 联机传输测试·客户端

func _ready() -> void:
	_run()

func _run() -> void:
	var net := NetGameNode.new()
	net.name = "Net"
	add_child(net)
	net.room_ready.connect(func(_seat): net.set_ready(true))
	net.client("127.0.0.1", 7510)
	print("[client] 尝试连接主机 7510 ...")
	var t := 0.0
	while t < 20.0:
		await get_tree().process_frame
		t += 0.016
		if net.game != null and net.game.phase == RoundState.Phase.SETTLED:
			print("[client] 收到结算同步 winner=%d 牌守恒=%s" % [net.game.round_meta.winner, str(_conserved(net.game))])
			if not _conserved(net.game):
				push_error("[client] 客户端渲染牌应守恒")
				get_tree().quit(1)
				return
			net.rpc_id(1, "ack", "settled-ok winner=%d" % net.game.round_meta.winner)
			await get_tree().create_timer(0.6).timeout
			print("[client] 通过")
			get_tree().quit(0)
			return
		if net.game.awaiting:
			var actor := AiPlayer.new("client test")
			if net.game._awaiting_response.get("seat", -1) == net.my_seat:
				var request: Dictionary = net.game._awaiting_response
				net.submit_client_response(request.tile, actor.decide_response(net.game, net.my_seat, request.disc_seat, request.tile, request.options))
				net.game.awaiting = false
			elif net.game.current_turn == net.my_seat and net.game.phase == RoundState.Phase.PLAYING:
				net.submit_client_turn(actor.decide_turn(net.game, net.my_seat))
				net.game.awaiting = false
	print("[client] 超时未收到结算同步")
	get_tree().quit(1)

func _conserved(r) -> bool:
	var n := 0
	for ps in r.players:
		n += ps.concealed.size() + ps.discards.size()
		for m in ps.melds:
			n += 3 if m.kind == "pung" else 4
	for s in 4:
		n += int(r.wall_remain.get(s, 0))
	return n == 108
