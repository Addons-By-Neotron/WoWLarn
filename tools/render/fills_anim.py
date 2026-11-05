"""Spells that fill a tile (wall of fire, flood, and the cone of cold on each tile it reaches) animated -> Media/Spells:
FRAMES renders through the whole effect (see build_spell.py: rising from the bottom, then dying down and fading out;
it plays once, it does not loop),
stitched into a flipbook spell_<id>_<slug>_anim.png (COLS x ROWS frames of 128px, left to right, top to bottom).
Drawn facing the camera, a billboard like the potions, but each in 3D on the tile, seen from 15 degrees.  Ids are
the game's spell ids (SP_MAGIC_FIRE, SP_FLOOD, SP_COLD).
Usage: [JOBS=4] python3 fills_anim.py [slug ...]   (no args = all)
"""
import os, sys
from PIL import Image
import runner

FRAMES, COLS = 32, 8
FRAME = 192                                         # one fixed crop (px of the 512 render): the tile with a margin
S = [
    (32, "wall_of_fire", dict(kind="firewall", solid=True, elev=15, halo=0.3, halo_color=(1.0, 0.4, 0.05))),
    (26, "flood", dict(kind="flood", solid=True, elev=15)),
    (16, "cone_of_cold", dict(kind="frost", elev=15, halo=0.3, halo_color=(0.4, 0.7, 1.0))),   # on each tile it reaches
]
want = set(sys.argv[1:])
S = [v for v in S if not want or v[1] in want]
# t at the middle of each frame's slice: the first is just starting, the last nearly gone
V = [(i, f"{slug}_f{k:02d}", dict(p, t=(k + 0.5)/FRAMES, frame=FRAME)) for i, slug, p in S for k in range(FRAMES)]

if __name__ == "__main__":
    tmp = os.path.join(runner.PREVIEW, "fills_anim")
    sys.argv[1:] = []                                   # the slugs were for this script, not runner's filter
    runner.main("build_spell.py", V, tmp, "spell")
    for i, slug, _ in S:
        frames = [Image.open(os.path.join(tmp, f"spell_{i:02d}_{slug}_f{k:02d}_icon.png")) for k in range(FRAMES)]
        w, h = frames[0].size; rows = (FRAMES + COLS - 1)//COLS
        sheet = Image.new("RGBA", (COLS*w, rows*h))
        for k, f in enumerate(frames):
            sheet.paste(f, ((k % COLS)*w, (k//COLS)*h))
        out = os.path.join(runner.REPO, "Media", "Spells", f"spell_{i:02d}_{slug}_anim.png")
        os.makedirs(os.path.dirname(out), exist_ok=True); sheet.save(out); print("wrote", out)
