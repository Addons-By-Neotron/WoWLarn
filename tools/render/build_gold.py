"""Build + render a pile of gold coins on the ground (with a shadow).  Usage:
blender -b -P build_gold.py -- out.png '{"radius":0.6, "height":0.35, "elev":45, ...}'
Coins lie on a lumpy heap (several overlapping mounds within radius, up to height), tilted with its slope plus\njitter, over a hidden core;
a few loose coins spill around the base.  The lens frames a view_radius (default: the pile's own radius); share one to keep coins one size.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "gold.png"
P = dict(radius=0.6, height=0.35, lumps=3, density=2.5, spill=0.12, gold=(0.9, 0.6, 0.18), elev=90, view_radius=None, seed=1, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rnd = random.Random(P["seed"])

CR, CT = 0.12, 0.025                               # coin radius, thickness
R, H = P["radius"], P["height"]

def coin_mesh():
    """One coin: short cylinder with a raised rim on both faces."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=CR, radius2=CR, depth=CT)
    caps = [f for f in bm.faces if abs(f.normal.z) > 0.9]
    bmesh.ops.inset_individual(bm, faces=caps, thickness=CR*0.14, depth=-CT*0.18)
    return bm

proto = coin_mesh()
bm = bmesh.new()
def place(loc, normal, spin):
    """Copy the prototype coin into the pile mesh, its face along normal, turned by spin about it."""
    m = Matrix.Translation(loc) @ normal.to_track_quat('Z', 'Y').to_matrix().to_4x4() @ Matrix.Rotation(spin, 4, 'Z')
    tmp = proto.copy(); tmp.transform(m)
    me = bpy.data.meshes.new("tmp"); tmp.to_mesh(me); tmp.free(); bm.from_mesh(me); bpy.data.meshes.remove(me)

# heap = several overlapping mounds of different size/height at random offsets: an irregular, lumpy pile
MOUNDS = []
for k in range(P["lumps"]):
    ang = rnd.uniform(0, math.tau); off = R*0.45*(rnd.random()**0.5 if k else 0)
    MOUNDS.append((off*math.cos(ang), off*math.sin(ang), R*rnd.uniform(0.28, 0.45), H*(1.0 if k == 0 else rnd.uniform(0.45, 0.85))))

def h(x, y):                                       # heap surface height
    return max(hm*math.exp(-((x-mx)**2 + (y-my)**2)/(s*s)) for mx, my, s, hm in MOUNDS)

def normal(x, y, e=0.01):
    return Vector((h(x-e, y) - h(x+e, y), h(x, y-e) - h(x, y+e), 2*e)).normalized()

FLOOR = CT*0.6                                     # where the heap fades into the ground
area = sum(1 for i in range(60) for j in range(60) if h(2*R*(i/29.5 - 1), 2*R*(j/29.5 - 1)) > FLOOR)*(4*R/60)**2
n = int(P["density"]*area/(math.pi*CR*CR)) + 3
placed = 0
while placed < n:                                  # coins lying on the heap's surface
    x, y = rnd.uniform(-2*R, 2*R), rnd.uniform(-2*R, 2*R)   # wide enough for every mound's foot
    z = h(x, y)
    if z < FLOOR: continue
    nrm = normal(x, y)
    tilt = 0.6 if rnd.random() < 0.12 else 0.25   # now and then a coin propped up on its neighbours
    nrm = (nrm + Vector((rnd.gauss(0, tilt), rnd.gauss(0, tilt), 0))).normalized()
    place(Vector((x, y, z + CT/2 + rnd.uniform(0, 0.03))), nrm, rnd.uniform(0, math.tau)); placed += 1
spill = 0
while spill < max(2, int(n*P["spill"])):           # loose coins round the foot of the pile, flat-ish on the ground
    x, y = rnd.uniform(-2.2*R, 2.2*R), rnd.uniform(-2.2*R, 2.2*R)
    if not (0.0003 < h(x, y) < FLOOR): continue    # just outside the heap
    nrm = Vector((rnd.gauss(0, 0.12), rnd.gauss(0, 0.12), 1)).normalized()
    place(Vector((x, y, CT/2 + 0.004)), nrm, rnd.uniform(0, math.tau)); spill += 1
proto.free()

me = bpy.data.meshes.new("Coins"); bm.to_mesh(me); bm.free()
for f in me.polygons: f.use_smooth = True
coins = link(sc, "Coins", me)

gold, gb = mat("Gold", P["gold"], Metallic=1.0, Roughness=0.25)
nt = gold.node_tree; N = nt.nodes.new; Lk = nt.links.new
tc = N("ShaderNodeTexCoord"); nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 6
Lk(tc.outputs["Object"], nz.inputs["Vector"])
cr = N("ShaderNodeValToRGB"); Lk(nz.outputs["Fac"], cr.inputs[0])        # some coins redder/paler, some worn
cr.color_ramp.elements[0].color = (*[c*0.75 for c in P["gold"]], 1); cr.color_ramp.elements[1].color = (*[min(1, c*1.1) for c in P["gold"]], 1)
Lk(cr.outputs["Color"], gb.inputs["Base Color"])
rr = N("ShaderNodeMapRange"); rr.inputs["To Min"].default_value = 0.22; rr.inputs["To Max"].default_value = 0.45
Lk(nz.outputs["Fac"], rr.inputs["Value"]); Lk(rr.outputs["Result"], gb.inputs["Roughness"])
coins.data.materials.append(gold)

core = bmesh.new()                                 # hidden core under the surface coins, so no gaps show through
bmesh.ops.create_grid(core, x_segments=64, y_segments=64, size=2.2*R)
for v in core.verts: v.co.z = max(0.0, h(v.co.x, v.co.y)*0.92 - 0.01)
bmesh.ops.delete(core, geom=[f for f in core.faces if all(v.co.z <= 0.0 for v in f.verts)], context='FACES')   # only under the heap
cm = bpy.data.meshes.new("Core"); core.to_mesh(cm); core.free()
dark, _ = mat("GoldDark", [c*0.3 for c in P["gold"]], Metallic=1.0, Roughness=0.6)   # reads as shadow in the gaps
co = link(sc, "Core", cm); co.data.materials.append(dark)

gp = bmesh.new(); bmesh.ops.create_grid(gp, x_segments=1, y_segments=1, size=10)
gm = bpy.data.meshes.new("Ground"); gp.to_mesh(gm); gp.free()
ground = link(sc, "Ground", gm); ground.is_shadow_catcher = True

rig(sc, tgt=Vector((0, 0, H*0.35)), elev=P["elev"])
sc.camera.data.lens = 12*36/(3.6*(P["view_radius"] or R))   # zoom: a shared view_radius keeps coins one size across piles
studio_world(sc, 0.35)
spot(sc, (-3, -4, 4), 150, (1, 0.95, 0.85), tgt=Vector((0, 0, 0))); spot(sc, (3, -3, 3), 80, (1, 1, 1), tgt=Vector((0, 0, 0)))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 9; sun.angle = math.radians(6)   # strong enough to show on the ground
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(60), 0, math.radians(-40))   # low (30 deg) sun: a low pile still casts a visible shadow
for l in bpy.data.lights:                          # only the sun darkens the ground (see build_throne.py)
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False
render(sc, OUT, P["save_blend"], samples=128)
