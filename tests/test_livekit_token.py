"""Dependency-free checks for the LiveKit JWT signer."""
import base64
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "server"))
from livekit_token import make_token


def decode(part: str):
    return json.loads(base64.urlsafe_b64decode(part + "=" * (-len(part) % 4)))


def main():
    token = make_token("API_test", "secret_value", "123456", "seat2", "小明", 600)
    header, body, signature = token.split(".")
    assert decode(header)["alg"] == "HS256"
    claims = decode(body)
    assert claims["iss"] == "API_test"
    assert claims["sub"] == "seat2"
    assert claims["name"] == "小明"
    assert claims["video"]["room"] == "123456"
    assert claims["video"]["roomJoin"] is True
    assert claims["video"]["canPublish"] is True
    assert claims["video"]["canSubscribe"] is True
    assert signature
    print("livekit token checks passed")


if __name__ == "__main__":
    main()
