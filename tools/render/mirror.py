"""Standing mirror -> Media/Mirror as 256px icons (world object).  Id is the game's OMIRROR.
Usage: [JOBS=4] python3 mirror.py [slug ...]   (no args = all)
<slug> is the 20 degree view (like the thrones); <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
Facing the camera square on.
"""
import runner

M = [
    (11, "mirror", dict(yaw=0, shadow_cut=24)),
]
# one fixed crop for all views (frame, px of the 512 render), bottom-aligned so the mirror stands on the icon's
# bottom edge; FRAME fits the widest view (BBOX=1 python3 mirror.py ... reports each view's reach from the centre)
FRAME = 240
VIEW = dict(frame=FRAME, align="bottom")
M = [(i, slug, dict(p, elev=20, **VIEW)) for i, slug, p in M] + \
    [(i, f"{slug}_{e}", dict(p, elev=e, **VIEW)) for i, slug, p in M for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_mirror.py", M, "Mirror", "mirror", size=256)   # world object: 256
