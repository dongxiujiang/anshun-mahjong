import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest


class OptimizationScopeTests(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location(
            "scope_gate", Path(__file__).parents[1] / "tools/check_optimization_scope.py")
        self.gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.gate)
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.gate.PROJECT = Path(self.directory.name)
        self.gate.MANIFEST = self.gate.PROJECT / "docs/baseline.json"
        self.gate.MANIFEST.parent.mkdir()
        self.gate.UI_MIGRATIONS = self.gate.PROJECT / "docs/migrations.json"
        self.gate.FROZEN_DIRS = ("scripts/core",)
        self.gate.FROZEN_FILES = ()
        self.core = self.write("scripts/core/Rule.gd", b"original\n")
        self.ui = self.write("tests/table_render_cache.gd", b"original\n")
        with contextlib.redirect_stdout(io.StringIO()):
            self.gate.snapshot()

    def write(self, name, data):
        path = self.gate.PROJECT / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def check(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.gate.check()

    def migration(self, name):
        baseline = json.loads(self.gate.MANIFEST.read_text())["files"]
        return {"baseline_sha256": baseline[name],
                "current_sha256": self.gate.digest(self.gate.PROJECT / name),
                "reason": "Explicit UI layout requirement"}

    def test_gameplay_edit_cannot_be_allowed_as_ui_migration(self):
        self.core.write_bytes(b"changed rule\n")
        self.gate.UI_MIGRATIONS.write_text(json.dumps({
            "files": {"scripts/core/Rule.gd": self.migration("scripts/core/Rule.gd")}}))
        with self.assertRaises(SystemExit):
            self.check()

    def test_ui_migration_requires_the_documented_exact_revision(self):
        self.ui.write_bytes(b"updated UI assertion\n")
        with self.assertRaises(SystemExit):
            self.check()
        self.gate.UI_MIGRATIONS.write_text(json.dumps({
            "files": {"tests/table_render_cache.gd": self.migration("tests/table_render_cache.gd")}}))
        self.check()
        self.ui.write_bytes(b"unreviewed later edit\n")
        with self.assertRaises(SystemExit):
            self.check()

    def test_added_or_deleted_gameplay_source_is_rejected(self):
        extra = self.write("scripts/core/Other.gd", b"new rule\n")
        with self.assertRaises(SystemExit):
            self.check()
        extra.unlink()
        self.core.unlink()
        with self.assertRaises(SystemExit):
            self.check()

    def test_checkout_line_endings_do_not_change_the_baseline(self):
        self.core.write_bytes(b"original\r\n")
        self.check()
        with self.assertRaises(SystemExit):
            self.gate.snapshot()


if __name__ == "__main__":
    unittest.main()
