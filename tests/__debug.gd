extends SceneTree
func _initialize():
 var r=RoundState.new(); r.build_players(0); r.controllers=[null,null,null,null]; r.wall=WallRing.new(TileSetFactory.create_deck()); r.wall.set_head(0); r.phase=RoundState.Phase.PLAYING; r.players[0].concealed=["wan1","wan1","wan1","wan2","wan2","wan2","tong3","tong3","tong3","tiao4","tiao4","tiao4","wan9","wan9"]; r.round_meta.merge({"winner":0,"winners":[0],"self_draw":true,"win_tile":"wan9","chicken_multiplier":1},true); print(RuleEngine.analyze(r.players[0].concealed,r.players[0].melds,"wan9")); var x=ScoringEngine.settle(r); print(x); quit()
