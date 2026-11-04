"""Scroll variants -> Media/Scrolls as 128px icons.
Usage: [JOBS=4] python3 scrolls.py [slug ...]   (no args = all)
kind: "rolled" (default, build_scroll.py: paper/ribbon/seal, length, turns, tilt, yaw, ribbon_y, pinch, seed)
      "open" (build_open_scroll.py: paper, ink_color, width, height, roll_r, turns, yaw, seed; glyph_seed)
"""
import os
import runner, glyphs

S = [
    (0, "generic", {}),
    (1, "open", dict(kind="open", glyph_seed=1)),
]

def prepare(name, i, p, script):
    if p.pop("kind", "rolled") == "open":   # flat sheet with rune text: generate its ink texture first
        ink = os.path.join(runner.PREVIEW, name + "_glyphs.png")      # kept: the saved .blend references it
        glyphs.make(ink, seed=p.pop("glyph_seed", i))
        p["ink"] = ink; script = "build_open_scroll.py"
    return script, p

if __name__ == "__main__":
    runner.main("build_scroll.py", S, "Scrolls", "scroll", prepare)
