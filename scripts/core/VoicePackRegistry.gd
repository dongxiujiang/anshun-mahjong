class_name VoicePackRegistry
extends RefCounted
## 音色包注册表。当前 10 套均已导入；未知/旧配置回退首套。

const DEFAULT := "usagi"
const ORDER := ["usagi", "lubenwei", "weilong", "xiaohei", "gaoxiaonv",
	"wuyuanzhao", "french", "wenrou", "hanli", "leishen", "nvyou"]
const LABELS := {
	"usagi": "乌沙奇",
	"lubenwei": "卢本伟",
	"weilong": "威龙",
	"xiaohei": "小黑",
	"gaoxiaonv": "搞笑女",
	"wuyuanzhao": "伍元照",
	"french": "法国赌神",
	"wenrou": "温柔帅哥",
	"hanli": "韩立",
	"leishen": "雷神",
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
