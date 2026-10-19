"""Minimal LiveKit access-token signer (HS256, no third-party dependencies)."""
from __future__ import annotations
import base64
import hashlib
import hmac
import json
import time


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def make_token(api_key: str, api_secret: str, room: str, identity: str,
               name: str = "", ttl_seconds: int = 3600) -> str:
    if not api_key or not api_secret:
        raise ValueError("LiveKit API key/secret 未配置")
    now = int(time.time())
    header = {"alg": "HS256", "typ": "JWT"}
    claims = {
        "iss": api_key,
        "sub": identity,
        "name": name or identity,
        "nbf": now - 5,
        "exp": now + max(60, int(ttl_seconds)),
        "video": {
            "room": room,
            "roomJoin": True,
            "canPublish": True,
            "canSubscribe": True,
            "canPublishData": True,
        },
    }
    signing_input = b".".join((
        _b64(json.dumps(header, separators=(",", ":")).encode("utf-8")).encode("ascii"),
        _b64(json.dumps(claims, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).encode("ascii"),
    ))
    signature = hmac.new(api_secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return signing_input.decode("ascii") + "." + _b64(signature)
