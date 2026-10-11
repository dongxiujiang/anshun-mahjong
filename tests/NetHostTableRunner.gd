extends Node
## 主机端 GameTable 全流程：主机当真人(seat0，测试里自动代打)，空位AI补。
## 验证 主机权威局 + GameTable 网络渲染 + 本机动作提交 能打完整局。

func _ready() -> void:
	_run()

func _run() -> void:
	var net = get_tree().root.get_node_or_null("Network")
	if net == null:
		push_error("[nethost] 应有 Network autoload")
		get_tree().quit(1)
		return
	net.start_host(false, true, 7511)  # 主机本人可操作(seat0=human)，空位AI
	net.net_node.set_ready(true)
	net.net_node.start_net_game(1000)
	var table = load("res://scenes/GameTable.tscn").instantiate()
	add_child(table)
	await get_tree().process_frame
	var elapsed := 0.0
	while elapsed < 25.0:
		await get_tree().process_frame
		elapsed += 0.016
		var r = table.round
		if r == null: continue
		if r.phase == "settled":
			print("[nethost] 结算 winner=%d 牌守恒=%s deltas=%s" % [r.round_meta.winner, str(_conserved(r)), str(r.last_result.deltas)])
			if not _conserved(r):
				push_error("[nethost] 牌应守恒")
				get_tree().quit(1)
				return
			print("[nethost] 通过")
			get_tree().quit(0); return
		if r.awaiting:
			if not r._awaiting_response.is_empty() and r._awaiting_response.seat == 0:
				r.submit_response(0, r._awaiting_response.tile, {"action": "pass"})
			elif r._awaiting_response.is_empty() and r.current_turn == 0:
				r.submit_turn(0, _decide(r.players[0]))
	print("[nethost] 超时")
	get_tree().quit(1)

func _decide(ps) -> Dictionary:
	if RuleEngine.analyze(ps.concealed, ps.melds).win:
		return {"self_win": true}
	var best: String = ps.concealed[0]
	var bs := 99
	for t in ps.concealed.duplicate():
		var trial: Array = ps.concealed.duplicate()
		trial.erase(t)
		var sh := Shanten.shanten(trial, ps.melds)
		if sh < bs:
			bs = sh; best = t
	return {"discard": best, "kong_declares": [], "add_kong": [], "ready": false, "self_win": false}

func _conserved(r) -> bool:
	var n := 0
	for ps in r.players:
		n += ps.concealed.size() + ps.discards.size()
		for m in ps.melds:
			n += 3 if m.kind == "pung" else 4
	n += r.wall.remaining
	return n == 108
