"""The holy altar -> Media/Objects as 256px icons.  Id is the game's OALTAR (1).
Usage: [JOBS=4] python3 altars.py
<slug> is the 20 degree view for the 2D map; <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
The model is Avramania's Low Poly Medieval Altar (CC0, see build_altar.py and CREDITS.md).
"""
import runner

A = [(1, "altar", dict(shadow_cut=24))]
# one fixed crop for the angled views (frame, px of the 512 render), bottom-aligned, so the altar keeps its size
# between angles; it fits the widest view (BBOX=1 python3 altars.py reports each view's reach from the centre)
FRAME = 400
A = A + [(i, f"{slug}_{e}", dict(p, elev=e, frame=FRAME, align="bottom")) for i, slug, p in A for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_altar.py", A, "Objects", "object", size=256)   # world object: 256
