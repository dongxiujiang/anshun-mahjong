"""Real exported PCK bootstrap tests, in an isolated user-data directory."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
import uuid

PROJECT = Path(__file__).resolve().parents[1]
FIXTURE = PROJECT / "build/hot_update_fixture"


def run(godot):
    FIXTURE.mkdir(parents=True, exist_ok=True)
    app_name = "MahjongHotTest-" + uuid.uuid4().hex
    user = Path(os.environ["APPDATA"]) / "Godot/app_userdata" / app_name
    engine = subprocess.check_output([godot, "--version"], text=True).strip().split(".")[:3]
    engine = ".".join(engine)
    template = Path(os.environ["APPDATA"]) / "Godot/export_templates" / (engine + ".stable/windows_release_x86_64.exe")
    assert template.is_file(), template
    runtime = FIXTURE / "base.exe"
    shutil.copy2(template, runtime)
    source = FIXTURE / "project"
    source.mkdir(exist_ok=True)
    (source / "scripts/autoload").mkdir(parents=True, exist_ok=True)
    shutil.copy2(PROJECT / "scripts/autoload/PatchBoot.gd", source / "scripts/autoload/PatchBoot.gd")
    shutil.copy2(PROJECT / "scripts/autoload/UpdateManager.gd", source / "scripts/autoload/UpdateManager.gd")
    (source / "dummy.gd").write_text('extends Node\nvar mode := ""\n', encoding="utf-8")
    for relative in ["scripts/core/RoundState.gd", "scripts/core/ScoringEngine.gd", "scripts/ui/GameTable.gd", "scripts/ui/Lobby.gd"]:
        target_script = source / relative
        target_script.parent.mkdir(parents=True, exist_ok=True)
        target_script.write_text("extends Node\n", encoding="utf-8")
    config = f'''config_version=5
[application]
config/name="{app_name}"
config/version="1.2.0"
run/main_scene="res://main.tscn"
[autoload]
PatchBoot="*res://scripts/autoload/PatchBoot.gd"
GameConfig="*res://game.gd"
AudioManager="*res://dummy.gd"
Network="*res://dummy.gd"
UpdateManager="*res://scripts/autoload/UpdateManager.gd"
[updates]
base_id="test-base"
auto_check=false
[rendering]
renderer/rendering_method="gl_compatibility"
'''
    (source / "project.godot").write_text(config, encoding="utf-8")
    (source / "export_presets.cfg").write_text('''[preset.0]
name="Windows"
platform="Windows Desktop"
export_filter="all_resources"
include_filter=""
exclude_filter=""
script_export_mode=2
[preset.0.options]
binary_format/architecture="x86_64"
''', encoding="utf-8")
    (source / "main.tscn").write_text('''[gd_scene load_steps=2 format=3]
[ext_resource type="Script" path="res://main.gd" id="1"]
[node name="Main" type="Node"]
script = ExtResource("1")
''', encoding="utf-8")
    (source / "main.gd").write_text('''extends Node
func _ready():
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--install="):
			var data = JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--install=")))
			UpdateManager.apply_release(data.manifest, "windows")
			UpdateManager.state = "ready"
			UpdateManager.downloaded_path = data.path
			Network.mode = "test-room"
			if UpdateManager.install_and_restart():
				get_tree().quit(3)
				return
			Network.mode = ""
			if not UpdateManager.install_and_restart(): get_tree().quit(4)
			return
	var result = {"value": GameConfig.value, "class_value": HotFixtureHelper.value(), "version": PatchBoot.effective_version, "message": PatchBoot.boot_message, "enabled": PatchBoot.enabled}
	var file = FileAccess.open("user://result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result))
	file.close()
	if not "--no-confirm" in OS.get_cmdline_user_args(): PatchBoot.confirm_boot()
	get_tree().quit()
''', encoding="utf-8")

    def command(args, label):
        result = subprocess.run(args, capture_output=True, timeout=90)
        text = (result.stdout + result.stderr).decode("utf-8", errors="replace")
        (FIXTURE / (label + ".log")).write_text(text, encoding="utf-8")
        assert result.returncode == 0 and "SCRIPT ERROR:" not in text and "\nERROR:" not in text, text[-7000:]

    def export(path, baseline=None):
        command([godot, "--headless", "--path", str(source), "--editor", "--import"], "import-" + path.stem)
        args = [godot, "--headless", "--path", str(source), "--export-patch" if baseline else "--export-pack", "Windows", str(path)]
        if baseline: args += ["--patches", str(baseline)]
        command(args, "export-" + path.stem)

    def launch(confirm=False):
        args = [str(runtime), "--headless"]
        if not confirm: args += ["--", "--no-confirm"]
        command(args, "launch")
        return json.loads((user / "result.json").read_text(encoding="utf-8"))

    def entry(pack, version="1.2.2"):
        digest = hashlib.sha256(pack.read_bytes()).hexdigest()
        directory = user / "updates/packs"
        directory.mkdir(parents=True, exist_ok=True)
        shutil.copy2(pack, directory / (digest + ".pck"))
        return {"version": version, "base_id": "test-base", "base_version": "1.2.0", "engine": engine, "platform": "windows", "sha256": digest, "size": pack.stat().st_size, "file": digest + ".pck"}

    def write_state(state):
        (user / "updates").mkdir(parents=True, exist_ok=True)
        (user / "updates/patch-state.json").write_text(json.dumps({"schema": 1, "base_id": "test-base", **state}))

    base = FIXTURE / "base.pck"
    pack = FIXTURE / "patch.pck"
    (source / "game.gd").write_text('extends Node\nvar value := "base"\n', encoding="utf-8")
    (source / "helper.gd").write_text('class_name HotFixtureHelper\nextends RefCounted\nstatic func value(): return "base-class"\n', encoding="utf-8")
    export(base)
    try:
        initial = launch()
        assert initial["value"] == "base" and initial["enabled"], initial
        (source / "game.gd").write_text('extends Node\nvar value := "patched-autoload"\n', encoding="utf-8")
        (source / "helper.gd").write_text('class_name HotFixtureHelper\nextends RefCounted\nstatic func value(): return "patched-class"\n', encoding="utf-8")
        export(pack, base)
        assert pack.stat().st_size < base.stat().st_size, "Not a differential patch"
        pending = entry(pack)
        write_state({"pending": pending})
        result = launch(True)
        assert result["value"] == "patched-autoload" and result["class_value"] == "patched-class" and result["version"] == "1.2.2", result
        assert launch()["value"] == "patched-autoload", "Confirmed patch not retained"
        print("[hot_update] compiled autoload patched before loading; skip 1.2.1; no reinstall: passed", flush=True)
        # A trial without confirmation simulates a crash before the main menu is ready.
        write_state({"pending": pending})
        assert launch()["value"] == "patched-autoload"
        result = launch()
        assert result["value"] == "base" and "恢复" in result["message"], result
        print("[hot_update] incomplete startup restores base on next launch: passed", flush=True)
        write_state({"pending": {**pending, "base_id": "wrong-base"}})
        assert launch()["value"] == "base", "Incompatible patch loaded"
        (user / "updates/packs" / pending["file"]).write_bytes(b"GDPC-corrupt")
        write_state({"pending": pending})
        assert launch()["value"] == "base", "Corrupt patch loaded"
        print("[hot_update] wrong base and corrupt pack retain game: passed", flush=True)
        # Missing primary JSON after an interrupted atomic rename recovers from backup.
        entry(pack)
        write_state({"active": pending})
        primary = user / "updates/patch-state.json"
        primary.replace(primary.with_suffix(".json.bak"))
        assert launch()["value"] == "patched-autoload", "Backup state not recovered"
        print("[hot_update] interrupted metadata write recovers previous state: passed", flush=True)
        (source / "game.gd").write_text('extends Node\nvar value := "second-patch"\n', encoding="utf-8")
        newer = FIXTURE / "patch2.pck"
        export(newer, base)
        write_state({"active": pending, "pending": entry(newer, "1.2.3")})
        assert launch()["value"] == "second-patch"
        assert launch()["value"] == "patched-autoload", "Failed trial did not restore last known-good patch"
        print("[hot_update] second cumulative patch failure restores known-good patch: passed", flush=True)
        # Run the actual install button path in an exported runtime, including its room guard and real restart.
        write_state({})
        info = entry(newer, "1.2.3")
        request = FIXTURE / "install.json"
        manifest = {"schema": 2, "version": "1.2.3", "patches": {"windows": {**info, "url": "https://example.com/patch.pck"}}}
        request.write_text(json.dumps({"manifest": manifest, "path": str(newer)}), encoding="utf-8")
        (user / "result.json").unlink(missing_ok=True)
        command([str(runtime), "--headless", "--", "--install=" + str(request)], "restart")
        deadline = time.monotonic() + 10
        while not (user / "result.json").exists() and time.monotonic() < deadline: time.sleep(0.05)
        result = json.loads((user / "result.json").read_text(encoding="utf-8"))
        assert result["value"] == "second-patch" and result["version"] == "1.2.3", result
        # Wait for confirm_boot's atomic state write before cleaning its fixture directory.
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                state = json.loads((user / "updates/patch-state.json").read_text(encoding="utf-8"))
                if not state.get("trial", False): break
            except (FileNotFoundError, json.JSONDecodeError): pass
            time.sleep(0.05)
        assert not state.get("trial", False), "Menu did not confirm restart"
        print("[hot_update] room guard, actual update installation, automatic restart and boot confirmation: passed", flush=True)
    finally:
        if user.exists():
            for _ in range(20):
                try:
                    shutil.rmtree(user)
                    break
                except PermissionError:
                    time.sleep(0.25)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    run(parser.parse_args().godot)
