"""Exercise real update HTTP requests, downloads, cancellation and Windows replacement."""
from pathlib import Path
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import subprocess
import threading
import time

PROJECT = Path(__file__).resolve().parents[1]
FIXTURE = PROJECT / "build" / "update_fixture"


def run(godot):
    FIXTURE.mkdir(parents=True, exist_ok=True)
    # The helper only ever touches these disposable executables in build/update_fixture.
    install = FIXTURE / "安装目录 ' 引号 $ 测试"
    install.mkdir(exist_ok=True)
    target = install / "麻将测试.exe"
    fresh = FIXTURE / "新版.exe"
    powershell = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"
    if os.name != "nt":
        raise RuntimeError("Windows replacement integration test requires Windows")
    compile_script = FIXTURE / "compile-fixture.ps1"
    def ps_literal(value): return "'" + str(value).replace("'", "''") + "'"
    source = r'''
using System;
using System.IO;
public class UpdateFixture {
    public static void Main() {
        File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "MARKER.txt"), "MARKER");
    }
}
'''
    code = "$ErrorActionPreference = 'Stop'\n"
    for path, marker in [(target, "old"), (fresh, "new")]:
        if path.exists(): path.unlink()
        code += "$fixtureCode = @'\n" + source.replace("MARKER", marker).strip() + "\n'@\n"
        code += f"Add-Type -TypeDefinition $fixtureCode -OutputAssembly {ps_literal(path)} -OutputType ConsoleApplication\n"
    # Different class names avoid Add-Type's cache reusing the old class.
    code = code.replace('public class UpdateFixture {', 'public class UpdateFixtureOld {', 1)
    code = code.replace('public class UpdateFixture {', 'public class UpdateFixtureNew {', 1)
    compile_script.write_text(code, encoding="utf-8-sig")
    compiled = subprocess.run([str(powershell), "-NoProfile", "-NonInteractive", "-File", str(compile_script)], capture_output=True, text=True)
    if compiled.returncode:
        raise AssertionError(compiled.stderr)
    package = fresh.read_bytes()
    sha = hashlib.sha256(package).hexdigest()
    old_hash = hashlib.sha256(target.read_bytes()).hexdigest()
    # Valid PCK fixture exercises the same streamed download on Windows and Android.
    patch_path = FIXTURE / "patch.pck"
    packer = FIXTURE / "pack_fixture.gd"
    packer.write_text('''extends SceneTree
func _initialize():
	var source = "res://build/update_fixture/resource.txt"
	var file = FileAccess.open(source, FileAccess.WRITE)
	file.store_string("real hot-update resource")
	file.close()
	var pack = PCKPacker.new()
	var result = pack.pck_start("res://build/update_fixture/patch.pck")
	if result == OK: result = pack.add_file("res://fixture-resource.txt", source)
	if result == OK: result = pack.flush()
	quit(0 if result == OK else 1)
''', encoding="utf-8")
    packed = subprocess.run([godot, "--headless", "--path", str(PROJECT), "--script", str(packer)], capture_output=True, timeout=15)
    assert packed.returncode == 0 and b"SCRIPT ERROR:" not in packed.stderr, packed.stderr
    patch_package = patch_path.read_bytes()
    patch_sha = hashlib.sha256(patch_package).hexdigest()
    engine_version = subprocess.check_output([godot, "--version"], text=True).strip().split(".stable")[0]

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path in ["/package.exe", "/slow.exe", "/wrong.exe", "/patch.pck", "/wrong.pck"]:
                payload = b"not-an-executable" if self.path in ["/wrong.exe", "/wrong.pck"] else patch_package if self.path == "/patch.pck" else package
                self.send_response(200)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                if self.path == "/slow.exe":
                    self.wfile.write(payload[:32])
                    self.wfile.flush()
                    time.sleep(1.0)
                    try: self.wfile.write(payload[32:])
                    except (BrokenPipeError, ConnectionResetError): pass
                else: self.wfile.write(payload)
                return
            code = 200
            def patch_manifest():
                entry = {"url": base + "/patch.pck", "sha256": patch_sha, "size": len(patch_package), "base_id": "1.2.0-boot1", "base_version": "1.2.0", "engine": engine_version}
                return {"schema": 2, "version": "1.2.2", "notes": "小版本资源更新", "release_url": base + "/release", "patches": {"windows": entry, "android": entry}}
            if self.path == "/missing": code, data = 404, {}
            elif self.path == "/limited": code, data = 429, {}
            elif self.path == "/broken":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"{broken-json")
                return
            elif self.path in ["/patch-manifest", "/patch-bad-hash", "/patch-wrong-format"]:
                data = patch_manifest()
                if self.path == "/patch-bad-hash": data["patches"]["windows"]["sha256"] = "0" * 64
                if self.path == "/patch-wrong-format":
                    data["patches"]["windows"].update(url=base + "/wrong.pck", sha256=hashlib.sha256(b"not-an-executable").hexdigest(), size=len(b"not-an-executable"))
            elif self.path in ["/github-patch", "/github-wrong-digest"]:
                encoded = json.dumps(patch_manifest(), ensure_ascii=False).encode()
                digest = hashlib.sha256(encoded).hexdigest() if self.path == "/github-patch" else "0" * 64
                data = {"tag_name": "v1.2.2", "html_url": base + "/release", "assets": [{"name": "update-manifest.json", "browser_download_url": base + "/patch-manifest", "digest": "sha256:" + digest}]}
            else:
                version = "1.2.0" if self.path == "/current" else "9.0.10"
                url = base + "/package.exe"
                digest, size = sha, len(package)
                if self.path == "/bad-hash": digest = "0" * 64
                if self.path == "/download-error": url = base + "/missing"
                if self.path == "/bad-size": size += 1
                if self.path == "/bad-exe":
                    url, digest, size = base + "/wrong.exe", hashlib.sha256(b"not-an-executable").hexdigest(), len(b"not-an-executable")
                if self.path == "/slow-manifest": url = base + "/slow.exe"
                data = {"version": version, "notes": "更新联机房间与牌桌显示", "release_url": base + "/release", "platforms": {"windows": {"url": url, "sha256": digest, "size": size}}}
            payload = json.dumps(data, ensure_ascii=False).encode()
            self.send_response(code)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def log_message(self, *_): pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    base = f"http://127.0.0.1:{server.server_port}"
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    waiter = subprocess.Popen([str(powershell), "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", "Start-Sleep -Seconds 6"], creationflags=subprocess.CREATE_NO_WINDOW)
    try:
        log = FIXTURE / "godot.log"
        errors = FIXTURE / "godot.err"
        with log.open("w", encoding="utf-8") as output, errors.open("w", encoding="utf-8") as err:
            result = subprocess.run([godot, "--headless", "--path", str(PROJECT), "res://tests/update_http.tscn", "--quit-after", "30000", "--", f"--update-base={base}", f"--target={target}", f"--wait-pid={waiter.pid}"], stdout=output, stderr=err, timeout=30)
        text = log.read_text(encoding="utf-8-sig")
        error_text = errors.read_text(encoding="utf-8-sig")
        if result.returncode != 0 or "passed" not in text or "ERROR:" in error_text:
            raise AssertionError(text + "\n" + error_text)
        print(text.splitlines()[-1], flush=True)
        info = json.loads((FIXTURE / "test-result.json").read_text())
        applied = subprocess.run([str(powershell), "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", info["helper"]], capture_output=True, timeout=15)
        if applied.returncode: raise AssertionError(applied.stderr.decode(errors="replace"))
        assert hashlib.sha256(target.read_bytes()).hexdigest() == sha, "Helper failed to replace executable"
        backup = Path(str(target) + ".previous")
        assert backup.exists() and hashlib.sha256(backup.read_bytes()).hexdigest() == old_hash, "Old version backup missing"
        deadline = time.monotonic() + 3
        while not (install / "new.txt").exists() and time.monotonic() < deadline: time.sleep(0.05)
        assert (install / "new.txt").read_text() == "new", "New exe was not relaunched"
        status = (Path(info["source"]).parent / "update-result.txt").read_text(encoding="utf-8-sig")
        assert "9.0.10" in status, "No update completion status"
        assert not Path(str(target) + ".update-new").exists(), "Temporary copy remains"
        print("[run_update] downloaded, verified, waited, replaced, backed up and relaunched: passed", flush=True)
        # Exercise rollback with a checksum-valid file that Windows cannot execute.
        rollback_dir = FIXTURE / "rollback-install"
        rollback_dir.mkdir(exist_ok=True)
        rollback_target = rollback_dir / "game.exe"
        rollback_target.write_bytes(backup.read_bytes())
        invalid_source = FIXTURE / "invalid.exe"
        invalid_source.write_bytes(b"MZ" + b"invalid-binary" * 10)
        rollback_script = FIXTURE / "rollback.ps1"
        script_text = Path(info["helper"]).read_text(encoding="utf-8-sig")
        lines = []
        for line in script_text.splitlines():
            if line.startswith("$updateTarget ="): line = "$updateTarget = " + ps_literal(rollback_target)
            elif line.startswith("$updateSource ="): line = "$updateSource = " + ps_literal(invalid_source)
            elif line.startswith("$updateHash ="): line = "$updateHash = " + ps_literal(hashlib.sha256(invalid_source.read_bytes()).hexdigest())
            elif "Start-Process -FilePath 'notepad.exe'" in line: line = "    # No desktop notification during automated rollback test."
            lines.append(line)
        rollback_script.write_text("\n".join(lines), encoding="utf-8-sig")
        rolled_back = subprocess.run([str(powershell), "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-File", str(rollback_script)], capture_output=True, timeout=15)
        assert rolled_back.returncode == 0, rolled_back.stderr.decode(errors="replace")
        assert hashlib.sha256(rollback_target.read_bytes()).hexdigest() == old_hash, "Failed restart did not restore original"
        status = (FIXTURE / "update-result.txt").read_text(encoding="utf-8-sig")
        assert "自动更新失败" in status, "No failure report after rollback"
        print("[run_update] failed restart restores original executable: passed", flush=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        if waiter.poll() is None: waiter.terminate()
        waiter.wait(timeout=5)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    run(parser.parse_args().godot)
