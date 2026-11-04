"""Ring variants -> Media/Rings as 128px icons.
Usage: [JOBS=4] python3 rings.py [slug ...]   (no args = all)
Keys (see build_ring.py): style (plain|twisted|vine|shield|zigzag|stacked|studded|waves|spiked),
      metal (linear RGB), metal_rough, accent (enamel/inlay colour), accent_glow, tilt, roll,
      halo (0..1 post glow, halo_color)
"""
import runner

GOLD, SILVER, ROSE = (1.0, 0.72, 0.3), (0.9, 0.91, 0.93), (0.95, 0.6, 0.48)
BRONZE, STEEL, DARK, PLAT = (0.7, 0.42, 0.18), (0.6, 0.63, 0.68), (0.22, 0.22, 0.25), (0.8, 0.82, 0.86)

R = [
    (0, "generic",            dict(style="plain", metal=GOLD)),
    (1, "extra_regeneration", dict(style="twisted", metal=GOLD, accent=(0.05, 0.7, 0.2), accent_glow=0.6,
                                   halo=0.35, halo_color=(0.2, 0.9, 0.35))),
    (2, "regeneration",       dict(style="vine", metal=GOLD, accent=(0.05, 0.5, 0.12))),
    (3, "protection",         dict(style="shield", metal=SILVER, accent=(0.05, 0.2, 0.7))),
    (4, "energy",             dict(style="zigzag", metal=STEEL, accent=(0.1, 0.8, 1.0), accent_glow=4.0,
                                   halo=0.45, halo_color=(0.2, 0.8, 1.0))),
    (5, "dexterity",          dict(style="stacked", metal=ROSE)),
    (6, "strength",           dict(style="studded", metal=BRONZE, metal_rough=0.3)),
    (7, "cleverness",         dict(style="waves", metal=PLAT, accent=(0.4, 0.08, 0.75), accent_glow=0.5)),
    (8, "increase_damage",    dict(style="spiked", metal=DARK, metal_rough=0.25, accent=(0.8, 0.02, 0.02),
                                   accent_glow=1.5, halo=0.3, halo_color=(0.9, 0.05, 0.05))),
]

if __name__ == "__main__":
    runner.main("build_ring.py", R, "Rings", "ring")
