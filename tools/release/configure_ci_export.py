"""Configure an isolated Actions runner for Godot Android export.

Secrets are read only from the environment and never printed. This does not
change project.godot, export_presets.cfg or the developer's signing directory.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import re


def configure(project, config_dir, signing_dir, environment, godot_version, signing=False):
    version = re.fullmatch(r"([0-9]+\.[0-9]+)\.[0-9]+", godot_version)
    if not version:
        raise ValueError("GODOT_VERSION must be x.y.z")
    sdk_value = environment.get("ANDROID_HOME") or environment.get("ANDROID_SDK_ROOT")
    java_value = environment.get("JAVA_HOME")
    if not sdk_value or not java_value:
        raise ValueError("ANDROID_HOME and JAVA_HOME are required")
    sdk, java = Path(sdk_value).resolve(), Path(java_value).resolve()
    if not (sdk / "platform-tools").is_dir() or not (sdk / "build-tools").is_dir():
        raise ValueError("Android SDK tools are not installed")
    if not (java / "bin").is_dir():
        raise ValueError("Java SDK is not installed")

    # Validate all secrets before writing any signing file.
    key_bytes = None
    if signing:
        required = ["ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_USER", "ANDROID_KEYSTORE_PASSWORD"]
        for name in required:
            if not environment.get(name):
                raise ValueError(f"{name} is required")
        try:
            encoded = "".join(environment["ANDROID_KEYSTORE_BASE64"].split())
            key_bytes = base64.b64decode(encoded, validate=True)
        except (ValueError, UnicodeError):
            raise ValueError("ANDROID_KEYSTORE_BASE64 is invalid") from None
        if not key_bytes:
            raise ValueError("ANDROID_KEYSTORE_BASE64 is empty")

    settings = Path(config_dir) / "godot" / f"editor_settings-{version[1]}.tres"
    settings.parent.mkdir(parents=True, exist_ok=True)
    settings.write_text(
        '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
        + "export/android/android_sdk_path=" + json.dumps(sdk.as_posix(), ensure_ascii=False) + "\n"
        + "export/android/java_sdk_path=" + json.dumps(java.as_posix(), ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    if signing:
        key = Path(signing_dir) / "release.keystore"
        key.parent.mkdir(parents=True, exist_ok=True)
        key.write_bytes(key_bytes)
        key.chmod(0o600)
        credentials = Path(project) / ".godot" / "export_credentials.cfg"
        credentials.parent.mkdir(parents=True, exist_ok=True)
        values = {
            "keystore/release": key.resolve().as_posix(),
            "keystore/release_user": environment["ANDROID_KEYSTORE_USER"],
            "keystore/release_password": environment["ANDROID_KEYSTORE_PASSWORD"],
        }
        credentials.write_text(
            "[preset.0.options]\n" + "\n".join(
                name + "=" + json.dumps(value, ensure_ascii=False) for name, value in values.items()
            ) + "\n", encoding="utf-8",
        )
        credentials.chmod(0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--signing", action="store_true", help="Configure signing for a full APK build")
    args = parser.parse_args()
    if os.environ.get("GITHUB_ACTIONS") != "true":
        parser.exit(1, "This script is only for an isolated GitHub Actions runner.\n")
    try:
        configure(
            Path(__file__).resolve().parents[2],
            Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))),
            Path(os.environ["RUNNER_TEMP"]) / "signing",
            os.environ, os.environ["GODOT_VERSION"], args.signing,
        )
    except (ValueError, KeyError, OSError) as error:
        # Do not include environment values or private file contents in logs.
        parser.exit(1, str(error) + "\n")
    print("Godot Android SDK configured; signing configured." if args.signing else "Godot Android SDK configured.")


if __name__ == "__main__":
    main()

