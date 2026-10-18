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

## 大对子(对对胡)：固定面子全为刻/杠，且 concealed 仅含刻+1将（无顺）
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

static func _is_single_wait(concealed: Array, melds: Array, winning_tile: String, require_flush: bool) -> bool:
	# 单吊：胡牌前只剩四组面子和一张单牌，胡牌张正好与单牌配成将。
	# 用实际胡牌张检查，避免把普通清一色对子手误判成单吊；不能调用 is_tenpai，
	# 因为 analyze() 本身会计算牌型标记。
	if winning_tile == "" or not concealed.has(winning_tile):
		return false
	if require_flush and not _is_flush(concealed, melds):
		return false
	# §十六：手牌只剩一张，必须已有四组固定碰杠；手内可拆面子不算。
	return melds.size() == 4 and concealed.size() == 2 \
		and concealed[0] == winning_tile and concealed[1] == winning_tile \
		and melds.all(func(m): return m.get("kind", "") in ["pung", "kong", "add_kong"])

## 综合分析手牌是否为胡、以及叠加番型标记
## 返回: {"win":bool, "seven_pairs":bool, "all_triplets":bool, "flush":bool}
static func analyze(concealed: Array, melds: Array, winning_tile: String = "") -> Dictionary:
	var e := exposed_melds_count(melds)
	var invalid := {"win": false, "normal": false, "seven_pairs": false, "dragon_seven_pairs": false, "all_triplets": false, "flush": false, "clean_big_triplets": false, "clean_single_wait": false, "clean_dragon_seven_pairs": false, "clean_seven_pairs": false, "big_triplet_single_wait": false}
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
	var clean_big_triplets := all_triplets and flush
	var clean_dragon_seven_pairs := dragon_seven_pairs and flush
	var clean_seven_pairs := seven_pairs and flush
	var big_triplet_single_wait := all_triplets and _is_single_wait(concealed, melds, winning_tile, false)
	var clean_single_wait := _is_single_wait(concealed, melds, winning_tile, true)
	return {
		"win": normal or seven_pairs or all_triplets,
		"normal": normal,
		"seven_pairs": seven_pairs,
		"dragon_seven_pairs": dragon_seven_pairs,
		"all_triplets": all_triplets,
		"flush": flush,
		"clean_big_triplets": clean_big_triplets,
		"clean_single_wait": clean_single_wait,
		"clean_dragon_seven_pairs": clean_dragon_seven_pairs,
		"clean_seven_pairs": clean_seven_pairs,
		"big_triplet_single_wait": big_triplet_single_wait,
	}

## 加入一张牌后能否胡（用于自摸/听牌/胡别家）
static func can_win_on(concealed: Array, melds: Array, tile: String) -> bool:
	var combined := concealed.duplicate()
	combined.append(tile)
	# 合法手牌上向听数 == -1 与 analyze().win 完全等价（已用数万样本验证），先用向听数快速剪枝，
	# 避免对 27 张候选牌逐一做完整递归拆解；只有真正成胡的那几张才走 analyze 确认牌型。
	if Shanten.shanten(combined, melds) > -1:
		return false
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
static func hand_pattern(concealed: Array, melds: Array, winning_tile: String = "") -> Dictionary:
	return analyze(concealed, melds, winning_tile)

## 返回实际计分时应使用的牌型。清牌型是替代分，不与其组成牌型重复相加。
static func special_pattern_key(pattern: Dictionary) -> String:
	if pattern.get("clean_dragon_seven_pairs", false):
		return "clean_dragon_seven_pairs"
	if pattern.get("clean_single_wait", false):
		return "clean_single_wait"
	if pattern.get("clean_seven_pairs", false):
		return "clean_seven_pairs"
	if pattern.get("clean_big_triplets", false):
		return "clean_big_triplets"
	if pattern.get("big_triplet_single_wait", false):
		return "big_triplet_single_wait"
	return ""

static func is_scoring_pattern(pattern: Dictionary, key: String) -> bool:
	var special := special_pattern_key(pattern)
	return key == special if special != "" else bool(pattern.get(key, false))
