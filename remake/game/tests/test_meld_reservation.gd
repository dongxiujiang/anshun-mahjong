extends SceneTree
const Table = preload("res://src/presentation/TableView.gd")
const Layout = preload("res://src/presentation/TableLayout.gd")
var checks := 0
var failures := 0

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL meld reserve: ", note)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var table := Table.new(false)
	root.add_child(table)
	for owner in 4:
		for provider in 4:
			if owner == provider: continue
			var pung := {"kind": "pung", "tile": "wan6", "tile_ids": [0,1,2], "source_id": 2, "from_seat": provider}
			var kong := pung.duplicate(true)
			kong.kind = "add_kong"
			kong.tile_ids.append(3)
			var groups := {"m0": table._meld(owner, 0, pung), "c4": {"width":1.0, "pieces":[[4,"tong8",0.0,0.0,false]]}}
			var layout := Layout.new()
			for key in groups: check(layout.reserve(owner, key, groups[key], 11, groups), "initial group fits")
			var initial: Dictionary = layout.anchors[owner].duplicate(true)
			groups.m0 = table._meld(owner, 0, kong)
			check(layout.reserve(owner, "m0", groups.m0, 11, groups), "upgrade retains reservation")
			check(layout.anchors[owner] == initial, "old anchors remain unchanged")
			var item: Dictionary = layout.anchors[owner].m0
			for piece in groups.m0.pieces:
				var size := Vector2(Layout.LONG, 1.0) if piece[4] else Vector2(1.0, Layout.LONG)
				var actual := Rect2(item.center + Vector2(piece[2],piece[3]) - size * 0.5, size)
				check(item.rect.grow(0.0001).encloses(actual), "upgraded tile stays inside initial footprint")
				check(not actual.intersects(initial.c4.rect), "upgrade does not invade next public tile")
			var resumed := Layout.new()
			for key in groups: resumed.reserve(owner, key, groups[key], 11, groups)
			check(resumed.anchors[owner] == initial, "fresh observer reconstructs identical group anchors")
	table.free()
	print("Meld reservation: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
