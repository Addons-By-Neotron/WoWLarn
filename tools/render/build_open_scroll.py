"""Build + render an open scroll: a flat sheet with a roll at top and bottom, both curling backwards.
Usage: blender -b -P build_open_scroll.py -- out.png '{"ink":"/path/glyphs.png", ...}'
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import paper_material, rig, render

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "open_scroll.png"
P = dict(paper=(0.8, 0.66, 0.42), ink=None, ink_color=(0.12, 0.05, 0.02),
         width=1.5, height=1.8, roll_r=0.17, turns=2.3, yaw=24, seed=5, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
random.seed(P["seed"])
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---- cross-section in (y, z): top spiral (inner -> outer), flat sheet, bottom spiral (outer -> inner).
#      Roll centres sit in front of the sheet (-y): the sheet leaves the back of each roll, so both
#      rolls lie on the sheet's ends and curl the same way (towards the viewer).
W, H, R = P["width"], P["height"], P["roll_r"]
PHI = P["turns"]*math.tau
def spiral(phi, sign):
    r = R*(1 - 0.65*phi/PHI)
    return (-R + r*math.cos(phi), sign*(H/2 + r*math.sin(phi)))
ns = 120
sec = [spiral(PHI*(1 - k/ns), 1) for k in range(ns)]                    # top roll, inner -> front edge
nf = 40
for k in range(nf+1):                                                    # flat sheet with a slight bow
    t = k/nf; sec.append((0.03*math.sin(t*math.pi), H/2 - H*t))   # bows slightly away
sec += [spiral(PHI*k/ns, -1) for k in range(1, ns+1)]                    # bottom roll, front edge -> inner
# arc length along the section, for UVs; flat part spans [s_top, s_bot]
s = [0.0]
for a, b in zip(sec, sec[1:]): s.append(s[-1] + math.dist(a, b))
s_top, s_bot = s[ns], s[ns+nf]

me = bpy.data.meshes.new("Sheet"); bm = bmesh.new()
nx = 40; cols = []
for j in range(nx+1):
    x = -W/2 + W*j/nx
    col = []
    for i, (y, z) in enumerate(sec):
        xx = x
        if j in (0, nx):                                                 # torn side edges
            xx += (1 if j == 0 else -1)*random.uniform(0, 0.04)
        col.append(bm.verts.new((xx, y, z)))
    cols.append(col)
for c0, c1 in zip(cols, cols[1:]):
    for i in range(len(sec)-1):
        bm.faces.new((c0[i], c0[i+1], c1[i+1], c1[i]))
uv = bm.loops.layers.uv.new("UVMap"); ink = bm.loops.layers.uv.new("Ink")
idx = {v: (j, i) for j, c in enumerate(cols) for i, v in enumerate(c)}
for f in bm.faces:
    for lp in f.loops:
        j, i = idx[lp.vert]
        u = j/nx
        lp[uv].uv = (u, s[i]/s[-1])
        lp[ink].uv = (u, 1 - (s[i]-s_top)/(s_bot-s_top))                 # 0..1 over the flat sheet only
bm.normal_update(); bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
sheet = bpy.data.objects.new("Sheet", me); sc.collection.objects.link(sheet)
sheet.modifiers.new("Solidify", 'SOLIDIFY').thickness = 0.01
dt = bpy.data.textures.new("crinkle", 'CLOUDS'); dt.noise_scale = 0.3; dt.noise_depth = 4
dm = sheet.modifiers.new("Disp", 'DISPLACE'); dm.texture = dt; dm.strength = 0.015
sheet.data.materials.append(paper_material(P["paper"], edge_axes="X", ink=P["ink"], ink_color=P["ink_color"]))

# ---- pose: upright, turned a little so the rolls read as cylinders
sheet.rotation_euler = (0, 0, math.radians(P["yaw"]))
sheet.location = (0, 0, 1.4)

rig(sc)
render(sc, OUT, P["save_blend"])
