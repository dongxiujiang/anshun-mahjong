extends RefCounted
## 100 个与麻将、茶馆及安顺捉鸡相关的趣味昵称库（全部为 1–6 个汉字、无牌名、无重复）。
## 玩家可在资料页随机或挑选，人机座位从中不重复抽取。

const POOL: Array[String] = [
	# 胡牌 / 自摸（10）
	"摸张好牌", "天选雀神", "自摸达人", "杠上开花", "海底捞月",
	"门清大师", "满堂大胡", "妙手自摸", "连胡不断", "绝张自摸",
	# 安顺捉鸡 / 鸡牌特色（10）
	"捉鸡先锋", "冲锋小将", "金鸡报晓", "翻鸡福星", "责任克星",
	"鸡牌猎手", "摇摆捉鸡", "满堂抓鸡", "星期鸡王", "安顺雀王",
	# 安顺 / 贵州牌桌茶馆（10）
	"屯堡牌客", "黔中雀圣", "瀑乡牌友", "贵阳雀友", "茶馆东家",
	"棋牌掌柜", "老街牌友", "巷口雀侠", "竹凳牌客", "茗香牌友",
	# 听牌 / 报听（10）
	"报听达人", "听牌雷达", "听牌高手", "起手报听", "天听传奇",
	"绝张捕手", "单吊王子", "卡张圣手", "边张杀手", "双碰高手",
	# 番型 / 牌型（10）
	"大对子王", "清色剑客", "七对奇侠", "龙七传人", "清对宗师",
	"平胡稳王", "暗杠大师", "明杠好手", "补杠狂人", "抢杠克星",
	# 起手 / 庄家 / 骰子（10）
	"天胡传说", "地胡奇才", "连庄霸主", "坐庄老手", "庄家克星",
	"起手顺牌", "掷骰手气", "豹子幸运", "翻倍达人", "稳坐上家",
	# 攻防 / 算牌策略（10）
	"牌桌神算", "算牌大师", "记牌鬼才", "控牌老将", "拆搭好手",
	"留张高手", "避炮专家", "防守铁闸", "热炮终结", "干扣猎手",
	# 碰杠 / 理牌操作（10）
	"碰碰乐手", "见碰必碰", "杠王之王", "连杠高手", "抢碰快手",
	"吃碰不误", "巧打生张", "熟张行家", "摸打如风", "理牌能手",
	# 牌运 / 雀坛风范（10）
	"牌运亨通", "手气爆棚", "摸啥来啥", "逢听必胡", "牌神附体",
	"雀坛新秀", "雀林盟主", "雀道中人", "笑傲雀坛", "棋牌常胜",
	# 搓麻趣味（10）
	"搓麻健将", "麻坛老炮", "夜战麻将", "通宵牌友", "逢局必到",
	"四方牌友", "牌桌雅士", "摸牌锦鲤", "雀桌开心", "桌上见",
]


static func pick_unique(count: int, excluded: Array = []) -> Array[String]:
	var blocked := {}
	for name in excluded:
		var s := str(name)
		if not s.is_empty():
			blocked[s] = true
	var candidates: Array[String] = []
	for entry in POOL:
		if not blocked.has(entry):
			candidates.append(entry)
	if candidates.size() < count:
		for entry in POOL:
			if not candidates.has(entry):
				candidates.append(entry)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	var picked: Array[String] = []
	for idx in mini(count, candidates.size()):
		picked.append(candidates[idx])
	return picked


static func pick_one(excluded: Array = []) -> String:
	var list := pick_unique(1, excluded)
	return list[0] if not list.is_empty() else POOL[0]
