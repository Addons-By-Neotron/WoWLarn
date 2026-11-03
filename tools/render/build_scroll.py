"""Build + render a rolled scroll.  Usage:
blender -b -P build_scroll.py -- out.png '{"ribbon":[r,g,b], ...}'
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scroll_common import mat, paper_material, rig, render

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "scroll.png"
P = dict(paper=(0.8, 0.66, 0.42), ribbon=(0.45, 0.02, 0.02), seal=(0.55, 0.03, 0.02),
         length=2.6, turns=3.4, tilt=-45, yaw=55, ribbon_y=0.0, pinch=0.4, seed=3,
         save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
random.seed(P["seed"])
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

def link(name, me):
    ob = bpy.data.objects.new(name, me); sc.collection.objects.link(ob); return ob

def lathe_y(name, pts, steps=48):
    """Revolve (radius, y) profile around the Y axis (the roll's axis)."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    vs = [bm.verts.new((r, y, 0)) for r, y in pts]
    for a, b in zip(vs, vs[1:]): bm.edges.new((a, b))
    bmesh.ops.spin(bm, geom=bm.verts[:]+bm.edges[:], axis=(0,1,0), cent=(0,0,0), angle=math.tau, steps=steps)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    return link(name, me)

# ---- rolled parchment: an Archimedean spiral swept along Y, ending in a short loose flap.
#      The roll is cinched in where the ribbon sits, and the paper ends/edge are torn-rough.
L = P["length"]; R0, R1 = 0.06, 0.36
RY = P["ribbon_y"]                                  # ribbon position along the roll (0 = centre)
def pinch(y): return 1 - P["pinch"]*max(0.0, 1 - abs(y-RY)/(L/2))   # linear hourglass, narrowest at the tie
n = 160
sec = []
for i in range(n+1):
    t = i/n; a = t*P["turns"]*math.tau
    r = R0 + (R1-R0)*t
    sec.append((r*math.cos(a), r*math.sin(a)))
ax, az = sec[-1]; a_end = P["turns"]*math.tau
tx, tz = -math.sin(a_end), math.cos(a_end)          # tangent at the outer end
flat = []                                           # same flap, wrapped tight to the roll
for k in range(1, 6):                               # flap hangs down so its edge ends front-centre (turns=3.4)
    s = k*0.05
    sec.append((ax + tx*s + math.cos(a_end)*s*s*0.6, az + tz*s + math.sin(a_end)*s*s*0.6))
    a = a_end + s/R1; flat.append(((R1+0.004)*math.cos(a), (R1+0.004)*math.sin(a)))
me = bpy.data.meshes.new("Paper"); bm = bmesh.new()
ny = 48; cols = []
for j in range(ny+1):
    y = -L/2 + L*j/ny
    press = math.exp(-((y-RY)/0.32)**2)             # 1 under the seal: flap pressed flat, lifts away further out
    col = []
    for i, (x, z) in enumerate(sec):
        f = pinch(y); yy = y
        if i > n:
            fx, fz = flat[i-n-1]; x += (fx-x)*press; z += (fz-z)*press
        if j in (0, ny):                            # torn ends
            yy += (1 if j == 0 else -1) * random.uniform(0, 0.045)
        if i == len(sec)-1:                         # torn free edge of the flap
            d = random.uniform(-0.03, 0.02); x += tx*d; z += tz*d
        col.append(bm.verts.new((x*f, yy, z*f)))
    cols.append(col)
for c0, c1 in zip(cols, cols[1:]):
    for i in range(len(sec)-1):
        bm.faces.new((c0[i], c0[i+1], c1[i+1], c1[i]))
uv = bm.loops.layers.uv.new("UVMap")
for f in bm.faces:
    for lp in f.loops:
        lp[uv].uv = (lp.vert.co.y/L + 0.5, 0)
bm.to_mesh(me); bm.free()
for p in me.polygons: p.use_smooth = True
paper = link("Paper", me)
paper.modifiers.new("Solidify", 'SOLIDIFY').thickness = 0.012
dt = bpy.data.textures.new("crinkle", 'CLOUDS'); dt.noise_scale = 0.18; dt.noise_depth = 4
dm = paper.modifiers.new("Disp", 'DISPLACE'); dm.texture = dt; dm.strength = 0.02

# ---- ribbon band wrapped round the roll at the cinch
Rp = R1*pinch(RY)
band = lathe_y("Band", [(Rp+0.02, RY-0.07), (Rp+0.035, RY-0.05), (Rp+0.035, RY+0.05), (Rp+0.02, RY+0.07)])

# ---- wax seal on the camera-facing side of the band, with two ribbon tails
seal = lathe_y("Seal", [(0.0, 0.07), (0.14, 0.065), (0.19, 0.04), (0.2, 0.0), (0.17, -0.02), (0.0, -0.02)], steps=40)
st = bpy.data.textures.new("sealn", 'CLOUDS'); st.noise_scale = 0.08
dm = seal.modifiers.new("Disp", 'DISPLACE'); dm.texture = st; dm.strength = 0.03
# local -X ends up facing the camera once the pivot turns the roll axis to screen-horizontal
seal.rotation_euler = (0, 0, math.pi/2)             # disc axis Y -> -X
seal.location = (-(Rp+0.045), RY, 0)              # sits on the band, on top of the flap
emb = lathe_y("Emboss", [(0.0, 0.085), (0.06, 0.085), (0.09, 0.075), (0.1, 0.06)], steps=40)
emb.location = seal.location; emb.rotation_euler = seal.rotation_euler

def tail(name, y0, ang):
    """Ribbon tail hanging down from under the seal, in front of the roll."""
    me = bpy.data.meshes.new(name); bm = bmesh.new(); w = 0.05; ln = 0.55
    d = Vector((0, math.sin(ang), -math.cos(ang)))
    side = Vector((0, math.cos(ang), math.sin(ang)))
    base = Vector((-(Rp+0.06), RY + y0, -0.05)); prev = None
    for k in range(9):
        t = k/8; c = base + d*ln*t + Vector((-0.04*math.sin(t*3), 0, 0))
        row = (bm.verts.new(c - side*w*(1-0.3*t)), bm.verts.new(c + side*w*(1-0.3*t)))
        if prev: bm.faces.new((prev[0], prev[1], row[1], row[0]))
        prev = row
    bm.to_mesh(me); bm.free()
    ob = link(name, me); ob.modifiers.new("Solidify", 'SOLIDIFY').thickness = 0.01
    return ob
tails = [tail("TailA", -0.05, -0.35), tail("TailB", 0.05, 0.25)]

# ---- materials
paper.data.materials.append(paper_material(P["paper"], edge_axes="X"))

m, b = mat("Ribbon", P["ribbon"], Roughness=0.45, **{"Sheen Weight":0.6})
for o in [band] + tails: o.data.materials.append(m)
m, b = mat("Wax", P["seal"], Roughness=0.25, **{"Coat Weight":0.6})
for o in (seal, emb): o.data.materials.append(m)

# ---- pose: roll lies diagonally, seal toward camera
pivot = bpy.data.objects.new("Pivot", None); sc.collection.objects.link(pivot)
for o in [paper, band, seal, emb] + tails: o.parent = pivot
pivot.rotation_mode = 'ZXY'                        # Z first: roll axis Y -> screen X; then tilt about view axis
pivot.rotation_euler = (0, math.radians(P["tilt"]), math.radians(90 + P["yaw"]))   # yaw > 0: left end nearest the camera
pivot.location = (0, 0, 1.4)

# ---- camera / lights / render (same rig as the potions)
rig(sc)
render(sc, OUT, P["save_blend"])
