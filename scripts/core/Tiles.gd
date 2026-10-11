class_name Tiles
## 牌值工具：牌用字符串表示 "wan3" / "tiao1" / "tong8" 等（4 张同值牌即同字符串）。

const SUITS := ["wan", "tiao", "tong"]
const SUIT_WAN := "wan"
const SUIT_TIAO := "tiao"
const SUIT_TONG := "tong"
const RANKS := [1, 2, 3, 4, 5, 6, 7, 8, 9]

static func val(suit: String, rank: int) -> String:
	return suit + str(rank)

static func suit(tile: String) -> String:
	return tile.substr(0, tile.length() - 1)

static func rank(tile: String) -> int:
	return int(tile.substr(tile.length() - 1, 1))

## 全部 34 种牌值（按值排序，用于遍历听牌/有效张）
static func all_values() -> Array[String]:
	var out: Array[String] = []
	for s in SUITS:
		for r in RANKS:
			out.append(val(s, r))
	return out

## 鸡牌集合：一条、八筒
static func is_chicken(tile: String) -> bool:
	return tile == "tiao1" or tile == "tong8"

## 翻牌鸡三张：同花色上下相邻，1 与 9 首尾循环。
static func flip_related(flipped: String) -> Array[String]:
	if flipped == "":
		return []
	var s := suit(flipped)
	var r := rank(flipped)
	var out: Array[String] = []
	out.append(flipped)
	out.append(val(s, posmod(r - 2, 9) + 1))
	out.append(val(s, r % 9 + 1))
	return out

## 同值计数：hand 中该牌出现次数。hand 为 Array[String]
static func count(hand: Array, tile: String) -> int:
	var n := 0
	for t in hand:
		if t == tile: n += 1
	return n

## 手牌转计数字典 {tile:count}
static func to_counts(hand: Array) -> Dictionary:
	var d := {}
	for t in hand:
		d[t] = d.get(t, 0) + 1
	return d

## 某值的 0..26 索引（用于 9x3 矩阵运算） = 花色*9 + (rank-1)
static func value_index(tile: String) -> int:
	return SUITS.find(suit(tile)) * 9 + (rank(tile) - 1)

## 花色索引 0..2
static func suit_index(tile: String) -> int:
	return SUITS.find(suit(tile))

## 由价值索引反推牌值字符串（0..26）
static func from_index(idx: int) -> String:
	return SUITS[idx / 9] + str(idx % 9 + 1)

## 34 个价值的索引 0..26
static func all_indices() -> Array:
	var out := []
	for i in 27: out.append(i)
	return out

## 手牌排序（万→条→筒，各花色按 1→9）
static func sort_hand(hand: Array) -> Array:
	var arr: Array = hand.duplicate()
	arr.sort_custom(func(a, b): return value_index(a) < value_index(b))
	return arr

## 由记数字典构建 27 长计数数组
static func counts_array(counts: Dictionary) -> Array:
	var arr := []
	arr.resize(27)
	for i in 27: arr[i] = 0
	for tile in counts:
		arr[value_index(tile)] = counts[tile]
	return arr

## 手牌数组直接转 27 长计数数组
static func hand_to_counts_array(hand: Array) -> Array:
	var d := to_counts(hand)
	return counts_array(d)
