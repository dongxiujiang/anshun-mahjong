import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "update"))
import publish_self_hosted as publish


class PublishSelfHostedTests(unittest.TestCase):
    def test_rewrites_urls_and_verifies_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            payload = b"test-apk"
            (release / "anshun-mahjong.apk").write_bytes(payload)
            data = {
                "schema": 2,
                "packages": {"android": {
                    "url": "https://github.com/example/anshun-mahjong.apk",
                    "sha256": hashlib.sha256(payload).hexdigest(),
                    "size": len(payload),
                }},
            }
            result = publish.rewrite_urls(data, release, "mj.example.com", {"anshun-mahjong.apk"})
            self.assertEqual(result["packages"]["android"]["url"],
                             "https://mj.example.com/updates/anshun-mahjong.apk")

    def test_rejects_unsafe_asset_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            unsafe = "bad;touch-pwn.apk"
            (release / unsafe).write_bytes(b"x")
            data = {"packages": {"android": {"url": "https://example.com/" + unsafe,
                                             "sha256": "", "size": 1}}}
            with self.assertRaises(SystemExit):
                publish.rewrite_urls(data, release, "mj.example.com", {unsafe})

    def test_rejects_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as temporary:
            release = Path(temporary)
            (release / "anshun-mahjong.apk").write_bytes(b"real")
            data = {"packages": {"android": {"url": "https://example.com/anshun-mahjong.apk",
                                             "sha256": "0" * 64, "size": 4}}}
            with self.assertRaises(SystemExit):
                publish.rewrite_urls(data, release, "mj.example.com", {"anshun-mahjong.apk"})


if __name__ == "__main__":
    unittest.main()
