"""One-off items -> Media/Misc as 128px icons.
Usage: [JOBS=4] python3 misc.py [slug ...]   (no args = all)
"""
import os
import glyphs, runner

M = [
    (0, "spell_tome", dict(script="build_tome.py", sigil_seed=3, border=True)),
]
# carried trinkets (build_item.py); ids are the game's object ids
I = [
    (3, "orb_of_enlightenment", dict(kind="enlightenment", halo=0.4, halo_color=(1.0, 0.9, 0.6))),
    (45, "amulet", dict(kind="amulet", halo=0.25, halo_color=(0.2, 0.4, 1.0))),
    (46, "orb_of_dragon_slaying", dict(kind="dragon_orb", halo=0.4, halo_color=(1.0, 0.35, 0.05))),
    (47, "spirit_scarab", dict(kind="scarab", halo=0.25, halo_color=(0.2, 0.9, 1.0))),
    (48, "cube_of_undead_control", dict(kind="cube", halo=0.35, halo_color=(0.2, 1.0, 0.4))),
    (49, "device_of_theft_prevention", dict(kind="lock", halo=0.25, halo_color=(0.2, 0.5, 1.0))),
    (83, "fortune_cookie", dict(kind="cookie")),
    (86, "hand_of_fear", dict(kind="hand", halo=0.3, halo_color=(0.5, 0.1, 0.8))),
    (87, "sphere_talisman", dict(kind="talisman", halo=0.35, halo_color=(0.55, 0.2, 1.0))),
    (88, "wand_of_wonder", dict(kind="wand", halo=0.35, halo_color=(1.0, 0.85, 1.0))),
    # Grizzik's elixirs (sold in his den in the dungeon)
    (93, "goblin_rocket_fuel", dict(kind="rocket_fuel", halo=0.25, halo_color=(1.0, 0.45, 0.1))),
    (94, "gnomish_mind_expander", dict(kind="mind_expander", halo=0.35, halo_color=(0.7, 0.3, 1.0))),
    (95, "volatile_swamp_brew", dict(kind="swamp_brew", halo=0.25, halo_color=(0.4, 1.0, 0.15))),
    (96, "glowcap_stew", dict(kind="glowcap_stew", halo=0.3, halo_color=(0.2, 0.6, 1.0))),
    (97, "overcharged_fel_tonic", dict(kind="fel_tonic", halo=0.4, halo_color=(0.45, 1.0, 0.1))),
    (40, "belt", dict(kind="belt", halo=0.2, halo_color=(1.0, 0.25, 0.15))),   # Belt of Striking
]
M += [(i, slug, dict(p, script="build_item.py")) for i, slug, p in I]
M += [(68, "shield", dict(script="build_shield.py"))]   # the model is Artem Mykhailov's Medieval Shield (see CREDITS.md)
# thrones: see thrones.py (Media/Throne); the chest and the brass lamp: objects.py (Media/Objects)

def prepare(name, i, p, script):
    script = p.pop("script", script)
    if "sigil_seed" in p:                              # textures are kept: the .blend references it
        path = os.path.join(runner.PREVIEW, name + "_sigil.png")
        glyphs.sigil(path, seed=p.pop("sigil_seed")); p["sigil"] = path
    if p.pop("border", False):
        path = os.path.join(runner.PREVIEW, name + "_border.png")
        glyphs.border(path); p["border"] = path
    return script, p

if __name__ == "__main__":
    runner.main("build_tome.py", M, "Misc", "misc", prepare)
