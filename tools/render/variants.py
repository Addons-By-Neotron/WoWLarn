"""Potion variants. Renders each via Blender, then makes 256px icons + a contact sheet.
Usage: [JOBS=4] python3 variants.py [slug ...]   (no args = all)
Keys: halo (0..1 post glow, halo_color), color/glow (linear RGB), glow_strength, alpha, transmission (liquid), sparks, spark_color,
      shape (round|wide|square|pyramid), cap (cork|wax|gold|silver), cap_color, fill (degrees, round/wide),
      fill_frac (square/pyramid), rot (deg, square/pyramid), lean (deg sideways tilt)
"""
import os
from PIL import Image, ImageDraw
import runner

V = [
    (0,  "generic", {}),
    (1,  "sleep", dict(color=(0.02,0.03,0.25), glow=(0.15,0.2,0.7), glow_strength=0.35,
                       sparks=12, spark_color=(0.7,0.7,1.0), cap="wax", cap_color=(0.1,0.12,0.35))),
    (2,  "healing", dict(color=(0.3,0.0,0.0), glow=(0.7,0.0,0.005), glow_strength=0.7, spark_color=(1,0.45,0.35))),
    (3,  "raise_level", dict(halo=0.7, color=(0.55,0.45,0.2), glow=(1,0.85,0.5), glow_strength=0.6, sparks=45,
                       spark_color=(1,1,0.9), shape="pyramid", cap="silver")),
    (4,  "increase_ability", dict(halo=0.5, color=(0.0,0.35,0.35), glow=(0.05,0.8,0.75), glow_strength=0.9,
                       spark_color=(0.7,1,1), shape="square", cap="silver")),
    (5,  "wisdom", dict(color=(0.02,0.08,0.5), glow=(0.1,0.3,1.0), glow_strength=0.8,
                       spark_color=(0.9,0.95,1), shape="square")),
    (6,  "strength", dict(color=(0.6,0.15,0.0), glow=(1.0,0.35,0.02), spark_color=(1,0.8,0.4),
                       shape="wide")),
    (7,  "raise_charisma", dict(halo=0.4, color=(0.7,0.08,0.35), glow=(1.0,0.3,0.6), glow_strength=0.9, sparks=40,
                       spark_color=(1,0.85,0.95), cap="wax", cap_color=(0.8,0.2,0.45))),
    (8,  "weakness", dict(color=(0.35,0.33,0.15), glow=(0.4,0.4,0.15), glow_strength=0.15, alpha=0.92,
                       transmission=0.3, sparks=0)),
    (9,  "learning", dict(color=(0.1,0.35,0.7), glow=(0.3,0.65,1.0), spark_color=(1,1,1))),
    (10, "gold_detection", dict(halo=0.5, color=(0.5,0.2,0.0), glow=(0.9,0.45,0.02), glow_strength=0.7, sparks=40,
                       spark_color=(1,0.85,0.3), shape="wide", cap="gold")),
    (11, "monster_detection", dict(halo=0.55, color=(0.25,0.0,0.02), glow=(0.7,0.0,0.05), glow_strength=0.5,
                       sparks=20, spark_color=(1,0.2,0.1), shape="pyramid", cap="wax", cap_color=(0.03,0.03,0.03))),
    (12, "forgetfulness", dict(color=(0.45,0.42,0.55), glow=(0.5,0.45,0.65), glow_strength=0.3,
                       alpha=0.78, sparks=8, spark_color=(0.8,0.8,0.9))),
    (13, "water", dict(color=(0.8,0.9,1.0), glow=(0.6,0.75,0.9), glow_strength=0.0, alpha=0.55,
                       transmission=0.8, sparks=0)),
    (14, "blindness", dict(halo=0.9, halo_color=(0.04,0.0,0.07), color=(0.01,0.01,0.015), glow=(0.08,0.05,0.12), glow_strength=0.05, alpha=0.98,
                       transmission=0.0, sparks=0)),
    (15, "confusion", dict(color=(0.35,0.5,0.0), glow=(0.6,0.9,0.05), glow_strength=0.8, sparks=40,
                       spark_color=(1,0.2,0.9), shape="wide")),
    (16, "heroism", dict(halo=0.6, color=(0.6,0.3,0.0), glow=(1.0,0.6,0.05), glow_strength=1.0, sparks=35,
                       spark_color=(1,1,0.7), shape="pyramid", cap="gold")),
    (17, "sturdiness", dict(shape="square", color=(0.3,0.15,0.04), glow=(0.55,0.3,0.08), glow_strength=0.4,
                       alpha=0.92, sparks=10, spark_color=(0.9,0.7,0.4))),
    (18, "giant_strength", dict(halo=0.5, color=(0.6,0.06,0.0), glow=(1.0,0.2,0.0), glow_strength=1.1, sparks=40,
                       spark_color=(1,0.7,0.2), shape="wide", cap="wax", cap_color=(0.45,0.02,0.0))),
    (19, "fire_resistance", dict(halo=0.4, color=(0.05,0.4,0.7), glow=(0.2,0.75,1.0), glow_strength=0.8,
                       spark_color=(1,0.5,0.1), cap="wax", cap_color=(0.85,0.85,0.9))),
    (20, "treasure_finding", dict(halo=0.5, color=(0.0,0.4,0.12), glow=(0.05,0.85,0.3), glow_strength=0.8, sparks=40,
                       spark_color=(1,0.85,0.3), shape="wide", cap="gold")),
    (21, "instant_healing", dict(halo=0.6, color=(0.45,0.0,0.0), glow=(1.0,0.02,0.0), glow_strength=1.0, sparks=45,
                       spark_color=(1,0.75,0.5), shape="pyramid", cap="gold")),
    (22, "cure_dianthroritis", dict(halo=0.8, color=(0.05,0.5,0.35), glow=(0.2,1.0,0.65), glow_strength=0.7, sparks=50,
                       spark_color=(1,0.85,0.35), shape="pyramid", cap="gold", cap_color=(1.0,0.55,0.2))),
    (23, "poison", dict(halo=0.4, color=(0.08,0.4,0.0), glow=(0.25,0.9,0.0), glow_strength=0.7, alpha=0.92,
                       sparks=14, spark_color=(0.6,1,0.2), cap="wax", cap_color=(0.03,0.03,0.03))),
    (24, "see_invisible", dict(halo=0.5, color=(0.7,0.9,1.0), glow=(0.6,0.9,1.0), glow_strength=0.6, alpha=0.65,
                       transmission=0.8, sparks=40, spark_color=(1,1,1), shape="square", cap="silver")),
]

OUTDIR = os.path.join(runner.REPO, "Media", "Potions")    # <name>_icon.png, 256px, cropped to the bottle

def contact_sheets():
    """Light + dark checkerboard sheets so transparency and halos are visible."""
    for fname, c1, c2 in (("contact_sheet.png", (205, 205, 205), (150, 150, 150)),
                          ("contact_sheet_dark.png", (40, 40, 46), (24, 24, 28))):
        sheet = Image.new("RGBA", (5*160, 5*180), (30, 30, 36, 255)); d = ImageDraw.Draw(sheet)
        for k, (i, slug, _) in enumerate(V):
            f = os.path.join(OUTDIR, f"potion_{i:02d}_{slug}_icon.png")
            if not os.path.exists(f): continue
            x, y = (k % 5)*160, (k // 5)*180
            for yy in range(0, 150, 10):
                for xx in range(0, 150, 10):
                    d.rectangle([x+5+xx, y+2+yy, x+14+xx, y+11+yy], fill=c2 if (xx//10 + yy//10) % 2 else c1)
            sheet.alpha_composite(Image.open(f).resize((150, 150)), (x+5, y+2))
            d.text((x+6, y+156), f"{i} {slug}", fill=(230, 230, 235, 255))
        sheet.save(os.path.join(runner.PREVIEW, fname))

if __name__ == "__main__":
    runner.main("build_potion.py", V, "Potions", "potion")
    contact_sheets()
