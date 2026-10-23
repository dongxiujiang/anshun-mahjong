extends SceneTree
## Regression for the empty-seat/background and stale vote races in NetGameNode.
const H := preload("res://tests/test_harness.gd")
var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _new_net() -> NetGameNode:
	var net := NetGameNode.new()
	net.name = "LobbySafetyNet"
	root.add_child(net)
	net.host_mode = true
	net.game = RoundState.new()
	net._started = false
	net._owner_peer = 1
	return net

func _run() -> void:
	var net := _new_net()
	net._members = {2: {"name": "guest", "ready": true, "wants_dealer": false, "resume_token": ""}}
	net._peer_seat = {2: 1}
	net._seat_peer = {0: -1, 1: 2, 2: -1, 3: -1}
	net._ctrl_hint = {0: "auto", 1: "remote", 2: "auto", 3: "auto"}
	net._on_peer_disconnected(2)
	t.expect(net._ctrl_hint[1] == "auto", "explicit lobby leave hands the empty seat to AI")
	t.expect(net._seat_peer[1] == -1, "explicit leave clears the peer binding")

	# Defensive controller assignment: a seat without a peer is AI even when a
	# stale hint says remote.
	net._started = false
	net._members = {1: {"name": "host", "ready": true, "wants_dealer": false, "resume_token": ""}}
	net._seat_peer = {0: 1, 1: -1, 2: -1, 3: -1}
	net._peer_seat = {1: 0}
	net._ctrl_hint = {0: "remote", 1: "remote", 2: "remote", 3: "remote"}
	t.expect(net.start_net_game(20261022), "lobby can start with an empty AI-filled seat")
	t.expect(net.game.controllers[1] is AiPlayer, "empty seat gets an AI controller at start")
	net.queue_free()
	await process_frame

	# A cancelled return-to-lobby vote must not accept a stale auto-yes.
	var vote := _new_net()
	vote._return_vote_active = false
	vote._background_vote_pending = {2: Time.get_ticks_msec() - 1}
	vote._return_vote_yes = {}
	vote._process(0.0)
	t.expect(not vote._return_vote_yes.has(2), "cancelled vote timer cannot add a yes")
	vote.queue_free()
	await process_frame

	# AI candidate pool must exclude the tile just claimed by pong.
	var round := RoundState.new()
	round.build_players(0)
	round.phase = RoundState.Phase.PLAYING
	round.current_turn = 0
	round.awaiting = true
	round.wall = WallRing.new(TileSetFactory.create_deck())
	round.wall.set_head(0)
	round.players[0].concealed = ["wan1", "wan2", "wan3", "tiao1", "tiao2", "tiao3", "tong1", "tong2", "tong3", "wan8", "wan9"]
	round.players[0].just_drew = "wan9"
	round.players[0].forbidden_discard_tile = "wan1"
	round.players[0].first_turn_done = true
	round.players[0].melds = [{"kind": "pung", "tile": "wan1", "from_seat": 1, "after_discard": 0}]
	var ai := AiPlayer.new()
	var decision: Dictionary = ai.decide_turn(round, 0)
	t.expect(str(decision.get("discard", "")) != "wan1", "AI never chooses the just-claimed forbidden tile")
	t.expect(round.legal_turn_options(0).discards.has(str(decision.get("discard", ""))), "AI discard is legal")
	await H.quit_cleanly(self, t.finish("lobby_safety"))
