"""Check the frozen gameplay baseline before accepting presentation optimizations."""
import argparse
import hashlib
import json
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
MANIFEST = PROJECT / "docs" / "optimization_frozen_baseline.json"
UI_MIGRATIONS = PROJECT / "docs" / "optimization_ui_test_migrations.json"
UI_TESTS = {
    "run_all", "settlement_arrangement_toolbar", "table_v2_hand_arrangement",
    "sort_usability", "hand_arrangement_lifecycle", "table_3d_own_exposed_readability",
    "table_render_cache", "table_v2_layout_guards", "table_3d_idle_cost",
    "table_3d_own_exposed_flight", "table_v2_red_spacing", "table_3d_touch_footer",
    "table_3d_bottom_controls", "table_3d", "sort_annotations_layout",
    "NetTableUiSmoke",
    "table_3d_river_badges",
}
FROZEN_DIRS = ("scripts/core", "scripts/ai")
FROZEN_FILES = (
    "scripts/autoload/GameConfig.gd",
    "server/RoomServer.gd",
    "server/Warmup.gd",
    "docs/游戏规则总纲.md",
)


def digest(path):
    data = path.read_bytes()
    if path.suffix in {".gd", ".uid", ".md", ".py", ".json", ".tscn", ".tres"}:
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def locked_files():
    paths = {PROJECT / name for name in FROZEN_FILES}
    for name in FROZEN_DIRS:
        paths.update(path for path in (PROJECT / name).rglob("*") if path.is_file())
    return paths


def snapshot():
    if MANIFEST.exists():
        raise SystemExit("Baseline already exists; do not replace the original snapshot.")
    paths = locked_files()
    paths.update(path for path in (PROJECT / "tests").rglob("*")
                 if path.is_file() and "__pycache__" not in path.parts
                 and path.suffix != ".pyc")
    files = {path.relative_to(PROJECT).as_posix(): digest(path) for path in sorted(paths)}
    MANIFEST.write_text(json.dumps({
        "source_commit": "6e0937ecb4b64fe208ff03f56ea568514537c8d0",
        "note": "Includes the seven inherited, uncommitted settlement display files.",
        "files": files,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Frozen {len(files)} baseline files: {MANIFEST}")


def check():
    files = json.loads(MANIFEST.read_text(encoding="utf-8"))["files"]
    failures = []
    migrations = json.loads(UI_MIGRATIONS.read_text(encoding="utf-8"))["files"] if UI_MIGRATIONS.exists() else {}
    for name, migration in migrations.items():
        path = Path(name)
        if path.parent.as_posix() != "tests" or path.suffix != ".gd" or path.stem not in UI_TESTS:
            failures.append("not an approved UI test migration: " + name)
        if migration.get("baseline_sha256") != files.get(name) or not migration.get("reason"):
            failures.append("invalid UI test migration baseline/reason: " + name)
    for name, expected in files.items():
        path = PROJECT / name
        expected = migrations.get(name, {}).get("current_sha256", expected)
        if not path.is_file():
            failures.append("deleted: " + name)
        elif digest(path) != expected:
            failures.append("modified: " + name)
    for path in locked_files():
        name = path.relative_to(PROJECT).as_posix()
        if name not in files:
            failures.append("added in frozen scope: " + name)
    for failure in sorted(failures):
        print(failure)
    if failures:
        raise SystemExit(1)
    print(f"PASS: {len(files)} baseline files checked; {len(migrations)} documented UI test migrations; no gameplay changes.")
    print("Mixed UI/network changes still require review and replay comparison.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", action="store_true", help="Create the one-time baseline")
    args = parser.parse_args()
    snapshot() if args.snapshot else check()
