extends RefCounted
## 本地玩家生涯战绩、连胜火焰与安顺捉鸡大牌成就图鉴（纯本地持久化，绝不影响权威规则与计分）。

const DEFAULT_PATH := "user://dongxiu-career-v1.cfg"

const RANKS := [
	{"min_wins": 0, "title": "麻坛新秀"},
	{"min_wins": 3, "title": "竹林雀士"},
	{"min_wins": 10, "title": "青玉妙手"},
	{"min_wins": 25, "title": "捉鸡名家"},
	{"min_wins": 50, "title": "金鸡尊师"},
	{"min_wins": 100, "title": "安顺雀圣"},
]

const BADGE_ORDER := [
	"first_win", "streak_3", "charge_chicken", "gold_chicken",
	"flush_master", "seven_pairs", "all_triplets", "kong_bloom",
]

const BADGES := {
	"first_win": {"name": "初试锋芒", "desc": "赢得首局安顺麻将"},
	"streak_3": {"name": "三连鸿运", "desc": "达成连续 3 局胡牌"},
	"charge_chicken": {"name": "冲锋先锋", "desc": "凭冲锋鸡斩获加分"},
	"gold_chicken": {"name": "金鸡报喜", "desc": "命中金鸡或冲锋金鸡"},
	"flush_master": {"name": "清一色大师", "desc": "胡出清一色大牌"},
	"seven_pairs": {"name": "七对奇才", "desc": "胡出小七对或龙七对"},
	"all_triplets": {"name": "对对碰王", "desc": "胡出大对子或单吊"},
	"kong_bloom": {"name": "杠上生花", "desc": "达成杠上开花或抢杠胡"},
}

var _path: String
var stats := {
	"rounds": 0,
	"wins": 0,
	"self_draws": 0,
	"streak": 0,
	"best_streak": 0,
	"best_round_gain": 0,
	"total_net": 0,
	"chickens_hit": 0,
	"gold_chickens": 0,
	"charge_chickens": 0,
}
var unlocked := {}
var _seen_rounds := {}

func _init(path: String = DEFAULT_PATH) -> void:
	_path = path
	_load()

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK or int(cfg.get_value("format", "version", 0)) != 1:
		return
	for key in stats:
		stats[key] = int(cfg.get_value("stats", key, stats[key]))
	var saved_badges = cfg.get_value("badges", "unlocked", PackedStringArray())
	if saved_badges is PackedStringArray or saved_badges is Array:
		for id in saved_badges:
			if BADGES.has(str(id)):
				unlocked[str(id)] = true

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("format", "version", 1)
	for key in stats:
		cfg.set_value("stats", key, int(stats[key]))
	var list := PackedStringArray()
	for id in BADGE_ORDER:
		if unlocked.has(id):
			list.append(id)
	cfg.set_value("badges", "unlocked", list)
	var tmp := _path + ".tmp"
	if cfg.save(tmp) == OK:
		if DirAccess.rename_absolute(tmp, _path) != OK:
			DirAccess.remove_absolute(tmp)

func rank_title() -> String:
	var title := "麻坛新秀"
	for entry in RANKS:
		if int(stats.wins) >= int(entry.min_wins):
			title = str(entry.title)
	return title

func win_rate_percent() -> int:
	if int(stats.rounds) <= 0:
		return 0
	return roundi(float(stats.wins) * 100.0 / float(stats.rounds))

func record_settlement(round_key: String, settlement: Dictionary, viewer_seat: int) -> Dictionary:
	if round_key.is_empty() or _seen_rounds.has(round_key) or settlement.is_empty():
		return {}
	var ledger: Dictionary = settlement.get("ledger", {})
	var deltas: Array = ledger.get("deltas", [])
	if viewer_seat < 0 or viewer_seat >= deltas.size():
		return {}
	_seen_rounds[round_key] = true
	var newly_unlocked: PackedStringArray = PackedStringArray()
	var delta := int(deltas[viewer_seat])
	var winners: Array = ledger.get("winners", [])
	var won: bool = winners.has(viewer_seat)
	var self_draw: bool = won and bool(settlement.get("round_meta", {}).get("self_draw", false))
	stats.rounds = int(stats.rounds) + 1
	stats.total_net = int(stats.total_net) + delta
	var new_record := false
	if delta > int(stats.best_round_gain):
		stats.best_round_gain = delta
		if int(stats.rounds) > 1 and delta > 0:
			new_record = true
	if won:
		stats.wins = int(stats.wins) + 1
		if self_draw:
			stats.self_draws = int(stats.self_draws) + 1
		stats.streak = int(stats.streak) + 1
		stats.best_streak = maxi(int(stats.best_streak), int(stats.streak))
		_grant("first_win", newly_unlocked)
		if int(stats.streak) >= 3:
			_grant("streak_3", newly_unlocked)
	else:
		stats.streak = 0
	var items_all: Array = ledger.get("items", [])
	if viewer_seat < items_all.size():
		for entry in items_all[viewer_seat]:
			var amount := int(entry.get("amount", 0))
			var kind := str(entry.get("kind", ""))
			var label := str(entry.get("label", ""))
			if amount > 0:
				if kind in ["chicken", "charge", "flip"]:
					var count := maxi(1, entry.get("tiles", []).size())
					stats.chickens_hit = int(stats.chickens_hit) + count
					if label.contains("冲锋"):
						stats.charge_chickens = int(stats.charge_chickens) + count
						_grant("charge_chicken", newly_unlocked)
					if label.contains("金鸡"):
						stats.gold_chickens = int(stats.gold_chickens) + count
						_grant("gold_chicken", newly_unlocked)
				if won:
					if label.contains("清一色"):
						_grant("flush_master", newly_unlocked)
					if label.contains("七对"):
						_grant("seven_pairs", newly_unlocked)
					if label.contains("大对子") or label.contains("单吊"):
						_grant("all_triplets", newly_unlocked)
					if label.contains("杠开") or label.contains("抢杠"):
						_grant("kong_bloom", newly_unlocked)
	_save()
	return {
		"won": won,
		"delta": delta,
		"streak": int(stats.streak),
		"new_record": new_record,
		"new_badges": newly_unlocked,
	}

func _grant(id: String, out: PackedStringArray) -> void:
	if not unlocked.has(id) and BADGES.has(id):
		unlocked[id] = true
		out.append(str(BADGES[id].name))
