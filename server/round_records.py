"""Bounded, persistent samples for offline diagnosis; no game rules run here."""
from collections import Counter
from datetime import datetime, timezone
import gzip
import hashlib
import json
import math
from pathlib import Path
import re
import sqlite3
import threading
import time

MAX_BODY = 2 * 1024 * 1024
TILES = {f"{suit}{rank}" for suit in ("wan", "tiao", "tong") for rank in range(1, 10)}


def validate_record(data):
    if not isinstance(data, dict) or data.get("mode") not in ("single", "lan", "online"):
        raise ValueError("记录来源无效")
    record = data.get("record")
    if not isinstance(record, dict) or record.get("schema") != 1:
        raise ValueError("不支持的记录格式")
    if not isinstance(record.get("id"), str) or not re.fullmatch(r"[A-Za-z0-9_-]{8,128}", record["id"]):
        raise ValueError("对局编号无效")
    initial, wall, final = (record.get(key) for key in ("initial", "wall", "final"))
    if not all(isinstance(item, dict) for item in (initial, wall, final)):
        raise ValueError("缺少开局、牌墙或结算记录")
    players, ring, drawn = initial.get("players"), wall.get("ring"), wall.get("drawn")
    if initial.get("phase") != "playing" or not isinstance(players, list) or len(players) != 4:
        raise ValueError("初始牌局不完整")
    if not isinstance(ring, list) or any(not isinstance(tile, str) for tile in ring) or Counter(ring) != Counter({tile: 4 for tile in TILES}):
        raise ValueError("必须包含完整的108张真实牌墙")
    if not isinstance(drawn, list) or len(drawn) != 108 or any(type(value) is not bool for value in drawn):
        raise ValueError("牌墙摸取位置无效")
    for key, upper in (("head", 107), ("tail", 107), ("remaining", 108)):
        if type(wall.get(key)) is not int or not 0 <= wall[key] <= upper:
            raise ValueError("牌墙位置越界")
    if wall["remaining"] != drawn.count(False):
        raise ValueError("牌墙剩余数量不一致")
    for seat, player in enumerate(players):
        if not isinstance(player, dict) or player.get("seat") != seat or not isinstance(player.get("concealed"), list):
            raise ValueError("初始手牌不完整")
        if any(not isinstance(tile, str) or tile not in TILES for tile in player["concealed"]):
            raise ValueError("牌面快照不能代替完整记录")
    actions = record.get("actions")
    if not isinstance(actions, list) or not 1 <= len(actions) <= 1024:
        raise ValueError("缺少完整操作过程")
    previous = 0
    for action in actions:
        if not isinstance(action, dict) or action.get("kind") not in ("turn", "response") or not isinstance(action.get("decision"), dict):
            raise ValueError("操作记录无效")
        if type(action.get("seat")) is not int or action["seat"] not in range(4):
            raise ValueError("操作座位无效")
        elapsed = action.get("elapsed_ms")
        if type(elapsed) is not int or elapsed < previous:
            raise ValueError("操作时间顺序无效")
        previous = elapsed
    result = final.get("result")
    if not isinstance(final.get("fingerprint"), str) or not re.fullmatch(r"[0-9a-f]{64}", final["fingerprint"]) or not isinstance(result, dict):
        raise ValueError("只能提交已经结算的完整记录")
    deltas = result.get("deltas")
    if not isinstance(deltas, list) or len(deltas) != 4 or any(type(value) not in (int, float) or not math.isfinite(value) for value in deltas) or abs(sum(deltas)) > 0.001:
        raise ValueError("结算分数不完整或不守恒")
    return record


class RoundRecords:
    def __init__(self, path, limit=100):
        if not 1 <= limit <= 10000:
            raise ValueError("RECORDS_LIMIT 必须在1到10000之间")
        self.limit = limit
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.lock = threading.Lock()
        self.attempts = {}
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.execute("CREATE TABLE IF NOT EXISTS records (seq INTEGER PRIMARY KEY, id TEXT UNIQUE NOT NULL, submitted_at TEXT NOT NULL, digest TEXT NOT NULL, mode TEXT NOT NULL, payload BLOB NOT NULL)")
        with self.db:
            self._prune()

    def _prune(self):
        self.db.execute("DELETE FROM records WHERE seq NOT IN (SELECT seq FROM records ORDER BY seq DESC LIMIT ?)", (self.limit,))

    def allow_submit(self, client):
        now = time.monotonic()
        with self.lock:
            self.attempts = {key: [stamp for stamp in stamps if now - stamp < 60] for key, stamps in self.attempts.items() if stamps and now - stamps[-1] < 60}
            stamps = self.attempts.setdefault(client, [])
            if len(stamps) >= 60 or len(self.attempts) > 10000:
                return False
            stamps.append(now)
            return True

    def submit(self, data):
        record = validate_record(data)
        raw = json.dumps(record, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")
        if len(raw) > MAX_BODY:
            raise ValueError("记录超过2MB上限")
        digest = hashlib.sha256(raw).hexdigest()
        with self.lock, self.db:
            existing = self.db.execute("SELECT submitted_at, digest FROM records WHERE id=?", (record["id"],)).fetchone()
            if existing:
                if existing[1] != digest:
                    raise FileExistsError("同一局的记录内容不一致，未覆盖原记录")
                return {"id": record["id"], "submitted_at": existing[0], "duplicate": True}
            stamp = datetime.now(timezone.utc).isoformat(timespec="microseconds")
            self.db.execute("INSERT INTO records (id, submitted_at, digest, mode, payload) VALUES (?, ?, ?, ?, ?)", (record["id"], stamp, digest, data["mode"], gzip.compress(raw)))
            self._prune()
            return {"id": record["id"], "submitted_at": stamp, "duplicate": False}

    def latest(self, limit):
        if not 1 <= limit <= 10000:
            raise ValueError("limit 必须在1到10000之间")
        with self.lock:
            rows = self.db.execute("SELECT id, submitted_at, mode, payload FROM records ORDER BY seq DESC LIMIT ?", (min(limit, self.limit),)).fetchall()
            total = self.db.execute("SELECT COUNT(*) FROM records").fetchone()[0]
        return {"count": len(rows), "total": total, "capacity": self.limit, "records": [{"id": row[0], "submitted_at": row[1], "mode": row[2], "record": json.loads(gzip.decompress(row[3]))} for row in rows]}

    def close(self):
        with self.lock:
            self.db.close()
