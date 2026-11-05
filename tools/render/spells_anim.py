"""Flying spell effects animated -> Media/Spells: FRAMES renders each through one seamless loop (see build_spell.py),
stitched into a flipbook spell_<id>_<slug>_anim.png (COLS x ROWS frames of 128px, left to right, top to bottom).
Ids are the game's spell ids (SP_MAGIC_MISSILE, SP_FIREBALL).
Usage: [JOBS=4] python3 spells_anim.py [slug ...]   (no args = all)
"""
import os, sys
from PIL import Image
import runner

FRAMES, COLS = 32, 8
# one fixed crop (frame, px of the 512 render) for all, so they keep their sizes: the missile small, the fireball big
FRAME = 150
S = [
    (2, "magic_missile", dict(kind="missile", halo=0.5, halo_color=(0.3, 0.6, 1.0))),
    (15, "fireball", dict(kind="fireball", halo=0.45, halo_color=(1.0, 0.4, 0.05))),
]
want = set(sys.argv[1:])
S = [v for v in S if not want or v[1] in want]
V = [(i, f"{slug}_f{k:02d}", dict(p, t=k/FRAMES, frame=FRAME)) for i, slug, p in S for k in range(FRAMES)]

if __name__ == "__main__":
    tmp = os.path.join(runner.PREVIEW, "spells_anim")
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
