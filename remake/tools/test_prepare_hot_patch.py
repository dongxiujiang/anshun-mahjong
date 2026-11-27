"""Compatibility guards and CLI orchestration tests; no Godot export templates needed."""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import prepare_hot_patch as tool


class HotPatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "remake/game"
        self.project.mkdir(parents=True)
        self.write("project.godot", 'config_version=5\n[application]\nconfig/version="2.4.0"\nconfig/name="Test"\n[updates]\nbase_id="android-base"\n')
        self.write("export_presets.cfg", '[preset.0]\nname="Android Release (arm64-v8a)"\n')
        self.write("src/app/PatchBoot.gd", "extends Node\n")
        self.write("src/domain/Tile.gd", "class_name Tile\nextends RefCounted\n")
        self.write("src/app/Main.gd", "extends Node\nvar value = 1\n")
        self.write("assets/tile.png", b"image")
        self.write("android/plugins/voice.so", b"native")
        self.snapshot = tool.take_snapshot(self.project)

    def write(self, name, data):
        path = self.project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data if isinstance(data, bytes) else data.encode("utf-8"))
        return path

    def entry(self, **overrides):
        path = self.root / "patch.pck"
        path.write_bytes(b"GDPCpatch contents")
        args = {"version": "2.4.1", "base_version": "2.4.0", "base_id": "android-base", "engine": "4.7.2"}
        args.update(overrides)
        return tool.build_hotpatch_entry(path, **args)

    def test_semver_and_compatibility(self):
        self.assertEqual(tool.parse_semver("2.4.10"), (2, 4, 10))
        for invalid in ("2.4", "v2.4.1", "2.4.1-beta", "2.4.1\n", "", None, 241):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                tool.parse_semver(invalid)
        for version in ("2.4.1", "2.5.0", "2.4.10"):
            self.assertTrue(tool.is_compatible_patch_version("2.4.0", version))
        for version in ("2.4.0", "2.3.9", "3.0.0", "1.9.9"):
            self.assertFalse(tool.is_compatible_patch_version("2.4.0", version))

    def test_allowed_resource_and_script_changes(self):
        self.write("src/app/Main.gd", "extends Node\nvar value = 2\n")
        self.write("assets/tile.png", b"new image")
        self.write("assets/new.png", b"extra image")
        self.write("src/domain/Tile.gd", "class_name Tile\nextends RefCounted\nvar extra = true\n")
        tool.validate_snapshot_diff(self.snapshot, tool.take_snapshot(self.project))

    def test_immutable_snapshot_fields(self):
        for key, label in (("patch_boot", "PatchBoot"), ("class_names", "class_name"),
                           ("native_libraries", "native"), ("project_settings", "project.godot"),
                           ("export_settings", "export_presets")):
            changed = copy.deepcopy(self.snapshot)
            changed[key]["changed"] = "new"
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, label):
                tool.validate_snapshot_diff(self.snapshot, changed)

    def test_patch_boot_modified(self):
        self.write("src/app/PatchBoot.gd", "extends Node\nvar changed = true\n")
        with self.assertRaisesRegex(ValueError, "PatchBoot.gd"):
            tool.validate_snapshot_diff(self.snapshot, tool.take_snapshot(self.project))

    def test_native_changes_and_additions(self):
        for extension in tool.NATIVE_SUFFIXES:
            with self.subTest(extension=extension):
                path = self.write("android/plugins/new" + extension, b"new library")
                with self.assertRaisesRegex(ValueError, "native libraries"):
                    tool.validate_snapshot_diff(self.snapshot, tool.take_snapshot(self.project))
                path.unlink()
        self.write("android/plugins/voice.so", b"changed native")
        with self.assertRaisesRegex(ValueError, "native libraries"):
            tool.validate_snapshot_diff(self.snapshot, tool.take_snapshot(self.project))

    def test_native_build_directory_is_scanned(self):
        self.write("android/build/lib/new.so", b"generated native")
        self.assertIn("android/build/lib/new.so", tool.take_snapshot(self.project)["native_libraries"])

    def test_deleted_baseline_file(self):
        (self.project / "assets/tile.png").unlink()
        with self.assertRaisesRegex(ValueError, "Baseline files deleted: assets/tile.png"):
            tool.validate_snapshot_diff(self.snapshot, tool.take_snapshot(self.project))

    def test_class_name_addition_and_rename(self):
        self.write("src/domain/Tile.gd", "class_name RenamedTile\nextends RefCounted\n")
        with self.assertRaisesRegex(ValueError, "class_name"):
            tool.validate_snapshot_diff(self.snapshot, tool.take_snapshot(self.project))

    def test_settings_normalization(self):
        project = self.project / "project.godot"
        text = project.read_text(encoding="utf-8").replace('config/version="2.4.0"', 'config/version = "2.4.1" ; new version')
        project.write_text("; comment\n" + text, encoding="utf-8")
        tool.validate_snapshot_diff(self.snapshot, tool.take_snapshot(self.project))
        self.write("project.godot", text.replace('config/name="Test"', 'config/name="Changed"'))
        with self.assertRaisesRegex(ValueError, "project.godot"):
            tool.validate_snapshot_diff(self.snapshot, tool.take_snapshot(self.project))
        self.write("settings.cfg", '[one]\nvalues = [\n "a=b",\n "#literal; value"\n]\n')
        values = tool.normalized_settings(self.project / "settings.cfg")
        self.assertEqual(values, {"one/values": '["a=b","#literal; value"]'})

    def test_export_settings_changed(self):
        self.write("export_presets.cfg", '[preset.0]\nname="Other"\n')
        with self.assertRaisesRegex(ValueError, "export_presets.cfg"):
            tool.validate_snapshot_diff(self.snapshot, tool.take_snapshot(self.project))

    def test_project_identity_fallback_and_missing_base(self):
        self.assertEqual(tool.project_identity(self.project), ("2.4.0", "android-base"))
        path = self.project / "project.godot"
        text = path.read_text(encoding="utf-8").replace('config/version="2.4.0"\n', "")
        path.write_text(text, encoding="utf-8")
        (self.project.parent / "version.json").write_text('{"version":"2.4.2"}', encoding="utf-8")
        self.assertEqual(tool.project_identity(self.project), ("2.4.2", "android-base"))
        path.write_text(text.replace('base_id="android-base"', 'base_id=""'), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "base_id"):
            tool.project_identity(self.project)

    def test_entry_hash_size_notes(self):
        entry = self.entry(notes="one\ntwo", mandatory=True)
        payload = (self.root / entry["filename"]).read_bytes()
        self.assertEqual(entry["sha256"], hashlib.sha256(payload).hexdigest())
        self.assertEqual(entry["size_bytes"], len(payload))
        self.assertEqual(entry["notes"], ["one", "two"])
        self.assertTrue(entry["mandatory"])
        self.assertEqual(entry["download_url"], "/v1/downloads/patch.pck")

    def test_non_gdpc_and_missing_output_rejected(self):
        path = self.root / "bad.pck"
        for payload in (b"", b"G", b"PK\x03\x04zip"):
            path.write_bytes(payload)
            with self.assertRaisesRegex(ValueError, "PCK magic"):
                tool.build_hotpatch_entry(path, version="2.4.1", base_version="2.4.0", base_id="base", engine="4.7.2")
        path.unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            tool.verify_pck(path)

    def test_entry_rejects_major_jump_and_bad_metadata(self):
        for args in ({"version": "3.0.0"}, {"version": "2.4.0"}, {"platform": "ios"}, {"base_id": ""}, {"engine": ""}):
            with self.subTest(args=args), self.assertRaises(ValueError):
                self.entry(**args)

    def test_manifest_generation_and_upsert(self):
        first = self.entry(notes=["first"])
        manifest = tool.merge_hotpatches_manifest({}, first)
        updated = dict(first, notes=["updated"])
        manifest = tool.merge_hotpatches_manifest(manifest, updated)
        self.assertEqual(manifest, {"hotpatches": [updated]})
        newer = dict(first, filename="new.pck", version="2.4.10")
        manifest["extra"] = "retained"
        result = tool.merge_hotpatches_manifest(manifest, newer)
        self.assertEqual([item["version"] for item in result["hotpatches"]], ["2.4.10", "2.4.1"])
        self.assertEqual(result["extra"], "retained")
        self.assertEqual(tool.merge_hotpatches_manifest([first], updated), {"hotpatches": [updated]})
        for invalid in ({"hotpatches": "bad"}, [None], [{}]):
            with self.assertRaises(ValueError):
                tool.merge_hotpatches_manifest(invalid, first)

    def fake_godot(self, command, **kwargs):
        self.commands.append(command)
        if "--version" in command:
            return SimpleNamespace(stdout="4.7.2.stable.official.1234\n")
        if "--export-pack" in command or "--export-patch" in command:
            mode = "--export-pack" if "--export-pack" in command else "--export-patch"
            Path(command[command.index(mode) + 2]).write_bytes(b"GDPCexported")
        return SimpleNamespace(returncode=0)

    def test_cli_baseline_then_patch_and_manifest_upsert(self):
        self.commands = []
        with patch.object(tool, "PROJECT", self.project), patch.object(tool, "REPOSITORY", self.root), \
                patch.object(tool.subprocess, "run", side_effect=self.fake_godot):
            self.assertEqual(tool.main(["baseline", "--godot", "godot"]), 0)
            base = self.root / "build/update_baselines/android-base"
            metadata = json.loads((base / "baseline.json").read_text(encoding="utf-8"))
            self.assertEqual(metadata["schema"], 1)
            self.assertEqual(metadata["packs"], ["android-base.pck"])
            self.assertEqual(metadata["base_version"], "2.4.0")
            self.assertEqual(metadata["engine"], "4.7.2")
            self.assertEqual(metadata["snapshot"], self.snapshot)
            self.write("src/app/Main.gd", "extends Node\nvar patched = true\n")
            merged_path = self.root / "downloads/hotpatches.json"
            args = ["patch", "--godot", "godot", "--baseline", str(base), "--version", "2.4.1",
                    "--note", "first", "--notes", "second\nthird", "--mandatory", "--merge-manifest", str(merged_path)]
            self.assertEqual(tool.main(args), 0)
            result_path = self.root / "build/hotpatches/v2.4.1/hotpatches.json"
            result = json.loads(result_path.read_text(encoding="utf-8"))
            entry = result["hotpatches"][0]
            self.assertEqual(entry["notes"], ["first", "second", "third"])
            self.assertTrue(entry["mandatory"])
            self.assertEqual(json.loads(merged_path.read_text(encoding="utf-8")), result)
            self.assertEqual(tool.main(args), 0)
            self.assertEqual(len(json.loads(merged_path.read_text(encoding="utf-8"))["hotpatches"]), 1)
            command = next(cmd for cmd in self.commands if "--export-patch" in cmd)
            self.assertEqual(command[-2:], ["--patches", str(base / "android-base.pck")])
            self.assertIn("--import", self.commands[1])

            # CLI must reject identity/engine changes before exporting any patch.
            before = sum("--export-patch" in cmd for cmd in self.commands)
            for key, value in (("base_id", "other-base"), ("engine", "4.8.0"), ("base_version", "3.0.0")):
                changed = dict(metadata, **{key: value})
                tool.write_json(base / "baseline.json", changed)
                with self.subTest(key=key), self.assertRaises(SystemExit) as error:
                    tool.main(args)
                self.assertEqual(error.exception.code, 1)
            self.assertEqual(sum("--export-patch" in cmd for cmd in self.commands), before)

    def test_engine_version_and_export_failure(self):
        with patch.object(tool.subprocess, "run", return_value=SimpleNamespace(stdout="unknown")):
            with self.assertRaisesRegex(ValueError, "Cannot parse"):
                tool.engine_version("godot")
        with patch.object(tool.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "godot")):
            with self.assertRaises(subprocess.CalledProcessError):
                tool.run_godot("godot", "--editor", "--import")


if __name__ == "__main__":
    unittest.main(verbosity=2)
