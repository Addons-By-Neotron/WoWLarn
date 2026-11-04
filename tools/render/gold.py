"""Gold piles -> Media/Gold as 256px icons.  Ids are the game's four gold objects by size tier.
Usage: [JOBS=4] python3 gold.py [slug ...]   (no args = all)
<slug> is the top-down view; <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
"""
import runner

G = [
    (18, "small",  dict(radius=0.7, height=0.18, lumps=2, density=2.6, spill=0.25, seed=1)),
    (72, "medium", dict(radius=0.85, height=0.32, lumps=3, density=3.0, spill=0.15, seed=2)),
    (70, "large",  dict(radius=1.0, height=0.5, lumps=4, density=3.4, spill=0.12, seed=3)),
    (71, "huge",   dict(radius=1.15, height=0.7, lumps=5, density=3.8, spill=0.1, seed=4)),
]
FRAME = 480
# every pile and view is framed alike (camera sized for the huge pile, one fixed crop), so coins stay the same
# size and bigger piles look bigger, sitting on the icon's bottom edge; FRAME fits the widest view (BBOX=1 python3 gold.py ... reports the reach)
VIEW = dict(view_radius=1.15, shadow_cut=24, frame=FRAME, align="bottom")
G = [(i, slug, dict(p, elev=90, **VIEW)) for i, slug, p in G] + \
    [(i, f"{slug}_{e}", dict(p, elev=e, **VIEW)) for i, slug, p in G for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_gold.py", G, "Gold", "gold", size=256)   # world object: 256
