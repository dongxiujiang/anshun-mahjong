class_name VoicePackRegistry
extends RefCounted
## 音色包注册表。当前 19 套均已导入；未知/旧配置回退首套。

const DEFAULT := "luoxiaohei"
const ORDER := ["luoxiaohei", "wuyuanzhao", "wenrounv", "jiejie",
	"gaoxiaonv", "weilong", "leishen", "shuaige", "mingliangnv",
	"diantainan", "huaqiang", "taiwannan", "wangye", "leijun",
	"lubenwei", "xiaohei", "french", "wenrou", "nvyou"]
const LABELS := {
	"luoxiaohei": "罗小黑",
	"wuyuanzhao": "武元照",
	"wenrounv": "温柔女",
	"jiejie": "姐姐",
	"gaoxiaonv": "搞笑女",
	"weilong": "威龙",
	"leishen": "雷神",
	"shuaige": "帅哥",
	"mingliangnv": "明亮女",
	"diantainan": "电台男",
	"huaqiang": "华强",
	"taiwannan": "台湾男",
	"wangye": "王也",
	"leijun": "雷军",
	"lubenwei": "卢本伟",
	"xiaohei": "小黑",
	"french": "法国赌神",
	"wenrou": "温柔帅哥",
	"nvyou": "女友",
}

static func normalize(value: Variant) -> String:
	var key := str(value)
	return key if LABELS.has(key) else DEFAULT

static func label(value: Variant) -> String:
	return str(LABELS.get(normalize(value), LABELS[DEFAULT]))

static func ids() -> Array:
	return ORDER.duplicate()

static func concrete_for_seat(value: Variant, _seat: int) -> String:
	return normalize(value)
