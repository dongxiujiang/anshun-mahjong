"""Create/reuse a private Android release key and configure local Godot credentials."""
from pathlib import Path
import json
import os
import secrets
import subprocess

PROJECT = Path(__file__).resolve().parents[2]
SIGNING = Path.home() / ".codex/mahjong-signing"
JAVA = PROJECT / "build/tools/java/jdk-17.0.16+8"


def configure():
    SIGNING.mkdir(parents=True, exist_ok=True)
    credentials = SIGNING / "credentials.json"
    keystore = SIGNING / "mahjong-release.keystore"
    if credentials.exists():
        data = json.loads(credentials.read_text(encoding="utf-8"))
    else:
        if keystore.exists():
            raise RuntimeError("正式签名文件已存在但缺少凭据，请恢复签名备份，不要重新生成")
        data = {"keystore": str(keystore), "alias": "mahjong-release", "password": secrets.token_urlsafe(32)}
        credentials.write_text(json.dumps(data, indent=2), encoding="utf-8")
    if not keystore.exists():
        environment = os.environ.copy()
        environment["MAHJONG_RELEASE_PASSWORD"] = data["password"]
        result = subprocess.run([
            str(JAVA / "bin/keytool.exe"), "-genkeypair", "-keystore", str(keystore),
            "-storetype", "JKS", "-storepass:env", "MAHJONG_RELEASE_PASSWORD",
            "-keypass:env", "MAHJONG_RELEASE_PASSWORD", "-alias", data["alias"],
            "-keyalg", "RSA", "-keysize", "3072", "-validity", "10000",
            "-dname", "CN=Dongxiu Mahjong, OU=Games, O=Dongxiu, L=Anshun, ST=Guizhou, C=CN",
        ], env=environment, capture_output=True)
        if result.returncode:
            raise RuntimeError("无法生成正式签名，请检查本地 JDK")
    # Keep both key and password private; Godot also needs the matching local copy.
    identity = subprocess.check_output(["whoami"], text=True).strip()
    subprocess.run(["icacls", str(SIGNING), "/inheritance:r", "/grant:r", identity + ":(OI)(CI)F", "/Q"], check=True, capture_output=True)
    lines = ["[preset.1.options]"]
    for key, value in [("keystore/release", str(keystore).replace("\\", "/")), ("keystore/release_user", data["alias"]), ("keystore/release_password", data["password"])]:
        lines.append(key + "=" + json.dumps(value, ensure_ascii=False))
    local = PROJECT / ".godot/export_credentials.cfg"
    local.write_text("\n".join(lines) + "\n", encoding="utf-8")
    subprocess.run(["icacls", str(local), "/inheritance:r", "/grant:r", identity + ":F", "/Q"], check=True, capture_output=True)
    (SIGNING / "签名备份说明.txt").write_text(
        "正式安卓签名备份\n\n请将本目录完整复制到私人备份盘。\n"
        "mahjong-release.keystore 与 credentials.json 必须一起保留，后续所有 APK 使用同一签名。\n"
        "不要上传到 GitHub、Releases 或发给玩家。\n"
        "遗失密钥后无法为现有正式安装版发布覆盖更新。\n",
        encoding="utf-8-sig")
    print("Android 正式签名已配置，私钥与密码仅保存在本机私人目录。")


if __name__ == "__main__": configure()
