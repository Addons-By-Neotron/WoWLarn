"""Scroll variants. Renders each via Blender into Media/Scrolls as 256px icons.
Usage: [JOBS=4] python3 scrolls.py [slug ...]   (no args = all)
kind: "rolled" (default, build_scroll.py: paper/ribbon/seal, length, turns, tilt, yaw, ribbon_y, pinch, seed)
      "open" (build_open_scroll.py: paper, ink_color, width, height, roll_r, turns, yaw, seed; glyph_seed)
"""
import json, os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from PIL import Image
from variants import BLENDER, icon
import glyphs

S = [
    (0, "generic", {}),
    (1, "open", dict(kind="open", glyph_seed=1)),
]

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
OUTDIR = os.path.join(REPO, "Media", "Scrolls")            # <name>_icon.png, 256px, cropped to the scroll
PREVIEW = os.path.join(HERE, "preview")

def render(i, slug, p):
    name = f"scroll_{i:02d}_{slug}"
    out = os.path.join(PREVIEW, f"_scroll_{i:02d}.png")
    p = dict(p, save_blend=os.path.join(PREVIEW, name + ".blend"))
    script = "build_scroll.py"
    if p.pop("kind", "rolled") == "open":   # flat sheet with rune text: generate its ink texture first
        ink = os.path.join(PREVIEW, name + "_glyphs.png")      # kept: the saved .blend references it
        glyphs.make(ink, seed=p.pop("glyph_seed", i))
        p["ink"] = ink; script = "build_open_scroll.py"
    cmd = [BLENDER, "-b", "-P", os.path.join(HERE, script), "--", out, json.dumps(p)]
    for attempt in range(4):                # parallel jobs can briefly run the GPU out of memory; wait + retry
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode == 0 and os.path.exists(out): break
        time.sleep(2 + 3*attempt)
    else:
        raise RuntimeError(f"{name} failed:\n" + "\n".join((r.stdout + r.stderr).splitlines()[-15:]))
    icon(out, os.path.join(OUTDIR, name + "_icon.png"), Image.open(out).getchannel("A").getbbox())
    os.remove(out)
    return name

if __name__ == "__main__":
    for d in (OUTDIR, PREVIEW): os.makedirs(d, exist_ok=True)
    want = set(sys.argv[1:])
    jobs = [v for v in S if not want or v[1] in want]
    with ThreadPoolExecutor(max_workers=int(os.environ.get("JOBS", 4))) as ex:
        for f in as_completed([ex.submit(render, *v) for v in jobs]):
            print("done", f.result(), flush=True)
