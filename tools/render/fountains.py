"""Fountains -> Media/Fountain as 256px icons (world objects).  Ids are the game's OFOUNTAIN / ODEADFOUNTAIN.
Usage: [JOBS=4] python3 fountains.py [slug ...]   (no args = all)
<slug> is the top-down view; <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
"""
import runner

F = [
    (7, "fountain", dict()),
    (17, "dead_fountain", dict(dry=True)),
]
# one fixed crop for all views (frame, px of the 512 render), bottom-aligned so the fountain stands on the icon's
# bottom edge; FRAME fits the widest view (BBOX=1 python3 fountains.py ... reports each view's reach from the centre)
FRAME = 220
VIEW = dict(shadow_cut=24, frame=FRAME, align="bottom")
F = [(i, slug, dict(p, elev=90, **VIEW)) for i, slug, p in F] + \
    [(i, f"{slug}_{e}", dict(p, elev=e, **VIEW)) for i, slug, p in F for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_fountain.py", F, "Fountain", "fountain", size=256)   # world object: 256
