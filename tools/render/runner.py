"""Shared batch runner for the item renders: one Blender process per variant, several in parallel,
then crop to a 256px icon (with optional glow) in Media/<dir>/<prefix>_<id>_<slug>_icon.png.

A variant is (id, slug, params). Params starting with "halo", "shadow_cut" or "frame" are post-processing
only (halo, halo_color, shadow_cut, frame); everything else is passed to the Blender build script as JSON.
"""
import json, os, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
from PIL import Image, ImageChops, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
PREVIEW = os.path.join(HERE, "preview")                    # .blend files + scratch, not shipped
BLENDER = "/home/neotron/Downloads/blender-5.2.3-linux-x64/blender"
SIZE = 256

def glow_layer(im, col, strength, radius=24):
    """Soft glow from the item's silhouette (works for a dark 'glow' too, since it's alpha-blended)."""
    a = im.getchannel("A").filter(ImageFilter.GaussianBlur(radius)).point(lambda v: min(255, int(v*strength*1.6)))
    rgb = tuple(int(255*min(1, c)**(1/2.2)) for c in col)
    h = Image.new("RGBA", im.size, (*rgb, 0)); h.putalpha(a)
    return h

def _mask(fn):
    m = Image.new("L", (SIZE, SIZE)); c = (SIZE - 1)/2
    m.putdata([int(255*fn(x, y, c)) for y in range(SIZE) for x in range(SIZE)])
    return m

def _smooth(t): t = min(1.0, max(0.0, t)); return t*t*(3 - 2*t)
# glow fades out on a circle so it never shows the square crop; item gets only a thin safety fade
GLOW_MASK = _mask(lambda x, y, c: 1 - _smooth((((x-c)**2 + (y-c)**2)**0.5/c - 0.7)/0.28))
EDGE_MASK = _mask(lambda x, y, c: _smooth(min(x, y, SIZE-1-x, SIZE-1-y)/6))

def cut_shadow(im, cut):
    """Drop the faint sampling noise a shadow catcher leaves over the whole ground (alpha <= cut on black
    pixels), keeping the real shadow; otherwise the square crop shows it as a grey box in game."""
    r, g, b, a = im.split()
    dark = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda v: 255 if v < 8 else 0)
    trimmed = a.point(lambda v: max(0, int((v - cut)*255/(255 - cut))))
    im.putalpha(Image.composite(trimmed, a, dark))
    return im

def icon(src, dst, bbox, pad=60, glow=None, frame=None):
    """Square crop around bbox (+pad px of the source), SIZE px. glow=(colour, strength) adds a halo layer.
    frame=s: instead a fixed s x s crop around the render's centre (the camera target), so a set of views
    keeps the item at the same size and place."""
    im = Image.open(src); x0, y0, x1, y1 = bbox
    s = max(x1-x0, y1-y0) + pad; cx, cy = (x0+x1)//2, (y0+y1)//2
    if frame:
        s = frame; cx, cy = im.width//2, im.height//2
    box = (cx-s//2, cy-s//2, cx+s//2, cy+s//2)
    out = im.crop(box).resize((SIZE, SIZE), Image.LANCZOS)
    if glow:
        h = glow_layer(im, *glow).crop(box).resize((SIZE, SIZE), Image.LANCZOS)
        h.putalpha(ImageChops.multiply(h.getchannel("A"), GLOW_MASK))
        h.alpha_composite(out); out = h
    out.putalpha(ImageChops.multiply(out.getchannel("A"), EDGE_MASK))
    out.save(dst)

def render_one(script, outdir, prefix, i, slug, p, prepare=None, pad=60):
    name = f"{prefix}_{i:02d}_{slug}"
    out = os.path.join(PREVIEW, f"_{name}.png")
    p = dict(p)
    if prepare:                                            # per-variant hook: may change script/params
        script, p = prepare(name, i, p, script)
    bp = {k: v for k, v in p.items() if not k.startswith(("halo", "shadow_cut", "frame"))}
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
    icon(out, os.path.join(outdir, name + "_icon.png"), bbox, pad=pad, glow=glow, frame=p.get("frame"))
    os.remove(out)
    blend1 = os.path.join(PREVIEW, name + ".blend1")
    if os.path.exists(blend1): os.remove(blend1)
    return name

def main(script, variants, media_dir, prefix, prepare=None, pad=60):
    """CLI entry: `python3 <runner>.py [slug ...]` (no args = all), JOBS env = parallel processes (default 4).
    pad: extra crop room (px of the 512 render) around the item; raise it for sets with wide halos."""
    outdir = os.path.join(REPO, "Media", media_dir)
    for d in (outdir, PREVIEW): os.makedirs(d, exist_ok=True)
    want = set(sys.argv[1:])
    jobs = [v for v in variants if not want or v[1] in want]
    with ThreadPoolExecutor(max_workers=int(os.environ.get("JOBS", 4))) as ex:
        for f in as_completed([ex.submit(render_one, script, outdir, prefix, *v, prepare=prepare, pad=pad) for v in jobs]):
            print("done", f.result(), flush=True)
