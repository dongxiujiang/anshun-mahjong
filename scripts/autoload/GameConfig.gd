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
const SCORE_NO_CHICKEN := 14.0    # 干扣：普通自摸且赢家无鸡时，总计14分（含基础4）。
const SCORE_BIG_NO_CHICKEN := 24.0 # 大干扣：四家均无鸡时，总计24分（含基础4），替代干扣。

# ---------- 番型 / 情境 ----------
const BASE_ROB := 0.0
const BASE_SELF_DRAW := 0.0
const SCORE_SELF_DRAW := 4.0      # 只有自摸 +4；普通点炮/抢杠胡不加自摸4。
const SCORE_RON_CALLED := 17.0    # 暗杠/加杠后第一张弃牌被胡，弃牌者已叫牌时的放炮基础分。
const SCORE_RON_UNCALLED := 21.0  # 同上，弃牌者未叫牌时的放炮基础分（17+4）。
const SCORE_ROB_KONG := 12.0      # 抢加杠胡由被抢杠者单独支付的基础分。
const SCORE_KONG_SELF_RON := 4.0  # 通行证胡牌：自带暗杠/加杠的玩家用普通小牌胡别人弃牌时，放炮者另付。
const SCORE_KONG_DRAW := 5.0      # 杠开（杠上开花）+5。
const SCORE_DRAW_KONG := 4.0      # 无人胡牌查叫：暗/加杠由未叫者各付，明杠由未叫的放杠者付。
const SCORE_LAST_FOUR := 5.0      # 最后四张任意牌自摸（海底）+5。
const SCORE_BIG_SET := 14.0       # 大对子（对对胡）自摸每家14
const SCORE_BIG_SET_DISCARD := 14.0 # 大对子放炮者支付14。
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
	{"key": "clean_dragon_seven_pairs", "label": "清龙对", "score": SCORE_CLEAN_DRAGON_SEVEN_PAIRS},
]

# 方向统一为座位编号递增方向：起手发牌、普通回合和响应顺序都使用 +1。
# 只保留一个方向源，避免起手和普通回合再次出现分叉配置。
# 逻辑方向与牌桌画面位置分离，座位映射由 UI 单独处理。
const ROUND_DIRECTION := 1
const DEAL_DIRECTION := ROUND_DIRECTION
const TURN_DIRECTION := ROUND_DIRECTION

# ---------- 座位 ----------
const SEAT_DEALER := 0  # 庄（下）
const SEAT_RIGHT := 1   # 下家（右）
const SEAT_ACROSS := 2  # 对家（上）
const SEAT_LEFT := 3    # 上家（左）

# 联机相关
var player_name := "玩家"
var online_mode := false

# AI 思考速度：快 0.8 秒 / 中 1.3 秒 / 慢 2 秒。
const AI_SPEED_DELAYS := {"fast": 0.8, "medium": 1.3, "slow": 2.0}
# Claims use the same wait as an ordinary AI discard; the speed buttons control
# both. Pass and win responses remain immediate.
var ai_speed := "medium"
# AI 强度入口先保留三档；当前仅弱档，后续再接中/强策略。
const AI_STRENGTHS := {"weak": "弱", "medium": "中", "strong": "强"}
var ai_strength := "weak"
const ANIMATION_SPEEDS := {"instant": 0.0, "fast": 0.5, "standard": 1.0}
const TILE_ANIMATION_SPEEDS := {"instant": 0.0, "fast": 0.5, "standard": 1.0, "slow": 1.8}
var draw_animation_speed := "fast"
var discard_animation_speed := "fast"
# 结算阅读节奏独立于摸牌、出牌等动画；慢速默认留足查看计分的时间。
signal settlement_speed_changed
const SETTLEMENT_SPEEDS := {"instant": 0.0, "standard": 1.0, "slow": 2.0, "detail": 3.5}
var settlement_speed := "standard"
# 联机语音聊天：麦克风增益与其它玩家语音音量独立保存。
signal voice_chat_settings_changed
var voice_chat_mic_gain := 1.0
var voice_chat_remote_volume := 0.8
signal debug_changed
var debug_enabled := false
# 开局采用共同节奏，权威端按时钟解锁；客户端动画不推进游戏逻辑。
const OPENING_DICE_SECONDS := 1.2
const OPENING_DICE_HOLD_SECONDS := 0.5
## A real table deals one four-tile packet at a time.  The packet itself is
## quick, but leaves enough time for a visible lift, flight and settle.
const OPENING_DEAL_SECONDS := 0.22
const OPENING_DEAL_TILE_STAGGER := 0.035
const OPENING_SORT_SECONDS := 0.34
const OPENING_SORT_TILE_STAGGER := 0.012
## Twelve four-tile packets plus four single dealer/turn packets.  Include the
## stagger inside each packet so authority unlock and the last visible tile
## settle at the same point in time.  The final hand-sorting pass also belongs
## to the opening presentation, so the first turn cannot begin over it.
const OPENING_WAIT_SECONDS := OPENING_DICE_SECONDS + OPENING_DICE_HOLD_SECONDS + 12 * (OPENING_DEAL_SECONDS + 3 * OPENING_DEAL_TILE_STAGGER) + 4 * OPENING_DEAL_SECONDS + OPENING_SORT_SECONDS + 13 * OPENING_SORT_TILE_STAGGER + 0.25
var animation_speed := "standard"

const SETTINGS_STORE := preload("res://scripts/core/UserSettingsStore.gd")
const SETTINGS_PATH := "user://game_settings.cfg"
const PREFERENCE_CHOICES := {
	"ai_speed": AI_SPEED_DELAYS,
	"ai_strength": AI_STRENGTHS,
	"animation_speed": ANIMATION_SPEEDS,
	"draw_animation_speed": TILE_ANIMATION_SPEEDS,
	"discard_animation_speed": TILE_ANIMATION_SPEEDS,
	"settlement_speed": SETTLEMENT_SPEEDS,
}
var settings_path := SETTINGS_PATH
# Dedicated servers and headless tests must not read/write a player's settings.
# Persistence tests opt in with an isolated path before _ready().
var persist_settings := DisplayServer.get_name() != "headless"

func _ready() -> void:
	if persist_settings: load_settings()

func load_settings(path: String = "") -> void:
	var config := SETTINGS_STORE.read_config(settings_path if path == "" else path)
	var saved_name = config.get_value("player", "name", player_name)
	if saved_name is String: set_player_name(saved_name, false)
	for key in PREFERENCE_CHOICES:
		var value = config.get_value("game", key, get(key))
		if value is String and PREFERENCE_CHOICES[key].has(value): set(key, value)
	voice_chat_mic_gain = clampf(float(config.get_value("voice_chat", "mic_gain", voice_chat_mic_gain)), 0.0, 2.0)
	voice_chat_remote_volume = clampf(float(config.get_value("voice_chat", "remote_volume", voice_chat_remote_volume)), 0.0, 2.0)
	debug_enabled = bool(config.get_value("debug", "enabled", debug_enabled))

func save_settings(path: String = "") -> Error:
	if path == "" and not persist_settings: return OK
	var target := settings_path if path == "" else path
	var config := SETTINGS_STORE.read_config(target)
	config.set_value("player", "name", player_name)
	for key in PREFERENCE_CHOICES: config.set_value("game", key, get(key))
	config.set_value("voice_chat", "mic_gain", voice_chat_mic_gain)
	config.set_value("voice_chat", "remote_volume", voice_chat_remote_volume)
	config.set_value("debug", "enabled", debug_enabled)
	return SETTINGS_STORE.write_config(config, target)

func set_debug_enabled(value: bool, persist: bool = true) -> void:
	debug_enabled = value
	debug_changed.emit()
	if persist: _save_preference(true)

func set_voice_chat_mic_gain(value: float, persist: bool = true) -> void:
	voice_chat_mic_gain = clampf(value, 0.0, 2.0)
	voice_chat_settings_changed.emit()
	_save_preference(persist)

func set_voice_chat_remote_volume(value: float, persist: bool = true) -> void:
	voice_chat_remote_volume = clampf(value, 0.0, 2.0)
	voice_chat_settings_changed.emit()
	_save_preference(persist)

func set_player_name(value: String, persist: bool = true) -> void:
	player_name = value.strip_edges().left(16)
	if player_name == "": player_name = "玩家"
	_save_preference(persist)

func _save_preference(persist: bool) -> void:
	if persist and save_settings() != OK: push_warning("无法保存游戏设置，请检查存储空间")

func set_ai_speed(value: String, persist: bool = true) -> void:
	if AI_SPEED_DELAYS.has(value):
		ai_speed = value
		_save_preference(persist)

func set_ai_strength(value: String, persist: bool = true) -> void:
	if AI_STRENGTHS.has(value):
		ai_strength = value
		_save_preference(persist)

func ai_delay_seconds() -> float:
	if DisplayServer.get_name() == "headless":
		return 0.0
	return float(AI_SPEED_DELAYS.get(ai_speed, 1.0))

func ai_response_delay_seconds() -> float:
	return ai_delay_seconds()

func set_animation_speed(value: String, persist: bool = true) -> void:
	if ANIMATION_SPEEDS.has(value):
		animation_speed = value
		_save_preference(persist)

func animation_duration(base_seconds: float) -> float:
	return base_seconds * float(ANIMATION_SPEEDS.get(animation_speed, 1.0))

func set_draw_animation_speed(value: String, persist: bool = true) -> void:
	if TILE_ANIMATION_SPEEDS.has(value):
		draw_animation_speed = value
		_save_preference(persist)

func set_discard_animation_speed(value: String, persist: bool = true) -> void:
	if TILE_ANIMATION_SPEEDS.has(value):
		discard_animation_speed = value
		_save_preference(persist)

func animation_scale_for(action: String) -> float:
	match action:
		"draw": return float(TILE_ANIMATION_SPEEDS.get(draw_animation_speed, 1.0))
		"discard": return float(TILE_ANIMATION_SPEEDS.get(discard_animation_speed, 1.0))
	return float(ANIMATION_SPEEDS.get(animation_speed, 1.0))

func set_settlement_speed(value: String, persist: bool = true) -> void:
	if not SETTLEMENT_SPEEDS.has(value): return
	var changed := settlement_speed != value
	settlement_speed = value
	_save_preference(persist)
	if changed: settlement_speed_changed.emit()

func settlement_duration(base_seconds: float) -> float:
	return base_seconds * float(SETTLEMENT_SPEEDS.get(settlement_speed, 2.0))
