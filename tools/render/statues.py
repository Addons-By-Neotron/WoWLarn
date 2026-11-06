"""The great marble statue -> Media/Objects as 256px icons.  Id is the game's OSTATUE (8).
Usage: [JOBS=4] python3 statues.py
<slug> is the 20 degree view for the 2D map; <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
The model is Poly Haven's Gothic Statue (CC0, see build_statue.py and CREDITS.md).
"""
import runner

S = [(8, "statue", dict(shadow_cut=24))]
# one fixed crop for the angled views (frame, px of the 512 render), bottom-aligned, so the statue keeps its size
# between angles; it fits the widest view (BBOX=1 python3 statues.py reports each view's reach from the centre)
FRAME = 400
S = S + [(i, f"{slug}_{e}", dict(p, elev=e, frame=FRAME, align="bottom")) for i, slug, p in S for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_statue.py", S, "Objects", "object", size=256)   # world object: 256
