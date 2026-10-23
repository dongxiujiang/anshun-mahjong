"""Publish a prepared release to a self-hosted HTTPS update directory.

Reads a local update-manifest.json (and its PCK/APK assets), rewrites all
download URLs to https://<domain>/updates/<filename>, writes a primary and a
fallback manifest, and optionally pushes the files to a server over SSH.

Examples:
  python tools/update/publish_self_hosted.py \
      --release build/releases/v1.1.10 --domain mj.dongxiu.fun

  python tools/update/publish_self_hosted.py \
      --release build/releases/v1.1.10 --domain mj.dongxiu.fun \
      --ssh admin@47.108.185.96 --remote-dir /var/www/mahjong/updates
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from urllib.parse import urlsplit

PROJECT = Path(__file__).resolve().parents[2]
ASSET_SUFFIXES = {".pck", ".apk", ".exe"}
MANIFEST_NAME = "update-manifest.json"
FALLBACK_NAME = "update-manifest-fallback.json"
SAFE_ASSET = re.compile(r"^[A-Za-z0-9._-]+$")


def fail(message: str) -> None:
    print(f"错误: {message}", file=sys.stderr)
    raise SystemExit(1)


def normalize_domain(value: str) -> str:
    raw = value.strip().rstrip("/")
    if not raw:
        fail("--domain 不能为空")
    if "://" in raw:
        parsed = urlsplit(raw)
        host = parsed.netloc
        if parsed.path not in ("", "/") or parsed.query or parsed.fragment:
            fail("--domain 只能是域名，不能带路径或参数")
    else:
        host = raw
    if not host or "/" in host or "@" in host or " " in host:
        fail("--domain 格式无效，例如 mj.dongxiu.fun")
    return host


def read_manifest(release: Path) -> dict:
    path = release / MANIFEST_NAME
    if not path.is_file():
        fail(f"找不到 {path}")
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as error:
        fail(f"无法读取清单: {error}")
    if not isinstance(data, dict) or int(data.get("schema", 0)) != 2:
        fail("清单格式不是 schema 2")
    return data


def collect_assets(release: Path) -> set[str]:
    return {
        path.name
        for path in release.iterdir()
        if path.is_file() and path.suffix.lower() in ASSET_SUFFIXES
    }


def rewrite_urls(data: dict, release: Path, domain: str, assets: set[str]) -> dict:
    result = json.loads(json.dumps(data, ensure_ascii=False))
    base = f"https://{domain}/updates"
    for section in ("patches", "packages"):
        entries = result.get(section, {})
        if not isinstance(entries, dict):
            continue
        for platform, entry in entries.items():
            if not isinstance(entry, dict):
                fail(f"{section}.{platform} 不是对象")
            url = str(entry.get("url", ""))
            filename = Path(urlsplit(url).path).name
            if not filename:
                fail(f"{section}.{platform} 没有可识别的文件名")
            if filename not in assets:
                fail(f"清单引用了不存在的文件: {filename}")
            if not SAFE_ASSET.fullmatch(filename):
                fail(f"清单文件名包含不安全字符: {filename}")
            local = release / filename
            if not local.is_file():
                fail(f"发布目录缺少文件: {filename}")
            expected_sha = str(entry.get("sha256", "")).lower()
            if expected_sha and hashlib.sha256(local.read_bytes()).hexdigest() != expected_sha:
                fail(f"清单 SHA-256 与本地文件不一致: {filename}")
            expected_size = int(entry.get("size", 0))
            if expected_size and local.stat().st_size != expected_size:
                fail(f"清单大小与本地文件不一致: {filename}")
            entry["url"] = f"{base}/{filename}"
    result["release_url"] = f"{base}/"
    apk = release / "anshun-mahjong.apk"
    result["installation_url"] = f"{base}/{apk.name}" if apk.is_file() else f"{base}/"
    return result


def stage(release: Path, domain: str, output: Path, data: dict, assets: set[str]) -> list[str]:
    output.mkdir(parents=True, exist_ok=True)
    for filename in sorted(assets):
        shutil.copy2(release / filename, output / filename)
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    (output / MANIFEST_NAME).write_text(text, encoding="utf-8")
    (output / FALLBACK_NAME).write_text(text, encoding="utf-8")
    return sorted(assets)


def run(command: list[str], dry_run: bool) -> None:
    print("+ " + shlex.join(command))
    if dry_run:
        return
    result = subprocess.run(command)
    if result.returncode != 0:
        fail(f"命令执行失败，退出码 {result.returncode}")


def remote_quote(value: str) -> str:
    return shlex.quote(value)


def push(staging: Path, domain: str, ssh_target: str, remote_dir: str, assets: list[str], dry_run: bool) -> None:
    remote_dir = remote_dir.rstrip("/") or "/"
    run(["ssh", ssh_target, f"mkdir -p {remote_quote(remote_dir)}"], dry_run)
    names = assets + [FALLBACK_NAME, MANIFEST_NAME]
    for name in names:
        if not SAFE_ASSET.fullmatch(name):
            fail(f"上传文件名包含不安全字符: {name}")
        temporary = f"{remote_dir}/.{name}.upload"
        final = f"{remote_dir}/{name}"
        # The destination is interpreted by the remote shell. Quote it instead
        # of relying on manifest filenames being benign.
        run(["scp", str(staging / name), f"{ssh_target}:{remote_quote(temporary)}"], dry_run)
        run(["ssh", ssh_target, f"mv -f {remote_quote(temporary)} {remote_quote(final)}"], dry_run)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", required=True, type=Path, help="build/releases/vX 目录")
    parser.add_argument("--domain", required=True, help="例如 mj.dongxiu.fun")
    parser.add_argument("--ssh", default="", help="SSH 目标，例如 admin@47.108.185.96；留空只生成本地目录")
    parser.add_argument("--remote-dir", default="/var/www/mahjong/updates")
    parser.add_argument("--output", type=Path, default=None, help="本地暂存目录；默认 build/self-hosted/<domain>")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--godot", default="", help="Godot 可执行文件，用于签名清单")
    parser.add_argument("--signing-key", type=Path, default=None, help="离线清单 RSA 私钥 PEM")
    args = parser.parse_args()

    release = args.release.resolve()
    if not release.is_dir():
        fail(f"release 目录不存在: {release}")
    domain = normalize_domain(args.domain)
    output = args.output.resolve() if args.output else PROJECT / "build" / "self-hosted" / domain

    data = read_manifest(release)
    assets = collect_assets(release)
    if not assets:
        fail(f"{release} 中没有 .pck/.apk/.exe 文件")
    rewritten = rewrite_urls(data, release, domain, assets)
    assets_list = stage(release, domain, output, rewritten, assets)
    if args.signing_key is not None:
        if not args.godot:
            fail("--signing-key 需要同时提供 --godot")
        if not args.signing_key.is_file():
            fail(f"签名私钥不存在: {args.signing_key}")
        for manifest in [output / MANIFEST_NAME, output / FALLBACK_NAME]:
            run([args.godot, "--headless", "--path", str(PROJECT), "--script",
                 "res://tools/update/sign_manifest.gd", "--", str(manifest),
                 str(args.signing_key)], args.dry_run)

    print(f"本地暂存: {output}")
    print(f"清单: https://{domain}/updates/{MANIFEST_NAME}")
    print(f"回退: https://{domain}/updates/{FALLBACK_NAME}")
    for filename in assets_list:
        print(f"资源: https://{domain}/updates/{filename}")

    if args.ssh:
        push(output, domain, args.ssh, args.remote_dir, assets_list, args.dry_run)
        print(f"已推送 {len(assets_list) + 2} 个文件到 {args.ssh}:{args.remote_dir}")
    elif not args.dry_run:
        print("未指定 --ssh；请把上面的本地暂存目录整体上传到服务器的 /var/www/mahjong/updates/")


if __name__ == "__main__":
    main()
