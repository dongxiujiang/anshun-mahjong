"""Generate desktop/Android icon sizes from the supplied game artwork."""
from pathlib import Path
import argparse
from PIL import Image, ImageOps

PROJECT = Path(__file__).resolve().parents[2]


def generate(source):
    output = PROJECT / "res/icons"
    output.mkdir(parents=True, exist_ok=True)
    artwork = ImageOps.exif_transpose(Image.open(source)).convert("RGBA")
    artwork = ImageOps.fit(artwork, (1024, 1024), method=Image.Resampling.LANCZOS)
    artwork.save(output / "game_icon.png")
    artwork.save(output / "game_icon.ico", format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    artwork.resize((192, 192), Image.Resampling.LANCZOS).save(output / "android_icon.png")
    # Android launchers crop adaptive icons to circles/squircles. Keep the complete
    # artwork within the central safe zone so the gold character and title survive.
    background = Image.new("RGBA", (432, 432), (3, 39, 57, 255))
    foreground = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    foreground.alpha_composite(artwork.resize((280, 280), Image.Resampling.LANCZOS), (76, 76))
    background.save(output / "android_background.png")
    foreground.save(output / "android_foreground.png")
    print(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    generate(parser.parse_args().source)
