class_name WallRing
extends RefCounted
## 逻辑环形牌墙按顺时针跨墙：下家(1)→庄家(0)→上家(3)→对家(2)。
## 牌头沿索引递增取牌；杠从牌尾反向补。

const N := 108
const SEG := {
	0: {"start": 0,  "len": 26, "seat": 1},  # 下家/右
	1: {"start": 26, "len": 28, "seat": 0},  # 庄家/下
	2: {"start": 54, "len": 26, "seat": 3},  # 上家/左
	3: {"start": 80, "len": 28, "seat": 2},  # 对家/上
}

var _ring: Array = []       # 108 张牌字符串，按顺时针逻辑次序
var _drawn: Array[bool] = []
var _head := 0
var _tail := 0
var remaining := 108
var _segments: Dictionary

const SUIT_LEN := 26  # 砖数单位，仅供内部：每砖2张
const PAIR := 2

func _init(ring_tiles: Array, dealer_seat: int = 0):
	# ring_tiles 为 108 张，按逻辑逆时针（与 SEG 边界一致）传入
	assert(ring_tiles.size() == N)
	_ring = ring_tiles.duplicate()
	_segments = segments_for_dealer(dealer_seat)
	_drawn.resize(N)
	_drawn.fill(false)

## 根据骰子点数 D 计算牌头索引（本子按你描述的规则）：
##   D∈{1,3,5} -> 对家墙；D=4 -> 上家；D∈{2,6} -> 下家。
static func segments_for_dealer(dealer_seat: int) -> Dictionary:
	var segments := {}
	var start := 0
	for index in 4:
		var seat := int(SEG[index].seat)
		var length := 28 if posmod(seat - dealer_seat, 2) == 0 else 26
		segments[index] = {"start": start, "len": length, "seat": seat}
		start += length
	return segments

static func compute_break(die: int, dealer_seat: int = 0) -> int:
	var offset := 2 if die in [1, 3, 5] else (3 if die == 4 else 1)
	var target := posmod(dealer_seat + offset, 4)
	for segment in segments_for_dealer(dealer_seat).values():
		if int(segment.seat) == target:
			return int(segment.start) + die * PAIR
	return 0

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

## 从牌头摸 1 张（逆时针）。空返回 ""（流局）
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
	for key in _segments:
		if _segments[key].seat == seat: return _segments[key]
	return _segments[0]

func remaining_in_wall_until_empty() -> bool:
	return remaining <= 0

## 剩余最后四张（用于"最后四张自摸+5"）：当前尚未摸的张数 <=4 且将要摸
func is_global_tail_four() -> bool:
	return remaining <= 4

# 调试
func debug_ring_head_tail() -> Dictionary:
	return {"head": _head, "tail": _tail, "remaining": remaining}
