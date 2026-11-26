"""Private, bounded diagnosis archive. The shipped rules engine verifies every new game."""
from collections import deque
from datetime import datetime, timezone
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import threading
import time

MAX_RECORD = 2 * 1024 * 1024
HEX = re.compile(r"[a-f0-9]{64}")
IDENTIFIER = re.compile(r"(?:(?:solo|lan|online):)?[a-f0-9]{64}:[1-9][0-9]{0,9}")
FIELDS = {"variant_id", "rules_version", "record_version", "protocol_version", "round_number", "dealer",
          "carry_multiplier", "wall", "dice", "inputs", "facts", "ledger", "next_dealer_seat", "checksum"}


class RecordError(Exception):
    def __init__(self, status, message):
        self.status = status
        super().__init__(message)


class RecordStore:
    def __init__(self, godot, project, runtime, limit):
        self.godot, self.project, self.runtime = str(godot), str(project), Path(runtime)
        if not 1 <= limit <= 10000:
            raise ValueError("record limit must be between 1 and 10000")
        self.limit = limit
        self.lock = threading.Lock()
        self.validators = threading.BoundedSemaphore(2)
        self.attempts = {}
        self.db = sqlite3.connect(self.runtime / "rounds.sqlite3", check_same_thread=False)
        self.db.execute("CREATE TABLE IF NOT EXISTS records (seq INTEGER PRIMARY KEY, id TEXT UNIQUE, mode TEXT NOT NULL, "
                        "checksum TEXT NOT NULL, transport TEXT NOT NULL, created TEXT NOT NULL, tape BLOB NOT NULL)")
        if "authority_verified" not in {column[1] for column in self.db.execute("PRAGMA table_info(records)")}:
            self.db.execute("ALTER TABLE records ADD COLUMN authority_verified INTEGER NOT NULL DEFAULT 0")
        with self.db:
            self._prune()

    def _prune(self):
        self.db.execute("DELETE FROM records WHERE seq NOT IN (SELECT seq FROM records ORDER BY seq DESC LIMIT ?)", (self.limit,))

    def admit(self, address):
        now = time.monotonic()
        with self.lock:
            self.attempts = {k: times for k, times in self.attempts.items() if times and times[-1] > now - 60}
            if len(self.attempts) >= 4096 and address not in self.attempts:
                raise RecordError(429, "提交请求过多")
            history = self.attempts.setdefault(address, deque())
            while history and history[0] <= now - 60:
                history.popleft()
            if len(history) >= 30:
                raise RecordError(429, "提交过于频繁，请稍后重试")
            history.append(now)

    def _verify(self, raw):
        if not self.validators.acquire(blocking=False):
            raise RecordError(503, "牌谱校验繁忙，请稍后重试")
        path = None
        try:
            with tempfile.NamedTemporaryFile(dir=self.runtime, suffix=".pending", delete=False) as pending:
                path = Path(pending.name)
                pending.write(raw)
            cmd = [self.godot, "--headless", "--path", self.project, "--script", "res://src/network/VerifyRecord.gd", "--", str(path)]
            # The validator only needs the rules project and a temporary JSON file.
            env = {k: v for k, v in os.environ.items() if k not in {"GME_APP_KEY", "RECORDS_API_KEY", "DONGXIU_RECORD_SIGNING_KEY"}}
            result = subprocess.run(cmd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL, timeout=15,
                                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
            if result.returncode != 0 or b"DONGXIU_REPLAY_OK" not in result.stdout.splitlines():
                raise RecordError(422, "权威规则重演未通过，牌谱未保存")
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise RecordError(503, "校验服务暂时不可用，牌谱未保存") from exc
        finally:
            if path:
                path.unlink(missing_ok=True)
            self.validators.release()

    def submit(self, data, authority_verified=False):
        if set(data) != {"mode", "room_instance_id", "record"} or data["mode"] not in ("solo", "lan", "online"):
            raise RecordError(400, "牌谱来源无效")
        instance, record, mode = data["room_instance_id"], data["record"], data["mode"]
        if mode == "online" and not authority_verified:
            raise RecordError(403, "在线牌谱来源验证失败")
        if not isinstance(instance, str) or not HEX.fullmatch(instance) or not isinstance(record, dict) or set(record) != FIELDS:
            raise RecordError(400, "新版牌谱格式无效")
        number = record.get("round_number")
        checksum = record.get("checksum")
        if type(number) not in (int, float) or not 1 <= number <= 2147483647 or number != int(number):
            raise RecordError(400, "局数无效")
        if not isinstance(checksum, str) or not HEX.fullmatch(checksum):
            raise RecordError(400, "牌谱摘要无效")
        if not isinstance(record["wall"], list) or len(record["wall"]) != 108 or not isinstance(record["inputs"], list) or not 1 <= len(record["inputs"]) <= 1024:
            raise RecordError(400, "牌谱缺少完整牌墙或操作")
        identifier = f"{instance}:{int(number)}"
        storage_id = f"{mode}:{identifier}"
        try:
            raw = json.dumps(record, ensure_ascii=False, separators=(",", ":"), sort_keys=True, allow_nan=False).encode("utf-8")
        except (ValueError, UnicodeError, RecursionError):
            raise RecordError(400, "牌谱 JSON 无效") from None
        if len(raw) > MAX_RECORD:
            raise RecordError(413, "牌谱超过2MiB")
        transport = hashlib.sha256(raw).hexdigest()
        received = {"status": "stored", "id": identifier, "checksum": checksum}
        with self.lock:
            saved = self.db.execute("SELECT checksum, transport, mode FROM records WHERE id=?", (storage_id,)).fetchone()
            if saved:
                if saved[0] != checksum or saved[2] != mode:
                    raise RecordError(409, "同一局已有不同记录，未覆盖")
                if saved[1] == transport:
                    return {**received, "duplicate": True}
        self._verify(raw)
        # Race-safe across threads and a directory-only restart sharing the same SQLite archive.
        packed = gzip.compress(raw, compresslevel=5)
        with self.lock, self.db:
            cursor = self.db.execute("INSERT OR IGNORE INTO records(id, mode, checksum, transport, created, tape, authority_verified) VALUES(?,?,?,?,?,?,?)",
                                     (storage_id, mode, checksum, transport, datetime.now(timezone.utc).isoformat(), packed, int(mode == "online" and authority_verified)))
            duplicate = cursor.rowcount == 0
            if duplicate:
                saved = self.db.execute("SELECT checksum, mode FROM records WHERE id=?", (storage_id,)).fetchone()
                if saved != (checksum, mode):
                    raise RecordError(409, "同一局已有不同记录，未覆盖")
            else:
                self._prune()
        return {**received, "duplicate": duplicate}

    def list_metadata(self, limit):
        with self.lock:
            results = self.db.execute("SELECT id, mode, checksum, created, authority_verified FROM records ORDER BY seq DESC LIMIT ?", (limit,)).fetchall()
        return [{"id": row[0], "mode": row[1], "checksum": row[2], "created": row[3], "authority_verified": bool(row[4])} for row in results]

    def summary(self):
        with self.lock:
            rows = self.db.execute("SELECT mode, COUNT(*) FROM records GROUP BY mode").fetchall()
        by_mode = {"online": 0, "lan": 0, "solo": 0}
        total = 0
        for mode, count in rows:
            c = int(count)
            total += c
            if mode in by_mode:
                by_mode[mode] = c
        return {"total": total, "by_mode": by_mode}

    def read(self, identifier):
        if not IDENTIFIER.fullmatch(identifier):
            raise RecordError(404, "记录不存在")
        with self.lock:
            row = self.db.execute("SELECT mode, tape, authority_verified FROM records WHERE id=?", (identifier,)).fetchone()
        if not row:
            raise RecordError(404, "记录不存在")
        return {"id": identifier, "mode": row[0], "record": json.loads(gzip.decompress(row[1])), "authority_verified": bool(row[2])}

    def close(self):
        with self.lock:
            self.db.close()
