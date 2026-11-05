"""World objects you can pick up or use where they stand -> Media/Objects as 256px icons.  Ids are the game's
OCHEST (44) and OBRASSLAMP (85).  Usage: [JOBS=4] python3 objects.py [slug ...]   (no args = all)
<slug> is the 20 degree view for the 2D map; <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
"""
import runner

O = [
    (44, "chest", dict(kind="chest", frame=330)),
    (85, "brass_lamp", dict(kind="lamp", frame=370)),
]
# standing on the floor with a ground shadow; one fixed crop for the angled views (frame, px of the 512 render),
# bottom-aligned; frame fits each object's widest view (BBOX=1 python3 objects.py ... reports each view's reach
# from the centre)
O = [(i, slug, dict({k: v for k, v in p.items() if k != "frame"}, ground=True, shadow_cut=24)) for i, slug, p in O] + \
    [(i, f"{slug}_{e}", dict(p, ground=True, elev=e, shadow_cut=24, align="bottom")) for i, slug, p in O for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_item.py", O, "Objects", "object", size=256)   # world object: 256
