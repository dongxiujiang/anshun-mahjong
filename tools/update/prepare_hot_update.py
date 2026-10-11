"""Save a baseline and export cumulative Godot PCK hot-update patches."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess

PROJECT = Path(__file__).resolve().parents[2]
PRESETS = {"windows": "Windows", "android": "Android"}
SKIP = {".git", ".godot", "build", "tests", "docs", "tools", "server", ".vscode", ".idea", "__pycache__"}


def sha256(path):
    with Path(path).open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def setting(key):
    text = (PROJECT / "project.godot").read_text(encoding="utf-8-sig")
    match = re.search(r'^' + re.escape(key) + r'="([^"\n]+)"$', text, re.MULTILINE)
    if not match: raise ValueError(f"project.godot 缺少 {key}")
    return match.group(1)


def engine(godot):
    text = subprocess.check_output([str(godot), "--version"], text=True).strip()
    match = re.match(r"([0-9]+\.[0-9]+\.[0-9]+)\.stable", text)
    if not match: raise ValueError("仅支持稳定版 Godot 引擎")
    return match.group(1)


def normalized_settings(path, ignored):
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    return "\n".join(line.strip() for line in lines if line.strip() and not line.lstrip().startswith(("#", ";")) and line.split("=", 1)[0].strip() not in ignored)


def snapshot():
    files, classes, native = {}, {}, {}
    for root, dirs, names in os.walk(PROJECT):
        dirs[:] = [name for name in dirs if name not in SKIP]
        for name in names:
            path = Path(root) / name
            if path.suffix.lower() in {".log", ".out", ".err", ".md", ".py", ".toml"} or name.startswith(".") or name == "export_credentials.cfg": continue
            relative = path.relative_to(PROJECT).as_posix()
            files[relative] = sha256(path)
            if path.suffix == ".gd":
                text = path.read_text(encoding="utf-8-sig")
                declaration = re.search(r"^class_name\s+([^\n]+)", text, re.MULTILINE)
                if declaration:
                    parent = re.search(r"^extends\s+([^\n]+)", text, re.MULTILINE)
                    uid = path.with_suffix(path.suffix + ".uid")
                    classes[relative] = {"name": declaration.group(1), "extends": parent.group(1) if parent else "", "uid": uid.read_text().strip() if uid.exists() else ""}
            if path.suffix.lower() in {".dll", ".so", ".gdextension", ".dylib", ".aar", ".jar"}: native[relative] = files[relative]
    return {"files": files, "classes": classes, "native": native,
            "boot": sha256(PROJECT / "scripts/autoload/PatchBoot.gd"),
            "settings": normalized_settings(PROJECT / "project.godot", {"config/version"}),
            "export": normalized_settings(PROJECT / "export_presets.cfg", {"export_path", "application/file_version", "application/product_version", "version/code", "version/name"})}


def run_godot(godot, args, log):
    result = subprocess.run([str(godot), "--headless", "--path", str(PROJECT), *args], capture_output=True, timeout=300)
    output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    log.write_text(output, encoding="utf-8")
    if result.returncode or "SCRIPT ERROR:" in output or "\nERROR:" in output: raise RuntimeError(f"Godot 导出失败：{log}")


def baseline(args):
    output = args.output.resolve()
    if (output / "baseline.json").exists(): raise ValueError("基线已存在，不可覆盖")
    output.mkdir(parents=True, exist_ok=True)
    run_godot(args.godot, ["--editor", "--import"], output / "import.log")
    data = {"schema": 1, "base_version": setting("config/version"), "base_id": setting("base_id"), "engine": engine(args.godot), "snapshot": snapshot(), "packs": {}}
    for platform in args.platforms:
        name = f"{platform}-base.pck"
        target = output / name
        run_godot(args.godot, ["--export-pack", PRESETS[platform], str(target)], output / (platform + ".log"))
        data["packs"][platform] = {"file": name, "sha256": sha256(target)}
    (output / "baseline.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"基线已保存：{output}。请永久保留并与安装包代码保持一致。")


def patch(args):
    folder = args.baseline.resolve()
    data = json.loads((folder / "baseline.json").read_text(encoding="utf-8"))
    version = args.version
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version): raise ValueError("版本号须为三段数字")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repository): raise ValueError("仓库须为 owner/repository")
    output = args.output.resolve() / ("v" + version)
    output.mkdir(parents=True, exist_ok=True)
    run_godot(args.godot, ["--editor", "--import"], output / "import.log")
    current = snapshot()
    if data["base_id"] != setting("base_id") or data["engine"] != engine(args.godot): raise ValueError("基线或引擎不兼容，请发布大版本")
    a, b = tuple(map(int, version.split("."))), tuple(map(int, data["base_version"].split(".")))
    if a[0] != b[0] or a <= b: raise ValueError("补丁必须高于基线且保持主版本号")
    for key in ["boot", "classes", "native", "settings", "export"]:
        if current[key] != data["snapshot"][key]: raise ValueError(f"{key} 已变化，请发布大版本")
    if set(data["snapshot"]["files"]) - set(current["files"]): raise ValueError("补丁不能删除基线文件，请发布大版本")
    release = {
        "schema": 2, "version": version, "notes": args.notes or "",
        "release_url": f"https://github.com/{args.repository}/releases/tag/v{version}",
        "installation_url": f"https://github.com/{args.repository}/releases/tag/v{data['base_version']}",
        "packages": {}, "patches": {},
    }
    for platform, info in data["packs"].items():
        base = folder / info["file"]
        if not base.is_file() or sha256(base) != info["sha256"]: raise ValueError(f"{platform} 基线包损坏或丢失")
        target = output / f"anshun-mahjong-{platform}-{version}.pck"
        run_godot(args.godot, ["--export-patch", PRESETS[platform], str(target), "--patches", str(base)], output / (platform + ".log"))
        digest = sha256(target)
        release["patches"][platform] = {
            "url": f"https://github.com/{args.repository}/releases/download/v{version}/{target.name}",
            "sha256": digest, "size": target.stat().st_size, "platform": platform,
            "base_id": data["base_id"], "base_version": data["base_version"], "engine": data["engine"],
        }
    (output / "update-manifest.json").write_text(json.dumps(release, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"累计小版本补丁已准备：{output}。只上传 PCK 与清单，未上传或发布。")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    base = sub.add_parser("baseline", help="保存完整安装包的补丁基线")
    base.add_argument("--godot", required=True, type=Path)
    base.add_argument("--output", type=Path, default=PROJECT / "build/update_baselines/1.2.0-boot1")
    base.add_argument("--platforms", nargs="+", choices=list(PRESETS), default=list(PRESETS))
    small = sub.add_parser("patch", help="相对固定安装基线导出累计补丁")
    small.add_argument("--godot", required=True, type=Path)
    small.add_argument("--baseline", required=True, type=Path)
    small.add_argument("--version", required=True)
    small.add_argument("--output", type=Path, default=PROJECT / "build/releases")
    small.add_argument("--repository", default="dongxiujiang/anshun-mahjong")
    small.add_argument("--notes", default="")
    args = parser.parse_args()
    try:
        baseline(args) if args.command == "baseline" else patch(args)
    except (ValueError, RuntimeError, OSError) as error:
        parser.exit(1, str(error) + "\n")
