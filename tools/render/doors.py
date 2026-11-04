"""Massive double doors -> Media/Doors as 256px icons (world objects), head on.  Ids are the game's
OCLOSEDDOOR (20) and OOPENDOOR (19), in three styles: wood, stone, iron.
Usage: [JOBS=4] python3 doors.py [slug ...]   (no args = all)
"""
import runner

D = []
for style in ("wood", "stone", "iron"):
    D += [(20, style, dict(style=style)), (19, f"{style}_open", dict(style=style, open=True))]
# set into a wall: head on, cropped exactly to the (square) stone frame so it fills the icon edge to edge;
# boosted (contrast, saturation, gamma): the flat head-on light looks washed out in the game
# <slug>_leaves: only the leaves, cropped to the opening (stretched to the square), for the 3D view, which
# draws the frame as geometry
B = (1.5, 1.3, 1.1)
D = [(i, slug, dict(p, fill=True, boost=B)) for i, slug, p in D] + \
    [(i, f"{slug}_leaves", dict(p, leaves=True, fill="box", boost=B)) for i, slug, p in D]

if __name__ == "__main__":
    runner.main("build_door.py", D, "Doors", "door", size=256)   # world object: 256
