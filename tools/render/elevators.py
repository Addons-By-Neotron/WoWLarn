"""Express elevators -> Media/Elevator as 256px icons (world objects).  Ids are the game's OELEVATORUP / OELEVATORDOWN.
Usage: [JOBS=4] python3 elevators.py [slug ...]   (no args = all)
<slug> is the top-down view; <slug>_<angle> the views for the game camera's 30-80 degrees, every 5.
"""
import runner

E = [
    (6, "elevator_up", dict()),
    (14, "elevator_down", dict(down=True)),
]
# one fixed crop for all views (frame, px of the 512 render), bottom-aligned so the platform lies on the icon's
# bottom edge; FRAME fits the down lift's gantry (BBOX=1 python3 elevators.py ... reports each view's reach from the
# centre); the up lift's chain runs off the top, faded out by then
FRAME = 360
VIEW = dict(shadow_cut=24, frame=FRAME, align="bottom")
E = [(i, slug, dict(p, elev=90, **VIEW)) for i, slug, p in E] + \
    [(i, f"{slug}_{e}", dict(p, elev=e, **VIEW)) for i, slug, p in E for e in range(30, 81, 5)]

if __name__ == "__main__":
    runner.main("build_elevator.py", E, "Elevator", "elevator", size=256)   # world object: 256
