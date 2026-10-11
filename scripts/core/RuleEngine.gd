class_name RuleEngine
## 判胡 / 番型 / 听牌。
## 手牌模型：
##   concealed  : 手内未固定的牌 (Array[String])
##   melds      : 已固定的面子 (Array[{kind:"pung"|"kong", tile:String}])，本打法定式全为刻子/杠
## e = melds.size()，concealed 应含 3*(4-e)+2 张（即 4面子1将 中非固定部分）。

static func exposed_melds_count(melds: Array) -> int:
	return melds.size()

## ---- 拆解 ----
## 剩余计数数组可否全部拆成 melds_left 个面子（刻/顺），返回是否成功
static func _melds_ok(arr: Array, melds_left: int, idx: int) -> bool:
	if melds_left == 0:
		for v in arr:
			if v != 0: return false
		return true
	# 找第一个非零
	var i := -1
	for k in range(idx, 27):
		if arr[k] > 0:
			i = k
			break
	if i < 0: return false
	# 刻
	if arr[i] >= 3:
		arr[i] -= 3
		var ok3 := _melds_ok(arr, melds_left - 1, i)
		arr[i] += 3
		if ok3: return true
	# 顺（须同花色：i%9<=6）
	if i % 9 <= 6 and arr[i] > 0 and arr[i + 1] > 0 and arr[i + 2] > 0:
		arr[i] -= 1; arr[i + 1] -= 1; arr[i + 2] -= 1
		var ok21 := _melds_ok(arr, melds_left - 1, i)
		arr[i] += 1; arr[i + 1] += 1; arr[i + 2] += 1
		if ok21: return true
	return false

## 普通胡（4面子1将），melds_needed 来自 concealed 的面子数
static func _win_normal(arr: Array, melds_needed: int) -> bool:
	for i in 27:
		if arr[i] >= 2:
			arr[i] -= 2
			var ok := _melds_ok(arr, melds_needed, 0)
			arr[i] += 2
			if ok: return true
	return false

## 小七对：无固定面子且每个牌恰好成对（7对）
static func _is_seven_pairs(concealed: Array) -> bool:
	if concealed.size() != 14: return false
	var counts := Tiles.to_counts(concealed)
	for tile in counts:
		if counts[tile] % 2 != 0: return false
	return true

## 大队子(对对胡)：固定面子全为刻/杠，且 concealed 仅含刻+1将（无顺）
static func _all_triplets_ok(arr: Array, melds_left: int, idx: int) -> bool:
	if melds_left == 0:
		for v in arr:
			if v != 0: return false
		return true
	var i := -1
	for k in range(idx, 27):
		if arr[k] > 0:
			i = k
			break
	if i < 0: return false
	if arr[i] >= 3:
		arr[i] -= 3
		var ok3 := _all_triplets_ok(arr, melds_left - 1, i)
		arr[i] += 3
		if ok3: return true
	return false

static func _is_all_triplets(concealed: Array, melds: Array, melds_needed: int) -> bool:
	# concealed 可拆成 melds_needed 个刻 + 1 对将
	var arr := Tiles.hand_to_counts_array(concealed)
	for i in 27:
		if arr[i] >= 2:
			arr[i] -= 2
			var ok := _all_triplets_ok(arr, melds_needed, 0)
			arr[i] += 2
			if ok: return true
	return false

## 清一色：concealed 与 固定面子 全部同花色
static func _is_flush(concealed: Array, melds: Array) -> bool:
	var suit := ""
	var first := true
	for t in concealed:
		var s := Tiles.suit(t)
		if first: suit = s; first = false
		elif s != suit: return false
	for m in melds:
		var s := Tiles.suit(m.tile)
		if first: suit = s; first = false
		elif s != suit: return false
	return not first

## 综合分析手牌是否为胡、以及叠加番型标记
## 返回: {"win":bool, "seven_pairs":bool, "all_triplets":bool, "flush":bool}
static func analyze(concealed: Array, melds: Array) -> Dictionary:
	var e := exposed_melds_count(melds)
	var invalid := {"win": false, "normal": false, "seven_pairs": false, "dragon_seven_pairs": false, "all_triplets": false, "flush": false}
	if e > 4 or concealed.size() != 3 * (4 - e) + 2:
		return invalid
	var counts := Tiles.to_counts(concealed)
	for tile in counts:
		if not Tiles.all_values().has(tile) or counts[tile] > 4:
			return invalid
	for meld in melds:
		if meld.get("kind", "") not in ["pung", "kong", "add_kong"] or not Tiles.all_values().has(meld.get("tile", "")):
			return invalid
		counts[meld.tile] = counts.get(meld.tile, 0) + (3 if meld.kind == "pung" else 4)
		if counts[meld.tile] > 4:
			return invalid
	var arr := Tiles.hand_to_counts_array(concealed)
	var melds_needed := 4 - e
	# 普通胡
	var normal := _win_normal(arr.duplicate(), melds_needed)
	var seven_pairs := false
	var dragon_seven_pairs := false
	var all_triplets := false
	if e == 0 and _is_seven_pairs(concealed):
		seven_pairs = true
		dragon_seven_pairs = counts.values().has(4)
	else:
		all_triplets = _is_all_triplets(concealed, melds, melds_needed)
	var flush := _is_flush(concealed, melds)
	return {
		"win": normal or seven_pairs or all_triplets,
		"normal": normal,
		"seven_pairs": seven_pairs,
		"dragon_seven_pairs": dragon_seven_pairs,
		"all_triplets": all_triplets,
		"flush": flush,
	}

## 加入一张牌后能否胡（用于自摸/听牌/胡别家）
static func can_win_on(concealed: Array, melds: Array, tile: String) -> bool:
	var combined := concealed.duplicate()
	combined.append(tile)
	return analyze(combined, melds).win

## 听牌（等待）集合：返回能胡的牌值 (Array[String])
static func waiting_tiles(concealed: Array, melds: Array) -> Array:
	var waits: Array = []
	for v in Tiles.all_values():
		if can_win_on(concealed, melds, v):
			waits.append(v)
	return waits

## 是否听牌
static func is_tenpai(concealed: Array, melds: Array) -> bool:
	return not waiting_tiles(concealed, melds).is_empty()

## 计算完整手牌的番型（供结算用）
static func hand_pattern(concealed: Array, melds: Array) -> Dictionary:
	return analyze(concealed, melds)
