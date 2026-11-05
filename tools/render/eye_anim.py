"""The Eye of Larn's core animated: FRAMES renders with the swirls turned through one seamless loop, stitched into a
flipbook (Media/Gems/gem_22_eye_of_larn_anim.png, COLS x ROWS frames of 128px, left to right, top to bottom).
Usage: [JOBS=4] python3 eye_anim.py
"""
import os
from PIL import Image
import gems, runner

FRAMES, COLS = 64, 8
slug = "eye_of_larn"
i, _, p = next(v for v in gems.G if v[1] == slug)
V = [(i, f"{slug}_f{k:02d}", dict(p, inner=dict(p["inner"], spin=360*k/FRAMES))) for k in range(FRAMES)]

if __name__ == "__main__":
    tmp = os.path.join(runner.PREVIEW, "eye_anim")
    runner.main("build_gem.py", V, tmp, "gem", pad=120)
    frames = [Image.open(os.path.join(tmp, f"gem_{i:02d}_{slug}_f{k:02d}_icon.png")) for k in range(FRAMES)]
    w, h = frames[0].size; rows = (FRAMES + COLS - 1)//COLS
    sheet = Image.new("RGBA", (COLS*w, rows*h))
    for k, f in enumerate(frames):
        sheet.paste(f, ((k % COLS)*w, (k//COLS)*h))
    out = os.path.join(runner.REPO, "Media", "Gems", f"gem_{i:02d}_{slug}_anim.png")
    sheet.save(out); print("wrote", out)
