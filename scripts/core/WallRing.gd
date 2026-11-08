class_name WallRing
extends RefCounted
## 物理牌墙按顺时针跨墙：北(上)→东(右)→南(下)→西(左)。
## 牌头沿索引递增取牌；杠从牌尾反向补。
## 注意：这是墙段顺序，不是玩家出牌顺序；玩家出牌仍是逆时针。

const N := 108
## 固定四墙：北14列、东13列、南14列、西13列。
## 每列两行，平铺成 108 个“列优先”槽位：
## 北 0..27，东 28..53，南 54..81，西 82..107。
const SEG := {
	0: {"start": 0,  "len": 28, "seat": 3},  # 北/上，14列
	1: {"start": 28, "len": 26, "seat": 0},  # 东/右，13列
	2: {"start": 54, "len": 28, "seat": 1},  # 南/下，14列
	3: {"start": 82, "len": 26, "seat": 2},  # 西/左，13列
}

var _ring: Array = []       # 108 张牌字符串，按顺时针逻辑次序
var _drawn: Array[bool] = []
var _head := 0
var _tail := 0
var remaining := 108
var _segments: Dictionary
## 调试牌墙按真实取牌顺序回放；正式逻辑不读取。
var draw_log: Array = []

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
static func segments_for_dealer(_dealer_seat: int) -> Dictionary:
	# 四墙长度是固定的，不随庄家改变；庄家只影响破墙方向。
	return SEG.duplicate(true)

static func compute_break(die: int, dealer_seat: int = 0) -> int:
	# 逆时针玩家顺序下：下家=dealer-1，上家=dealer+1。
	var offset := 2 if die in [1, 3, 5] else (1 if die == 4 else 3)
	var target := posmod(dealer_seat + offset, 4)
	for segment in segments_for_dealer(dealer_seat).values():
		if int(segment.seat) == target:
			return int(segment.start) + die * PAIR
	return 0

func set_head(break_idx: int):
	_head = break_idx
	remaining = N
	_drawn.fill(false)
	draw_log.clear()
	_tail = _tail_index()

func positive_mod(v: int, m: int) -> int:
	var r := v % m
	return r + m if r < 0 else r

func _advance(idx: int) -> int: return positive_mod(idx + 1, N)

## 杠后补牌从全墙最后一列开始：先上层，再下层，再前一列。
func _tail_index() -> int:
	for col in range(53, -1, -1):
		for row in 2:
			var index := col * 2 + row
			if not _drawn[index]: return index
	return -1

## 窥视牌头下一张（不消耗，用于翻牌鸡结算）
func peek_head() -> String:
	var index := peek_head_index()
	return str(_ring[index]) if index >= 0 else ""

func peek_head_index() -> int:
	if remaining <= 0: return -1
	var i := _head
	while _drawn[i]:
		i = _advance(i)
		if i == _head: return -1
	return i

## 从牌头摸 1 张（逆时针）。空返回 ""（流局）
func draw_head() -> String:
	if remaining <= 0: return ""
	while _drawn[_head]:
		_head = _advance(_head)
	var tile: String = _ring[_head]
	_drawn[_head] = true
	draw_log.append({"index": _head, "tail": false})
	_head = _advance(_head)
	remaining -= 1
	return tile

## 从牌尾补 1 张（杠）。同一列先上后下，再前一列。
func draw_tail() -> String:
	if remaining <= 0: return ""
	_tail = _tail_index()
	if _tail < 0: return ""
	var tile: String = _ring[_tail]
	_drawn[_tail] = true
	draw_log.append({"index": _tail, "tail": true})
	remaining -= 1
	_tail = _tail_index()
	return tile

## 某座位面前牌墙（物理段）还剩下多少张未摸（用于 UI 显示）
func wall_remaining(seat: int) -> int:
	var seg = _wall_seg_for_seat(seat)
	var n := 0
	for i in range(seg.start, seg.start + seg.len):
		if not _drawn[i]: n += 1
	return n

## 每列两层是否还在：[上层 poker[0], 下层 poker[1]]。
func wall_stack_slots(seat: int) -> Array:
	var segment := _wall_seg_for_seat(seat)
	var slots: Array = []
	for index in range(segment.start, segment.start + segment.len, 2):
		slots.append([not _drawn[index], not _drawn[index + 1]])
	return _physical_slot_order(segment, slots)

func wall_stack_counts(seat: int) -> Array:
	var counts: Array = []
	for slot in wall_stack_slots(seat):
		counts.append(int(slot[0]) + int(slot[1]))
	return counts

## 调试牌墙：只回放到前 count 次取牌，让每次摸牌都能单独刷新。
func debug_stack_slots_at(seat: int, count: int) -> Array:
	var limit := clampi(count, 0, draw_log.size())
	var removed := {}
	for i in limit:
		removed[int(draw_log[i].get("index", -1))] = true
	var segment := _wall_seg_for_seat(seat)
	var slots: Array = []
	for index in range(segment.start, segment.start + segment.len, 2):
		slots.append([not removed.has(index), not removed.has(index + 1)])
	return _physical_slot_order(segment, slots)

func debug_stack_counts_at(seat: int, count: int) -> Array:
	var counts: Array = []
	for slot in debug_stack_slots_at(seat, count):
		counts.append(int(slot[0]) + int(slot[1]))
	return counts

## 南/西墙内部按逆序拿牌，但 debug 显示仍按物理左→右、上→下。
func _physical_slot_order(segment: Dictionary, slots: Array) -> Array:
	if int(segment.seat) not in [1, 2]:
		return slots
	var ordered: Array = []
	for index in range(slots.size() - 1, -1, -1):
		ordered.append(slots[index])
	return ordered

func debug_remaining_at(count: int) -> int:
	return N - clampi(count, 0, draw_log.size())

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
