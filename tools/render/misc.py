"""One-off items -> Media/Misc as 128px icons.
Usage: [JOBS=4] python3 misc.py [slug ...]   (no args = all)
"""
import os
import glyphs, runner

M = [
    (0, "spell_tome", dict(script="build_tome.py", sigil_seed=3, border=True)),
]
# thrones: see thrones.py (Media/Throne)

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
