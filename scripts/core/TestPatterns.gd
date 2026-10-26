## 联机测试牌型的唯一数据源。每个牌型固定发 13 张，庄家首摸后再打一张。
## 所有牌都来自正常 108 张牌库，不制造超过 4 张的重复牌。

const CATALOG := [
	{"id": "ready", "name": "报听牌", "description": "13 张已听 5筒，摸牌后打一张即可报听"},
	{"id": "pong_kong", "name": "碰杠牌", "description": "带 3 个刻子和 2 个对子，方便测试碰、杠"},
	{"id": "chicken", "name": "鸡牌", "description": "带幺鸡和八筒，方便测试冲锋鸡/普通鸡"},
]

static func ids() -> Array:
	return CATALOG.map(func(item): return str(item.id))

static func get_entry(pattern: String) -> Dictionary:
	for item in CATALOG:
		if str(item.id) == pattern:
			return item.duplicate(true)
	return {}

static func hand(pattern: String) -> Array:
	match pattern:
		"ready":
			return ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9",
				"tong1", "tong2", "tong3", "tong5"]
		"pong_kong":
			return ["wan1", "wan1", "wan1", "tiao2", "tiao2", "tiao2", "tong3", "tong3", "tong3",
				"wan4", "wan4", "tiao6", "tiao6"]
		"chicken":
			return ["wan1", "wan2", "wan3", "wan4", "wan5", "wan6", "wan7", "wan8", "wan9",
				"tiao1", "tiao1", "tong8", "tong8"]
	return []

