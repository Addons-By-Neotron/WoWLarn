"""Floor traps -> Media/Traps as 256px icons (world objects).  Ids are the game's OPIT / OTRAPDOOR / OTELEPORTER / OTRAPARROW / ODARTRAP.
Usage: [JOBS=4] python3 traps.py [slug ...]   (no args = all)
<slug> is the 35 degree view (the 2D map, a little isometric); <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
trapdoor_top, arrow_top, dart_top: straight down, laid flat on the floor of the 3D view.
"""
import runner

T = [
    (4, "pit", dict(kind="pit")),
    (75, "trapdoor", dict(kind="trapdoor")),
    (9, "teleport", dict(kind="teleport")),             # also the hidden one (78), once it shows
    (66, "arrow", dict(kind="arrow")),                   # also the hidden one (67)
    (74, "dart", dict(kind="dart")),                     # also the hidden one (73)
]
# one fixed crop for all views (frame, px of the 512 render), bottom-aligned so the trap lies on the icon's
# bottom edge; FRAME fits the widest view (BBOX=1 python3 traps.py ... reports each view's reach from the centre)
FRAME = 320
VIEW = dict(shadow_cut=24, frame=FRAME, align="bottom")
T = [(i, slug, dict(p, elev=35, **VIEW)) for i, slug, p in T] + \
    [(i, f"{slug}_{e}", dict(p, elev=e, **VIEW)) for i, slug, p in T for e in range(30, 81, 5)] + \
    [(75, "trapdoor_top", dict(kind="trapdoor", elev=90, **VIEW)),   # straight down: laid on the 3D floor (V.FLAT)
     (66, "arrow_top", dict(kind="arrow", elev=90, **VIEW)), (74, "dart_top", dict(kind="dart", elev=90, **VIEW))]

if __name__ == "__main__":
    runner.main("build_pit.py", T, "Traps", "trap", size=256)   # world object: 256
