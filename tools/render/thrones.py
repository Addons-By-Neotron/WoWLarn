"""Thrones -> Media/Throne as 256px icons (file names keep the misc_ prefix).
Usage: [JOBS=4] python3 thrones.py [slug ...]   (no args = all)
"""
import runner

T = [
    (2, "throne", dict(shadow_cut=24)),                        # also id 81 (same throne, king already summoned)
    (79, "massive_throne", dict(jewels=False, shadow_cut=24)), # jewels pried off
]
# the game camera looks down at 30-80 degrees: views every 5 degrees, named <slug>_<angle>.
# One fixed crop for all of them (frame, px of the 512 render) so the throne keeps its size between angles;
# 410 fits the widest view (BBOX=1 python3 thrones.py ... reports each view's reach from the centre).
T += [(i, f"{slug}_{e}", dict(p, elev=e, frame=410)) for i, slug, p in T for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_throne.py", T, "Throne", "misc", size=256)   # world object: 256
