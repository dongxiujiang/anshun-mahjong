import base64
import json
import tempfile
import unittest
from pathlib import Path

from tools.release.configure_ci_export import configure


class ConfigureCiExportTests(unittest.TestCase):
    def _environment(self, root):
        sdk = root / "sdk"
        (sdk / "platform-tools").mkdir(parents=True)
        (sdk / "build-tools" / "35.0.0").mkdir(parents=True)
        java = root / "java"
        (java / "bin").mkdir(parents=True)
        return {"ANDROID_HOME": str(sdk), "JAVA_HOME": str(java)}

    def test_patch_configuration_writes_isolated_editor_settings(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            environment = self._environment(root)
            configure(root / "project", root / "config", root / "signing", environment, "4.7.2")
            settings = root / "config" / "godot" / "editor_settings-4.7.tres"
            text = settings.read_text(encoding="utf-8")
            self.assertIn("export/android/android_sdk_path", text)
            self.assertIn("export/android/java_sdk_path", text)
            self.assertFalse((root / "signing" / "release.keystore").exists())

    def test_signing_accepts_wrapped_base64_and_escapes_credentials(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            environment = self._environment(root)
            raw = b"test-keystore-bytes"
            encoded = base64.b64encode(raw).decode("ascii")
            environment.update({
                "ANDROID_KEYSTORE_BASE64": encoded[:5] + "\n" + encoded[5:],
                "ANDROID_KEYSTORE_USER": "alias\\with\"quote",
                "ANDROID_KEYSTORE_PASSWORD": "pass\\word\"quoted",
            })
            project = root / "project"
            configure(project, root / "config", root / "signing", environment, "4.7.2", signing=True)
            self.assertEqual((root / "signing" / "release.keystore").read_bytes(), raw)
            lines = (project / ".godot" / "export_credentials.cfg").read_text(encoding="utf-8").splitlines()[1:]
            values = {line.split("=", 1)[0]: json.loads(line.split("=", 1)[1]) for line in lines}
            self.assertEqual(values["keystore/release_user"], environment["ANDROID_KEYSTORE_USER"])
            self.assertEqual(values["keystore/release_password"], environment["ANDROID_KEYSTORE_PASSWORD"])

    def test_invalid_secret_fails_before_writing_signing_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            environment = self._environment(root)
            environment.update({
                "ANDROID_KEYSTORE_BASE64": "not base64!",
                "ANDROID_KEYSTORE_USER": "alias",
                "ANDROID_KEYSTORE_PASSWORD": "password",
            })
            with self.assertRaises(ValueError):
                configure(root / "project", root / "config", root / "signing", environment, "4.7.2", signing=True)
            self.assertFalse((root / "signing" / "release.keystore").exists())
            self.assertFalse((root / "project" / ".godot" / "export_credentials.cfg").exists())

    def test_missing_android_toolchain_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            environment = {"ANDROID_HOME": str(root / "missing"), "JAVA_HOME": str(root / "java")}
            with self.assertRaises(ValueError):
                configure(root / "project", root / "config", root / "signing", environment, "4.7.2")


if __name__ == "__main__":
    unittest.main()
