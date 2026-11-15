"""The ray of the scroll of pulverization (SPULVERIZE) -> Media/Scrolls/scroll_23_pulverization_ray_anim.png: a
flipbook laid out like the lightning's (lightning_anim.py, so the same V.BeamProgress drives it): FRAMES frames of
one tile's worth of ray (COLS x ROWS frames of 128px, left to right, top to bottom), drawn flat in 2D (no Blender).
The ray runs straight along the middle from the right edge to the left; what moves on it (the ripples down the core,
the swelling) dies away at the tile's edges, so a line of tiles joins up into one ray whichever frame each shows.
Frames 0-7: it shoots across the tile from the right; 8-23: it hums, ripples running down it and grit thrown off
(any of these can follow any other); 24-31: it dies away from the right, the caster's end, towards the left.
Usage: python3 ray_anim.py
"""
import math, os, random
import numpy as np
from PIL import Image
import runner

FRAMES, COLS, CELL = 32, 8, 128
GROW, OUT = 8, 8
S = 4                                               # drawn at S times the size, then shrunk: smooth edges
W = H = CELL*S
CORE = np.array([1.0, 0.97, 0.88])                   # a white-hot core
INNER = np.array([1.0, 0.78, 0.35])                  # in an amber sheath
GLOW = np.array([0.85, 0.42, 0.12])                  # and a dull orange glow
GRIT = np.array([0.95, 0.7, 0.4])

X = np.arange(W)[None, :] + 0.5
Y = np.arange(H)[:, None] + 0.5
EDGE = np.sin(np.pi*X/W)**0.8                        # 0 at the tile's edges: what moves there dies away

def frame(t, x0=0.0, x1=W, bright=1.0, tip=None, grit=()):
    """One frame at phase t (0..1 through the hum): the ray where x0 <= x <= x1, tip: a flash at that x."""
    # the core ripples (waves running down the ray, the way it goes: right to left) and the ray swells
    wave = np.sin(2*np.pi*(3*X/W + 2*t)) * EDGE
    swell = 1 + 0.18*np.sin(2*np.pi*(2*X/W + t)) * EDGE
    dy = np.abs(Y - H/2)                             # (straight: the ripples show in the brightness, not the line)
    core = np.exp(-(dy/(2.2*S*swell))**2) * (0.85 + 0.15*wave)
    inner = np.exp(-(dy/(6*S*swell))**2) * (0.8 + 0.2*np.sin(2*np.pi*(5*X/W + 3*t))*EDGE)
    glow = np.exp(-(dy/(17*S*swell))**2) * 0.75
    rgb = core[..., None]*CORE + inner[..., None]*INNER*0.9 + glow[..., None]*GLOW*0.8
    for gx, gy, gr, gb in grit:                      # grit thrown off the ray
        d2 = ((X - gx)**2 + (Y - gy)**2)/(gr*S)**2
        rgb += (np.exp(-d2)*gb)[..., None]*GRIT
    if tip is not None:                              # the front of the ray as it shoots
        d2 = ((X - tip)**2 + (Y - H/2)**2)/(14*S)**2
        rgb += (np.exp(-d2)*1.1)[..., None]*CORE
    # the part of the tile it is in (soft at the cut)
    soft = 4*S
    mask = (np.clip((X - x0)/soft + 0.5, 0, 1) if x0 > 0 else 1) * (np.clip((x1 - X)/soft + 0.5, 0, 1) if x1 < W else 1)
    mask = np.broadcast_to(mask, (H, W))
    rgb = np.clip(rgb*bright*mask[..., None], 0, 1)
    # un-premultiply: the colour at full strength, its brightness the alpha (it is all light, over anything)
    a = rgb.max(axis=2)
    col = np.where(a[..., None] > 1e-4, rgb/np.maximum(a, 1e-4)[..., None], 0)
    out = np.dstack([col, a])
    im = Image.fromarray((out*255 + 0.5).astype(np.uint8), "RGBA")
    return im.resize((CELL, CELL), Image.LANCZOS)

def grit(rnd, t):
    """Specks of grit flung out from the ray (positions at phase t), none near the tile's edges."""
    out = []
    for _ in range(7):
        x = rnd.uniform(0.15, 0.85)*W
        side = rnd.choice((-1, 1)); fly = (t + rnd.random()) % 1
        y = H/2 + side*(8 + 40*fly)*S
        out.append((x, y, rnd.uniform(1.0, 1.8), (1 - fly)*0.9))
    return out

if __name__ == "__main__":
    frames = []
    for k in range(GROW):                            # shooting across from the right
        x = W*(1 - (k + 1)/GROW)
        frames.append(frame(0, x0=x, tip=x if k < GROW - 1 else None))
    hum = FRAMES - GROW - OUT
    rnd = random.Random(7)
    for k in range(hum):                             # humming: one loop of the ripples, a flicker now and then
        t = k/hum
        frames.append(frame(t, bright=rnd.uniform(0.85, 1.0) if k % 5 else 1.1, grit=grit(random.Random(k), t)))
    for k in range(OUT):                             # dying away from the caster's end
        frames.append(frame(0, x1=W*(1 - (k + 1)/(OUT + 1)), bright=1 - 0.5*k/OUT))
    rows = (FRAMES + COLS - 1)//COLS
    sheet = Image.new("RGBA", (COLS*CELL, rows*CELL))
    for k, f in enumerate(frames):
        sheet.paste(f, ((k % COLS)*CELL, (k//COLS)*CELL))
    out = os.path.join(runner.REPO, "Media", "Scrolls", "scroll_23_pulverization_ray_anim.png")
    os.makedirs(os.path.dirname(out), exist_ok=True); sheet.save(out); print("wrote", out)
