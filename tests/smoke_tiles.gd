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

	# 牌背：无素材，用程序化绘制（不崩即可）
	var tv := TileView.new()
	tv.set_card("", false)
	tv.set_unit(1.0)
	t.expect(tv != null, "牌背程序化绘制不应崩溃")
	print("[ok] 牌背走程序化绘制（无素材）")
	tv.free()

	# 手牌排序：万→条→筒，各花色1→9
	var messy: Array = ["tong8", "wan1", "tiao9", "wan9", "tiao1", "tong1", "wan2"]
	var sorted := Tiles.sort_hand(messy)
	t.expect(sorted == ["wan1", "wan2", "wan9", "tiao1", "tiao9", "tong1", "tong8"], "排序错误: %s" % str(sorted))
	print("[ok] 手牌排序 万→条→筒、1→9")

	quit(t.finish("smoke_tiles"))
