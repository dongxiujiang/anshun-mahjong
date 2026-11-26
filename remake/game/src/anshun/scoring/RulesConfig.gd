extends RefCounted

## 安顺捉鸡的固定分值。
const START_SCORE := 200.0

# ---------- 鸡牌 ----------
const SCORE_CHARGE_CHICKEN := 4.0 # 一条与八筒各自首张冲锋鸡4分。
const SCORE_CALL_CHICKEN := 2.0   # 叫牌鸡：打出的/没打出的鸡牌每张 +2
const MAX_CHICKEN_MULTIPLIER := 2 # 骰子同点与流局倍率共用，封顶2倍。
const SCORE_FLIP_CHICKEN := 1.0   # 翻牌鸡：翻牌及上下相邻张，手中每张 +1
const SCORE_FLIP_DOUBLE := 2.0    # 翻牌张含一条/八筒 → 该张翻倍(倍率)
const SCORE_NO_CHICKEN := 14.0    # 干扣：普通自摸且赢家无鸡时，总计14分（含基础4）。
const SCORE_BIG_NO_CHICKEN := 24.0 # 大干扣：四家均无鸡时，总计24分（含基础4），替代干扣。

# ---------- 番型 / 情境 ----------
const SCORE_SELF_DRAW := 4.0      # 只有自摸 +4；普通点炮/抢杠胡不加自摸4。
const SCORE_RON_CALLED := 17.0    # 暗杠/加杠后第一张弃牌被胡，弃牌者已叫牌时的放炮基础分。
const SCORE_RON_UNCALLED := 21.0  # 同上，弃牌者未叫牌时的放炮基础分（17+4）。
const SCORE_ROB_KONG := 12.0      # 抢加杠胡由被抢杠者单独支付的基础分。
const SCORE_KONG_SELF_RON := 4.0  # 通行证胡牌：自带暗杠/加杠的玩家用普通小牌胡别人弃牌时，放炮者另付。
const SCORE_KONG_DRAW := 5.0      # 杠开（杠上开花）+5。
const SCORE_DRAW_KONG := 4.0      # 独立杠基础分，按杠类型及双方叫牌状态结算。
const SCORE_LAST_FOUR := 5.0      # 最后四张任意牌自摸（海底）+5。
const SCORE_BIG_SET := 14.0       # 大对子（对对胡）自摸每家14
const SCORE_SEVEN_PAIRS := 24.0   # 小七对 自摸+24 / 胡别人者给24
const SCORE_DRAGON_SEVEN_PAIRS := 44.0 # 七对中含四张同牌，替代小七对分。
const SCORE_FLUSH := 24.0         # 清一色 自摸+24 / 胡别人者给24
const SCORE_CLEAN_BIG_TRIPLETS := 34.0 # 清大对（清一色大对子）
const SCORE_CLEAN_SINGLE_WAIT := 54.0 # 清单吊
const SCORE_BIG_SET_SINGLE_WAIT := 24.0 # 大对子单吊。
const SCORE_CLEAN_SEVEN_PAIRS := 44.0 # 清七对。
const SCORE_CLEAN_DRAGON_SEVEN_PAIRS := 64.0 # 清龙对。
const SCORE_READY := 24.0         # 报听单独加24：自摸三家付，非自摸只由被胡者付。
const SCORE_KILL_READY := 24.0    # 杀报：报听者被胡或他人自摸时，向赢家额外支付24。
const SCORE_READY_PATTERN := 20.0 # 报听自摸有牌型：24-自摸基础4，只补20。

# ---------- 番型表 ----------
# 牌型按最高项替代；仅暗杠/加杠后放炮另收17/21，普通放炮无基础费。
const PATTERNS := [
	{"key": "seven_pairs", "label": "小七对", "score": SCORE_SEVEN_PAIRS},
	{"key": "dragon_seven_pairs", "label": "龙七对", "score": SCORE_DRAGON_SEVEN_PAIRS},
	{"key": "all_triplets", "label": "大对子", "score": SCORE_BIG_SET},
	{"key": "big_triplet_single_wait", "label": "大对子单吊", "score": SCORE_BIG_SET_SINGLE_WAIT},
	{"key": "flush", "label": "清一色", "score": SCORE_FLUSH},
	{"key": "clean_big_triplets", "label": "清大对", "score": SCORE_CLEAN_BIG_TRIPLETS},
	{"key": "clean_seven_pairs", "label": "清七对", "score": SCORE_CLEAN_SEVEN_PAIRS},
	{"key": "clean_single_wait", "label": "清单吊", "score": SCORE_CLEAN_SINGLE_WAIT},
	{"key": "clean_dragon_seven_pairs", "label": "清龙七对", "score": SCORE_CLEAN_DRAGON_SEVEN_PAIRS},
]

