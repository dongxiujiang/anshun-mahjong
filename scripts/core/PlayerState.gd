class_name PlayerState
extends RefCounted
## 一名玩家的回合状态（纯数据）。

var seat := 0                 # 0庄/1右/2对/3左
var is_human := false
var is_dealer := false
var name_label := ""
var concealed: Array = []     # 手内未固定牌 (Array[String])
var melds: Array = []         # {kind:"pung"|"kong"|"add_kong", tile:String, robbed:bool}
var discards: Array = []      # 打出过的牌（可见）
var discard_history: Array = []
var discard_ids: Array = []   # 与当前弃牌一一对应，碰杠移走时同时删除。
var discard_count := 0        # 本局出牌总次数，用于稳定排列碰杠和鸡牌。
var score := 200.0
var ready := false            # 报听
var announced_ready := false  # 是否已用过报听机会
var first_turn_done := false  # 是否已打过第一手（报听窗口=各自第一手）
var just_drew := ""           # 本轮摸到的牌（未打）
var charge_chicken := false   # 当前是否持有任一种冲锋鸡（可由碰杠转入）。
var passed_win_until_draw := false # 过胡后，到自己下一次摸牌前只能自摸。
var passed_pong_tiles: Array[String] = [] # 过碰后，同一张牌在自己下次摸牌前不能再碰。
var add_kong_locked_tiles: Array[String] = [] # 选择碰掉可明杠牌后，本局该牌不能再加杠。
var forbidden_discard_tile := "" # 碰牌后不能立即打出刚碰的牌。

func init_seat(s: int, human: bool, dealer: bool, nm: String) -> void:
	seat = s
	is_human = human
	is_dealer = dealer
	name_label = nm

## 固定面子里的牌值（用于清一色判定与展示）
func other_meld_tiles() -> Array:
	var out: Array = []
	for m in melds: out.append(m.tile)
	return out

func all_hand_tiles() -> Array:
	var out := concealed.duplicate()
	for meld in melds:
		for index in (3 if meld.kind == "pung" else 4):
			out.append(meld.tile)
	return out

func hand_tile_count() -> int:
	var n := concealed.size()
	for m in melds:
		n += 3 if m.kind == "pung" else 4
	return n

## 别家已打出的牌（用于 AI 防御/翻牌统计）
func discard_all() -> Array:
	return discards.duplicate()
