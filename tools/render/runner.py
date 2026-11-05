"""Shared batch runner for the item renders: one Blender process per variant, several in parallel,
then crop to a square icon, 128px by default (with optional glow), in Media/<dir>/<prefix>_<id>_<slug>_icon.png.

A variant is (id, slug, params). Params starting with "halo", "shadow_cut", "frame" or "align" are
post-processing only (halo, halo_color, shadow_cut, frame, align); everything else is passed to the Blender build script as JSON.
"""
import functools, json, os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from PIL import Image, ImageChops, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
PREVIEW = os.path.join(HERE, "preview")                    # .blend files + scratch, not shipped
BLENDER = "/home/neotron/Downloads/blender-5.2.3-linux-x64/blender"
SIZE = 128                       # icon size (px) for items; world objects (thrones, gold, ...) pass size=256

def glow_layer(im, col, strength, radius=24):
    """Soft glow from the item's silhouette (works for a dark 'glow' too, since it's alpha-blended)."""
    a = im.getchannel("A").filter(ImageFilter.GaussianBlur(radius)).point(lambda v: min(255, int(v*strength*1.6)))
    rgb = tuple(int(255*min(1, c)**(1/2.2)) for c in col)
    h = Image.new("RGBA", im.size, (*rgb, 0)); h.putalpha(a)
    return h

def _mask(fn, size):
    m = Image.new("L", (size, size)); c = (size - 1)/2
    m.putdata([int(255*fn(x, y, c)) for y in range(size) for x in range(size)])
    return m

def _smooth(t): t = min(1.0, max(0.0, t)); return t*t*(3 - 2*t)
# glow fades out on a circle so it never shows the square crop; item gets only a thin safety fade
@functools.cache
def glow_mask(size):
    return _mask(lambda x, y, c: 1 - _smooth((((x-c)**2 + (y-c)**2)**0.5/c - 0.7)/0.28), size)

@functools.cache
def edge_mask(size):                                       # ~6px fade at 256, scaled with the icon
    w = 6*size/256
    return _mask(lambda x, y, c: _smooth(min(x, y, size-1-x, size-1-y)/w), size)

def cut_shadow(im, cut):
    """Drop the faint sampling noise a shadow catcher leaves over the whole ground (alpha <= cut on black
    pixels), keeping the real shadow; otherwise the square crop shows it as a grey box in game."""
    r, g, b, a = im.split()
    dark = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda v: 255 if v < 8 else 0)
    trimmed = a.point(lambda v: max(0, int((v - cut)*255/(255 - cut))))
    im.putalpha(Image.composite(trimmed, a, dark))
    return im

def icon(src, dst, bbox, pad=60, glow=None, frame=None, align=None, fill=False, boost=None, size=SIZE):
    """Square crop around bbox (+pad px of the source), size px. glow=(colour, strength) adds a halo layer.
    frame=s: instead a fixed s x s crop around the render's centre (the camera target), so a set of views
    keeps the item at the same size and place.  align="bottom" then moves that crop up or down so the item
    (with its shadow) sits on the icon's bottom edge instead of floating in the middle.  fill: crop exactly to
    bbox and leave the edges sharp, so the item fills the icon edge to edge (doors set into walls);
    fill="box": the same, to the box the build script wrote to src + ".box" (a door's opening, round leaves
    that do not fill it).  boost=(contrast, saturation, gamma): punch up a flat-looking render (gamma > 1
    darkens the mid tones)."""
    im = Image.open(src); x0, y0, x1, y1 = bbox or (0, 0, im.width, im.height)   # None: an empty frame
    s = max(x1-x0, y1-y0) + pad; cx, cy = (x0+x1)//2, (y0+y1)//2
    if frame:
        s = frame; cx, cy = im.width//2, im.height//2
        if align == "bottom": cy = y1 + int(s*0.03) - s//2           # small margin under the item
    box = bbox if fill else (cx-s//2, cy-s//2, cx+s//2, cy+s//2)
    if fill == "box":
        with open(src + ".box") as f: box = tuple(json.load(f))
    out = im.crop(box).resize((size, size), Image.LANCZOS)
    if glow:
        h = glow_layer(im, *glow).crop(box).resize((size, size), Image.LANCZOS)
        h.putalpha(ImageChops.multiply(h.getchannel("A"), glow_mask(size)))
        h.alpha_composite(out); out = h
    if not fill:
        out.putalpha(ImageChops.multiply(out.getchannel("A"), edge_mask(size)))
    if boost:
        c, col, g = boost; a = out.getchannel("A")
        rgb = out.convert("RGB").point(lambda v: int(255*(v/255)**g))
        out = ImageEnhance.Color(ImageEnhance.Contrast(rgb).enhance(c)).enhance(col).convert("RGBA"); out.putalpha(a)
    out.save(dst)

def render_one(script, outdir, prefix, i, slug, p, prepare=None, pad=60, size=SIZE):
    name = f"{prefix}_{i:02d}_{slug}"
    out = os.path.join(PREVIEW, f"_{name}.png")
    p = dict(p)
    if prepare:                                            # per-variant hook: may change script/params
        script, p = prepare(name, i, p, script)
    bp = {k: v for k, v in p.items() if not k.startswith(("halo", "shadow_cut", "frame", "align", "fill", "boost"))}
    bp["save_blend"] = os.path.join(PREVIEW, name + ".blend")
    cmd = [BLENDER, "-b", "-P", os.path.join(HERE, script), "--", out, json.dumps(bp)]
    for attempt in range(4):                # parallel jobs can briefly run the GPU out of memory; wait + retry
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode == 0 and os.path.exists(out): break
        time.sleep(2 + 3*attempt)
    else:
        raise RuntimeError(f"{name} failed:\n" + "\n".join((r.stdout + r.stderr).splitlines()[-15:]))
    if p.get("shadow_cut"):
        cut_shadow(Image.open(out).convert("RGBA"), p["shadow_cut"]).save(out)
    bbox = Image.open(out).getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if os.environ.get("BBOX"):                          # BBOX=1: report how far the item reaches from the centre
        print(name, "reach", max(256 - bbox[0], bbox[2] - 256, 256 - bbox[1], bbox[3] - 256), flush=True)
    glow = (p.get("halo_color", p.get("glow") or p.get("color")), p["halo"]) if p.get("halo") else None
    icon(out, os.path.join(outdir, name + "_icon.png"), bbox, pad=pad, glow=glow, frame=p.get("frame"), align=p.get("align"), fill=p.get("fill"), boost=p.get("boost"), size=size)
    os.remove(out)
    if os.path.exists(out + ".box"): os.remove(out + ".box")
    blend1 = os.path.join(PREVIEW, name + ".blend1")
    if os.path.exists(blend1): os.remove(blend1)
    return name

def main(script, variants, media_dir, prefix, prepare=None, pad=60, size=SIZE):
    """CLI entry: `python3 <runner>.py [slug ...]` (no args = all), JOBS env = parallel processes (default 4).
    (Extra CPU-rendering workers were tried and made runs slower: the GPU jobs need the CPU too.)
    pad: extra crop room (px of the 512 render) around the item; raise it for sets with wide halos.
    size: icon size in px."""
    outdir = os.path.join(REPO, "Media", media_dir)
    for d in (outdir, PREVIEW): os.makedirs(d, exist_ok=True)
    want = set(sys.argv[1:])
    jobs = [v for v in variants if not want or v[1] in want]
    with ThreadPoolExecutor(max_workers=int(os.environ.get("JOBS", 4))) as ex:
        for f in as_completed([ex.submit(render_one, script, outdir, prefix, *v, prepare=prepare, pad=pad, size=size) for v in jobs]):
            print("done", f.result(), flush=True)
