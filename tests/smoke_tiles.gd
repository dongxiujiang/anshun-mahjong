extends SceneTree
## 验证 res/tiles 素材映射：1-9=筒, 11-19=条, 21-29=万；27 张全部存在且尺寸一致。
## 运行： godot --headless --script res://tests/smoke_tiles.gd

const H := preload("res://tests/test_harness.gd")

var t := H.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[smoke_tiles] 开始")
	var expected := {"tong8": "res://res/tiles/8.png", "tiao1": "res://res/tiles/11.png", "wan5": "res://res/tiles/25.png"}
	for key in expected:
		var got := TileView.texture_path(key)
		t.expect(got == expected[key], "%s 应映射到 %s, 实际 %s" % [key, expected[key], got])
	print("[ok] 关键映射: 筒1-9→1-9.png, 条→11-19.png, 万→21-29.png")

	var n := 0
	var size_ref := Vector2.ZERO
	for suit in Tiles.SUITS:
		for r in Tiles.RANKS:
			var tile := Tiles.val(suit, r)
			var path := TileView.texture_path(tile)
			if not t.expect(ResourceLoader.exists(path), "缺素材: %s -> %s" % [tile, path]):
				continue
			var tex: Texture2D = load(path)
			if not t.expect(tex != null, "加载失败: %s" % path):
				continue
			if n == 0:
				size_ref = tex.get_size()
			t.expect(tex.get_size() == size_ref, "%s 尺寸不一致: %s vs %s" % [tile, tex.get_size(), size_ref])
			n += 1
	print("[ok] %d 张牌面素材全部加载，尺寸统一 = %s" % [n, str(size_ref)])
	t.expect(n == 27, "应有 27 张牌面素材, 实际 %d" % n)

	# 牌背材质仍通过原 TileView 接口绘制。
	var tv := TileView.new()
	tv.set_card("", false)
	tv.set_unit(1.0)
	t.expect(tv != null, "牌背程序化绘制不应崩溃")
	print("[ok] 牌背走程序化绘制（无素材）")
	tv.free()
	for path in ["back-top.png", "back-bottom.png", "standing-right.png", "standing-north.png", "standing-left.png"]:
		var material: Texture2D = load("res://res/tiles/materials3d/" + path)
		t.expect(material != null and material.get_size() == Vector2(384, 512), "立体材质可加载：" + path)
	for scale_value in [0.85, 1.0, 1.35, 2.0]:
		var tile := TileView.new()
		tile.set_unit(scale_value)
		t.expect(tile.size.is_equal_approx(Vector2(48, 64) * scale_value), "材质不改变原有牌位和点击尺寸")
		tile.free()
	for path in ["hand-faces.png", "flat-faces.png"]:
		var atlas: Texture2D = load("res://res/tiles/materials3d/" + path)
		t.expect(atlas != null and atlas.get_size() == Vector2(2304, 1032), "27种牌面使用共享图集：" + path)
	var pooled := TileView.new()
	pooled.standing_back_view = 2
	pooled.reset()
	t.expect(pooled.standing_back_view == -1, "对象池回收清除立放视图，避免牌墙和暗杠继承手牌方向")
	pooled.free()
	var dice_atlas: Texture2D = load("res://res/tiles/materials3d/dice-atlas.png")
	t.expect(dice_atlas.get_size() == Vector2(1536, 512), "骰子贴图包含红黑两种颜色各六个实际顶面")

	# 手牌排序：万→条→筒，各花色1→9
	var messy: Array = ["tong8", "wan1", "tiao9", "wan9", "tiao1", "tong1", "wan2"]
	var sorted := Tiles.sort_hand(messy)
	t.expect(sorted == ["wan1", "wan2", "wan9", "tiao1", "tiao9", "tong1", "tong8"], "排序错误: %s" % str(sorted))
	print("[ok] 手牌排序 万→条→筒、1→9")

	quit(t.finish("smoke_tiles"))
