"""Install the existing Android arm64 GME SDK into this remake's Godot Gradle template."""

from pathlib import Path
from zipfile import ZipFile


DEPENDENCY = 'dependencies { implementation files("libs/gmesdk.aar") }'


def install(template: Path, sdk_dir: Path) -> None:
    gradle = template / "build.gradle"
    if not gradle.is_file():
        raise FileNotFoundError(f"Install the Godot Android build template first: {gradle}")
    sdk = sdk_dir / "gmesdk.aar"
    delegate = sdk_dir / "VoiceDelegate.java"
    with ZipFile(sdk) as archive:
        for name in ("classes.jar", "jni/arm64-v8a/libgmesdk.so", "AndroidManifest.xml"):
            archive.getinfo(name)
    files = {
        template / "libs/gmesdk.aar": sdk.read_bytes(),
        template / "src/main/java/com/anshun/mahjong/VoiceDelegate.java": delegate.read_bytes(),
    }
    contents = gradle.read_bytes()
    if DEPENDENCY.encode() not in contents:
        line_end = b"\r\n" if b"\r\n" in contents else b"\n"
        files[gradle] = contents.rstrip(b"\r\n") + 2 * line_end + DEPENDENCY.encode() + line_end
    for target, data in files.items():
        if not target.exists() or target.read_bytes() != data:
            target.parent.mkdir(exist_ok=True, parents=True)
            target.write_bytes(data)


if __name__ == "__main__":
    game = Path(__file__).resolve().parents[1]
    install(game / "android/build", game.parents[1] / "addons/gme")
    print("Installed Android GME SDK and callback for the remake.")
