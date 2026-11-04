"""Gem variants (ids match the game's object ids) -> Media/Gems as 128px icons.
Usage: [JOBS=4] python3 gems.py [slug ...]   (no args = all)
Keys (see build_gem.py): cut (brilliant|heart|emerald|trillion), color (linear RGB), ior, glow, glow_strength,
      fire (coloured sparkle lights), tilt, yaw, roll, halo (0..1 post glow, halo_color)
"""
import runner

G = [
    (50, "diamond",  dict(cut="brilliant", color=(0.85, 0.93, 1.0), ior=1.9, halo=0.3, halo_color=(0.75, 0.88, 1.0))),   # lower IOR than real: less internal chaos at icon size
    (51, "ruby",     dict(cut="heart", color=(0.75, 0.0, 0.03), ior=1.77, glow=(0.6, 0.0, 0.02), glow_strength=0.15,
                          halo=0.3, halo_color=(0.9, 0.05, 0.1))),
    (52, "emerald",  dict(cut="emerald", color=(0.02, 0.6, 0.15), ior=1.58, glow=(0.0, 0.4, 0.1), glow_strength=0.12,
                          yaw=30, halo=0.3, halo_color=(0.1, 0.85, 0.3))),
    (53, "sapphire", dict(cut="trillion", color=(0.03, 0.12, 0.85), ior=1.77, glow=(0.02, 0.08, 0.6), glow_strength=0.15,
                          yaw=0, halo=0.3, halo_color=(0.15, 0.3, 1.0))),
]

if __name__ == "__main__":
    runner.main("build_gem.py", G, "Gems", "gem", pad=120)   # room for the glow (edges also fade out)
