"""Volcanic shafts -> Media/Volcano as 256px icons (world objects).  Ids are the game's OVOLDOWN / OVOLUP.
They are the volcano level's stairs: natural basalt with a rough rock walkway (see build_volcano.py).
Usage: [JOBS=4] python3 volcanos.py [slug ...]   (no args = all)
<slug> is the top-down view; <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
"""
import runner

V = [
    (55, "volcano_down", dict(down=True)),        # "a Volcanic Shaft Leaning Downward"
    (56, "volcano_up", dict()),                   # "the Base of a Volcanic Shaft"
]
# one fixed crop for all views (frame, px of the 512 render), bottom-aligned so the shaft sits on the icon's
# bottom edge; FRAME fits the widest view (BBOX=1 python3 volcanos.py ... reports each view's reach from the centre)
FRAME = 340
VIEW = dict(shadow_cut=24, frame=FRAME, align="bottom")
V = [(i, slug, dict(p, elev=90, **VIEW)) for i, slug, p in V] + \
    [(i, f"{slug}_{e}", dict(p, elev=e, **VIEW)) for i, slug, p in V for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_volcano.py", V, "Volcano", "volcano", size=256)   # world object: 256
