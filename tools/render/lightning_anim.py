"""The lightning bolt (SP_LIGHTNING) -> Media/Spells/spell_23_lightning_anim.png: a flipbook of FRAMES frames of
one tile's worth of bolt (COLS x ROWS frames of 128px, left to right, top to bottom), drawn flat in 2D (no Blender).
The bolt runs from the middle of the right edge to the middle of the left edge in every frame, level as it
leaves each, so a line of tiles joins up into one bolt whichever frame each tile shows: lay them along the way
it goes (it is made for a caster on the right, so it goes left), turned to its heading.
Frames 0-7: the bolt shoots across the tile from the right; 8-23: it crackles, forking (any of these can follow
any other); 24-31: it dies away from the right, the caster's end, towards the left.
Usage: python3 lightning_anim.py
"""
import math, os, random
from PIL import Image, ImageChops, ImageDraw, ImageFilter
import runner

FRAMES, COLS, CELL = 32, 8, 128
GROW, OUT = 8, 8
S = 4                                               # drawn at S times the size, then shrunk: smooth lines
W = H = CELL*S
CORE, GLOW = (255, 255, 255), (90, 140, 255)

def jag(a, b, rough, depth, rnd, pin=True):
    """Points of a jagged line from a to b by midpoint displacement; pin: the offsets die away near the ends,
    so the line leaves them level (the main bolt, which has to meet the next tile's)."""
    pts = [a, b]
    for d in range(depth):
        out = [pts[0]]
        for p, q in zip(pts, pts[1:]):
            mx, my = (p[0] + q[0])/2, (p[1] + q[1])/2
            ln = math.hypot(q[0] - p[0], q[1] - p[1])
            nx, ny = -(q[1] - p[1])/ln, (q[0] - p[0])/ln
            o = rnd.uniform(-1, 1)*rough*ln
            if pin:
                o *= math.sin(math.pi*min(1.0, max(0.0, mx/W)))**0.6
            out += [(mx + nx*o, my + ny*o), q]
        pts = out
    return pts

def bolt(seed):
    """The main bolt (right to left) and its forks: [(points, width, brightness)]."""
    rnd = random.Random(seed)
    main = jag((W, H/2), (0, H/2), 0.32, 6, rnd)
    lines = [(main, 1.0, 1.0)]
    for _ in range(rnd.randint(2, 4)):               # forks off it, thrown forwards (left) and out
        i = rnd.randint(len(main)//6, len(main)*4//6); p = main[i]
        ang = math.pi + rnd.choice((-1, 1))*rnd.uniform(0.35, 0.9); ln = rnd.uniform(0.2, 0.45)*W
        q = (p[0] + ln*math.cos(ang), p[1] + ln*math.sin(ang))
        q = (min(W*0.92, max(W*0.08, q[0])), min(H*0.9, max(H*0.1, q[1])))
        fork = jag(p, q, 0.3, 4, rnd, pin=False)
        lines.append((fork, 0.55, 0.75))
        if rnd.random() < 0.5:                       # and a twig off the fork
            j = rnd.randint(1, len(fork) - 2); a2 = ang + rnd.choice((-1, 1))*0.6
            r2 = (fork[j][0] + 0.35*ln*math.cos(a2), fork[j][1] + 0.35*ln*math.sin(a2))
            r2 = (min(W*0.92, max(W*0.08, r2[0])), min(H*0.9, max(H*0.1, r2[1])))
            lines.append((jag(fork[j], r2, 0.3, 3, rnd, pin=False), 0.35, 0.55))
    return lines

def clip(pts, x0, x1):
    """The part of a line with x0 <= x <= x1 (cut where it crosses)."""
    out = []
    for p, q in zip(pts, pts[1:]):
        seg = []
        for a, b in ((p, q),):
            ta, tb = 0.0, 1.0
            dx = b[0] - a[0]
            for lim, sgn in ((x0, 1), (x1, -1)):
                if dx == 0:
                    if sgn*(a[0] - lim) < 0: ta = 2
                else:
                    tt = (lim - a[0])/dx
                    if sgn*dx > 0: ta = max(ta, tt)
                    else: tb = min(tb, tt)
            if ta <= tb:
                seg = [(a[0] + dx*ta, a[1] + (b[1] - a[1])*ta), (a[0] + dx*tb, a[1] + (b[1] - a[1])*tb)]
        if seg:
            if out and out[-1] == seg[0]: out.append(seg[1])
            else:
                if len(out) > 1: yield out
                out = seg
    if len(out) > 1: yield out

def draw(lines, x0=0, x1=W, bright=1.0, tip=None):
    """The frame: lines (only where x0 <= x <= x1) as a white core in a blue glow, tip: a flash at that point."""
    layers = []
    for width, blur, col, k in ((26, 34, GLOW, 0.8), (10, 9, (170, 200, 255), 0.9), (3.2, 1.2, CORE, 1.0)):
        im = Image.new("RGB", (W, H)); d = ImageDraw.Draw(im)
        for pts, w, b in lines:
            c = tuple(int(v*k*b*bright) for v in col)
            for part in clip(pts, x0, x1):
                d.line(part, fill=c, width=max(1, int(width*w*S/4)), joint="curve")
        if tip:
            r = width*1.8
            d.ellipse((tip[0] - r, tip[1] - r, tip[0] + r, tip[1] + r), fill=tuple(int(v*k*bright) for v in col))
        layers.append(im.filter(ImageFilter.GaussianBlur(blur*S/4)))
    rgb = layers[0]
    for im in layers[1:]: rgb = ImageChops.add(rgb, im)
    a = ImageChops.lighter(ImageChops.lighter(*rgb.split()[:2]), rgb.split()[2])
    # un-premultiply: the colour at full strength, its brightness the alpha (it is all light, over anything)
    r, g, b = [Image.eval(ch, lambda v: v) for ch in rgb.split()]
    px = rgb.load(); ap = a.load(); out = Image.new("RGBA", (W, H)); op = out.load()
    for y in range(H):
        for x in range(W):
            al = ap[x, y]
            if al:
                c = px[x, y]; op[x, y] = (c[0]*255//al, c[1]*255//al, c[2]*255//al, al)
    return out.resize((CELL, CELL), Image.LANCZOS)

def point_at(pts, x):
    """Where the line crosses x (the first time from the right)."""
    for p, q in zip(pts, pts[1:]):
        if (p[0] - x)*(q[0] - x) <= 0 and p[0] != q[0]:
            u = (x - p[0])/(q[0] - p[0]); return (x, p[1] + (q[1] - p[1])*u)
    return (x, H/2)

if __name__ == "__main__":
    frames = []
    first = bolt(1)
    for k in range(GROW):                            # shooting across from the right
        x = W*(1 - (k + 1)/GROW)
        frames.append(draw(first, x0=x, tip=point_at(first[0][0], x) if k < GROW - 1 else None))
    rnd = random.Random(99)
    for k in range(FRAMES - GROW - OUT):             # crackling: a new bolt every other frame, flickering
        lines = first if k < 2 else bolt(100 + k//2)
        frames.append(draw(lines, bright=rnd.uniform(0.7, 1.0) if k % 5 else 1.15))
    last = bolt(200)
    for k in range(OUT):                             # dying away from the caster's end
        frames.append(draw(last, x1=W*(1 - (k + 1)/(OUT + 1)), bright=1 - 0.5*k/OUT))
    rows = (FRAMES + COLS - 1)//COLS
    sheet = Image.new("RGBA", (COLS*CELL, rows*CELL))
    for k, f in enumerate(frames):
        sheet.paste(f, ((k % COLS)*CELL, (k//COLS)*CELL))
    out = os.path.join(runner.REPO, "Media", "Spells", "spell_23_lightning_anim.png")
    os.makedirs(os.path.dirname(out), exist_ok=True); sheet.save(out); print("wrote", out)
