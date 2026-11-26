extends RefCounted
## 牌桌桌布、边框与牌背的新中式主题定义。只影响视觉材质，不改变任何牌桌物理坐标或规则。

const TABLE_ORDER := ["jade_classic", "walnut_classic", "obsidian_gold", "bamboo_mist"]
const TILE_BACK_ORDER := ["jade", "amber", "porcelain", "cinnabar"]

const TABLE_THEMES := {
	"jade_classic": {
		"label": "翠玉雅轩（默认）",
		"bg": Color("#0e211d"),
		"felt_center": Color("#0c4f41"),
		"felt_edge": Color("#062c25"),
		"trim_gold": Color("#c8a862"),
		"wood": Color("#4d2f1c"),
		"wood_roughness": 0.44,
		"inlay": Color("#b48f52"),
		"corner_metal": Color("#d1af68"),
		"ambient": Color("#fff6e4"),
		"ambient_energy": 0.56,
		"key_color": Color("#fffaf0"),
		"key_energy": 0.52,
		"hub_plate": Color("#132b24"),
		"hub_rim": Color("#c7a258"),
		"hub_glow": Color("#ffcf6e"),
	},
	"walnut_classic": {
		"label": "胡桃古韵",
		"bg": Color("#171512"),
		"felt_center": Color("#184539"),
		"felt_edge": Color("#0c2620"),
		"trim_gold": Color("#d0a960"),
		"wood": Color("#5a321d"),
		"wood_roughness": 0.40,
		"inlay": Color("#c49650"),
		"corner_metal": Color("#deb86d"),
		"ambient": Color("#ffefd6"),
		"ambient_energy": 0.55,
		"key_color": Color("#fff2dd"),
		"key_energy": 0.54,
		"hub_plate": Color("#241812"),
		"hub_rim": Color("#cfa158"),
		"hub_glow": Color("#ffd075"),
	},
	"obsidian_gold": {
		"label": "墨韵鎏金",
		"bg": Color("#0d1113"),
		"felt_center": Color("#1b282b"),
		"felt_edge": Color("#0f171a"),
		"trim_gold": Color("#dfb96d"),
		"wood": Color("#231c18"),
		"wood_roughness": 0.36,
		"inlay": Color("#d4ae62"),
		"corner_metal": Color("#e8c57b"),
		"ambient": Color("#f4f6ff"),
		"ambient_energy": 0.58,
		"key_color": Color("#fffaf2"),
		"key_energy": 0.52,
		"hub_plate": Color("#141a1d"),
		"hub_rim": Color("#dfb96d"),
		"hub_glow": Color("#ffd97d"),
	},
	"bamboo_mist": {
		"label": "松竹清风",
		"bg": Color("#112321"),
		"felt_center": Color("#1d5a51"),
		"felt_edge": Color("#0f3732"),
		"trim_gold": Color("#c4c99e"),
		"wood": Color("#6e4c30"),
		"wood_roughness": 0.48,
		"inlay": Color("#a9b388"),
		"corner_metal": Color("#c8c69b"),
		"ambient": Color("#f6fff7"),
		"ambient_energy": 0.57,
		"key_color": Color("#fafff5"),
		"key_energy": 0.50,
		"hub_plate": Color("#173631"),
		"hub_rim": Color("#b4bf96"),
		"hub_glow": Color("#e8e49c"),
	},
}

const TILE_BACKS := {
	"jade": {
		"label": "翡翠玉背（默认）",
		"back": Color(0.18, 0.44, 0.29, 1.0),
		"ivory": Color(0.98, 0.97, 0.92, 1.0),
	},
	"amber": {
		"label": "琥珀鎏金",
		"back": Color(0.62, 0.41, 0.14, 1.0),
		"ivory": Color(0.99, 0.97, 0.91, 1.0),
	},
	"porcelain": {
		"label": "青花瓷蓝",
		"back": Color(0.15, 0.33, 0.56, 1.0),
		"ivory": Color(0.97, 0.98, 0.99, 1.0),
	},
	"cinnabar": {
		"label": "朱砂赤玉",
		"back": Color(0.56, 0.17, 0.15, 1.0),
		"ivory": Color(0.99, 0.96, 0.91, 1.0),
	},
}

static func table_data(id: String) -> Dictionary:
	return TABLE_THEMES.get(id, TABLE_THEMES.jade_classic)

static func tile_back_data(id: String) -> Dictionary:
	return TILE_BACKS.get(id, TILE_BACKS.jade)

static func table_labels() -> Array:
	return TABLE_ORDER.map(func(id): return TABLE_THEMES[id].label)

static func tile_back_labels() -> Array:
	return TILE_BACK_ORDER.map(func(id): return TILE_BACKS[id].label)
