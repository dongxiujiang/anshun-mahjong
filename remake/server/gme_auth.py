"""GME AuthBuffer generator (TEA, per Tencent GME server-side sample)."""
from __future__ import annotations
import os
import struct
import time

DELTA = 0x9E3779B9
ROUNDS = 16
SALT_LEN = 2
ZERO_LEN = 7


def _tea_encrypt_ecb(block: bytes, key: bytes) -> bytes:
    y, z = struct.unpack(">II", block)
    k = struct.unpack(">IIII", key)
    total = 0
    for _ in range(ROUNDS):
        total = (total + DELTA) & 0xFFFFFFFF
        y = (y + ((((z << 4) + k[0]) & 0xFFFFFFFF) ^ ((z + total) & 0xFFFFFFFF) ^ (((z >> 5) + k[1]) & 0xFFFFFFFF))) & 0xFFFFFFFF
        z = (z + ((((y << 4) + k[2]) & 0xFFFFFFFF) ^ ((y + total) & 0xFFFFFFFF) ^ (((y >> 5) + k[3]) & 0xFFFFFFFF))) & 0xFFFFFFFF
    return struct.pack(">II", y, z)


def _tea_symmetry_encrypt(data: bytes, key: bytes) -> bytes:
    if len(key) < 16:
        raise ValueError("GME AppKey 至少需要 16 字节")
    key = key[:16]
    total = len(data) + 1 + SALT_LEN + ZERO_LEN
    pad_len = total % 8
    if pad_len:
        pad_len = 8 - pad_len

    src = bytearray(8)
    src[0] = (os.urandom(1)[0] & 0xF8) | pad_len
    src_i = 1
    for _ in range(pad_len):
        src[src_i] = os.urandom(1)[0]
        src_i += 1

    iv = bytearray(8)
    out = bytearray()

    def flush() -> None:
        nonlocal src_i, iv
        for i in range(8):
            src[i] ^= iv[i]
        encrypted = _tea_encrypt_ecb(bytes(src), key)
        out.extend(encrypted)
        iv = bytearray(encrypted)
        src_i = 0

    def feed(value: int) -> None:
        nonlocal src_i
        if src_i < 8:
            src[src_i] = value
            src_i += 1
        if src_i == 8:
            flush()

    for _ in range(SALT_LEN):
        feed(os.urandom(1)[0])
    for value in data:
        feed(value)
    for _ in range(ZERO_LEN):
        feed(0)
    while src_i:
        feed(0)
    return bytes(out)


def make_auth_buffer(app_id: int, room: str, open_id: str, app_key: str,
                     ttl_seconds: int = 300) -> bytes:
    open_bytes = open_id.encode("utf-8")[:127]
    room_bytes = room.encode("utf-8")[:127]
    now = int(time.time())
    plain = bytearray()
    plain += struct.pack(">B", 1)
    plain += struct.pack(">H", len(open_bytes))
    plain += open_bytes
    plain += struct.pack(">I", int(app_id) & 0xFFFFFFFF)
    plain += struct.pack(">I", 0)
    plain += struct.pack(">I", (now + max(60, ttl_seconds)) & 0xFFFFFFFF)
    plain += struct.pack(">I", 0xFFFFFFFF)
    plain += struct.pack(">I", 0)
    plain += struct.pack(">H", len(room_bytes))
    plain += room_bytes
    return _tea_symmetry_encrypt(bytes(plain), app_key.encode("utf-8"))
