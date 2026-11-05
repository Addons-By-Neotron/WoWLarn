"""Floor traps -> Media/Traps as 256px icons (world objects).  Ids are the game's OPIT / OTRAPDOOR.
Usage: [JOBS=4] python3 traps.py [slug ...]   (no args = all)
<slug> is the 35 degree view (the 2D map, a little isometric); <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
"""
import runner

T = [
    (4, "pit", dict(kind="pit")),
    (75, "trapdoor", dict(kind="trapdoor")),
]
# one fixed crop for all views (frame, px of the 512 render), bottom-aligned so the trap lies on the icon's
# bottom edge; FRAME fits the widest view (BBOX=1 python3 traps.py ... reports each view's reach from the centre)
FRAME = 320
VIEW = dict(shadow_cut=24, frame=FRAME, align="bottom")
T = [(i, slug, dict(p, elev=35, **VIEW)) for i, slug, p in T] + \
    [(i, f"{slug}_{e}", dict(p, elev=e, **VIEW)) for i, slug, p in T for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_pit.py", T, "Traps", "trap", size=256)   # world object: 256
