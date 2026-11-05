"""Stairs -> Media/Stairs as 256px icons (world objects).  Ids are the game's OSTAIRSUP / OSTAIRSDOWN.
Usage: [JOBS=4] python3 stairs.py [slug ...]   (no args = all)
<slug> is the 35 degree view (the 2D map, a little isometric); <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
"""
import runner

S = [
    (5, "stairs_up", dict(turns=0.8, steps=13)),        # 80% of a turn, same step width as the down stair
    (13, "stairs_down", dict(down=True)),
]
# one fixed crop for all views (frame, px of the 512 render), bottom-aligned so the stair stands on the icon's
# bottom edge; FRAME fits the widest view (BBOX=1 python3 stairs.py ... reports each view's reach from the centre)
FRAME = 320
VIEW = dict(shadow_cut=24, frame=FRAME, align="bottom")
S = [(i, slug, dict(p, elev=35, **VIEW)) for i, slug, p in S] + \
    [(i, f"{slug}_{e}", dict(p, elev=e, **VIEW)) for i, slug, p in S for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_stairs.py", S, "Stairs", "stairs", size=256)   # world object: 256
