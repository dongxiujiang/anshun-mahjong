class_name VoicePackRegistry
extends RefCounted
## 音色包注册表。当前 15 套均已导入；未知/旧配置回退首套。

const DEFAULT := "luoxiaohei"
const ORDER := ["luoxiaohei", "wuyuanzhao", "wenrounv",
	"gaoxiaonv", "weilong", "shuaige",
	"diantainan", "huaqiang", "taiwannan", "wangye", "leijun",
	"lubenwei", "french", "wenrou", "nvyou"]
const LABELS := {
	"luoxiaohei": "罗小黑",
	"wuyuanzhao": "武元照",
	"wenrounv": "温柔女",
	"gaoxiaonv": "搞笑女",
	"weilong": "威龙",
	"shuaige": "帅哥",
	"diantainan": "电台男",
	"huaqiang": "华强",
	"taiwannan": "台湾男",
	"wangye": "王也",
	"leijun": "雷军",
	"lubenwei": "卢本伟",
	"french": "法国赌神",
	"wenrou": "温柔帅哥",
	# “女友”素材继续保留，但对外统一改名为“明亮女”。
	"nvyou": "明亮女",
}
const LEGACY_IDS := {
	"jiejie": "nvyou", "mingliangnv": "nvyou",
	"leishen": "wangye", "xiaohei": "luoxiaohei",
}

static func normalize(value: Variant) -> String:
	var key := str(value)
	if LEGACY_IDS.has(key):
		key = str(LEGACY_IDS[key])
	return key if LABELS.has(key) else DEFAULT

static func label(value: Variant) -> String:
	return str(LABELS.get(normalize(value), LABELS[DEFAULT]))

static func ids() -> Array:
	return ORDER.duplicate()

static func concrete_for_seat(value: Variant, _seat: int) -> String:
	return normalize(value)
