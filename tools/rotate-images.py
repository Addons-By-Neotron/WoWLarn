#!/usr/bin/env python3
"""Rotates the weapon pictures (webp with transparency) 45 degrees clockwise and saves them as
transparent 256x256 PNG and TGA files in Media/Weapons.  Usage: rotate-images.py <folder> [angle]"""
import sys
from pathlib import Path
from PIL import Image

NAMES = ["slayer", "dagger", "staffofpower", "spear", "flail", "battleaxe", "lanceofdeath", "longsword",
         "vorpal", "2hs", "slash", "sunsword", "hammer"]
SIZE = 256

def convert(source, target, angle):
    image = Image.open(source).convert("RGBA")
    image = image.rotate(-angle, resample=Image.BICUBIC, expand=True)  # clockwise
    box = image.getchannel("A").getbbox()
    if box:
        image = image.crop(box)
    side = max(image.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
    canvas = canvas.resize((SIZE, SIZE), Image.LANCZOS)
    canvas.save(target.with_suffix(".png"))
    canvas.save(target.with_suffix(".tga"))

if __name__ == "__main__":
    folder = Path(sys.argv[1]).expanduser()
    angle = float(sys.argv[2]) if len(sys.argv) > 2 else 45
    out = Path(__file__).resolve().parent.parent / "Media" / "Weapons"
    out.mkdir(parents=True, exist_ok=True)
    for name in NAMES:
        source = folder / (name + ".webp")
        if source.exists():
            convert(source, out / name, angle)
            print("ok", name)
        else:
            print("missing", source)
