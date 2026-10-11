class_name WallRing
extends RefCounted
## 环形牌墙：把 4 家 108 张按物理顺时针连成环line。
## 摸牌从"牌头"顺时针走；杠从"牌尾"(远端)补。
## 座位↔墙关系：
##   庄(下) -> seg2  下家(右)-> seg1  对家(上)-> seg0  上家(左)-> seg3
## 分段(顺时针内部方向): [0,27]对家(左→右) [28,53]下家(上→下) [54,81]庄家(右→左) [82,107]上家(下→上)

const N := 108
const SEG := {
	0: {"start": 0,  "len": 28, "seat": 2},  # 对家/上
	1: {"start": 28, "len": 26, "seat": 1},  # 下家/右
	2: {"start": 54, "len": 28, "seat": 0},  # 庄家/下
	3: {"start": 82, "len": 26, "seat": 3},  # 上家/左
}

var _ring: Array = []       # 108 张牌字符串，按顺时针物理次序
var _drawn: Array[bool] = []
var _head := 0
var _tail := 0
var remaining := 108

const SUIT_LEN := 26  # 砖数单位，仅供内部：每砖2张
const PAIR := 2

func _init(ring_tiles: Array):
	# ring_tiles 为 108 张，按物理顺时针（与 SEG 边界一致）传入
	assert(ring_tiles.size() == N)
	_ring = ring_tiles.duplicate()
	_drawn.resize(N)
	_drawn.fill(false)

## 根据骰子点数 D 计算牌头索引（本子按你描述的规则）：
##   D∈{1,3,5} -> 对家墙(seg0) 跳过D砖 ; D=4 -> 上家(seg3) 跳4砖 ; D∈{2,6} -> 下家(seg1) 跳D砖
static func compute_break(die: int) -> int:
	if die in [1, 3, 5]:
		return SEG[0].start + die * PAIR          # 对家
	elif die == 4:
		return SEG[3].start + 4 * PAIR            # 上家
	else:  # 2,6
		return SEG[1].start + die * PAIR          # 下家

func set_head(break_idx: int):
	_head = break_idx
	_tail = positive_mod(break_idx - 1, N)
	remaining = N
	_drawn.fill(false)

func positive_mod(v: int, m: int) -> int:
	var r := v % m
	return r + m if r < 0 else r

func _advance(idx: int) -> int: return positive_mod(idx + 1, N)
func _retreat(idx: int) -> int: return positive_mod(idx - 1, N)

## 窥视牌头下一张（不消耗，用于翻牌鸡结算）
func peek_head() -> String:
	if remaining <= 0: return ""
	var i := _head
	while _drawn[i]:
		i = _advance(i)
		if i == _head: return ""
	return _ring[i]

## 从牌头摸 1 张（顺时针）。空返回 ""（荒庄）
func draw_head() -> String:
	if remaining <= 0: return ""
	while _drawn[_head]:
		_head = _advance(_head)
	var tile: String = _ring[_head]
	_drawn[_head] = true
	_head = _advance(_head)
	remaining -= 1
	return tile

## 从牌尾补 1 张（杠）。空返回 ""
func draw_tail() -> String:
	if remaining <= 0: return ""
	while _drawn[_tail]:
		_tail = _retreat(_tail)
	var tile: String = _ring[_tail]
	_drawn[_tail] = true
	_tail = _retreat(_tail)
	remaining -= 1
	return tile

## 某座位面前牌墙（物理段）还剩下多少张未摸（用于 UI 显示）
func wall_remaining(seat: int) -> int:
	var seg = _wall_seg_for_seat(seat)
	var n := 0
	for i in range(seg.start, seg.start + seg.len):
		if not _drawn[i]: n += 1
	return n

func wall_stack_counts(seat: int) -> Array:
	var segment := _wall_seg_for_seat(seat)
	var stacks: Array = []
	for index in range(segment.start, segment.start + segment.len, 2):
		stacks.append(int(not _drawn[index]) + int(not _drawn[index + 1]))
	return stacks

func _wall_seg_for_seat(seat: int) -> Dictionary:
	for key in SEG:
		if SEG[key].seat == seat: return SEG[key]
	return SEG[0]

func remaining_in_wall_until_empty() -> bool:
	return remaining <= 0

## 剩余最后四张（用于"最后四张自摸+9"）：当前尚未摸的张数 <=4 且将要摸
func is_global_tail_four() -> bool:
	return remaining <= 4

# 调试
func debug_ring_head_tail() -> Dictionary:
	return {"head": _head, "tail": _tail, "remaining": remaining}
