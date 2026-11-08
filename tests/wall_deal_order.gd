extends SceneTree
## 骰子1、庄家南：牌墙从对家北墙隔一蹲开始，按南→东→北→西
## 每次取两蹲（4张），连续沿北→东→南→西的物理墙段推进。
const H := preload("res://tests/test_harness.gd")
const DEAL_ORDER := [1, 0, 3, 2]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var t := H.new()
	var wall := WallRing.new(TileSetFactory.create_deck(), 1)
	t.expect(WallRing.compute_break(1, 1) == 2, "庄南骰1从北墙第一蹲之后开墙")
	wall.set_head(WallRing.compute_break(1, 1))
	var groups: Array = []
	for _round in 2:
		for seat in DEAL_ORDER:
			var indexes: Array = []
			for _tile in 4:
				var before := wall.draw_log.size()
				wall.draw_head()
				indexes.append(int(wall.draw_log[before].index))
			groups.append({"seat": seat, "indexes": indexes})
	var expected := [
		[2, 3, 4, 5],
		[6, 7, 8, 9],
		[10, 11, 12, 13],
		[14, 15, 16, 17],
		[18, 19, 20, 21],
		[22, 23, 24, 25],
		[26, 27, 28, 29],
		[30, 31, 32, 33],
	]
	for index in groups.size():
		t.expect(groups[index].indexes == expected[index],
			"第%d次两蹲沿北→东墙连续推进" % (index + 1))
	for index in 8:
		t.expect(int(groups[index].seat) == DEAL_ORDER[index % 4],
			"第%d次拿牌给正确的南→东→北→西座位" % (index + 1))
	var first_stack := wall.debug_stack_counts_at(3, 0)
	t.expect(first_stack[0] == 2, "开墙前留下的一蹲仍在北墙")
	t.expect(wall.debug_stack_counts_at(3, 8)[1] == 0, "北墙第二蹲已经被取走")
	var south_wall := WallRing.new(TileSetFactory.create_deck(), 1)
	south_wall.set_head(54)  # 南墙起点，物理右端
	for _i in 4:
		south_wall.draw_head()
	var south_stacks := south_wall.wall_stack_counts(1)
	t.expect(south_stacks[0] == 2 and south_stacks[south_stacks.size() - 1] == 0,
		"南墙从右侧牌头开始，左侧仍完整")
	var north_slot := WallRing.new(TileSetFactory.create_deck(), 1)
	north_slot.set_head(0)
	north_slot.draw_head()
	var north_slots := north_slot.debug_stack_slots_at(3, 1)
	t.expect(north_slots[0] == [false, true], "北墙上层先摸、下层保留")

	var east_slot := WallRing.new(TileSetFactory.create_deck(), 1)
	east_slot.set_head(28)
	east_slot.draw_head()
	var east_slots := east_slot.debug_stack_slots_at(0, 1)
	t.expect(east_slots[0] == [false, true], "东墙 poker[0] 是上层，先被摸走")

	var south_slot := WallRing.new(TileSetFactory.create_deck(), 1)
	south_slot.set_head(54)
	south_slot.draw_head()
	var south_slots := south_slot.debug_stack_slots_at(1, 1)
	t.expect(south_slots[south_slots.size() - 1] == [false, true], "南墙右端上层先摸走")

	var west_slot := WallRing.new(TileSetFactory.create_deck(), 1)
	west_slot.set_head(82)
	west_slot.draw_head()
	var west_slots := west_slot.debug_stack_slots_at(2, 1)
	t.expect(west_slots[west_slots.size() - 1] == [false, true], "西墙下端上层先摸走")

	var tail_wall := WallRing.new(TileSetFactory.create_deck())
	tail_wall.set_head(0)
	t.expect(tail_wall.draw_tail() == tail_wall._ring[106], "杠后先摸最后一列上层")
	t.expect(tail_wall.draw_tail() == tail_wall._ring[107], "同一列再摸下层")
	t.expect(tail_wall.draw_tail() == tail_wall._ring[104], "再退到前一列上层")
	quit(t.finish("wall_deal_order"))
