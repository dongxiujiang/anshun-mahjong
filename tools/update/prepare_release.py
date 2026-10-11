"""Prepare full EXE/APK release assets locally; never upload or publish."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil

PROJECT = Path(__file__).resolve().parents[2]
ASSETS = {"windows": "anshun-mahjong-windows-x64.exe", "android": "anshun-mahjong.apk"}


def sha256(path):
    with Path(path).open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def project_value(key):
    config = (PROJECT / "project.godot").read_text(encoding="utf-8-sig")
    match = re.search(r'^' + re.escape(key) + r'="([^"\n]+)"$', config, re.MULTILINE)
    if not match:
        raise ValueError(f"project.godot 缺少 {key}")
    return match.group(1)


def manifest(version, repository, notes=""):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("版本号必须是三段数字")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("仓库应为 owner/repository")
    return {"schema": 2, "version": version, "notes": notes,
            "release_url": f"https://github.com/{repository}/releases/tag/v{version}",
            "packages": {}, "patches": {}}


def copy_packages(data, windows, android, output, repository):
    for platform, source in [("windows", windows), ("android", android)]:
        if not source: continue
        source = Path(source).resolve()
        if not source.is_file():
            raise FileNotFoundError(f"先导出 {platform} 文件：{source}")
        target = output / ASSETS[platform]
        if source != target: shutil.copy2(source, target)
        data["packages"][platform] = {
            "url": f"https://github.com/{repository}/releases/download/v{data['version']}/{target.name}",
            "sha256": sha256(target), "size": target.stat().st_size,
        }


def write_manifest(data, output):
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    (output / "update-manifest.json").write_text(text, encoding="utf-8")
    (output / "checksums.json").write_text(text, encoding="utf-8")


def prepare(windows, android, output, repository=None, notes=""):
    version = project_value("config/version")
    repository = repository or project_value("github_repository")
    output = Path(output).resolve() / ("v" + version)
    output.mkdir(parents=True, exist_ok=True)
    data = manifest(version, repository, notes)
    copy_packages(data, windows, android, output, repository)
    write_manifest(data, output)
    print(f"已准备大版本 v{version}：{output}")
    print("未上传或发布；导出文件须与当前工程版本一致。")
    return data


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--windows", default=str(PROJECT / "build/windows/安顺麻将.exe"))
    parser.add_argument("--android", default=str(PROJECT / "build/android/安顺麻将.apk"))
    parser.add_argument("--output", default=str(PROJECT / "build/releases"))
    parser.add_argument("--repository", default=None)
    parser.add_argument("--notes", type=Path, help="UTF-8 更新说明文本")
    args = parser.parse_args()
    notes = args.notes.read_text(encoding="utf-8-sig") if args.notes else ""
    prepare(args.windows, args.android, args.output, args.repository, notes)
