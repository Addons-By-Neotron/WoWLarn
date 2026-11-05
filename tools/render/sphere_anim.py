"""The Sphere of Annihilation animated: FRAMES renders with its disc turned through one full turn (a seamless loop,
the spiral arms winding inwards), stitched into a flipbook (Media/Misc/misc_80_sphere_of_annihilation_anim.png,
COLS x ROWS frames of 128px, left to right, top to bottom).
Usage: [JOBS=4] python3 sphere_anim.py
"""
import os
from PIL import Image
import runner

FRAMES, COLS = 64, 8
# not an item (it can't be picked up), so no still icon: only the flipbook.  frame: a fixed crop, so the sphere sits
# smaller in the picture than the pickups do
i, slug = 80, "sphere_of_annihilation"                 # the game's OANNIHILATION
p = dict(kind="annihilation", halo=0.35, halo_color=(0.55, 0.1, 1.0), frame=380)
V = [(i, f"{slug}_f{k:02d}", dict(p, spin=360*k/FRAMES)) for k in range(FRAMES)]

if __name__ == "__main__":
    tmp = os.path.join(runner.PREVIEW, "sphere_anim")
    runner.main("build_item.py", V, tmp, "misc")
    frames = [Image.open(os.path.join(tmp, f"misc_{i:02d}_{slug}_f{k:02d}_icon.png")) for k in range(FRAMES)]
    w, h = frames[0].size; rows = (FRAMES + COLS - 1)//COLS
    sheet = Image.new("RGBA", (COLS*w, rows*h))
    for k, f in enumerate(frames):
        sheet.paste(f, ((k % COLS)*w, (k//COLS)*h))
    out = os.path.join(runner.REPO, "Media", "Misc", f"misc_{i:02d}_{slug}_anim.png")
    sheet.save(out); print("wrote", out)
