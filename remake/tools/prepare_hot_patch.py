"""Build a Godot baseline and compatible PCK hot patches for remake/game."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess


REPOSITORY = Path(__file__).resolve().parents[2]
PROJECT = REPOSITORY / "remake/game"
PLATFORMS = ("android", "windows", "linux", "all")
NATIVE_SUFFIXES = {".so", ".dll", ".aar", ".jar", ".gdextension", ".dylib"}


def parse_semver(version):
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        raise ValueError("Version must be X.Y.Z")
    return tuple(map(int, version.split(".")))


def is_compatible_patch_version(base_version, version):
    base, target = parse_semver(base_version), parse_semver(version)
    return target[0] == base[0] and target > base


def file_sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def normalized_settings(path, ignore_version=False):
    """Ignore comments, key order and whitespace outside quoted Godot values."""
    settings = {}
    section, current = "", None
    quoted, escaped = False, False
    for line in Path(path).read_text(encoding="utf-8-sig").splitlines():
        value = ""
        for char in line:
            if escaped:
                value += char
                escaped = False
            elif quoted and char == "\\":
                value += char
                escaped = True
            elif char == '"':
                quoted = not quoted
                value += char
            elif not quoted and char in ";#":
                break
            elif quoted or not char.isspace():
                value += char
        if not value:
            continue
        if value.startswith("[") and value.endswith("]"):
            section, current = value[1:-1], None
        elif re.match(r"^[A-Za-z0-9_./-]+=", value):
            key, value = value.split("=", 1)
            current = f"{section}/{key}" if section else key
            settings[current] = value
        elif current:
            settings[current] += value
    if ignore_version:
        settings.pop("application/config/version", None)
    return settings


def project_identity(project=None):
    project = PROJECT if project is None else Path(project)
    settings = normalized_settings(project / "project.godot")
    version = settings.get("application/config/version")
    if version is None:
        version = json.loads((project.parent / "version.json").read_text(encoding="utf-8"))["version"]
    else:
        version = json.loads(version)
    parse_semver(version)
    base_id = json.loads(settings.get("updates/base_id", '""'))
    if not isinstance(base_id, str) or not base_id.strip():
        raise ValueError("project.godot must define a non-empty [updates] base_id")
    return version, base_id


def take_snapshot(project=None):
    project = PROJECT if project is None else Path(project)
    files, boot, classes, native = {}, {}, {}, {}
    for path in sorted(project.rglob("*")):
        relative = path.relative_to(project)
        if any(part in {".godot", ".git", "__pycache__"} for part in relative.parts):
            continue
        if "build" in relative.parts and path.suffix.lower() not in NATIVE_SUFFIXES:
            continue
        if not path.is_file() or path.name == "export_credentials.cfg":
            continue
        name = relative.as_posix()
        files[name] = file_sha256(path)
        if path.name == "PatchBoot.gd":
            boot[name] = files[name]
        if path.suffix.lower() in NATIVE_SUFFIXES:
            native[name] = files[name]
        if path.suffix == ".gd":
            declarations = re.findall(r"^\s*class_name\s+([^\r\n#]+)", path.read_text(encoding="utf-8-sig"), re.MULTILINE)
            if declarations:
                classes[name] = [" ".join(line.split()) for line in declarations]
    return {"files": files, "patch_boot": boot, "class_names": classes, "native_libraries": native,
            "project_settings": normalized_settings(project / "project.godot", ignore_version=True),
            "export_settings": normalized_settings(project / "export_presets.cfg")}


def validate_snapshot_diff(baseline, current):
    """Raise on changes that cannot safely be applied to an installed base."""
    deleted = set(baseline["files"]) - set(current["files"])
    if deleted:
        raise ValueError("Baseline files deleted: " + ", ".join(sorted(deleted)))
    for key, label in (("patch_boot", "PatchBoot.gd"), ("class_names", "class_name declarations"),
                       ("native_libraries", "native libraries"), ("project_settings", "project.godot settings"),
                       ("export_settings", "export_presets.cfg settings")):
        if baseline[key] != current[key]:
            raise ValueError(f"Incompatible patch: {label} changed; create a new full release")


def verify_pck(path):
    path = Path(path)
    if not path.is_file():
        raise ValueError(f"PCK file missing: {path}")
    with path.open("rb") as source:
        if source.read(4) != b"GDPC":
            raise ValueError(f"Invalid Godot PCK magic: {path}")


def build_hotpatch_entry(path, *, version, base_version, base_id, engine, platform="android", notes=None, mandatory=False):
    path = Path(path)
    if not is_compatible_patch_version(base_version, version):
        raise ValueError("Patch version must exceed base_version and keep the same major version")
    if not isinstance(base_id, str) or not base_id.strip() or not isinstance(engine, str) or not engine.strip():
        raise ValueError("base_id and engine must be non-empty strings")
    if platform not in PLATFORMS:
        raise ValueError("Unsupported platform")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,120}\.pck", path.name):
        raise ValueError("Unsafe PCK filename")
    verify_pck(path)
    size = path.stat().st_size
    if isinstance(notes, str):
        notes = notes.splitlines()
    return {"version": version, "base_version": base_version, "base_id": base_id, "engine": engine,
            "platform": platform, "filename": path.name, "size_bytes": size,
            "size_mb": round(size / (1024 * 1024), 2), "sha256": file_sha256(path),
            "published_at": datetime.now(timezone.utc).isoformat(),
            "download_url": f"/v1/downloads/{path.name}", "direct_url": f"/v1/downloads/{path.name}",
            "notes": list(notes or []), "mandatory": bool(mandatory), "available": True}


def merge_hotpatches_manifest(manifest, entry):
    items = manifest.get("hotpatches", []) if isinstance(manifest, dict) else manifest
    if not isinstance(items, list) or any(not isinstance(item, dict) or "filename" not in item for item in items):
        raise ValueError("Manifest must contain a hotpatches array of entries with filenames")
    by_filename = {item["filename"]: item for item in items}
    by_filename[entry["filename"]] = entry
    result = dict(manifest) if isinstance(manifest, dict) else {}
    result["hotpatches"] = sorted(by_filename.values(), key=lambda item: parse_semver(item["version"]), reverse=True)
    return result


def write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def engine_version(godot):
    result = subprocess.run([str(godot), "--version"], check=True, capture_output=True, text=True, encoding="utf-8")
    match = re.search(r"(?m)^([0-9]+\.[0-9]+(?:\.[0-9]+)?)", result.stdout)
    if not match:
        raise ValueError("Cannot parse Godot --version output")
    return match[1]


def run_godot(godot, *arguments):
    subprocess.run([str(godot), "--headless", "--path", str(PROJECT), *map(str, arguments)], check=True)


def baseline(args):
    version, base_id = project_identity()
    # base_id becomes a directory name for the default output.
    if args.output is None and not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", base_id):
        raise ValueError("base_id must be a safe directory name or use --output")
    output = (args.output or REPOSITORY / "build/update_baselines" / base_id).resolve()
    if (output / "baseline.json").exists():
        raise ValueError("Baseline already exists; use a new output directory")
    engine = engine_version(args.godot)
    run_godot(args.godot, "--editor", "--import")
    snapshot = take_snapshot()
    output.mkdir(parents=True, exist_ok=True)
    pack = output / f"{args.platform}-base.pck"
    run_godot(args.godot, "--export-pack", args.preset, pack)
    verify_pck(pack)
    validate_snapshot_diff(snapshot, take_snapshot())
    write_json(output / "baseline.json", {"schema": 1, "base_version": version, "base_id": base_id,
               "engine": engine, "preset": args.preset, "platform": args.platform,
               "packs": [pack.name], "snapshot": snapshot})
    print(f"Baseline: {output / 'baseline.json'}")


def patch(args):
    baseline_dir = args.baseline.resolve()
    base = json.loads((baseline_dir / "baseline.json").read_text(encoding="utf-8"))
    if base["schema"] != 1:
        raise ValueError("Unsupported baseline schema")
    if not is_compatible_patch_version(base["base_version"], args.version):
        raise ValueError("Patch version must exceed base_version and keep the same major version")
    _, base_id = project_identity()
    if base_id != base["base_id"]:
        raise ValueError("base_id differs from baseline")
    if engine_version(args.godot) != base["engine"]:
        raise ValueError("Godot engine version differs from baseline")
    packs = [(baseline_dir / name).resolve() for name in base["packs"]]
    if not packs or any(not path.is_relative_to(baseline_dir) for path in packs):
        raise ValueError("Baseline packs must be inside the baseline directory")
    for pack in packs:
        verify_pck(pack)
    run_godot(args.godot, "--editor", "--import")
    validate_snapshot_diff(base["snapshot"], take_snapshot())
    output = args.output.resolve() / f"v{args.version}"
    output.mkdir(parents=True, exist_ok=True)
    # Include the base identity to avoid collisions between incompatible installs.
    identity = hashlib.sha256(base_id.encode("utf-8")).hexdigest()[:12]
    target = output / f"dongxiu-{base['platform']}-{identity}-{args.version}.pck"
    target.unlink(missing_ok=True)
    run_godot(args.godot, "--export-patch", base["preset"], target, "--patches", ",".join(map(str, packs)))
    validate_snapshot_diff(base["snapshot"], take_snapshot())
    entry = build_hotpatch_entry(target, version=args.version, base_version=base["base_version"], base_id=base_id,
                                engine=base["engine"], platform=base["platform"], notes=args.notes, mandatory=args.mandatory)
    manifest = merge_hotpatches_manifest({}, entry)
    write_json(output / "hotpatches.json", manifest)
    if args.merge_manifest:
        previous = json.loads(args.merge_manifest.read_text(encoding="utf-8")) if args.merge_manifest.exists() else {}
        write_json(args.merge_manifest, merge_hotpatches_manifest(previous, entry))
    print(f"Hot patch: {target}\nManifest: {output / 'hotpatches.json'}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    base = commands.add_parser("baseline", help="Export the pack and immutable compatibility snapshot")
    base.add_argument("--godot", required=True, type=Path)
    base.add_argument("--output", type=Path)
    base.add_argument("--preset", default="Android Release (arm64-v8a)")
    base.add_argument("--platform", choices=PLATFORMS, default="android")
    base.set_defaults(run=baseline)
    update = commands.add_parser("patch", help="Export changed resources against an installed baseline")
    update.add_argument("--godot", required=True, type=Path)
    update.add_argument("--baseline", required=True, type=Path)
    update.add_argument("--version", required=True)
    update.add_argument("--output", type=Path, default=REPOSITORY / "build/hotpatches")
    update.add_argument("--note", "--notes", dest="notes", action="append", default=[])
    update.add_argument("--mandatory", action="store_true")
    update.add_argument("--merge-manifest", type=Path)
    update.set_defaults(run=patch)
    args = parser.parse_args(argv)
    if hasattr(args, "notes"):
        args.notes = [line for note in args.notes for line in note.splitlines() if line.strip()]
    try:
        args.run(args)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Hot-patch build failed: {error}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
