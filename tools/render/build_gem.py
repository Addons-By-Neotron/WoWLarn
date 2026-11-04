"""Build + render one faceted gem.  Usage:
blender -b -P build_gem.py -- out.png '{"cut":"brilliant", "color":[r,g,b], ...}'
Cuts: brilliant (round), heart, emerald (step cut), trillion (triangle).
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import mat, rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "gem.png"
P = dict(cut="brilliant", color=(0.95, 0.97, 1.0), ior=2.42, glow=None, glow_strength=0.0,
         fire=False, tilt=52, yaw=18, roll=0, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---- outlines: closed 2D curves on t in [0, 1), unit size, centred
def circle(t):
    a = t*math.tau; return (math.cos(a), math.sin(a))

def heart(t):
    a = t*math.tau
    x = 16*math.sin(a)**3
    y = 13*math.cos(a) - 5*math.cos(2*a) - 2*math.cos(3*a) - math.cos(4*a)
    return (x/17, (y+2.5)/17)

def polyline(pts):
    """Piecewise-linear closed outline through pts, parameterised by perimeter length."""
    segs = list(zip(pts, pts[1:] + pts[:1])); lens = [math.dist(a, b) for a, b in segs]; tot = sum(lens)
    def f(t):
        d = (t % 1.0)*tot
        for (a, b), l in zip(segs, lens):
            if d <= l:
                u = d/l; return (a[0] + (b[0]-a[0])*u, a[1] + (b[1]-a[1])*u)
            d -= l
        return pts[0]
    return f

W, Hh, C = 1.0, 0.7, 0.22                          # emerald cut: rectangle with chamfered corners
octagon = polyline([(W, Hh-C), (W-C, Hh), (-W+C, Hh), (-W, Hh-C), (-W, -Hh+C), (-W+C, -Hh), (W-C, -Hh), (W, -Hh+C)])

def trillion(t):                                   # triangle with slightly convex sides, rounded tips
    a = t*math.tau + math.pi/2
    r = 0.62/math.cos(((a - math.pi/2) % (math.tau/3)) - math.pi/3)**0.85
    return (r*math.cos(a), r*math.sin(a))

# ---- cuts: (outline, segments, rings).  A ring is (scale, z, half-step twist).  Twisted rings
#      between plain ones make the triangular star/kite facets of brilliant cuts; step cuts don't twist.
# Kept deliberately simple (few, large facets): the icons are shown at ~40px in game.
CUTS = {
    "brilliant": (circle, 8, [(0.0, -0.62, 0), (1.0, 0.0, 0), (1.0, 0.05, 0),
                              (0.6, 0.3, 1), (0.0, 0.3, 0)]),
    "heart":     (heart, 14, [(0.0, -0.55, 0), (1.0, 0.0, 0), (1.0, 0.05, 0),
                              (0.6, 0.27, 0), (0.0, 0.27, 0)]),
    "emerald":   (octagon, 8, [(0.1, -0.45, 0), (0.6, -0.25, 0), (1.0, 0.0, 0), (1.0, 0.05, 0),
                               (0.84, 0.17, 0), (0.7, 0.26, 0), (0.0, 0.26, 0)]),
    "trillion":  (trillion, 6, [(0.0, -0.5, 0), (1.0, 0.0, 0), (1.0, 0.05, 0),
                                (0.55, 0.25, 1), (0.0, 0.25, 0)]),
}
outline, N, rings = CUTS[P["cut"]]

me = bpy.data.meshes.new("Gem"); bm = bmesh.new()
loops = []
for s, z, tw in rings:
    if s == 0.0:
        loops.append([bm.verts.new((0, 0, z))])
    else:
        loops.append([bm.verts.new((*(c*s for c in outline((k + 0.5*tw)/N)), z)) for k in range(N)])
for a, b in zip(loops, loops[1:]):
    if len(a) == 1 or len(b) == 1:                 # fan to the culet / table centre
        ring, pt = (b, a[0]) if len(a) == 1 else (a, b[0])
        for k in range(N):
            bm.faces.new((ring[k], ring[(k+1) % N], pt))
    else:
        for k in range(N):                         # quads split into triangles so twisted rings stay planar-ish
            bm.faces.new((a[k], a[(k+1) % N], b[(k+1) % N])); bm.faces.new((a[k], b[(k+1) % N], b[k]))
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1), verts=bm.verts, edges=bm.edges)   # merge coplanar tris (table)
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
bm.to_mesh(me); bm.free()
gem = bpy.data.objects.new("Gem", me); sc.collection.objects.link(gem)
gem.scale = (0.85, 0.85, 0.85)
gem.rotation_mode = 'ZXY'
gem.rotation_euler = (math.radians(P["tilt"]), math.radians(P["roll"]), math.radians(P["yaw"]))   # tilt table toward camera
gem.location = (0, 0, 1.4)

m, b = mat("Gem", P["color"], Roughness=0.0, IOR=P["ior"], **{"Transmission Weight": 1.0})
if P["glow"]:
    b.inputs["Emission Color"].default_value = (*P["glow"], 1); b.inputs["Emission Strength"].default_value = P["glow_strength"]
gem.data.materials.append(m)

rig(sc)
studio_world(sc, 1.2, scale=0.7, distortion=0.4)  # few broad bands: each facet reads as one clean tone
spot(sc, (-2.5, -3, 4), 250, (1, 1, 1)); spot(sc, (3, -2, 3.5), 180, (1, 1, 1))
if P["fire"]:                                      # fake dispersion: coloured sparkle lights
    spot(sc, (-3.5, -1.5, 2.5), 120, (0.2, 0.6, 1)); spot(sc, (3.5, -3, 1.5), 120, (1, 0.5, 0.1)); spot(sc, (0, -4, 5), 80, (0.9, 0.3, 1))

sc.cycles.max_bounces = 24; sc.cycles.transmission_bounces = 24; sc.cycles.glossy_bounces = 16
render(sc, OUT, P["save_blend"], samples=256)
