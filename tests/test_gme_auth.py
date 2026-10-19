"""Smoke checks for the GME AuthBuffer layout (TEA/CBC round-trip)."""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "server"))
from gme_auth import DELTA, ROUNDS, make_auth_buffer


def tea_decrypt(block, key):
    y, z = struct.unpack(">II", block)
    k = struct.unpack(">IIII", key)
    total = (DELTA * ROUNDS) & 0xFFFFFFFF
    for _ in range(ROUNDS):
        z = (z - ((((y << 4) + k[2]) & 0xFFFFFFFF) ^ ((y + total) & 0xFFFFFFFF) ^ (((y >> 5) + k[3]) & 0xFFFFFFFF))) & 0xFFFFFFFF
        y = (y - ((((z << 4) + k[0]) & 0xFFFFFFFF) ^ ((z + total) & 0xFFFFFFFF) ^ (((z >> 5) + k[1]) & 0xFFFFFFFF))) & 0xFFFFFFFF
        total = (total - DELTA) & 0xFFFFFFFF
    return struct.pack(">II", y, z)


def decrypt(payload, key):
    key = key[:16].encode()
    out = bytearray()
    iv = b"\x00" * 8
    for offset in range(0, len(payload), 8):
        block = payload[offset:offset + 8]
        plain = tea_decrypt(block, key)
        out.extend(bytes(a ^ b for a, b in zip(plain, iv)))
        iv = block
    return bytes(out)


def main():
    key = "0123456789abcdef"
    payload = make_auth_buffer(1400802279, "123456", "seat1", key)
    assert payload and len(payload) % 8 == 0
    plain = decrypt(payload, key)
    # TeaSymmetryEncrypt prefixes PadLen + padding + 2-byte salt before the
    # actual AuthBuffer plaintext.
    pad_len = plain[0] & 0x07
    pos = 1 + pad_len + 2
    assert plain[pos] == 1
    open_len = struct.unpack(">H", plain[pos + 1:pos + 3])[0]
    pos += 3
    assert plain[pos:pos + open_len] == b"seat1"
    pos += open_len
    assert struct.unpack(">I", plain[pos:pos + 4])[0] == 1400802279
    pos += 4 + 4
    exp = struct.unpack(">I", plain[pos:pos + 4])[0]
    assert exp > 0
    pos += 4 + 4 + 4
    room_len = struct.unpack(">H", plain[pos:pos + 2])[0]
    pos += 2
    assert plain[pos:pos + room_len] == b"123456"
    print("gme auth checks passed")


if __name__ == "__main__":
    main()
