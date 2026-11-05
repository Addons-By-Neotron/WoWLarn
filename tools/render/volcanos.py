"""Volcanic shafts -> Media/Volcano as 256px icons (world objects).  Ids are the game's OVOLDOWN / OVOLUP.
They are the volcano level's stairs: natural basalt with a rough rock walkway (see build_volcano.py).
Usage: [JOBS=4] python3 volcanos.py [slug ...]   (no args = all)
<slug> is the 35 degree view (the 2D map, a little isometric); <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
"""
import runner

V = [
    (55, "volcano_down", dict(down=True, cracks=4)),        # "a Volcanic Shaft Leaning Downward"
    (56, "volcano_up", dict()),                   # "the Base of a Volcanic Shaft"
]
# one fixed crop for all views (frame, px of the 512 render), bottom-aligned so the shaft sits on the icon's
# bottom edge; FRAME fits the widest view (BBOX=1 python3 volcanos.py ... reports each view's reach from the centre)
FRAME = 340
# boosted (contrast, saturation, gamma): dark basalt and red lava read washed out in the game otherwise
VIEW = dict(shadow_cut=24, frame=FRAME, align="bottom", boost=(1.35, 1.25, 1.15))
OUTSIDE = {"volcano_down"}                         # in the open world, which has no 3D view: no angle views
V = [(i, slug, dict(p, elev=35, **VIEW)) for i, slug, p in V] + \
    [(i, f"{slug}_{e}", dict(p, elev=e, **VIEW)) for i, slug, p in V if slug not in OUTSIDE for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_volcano.py", V, "Volcano", "volcano", size=256)   # world object: 256
