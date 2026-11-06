"""Town buildings (and the dungeon's bank branch) -> Media/Buildings as 256px icons (world objects).  Ids are the
game's object ids (OENTRANCE, OHOME, OBANK, OBANK2, ODNDSTORE, OSCHOOL, OTRADEPOST, OLRS, OPAD).
Usage: [JOBS=4] python3 buildings.py [slug ...]   (no args = all)
<slug> is the 35 degree view (the 2D map); <slug>_<angle> (bank2 and pad only, the rest are in the town) the views for the game camera's 30-80 degrees, every 5.
"""
import runner

B = [
    (54, "entrance", dict(kind="entrance")),
    (69, "home", dict(kind="home")),
    (16, "bank", dict(kind="bank")),
    (15, "bank2", dict(kind="bank2")),
    (12, "thrift_shoppe", dict(kind="dndstore")),
    (10, "school", dict(kind="school")),
    (77, "trading_post", dict(kind="tradepost")),
    (82, "lrs", dict(kind="lrs")),
    (98, "pad", dict(kind="pad")),                       # Grizzik's Questionable Elixirs, in the dungeon
]
# one fixed crop per building for all its views (frame, px of the 512 render), bottom-aligned; each frame fits its
# widest view (BBOX=1 python3 buildings.py ... reports each view's reach from the centre)
FRAME = {"bank2": 200, "pad": 210}
INSIDE = {"bank2", "pad"}                                 # the rest are in the town, which has no 3D view: no angle views
B = [(i, slug, dict(p, elev=35, shadow_cut=24, frame=FRAME.get(slug, 250), align="bottom")) for i, slug, p in B] + \
    [(i, f"{slug}_{e}", dict(p, elev=e, shadow_cut=24, frame=FRAME.get(slug, 250), align="bottom")) for i, slug, p in B if slug in INSIDE for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_building.py", B, "Buildings", "building", size=256)
