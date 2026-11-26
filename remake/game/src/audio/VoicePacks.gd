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
