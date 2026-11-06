"""Spells that fill a tile (wall of fire, flood, cloud kill, the cone of cold on each tile it reaches), that hit or
act on one monster (the summoned demon's claws, phantasmal forces, dehydration, drain life, finger of death, sleep,
web, polymorph, teleport away), and that the caster casts on themself (the rest) animated -> Media/Spells:
FRAMES renders through the whole effect (see build_spell.py: rising from the bottom, then dying down and fading out;
it plays once, it does not loop),
stitched into a flipbook spell_<id>_<slug>_anim.png (COLS x ROWS frames of 128px, left to right, top to bottom).
Drawn facing the camera, a billboard like the potions, but each in 3D on the tile, seen from 15 degrees.  Ids are
the game's spell ids (K.SP_*).
Usage: [JOBS=4] python3 fills_anim.py [slug ...]   (no args = all)
"""
import os, sys
from PIL import Image
import runner

FRAMES, COLS = 32, 8
FRAME = 192                                         # one fixed crop (px of the 512 render): the tile with a margin
S = [
    (32, "wall_of_fire", dict(kind="firewall", solid=True, elev=15, halo=0.3, halo_color=(1.0, 0.4, 0.05))),
    (26, "flood", dict(kind="flood", solid=True, elev=15)),
    (16, "cone_of_cold", dict(kind="frost", elev=15, halo=0.3, halo_color=(0.4, 0.7, 1.0))),   # on each tile it reaches
    (20, "cloud_kill", dict(kind="gas", elev=15)),                  # on each tile round the caster
    (36, "summon_demon", dict(kind="claw", elev=15, halo=0.5, halo_color=(1.0, 0.1, 0.02))),   # the demon's strike
    # the spells that hit one monster: each on its tile
    (13, "phantasmal_forces", dict(kind="phantasm", elev=15, halo=0.3, halo_color=(0.6, 0.4, 1.0))),
    (22, "dehydration", dict(kind="dehydrate", elev=15)),
    (24, "drain_life", dict(kind="drain", elev=15, halo=0.4, halo_color=(1.0, 0.1, 0.1))),
    (27, "finger_of_death", dict(kind="death", elev=15, halo=0.35, halo_color=(0.4, 1.0, 0.2))),
    # the ones that act on a monster without hurting it, on its tile
    (4, "sleep", dict(kind="sleep", elev=15)),
    (7, "web", dict(kind="web", elev=15)),
    (17, "polymorph", dict(kind="polymorph", elev=15)),
    (31, "teleport_away", dict(kind="teleport", elev=15, halo=0.3, halo_color=(0.4, 0.5, 1.0))),
    # and the ones the caster casts on themself, on the caster's tile
    (1, "protection", dict(kind="protection", elev=15)),
    (3, "dexterity", dict(kind="dexterity", elev=15)),
    (5, "charm_monster", dict(kind="charm", elev=15)),
    (8, "strength", dict(kind="strength", elev=15, halo=0.3, halo_color=(1.0, 0.4, 0.1))),
    (10, "healing", dict(kind="heal", elev=15, halo=0.3, halo_color=(1.0, 0.85, 0.4))),
    (11, "cure_blindness", dict(kind="sight", elev=15, halo=0.35, halo_color=(1.0, 0.95, 0.8))),
    (14, "invisibility", dict(kind="invisible", elev=15)),
    (19, "haste_self", dict(kind="haste", elev=15)),
    (25, "invulnerability", dict(kind="globe", elev=15, halo=0.3, halo_color=(1.0, 0.8, 0.4))),
    (28, "scare_monster", dict(kind="scare", elev=15)),
    (29, "hold_monster", dict(kind="hold", elev=15, halo=0.3, halo_color=(0.7, 0.4, 1.0))),
    (30, "time_stop", dict(kind="timestop", elev=15, halo=0.3, halo_color=(0.3, 0.9, 1.0))),
    (37, "walk_through_walls", dict(kind="wtw", elev=15)),
]
want = set(sys.argv[1:])
S = [v for v in S if not want or v[1] in want]
# t at the middle of each frame's slice: the first is just starting, the last nearly gone
V = [(i, f"{slug}_f{k:02d}", dict(p, t=(k + 0.5)/FRAMES, frame=FRAME)) for i, slug, p in S for k in range(FRAMES)]

if __name__ == "__main__":
    tmp = os.path.join(runner.PREVIEW, "fills_anim")
    sys.argv[1:] = []                                   # the slugs were for this script, not runner's filter
    runner.main("build_spell.py", V, tmp, "spell")
    for i, slug, _ in S:
        frames = [Image.open(os.path.join(tmp, f"spell_{i:02d}_{slug}_f{k:02d}_icon.png")) for k in range(FRAMES)]
        w, h = frames[0].size; rows = (FRAMES + COLS - 1)//COLS
        sheet = Image.new("RGBA", (COLS*w, rows*h))
        for k, f in enumerate(frames):
            sheet.paste(f, ((k % COLS)*w, (k//COLS)*h))
        out = os.path.join(runner.REPO, "Media", "Spells", f"spell_{i:02d}_{slug}_anim.png")
        os.makedirs(os.path.dirname(out), exist_ok=True); sheet.save(out); print("wrote", out)
