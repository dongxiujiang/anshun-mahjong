extends Node
## 全局配置与规则数值表（Autoload）
## 所有番值/鸡值集中于此常亮，便于按真实规则微调。

# ---------- 玩家 ----------
const START_SCORE := 200.0        # 每人默认分数（可为负）

# ---------- 鸡牌 ----------
const CHICKEN_TIAO1 := "tiao1"    # 一条（1条）
const CHICKEN_TONG8 := "tong8"    # 八筒（8筒）
const SCORE_CHARGE_CHICKEN := 4.0 # 一条与八筒各自首张冲锋鸡4分。
const SCORE_CALL_CHICKEN := 2.0   # 叫牌鸡：打出的/没打出的鸡牌每张 +2
const MAX_CHICKEN_MULTIPLIER := 2 # 连续四家叫牌流局后倍率保留2倍，不继续累乘。
const SCORE_FLIP_CHICKEN := 1.0   # 翻牌鸡：翻牌及上下相邻张，手中每张 +1
const SCORE_FLIP_DOUBLE := 2.0    # 翻牌张含一条/八筒 → 该张翻倍(倍率)
const SCORE_NO_CHICKEN := 14.0    # 无鸡：手中既无鸡牌也无翻牌三张 +14

# ---------- 番型 / 情境 ----------
const BASE_ROB := 0.0
const BASE_SELF_DRAW := 0.0
const SCORE_SELF_DRAW := 4.0      # 自摸 +4（额外自摸奖）
const SCORE_KONG_DRAW := 9.0      # 杠开（杠上开花） +9
const SCORE_DRAW_KONG := 4.0      # 无人胡牌查叫：暗/加杠由未叫者各付，明杠由未叫的放杠者付。
const SCORE_LAST_FOUR := 9.0      # 最后四张自摸（海底） +9
const SCORE_BIG_SET := 14.0       # 大队子（对对胡）自摸每家14
const SCORE_BIG_SET_DISCARD := 14.0 # 大队子放炮者支付14。
const SCORE_SEVEN_PAIRS := 24.0   # 小七对 自摸+24 / 胡别人者给24
const SCORE_DRAGON_SEVEN_PAIRS := 44.0 # 七对中含四张同牌，替代小七对分。
const SCORE_FLUSH := 24.0         # 清一色 自摸+24 / 胡别人者给24
const SCORE_CLEAN_BIG_TRIPLETS := 34.0 # 清大对（清一色大对子）
const SCORE_CLEAN_SINGLE_WAIT := 54.0 # 清单吊
const SCORE_CLEAN_DRAGON_SEVEN_PAIRS := 88.0 # 清龙七对
const SCORE_READY := 24.0         # 报听：自摸每家给24；被杀给24；胡别家别家给24

# ---------- 番型表 ----------
# 统一番型定义：key 对应 RuleEngine.analyze 的返回标志；self/discard 为自摸/放炮时各家应付分值。
# dragon_* 为“龙七对”变体，仅在 dragon_flag 为真时替换 seven_pairs 的基础值。
const PATTERNS := [
	{"key": "seven_pairs", "label": "小七对", "self": SCORE_SEVEN_PAIRS, "discard": SCORE_SEVEN_PAIRS, "dragon_flag": "dragon_seven_pairs", "dragon_label": "龙七对", "dragon_self": SCORE_DRAGON_SEVEN_PAIRS, "dragon_discard": SCORE_DRAGON_SEVEN_PAIRS},
	{"key": "all_triplets", "label": "大队子", "self": SCORE_BIG_SET, "discard": SCORE_BIG_SET_DISCARD},
	{"key": "flush", "label": "清一色", "self": SCORE_FLUSH, "discard": SCORE_FLUSH},
	{"key": "clean_big_triplets", "label": "清大对", "self": SCORE_CLEAN_BIG_TRIPLETS, "discard": SCORE_CLEAN_BIG_TRIPLETS},
	{"key": "clean_single_wait", "label": "清单吊", "self": SCORE_CLEAN_SINGLE_WAIT, "discard": SCORE_CLEAN_SINGLE_WAIT},
	{"key": "clean_dragon_seven_pairs", "label": "清龙七对", "self": SCORE_CLEAN_DRAGON_SEVEN_PAIRS, "discard": SCORE_CLEAN_DRAGON_SEVEN_PAIRS},
]

# ---------- 座位 ----------
const SEAT_DEALER := 0  # 庄（下）
const SEAT_RIGHT := 1   # 下家（右）
const SEAT_ACROSS := 2  # 对家（上）
const SEAT_LEFT := 3    # 上家（左）

# 联机相关
var player_name := "玩家"
var online_mode := false

# AI 思考速度：快 1 秒 / 中 2 秒 / 慢 3 秒。
const AI_SPEED_DELAYS := {"fast": 1.0, "medium": 2.0, "slow": 3.0}
var ai_speed := "fast"
const ANIMATION_SPEEDS := {"fast": 0.5, "standard": 1.0, "slow": 2.0}
# 开局采用共同节奏，权威端按时钟解锁；客户端动画不推进游戏逻辑。
const OPENING_DICE_SECONDS := 1.2
const OPENING_DICE_HOLD_SECONDS := 0.5
const OPENING_DEAL_SECONDS := 0.16
const OPENING_WAIT_SECONDS := OPENING_DICE_SECONDS + OPENING_DICE_HOLD_SECONDS + 16 * OPENING_DEAL_SECONDS + 0.25
var animation_speed := "standard"

func set_ai_speed(value: String) -> void:
	if AI_SPEED_DELAYS.has(value):
		ai_speed = value

func ai_delay_seconds() -> float:
	if DisplayServer.get_name() == "headless":
		return 0.0
	return float(AI_SPEED_DELAYS.get(ai_speed, 1.0))

func set_animation_speed(value: String) -> void:
	if ANIMATION_SPEEDS.has(value):
		animation_speed = value

func animation_duration(base_seconds: float) -> float:
	return base_seconds * float(ANIMATION_SPEEDS.get(animation_speed, 1.0))
