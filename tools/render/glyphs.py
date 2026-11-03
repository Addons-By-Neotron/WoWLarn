"""Procedural rune 'handwriting' as an RGBA ink texture (black ink, alpha = coverage)."""
import random
from PIL import Image, ImageDraw, ImageFilter

GRID = [(x, y) for y in range(4) for x in range(3)]          # 3x4 stroke anchor points per glyph cell

def _glyph(rnd):
    """A rune: a vertical stem plus 1-3 branches/bars, sometimes a dot or ring."""
    strokes = []
    stem = rnd.choice([0, 1, 2])
    if rnd.random() < 0.8:
        strokes.append(((stem, 0), (stem, 3)))
    for _ in range(rnd.randint(1, 3)):
        a = rnd.choice(GRID); b = rnd.choice(GRID)
        if a != b and abs(a[0]-b[0]) + abs(a[1]-b[1]) <= 3:
            strokes.append((a, b))
    extra = rnd.random()
    return strokes, ("dot" if extra < 0.15 else "ring" if extra < 0.25 else None)

def make(path, seed=1, size=(1024, 1280), lines=8, title=True):
    rnd = random.Random(seed)
    W, H = size
    im = Image.new("RGBA", size, (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    mx, my = int(W*0.1), int(H*0.08)
    y = my
    if title:                                                 # sigil: double ring with a large rune inside
        r = int(W*0.11); cx = W//2; cy = y + r
        for rr, wd in ((r, 7), (int(r*0.82), 4)):
            d.ellipse((cx-rr, cy-rr, cx+rr, cy+rr), outline=(0, 0, 0, 235), width=wd)
        strokes, _ = _glyph(rnd)
        s = r*0.45
        for a, b in strokes + [((0, 1), (2, 1))]:
            d.line((cx + (a[0]-1)*s, cy + (a[1]-1.5)*s*0.9, cx + (b[0]-1)*s, cy + (b[1]-1.5)*s*0.9), fill=(0, 0, 0, 235), width=7)
        y = cy + r + int(H*0.05)
    gh = (H - my - y) / lines                                 # line pitch
    ch = gh*0.55; cw = ch*0.55; gap = cw*0.55
    for ln in range(lines):
        x = mx + (rnd.uniform(0, cw) if ln else 0)
        right = W - mx - (rnd.uniform(0, W*0.3) if ln == lines-1 else 0)
        while x + cw < right:
            for _ in range(rnd.randint(2, 6)):                # one "word"
                if x + cw > right: break
                strokes, extra = _glyph(rnd)
                ox, oy = x, y + rnd.uniform(-2, 2)
                alpha = rnd.randint(200, 245); wd = rnd.choice([5, 6, 6, 7])
                P = lambda p: (ox + p[0]/2*cw + rnd.uniform(-1.5, 1.5), oy + p[1]/3*ch + rnd.uniform(-1.5, 1.5))
                for a, b in strokes:
                    d.line((*P(a), *P(b)), fill=(0, 0, 0, alpha), width=wd)
                if extra == "dot":
                    cx, cy = P((1, -0.6)); d.ellipse((cx-3, cy-3, cx+3, cy+3), fill=(0, 0, 0, alpha))
                elif extra == "ring":
                    cx, cy = P((1, 1.5)); d.ellipse((cx-cw*0.3, cy-cw*0.3, cx+cw*0.3, cy+cw*0.3), outline=(0, 0, 0, alpha), width=wd-1)
                x += cw + cw*0.35
            x += gap
        y += gh
    im = im.filter(ImageFilter.GaussianBlur(0.8))             # soften like ink bleeding into paper
    im.save(path)

if __name__ == "__main__":
    import sys
    make(sys.argv[1] if len(sys.argv) > 1 else "glyphs.png")
