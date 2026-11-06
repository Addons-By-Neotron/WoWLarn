"""Build + render a stone fountain standing on the ground (with a shadow).  Usage:
blender -b -P build_fountain.py -- out.png '{"dry":false, "elev":45, ...}'
The model is "Medieval Fountain Empty (Free)" by wolfgar74 (CC-BY 4.0, models/medieval_fountain, see CREDITS.md), with
its own textures: a drum plinth carrying three stacked bowls and a spire.  Running: water is added in the bowls, with
spouts from the spire's bulb and streams over the upper lips into the bowl below.  Dry: no water, grime where it
stood and rubble.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "fountain.png"
P = dict(dry=False, size=2.0, water=(0.012, 0.05, 0.06), elev=90, seed=2, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rnd = random.Random(P["seed"])
MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "medieval_fountain")

bpy.ops.import_scene.gltf(filepath=os.path.join(MODEL, "scene.gltf"))
bpy.context.view_layer.update()
root = bpy.data.objects.new("Fountain", None); sc.collection.objects.link(root)
K = P["size"]/250                                   # the model is 250 across, its plinth's foot at z=-125
for o in [o for o in sc.objects if o.type == 'MESH']:
    o.data.transform(Matrix.Translation((0, 0, 125*K)) @ Matrix.Scale(K, 4) @ o.matrix_world)   # bake + scale, foot at z=0
    o.parent = root; o.matrix_world = Matrix.Identity(4)
for o in [o for o in sc.objects if o.type == 'EMPTY' and o is not root]: bpy.data.objects.remove(o)
Z = lambda z: (z + 125)*K                           # model heights / radii (measured by raycasting) to scene units
R = lambda r: r*K

def obj(name, bm, material, smooth=True):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = root; o.data.materials.append(material)
    return o

def ring(r0, r1, z, segs=64):
    """Flat annulus (a disk when r0 is 0)."""
    bm = bmesh.new()
    outer = [bm.verts.new((r1*math.cos(a), r1*math.sin(a), z)) for a in (math.tau*k/segs for k in range(segs))]
    if r0 <= 0:
        bm.faces.new(outer); return bm
    inner = [bm.verts.new((r0*math.cos(a), r0*math.sin(a), z)) for a in (math.tau*k/segs for k in range(segs))]
    for k in range(segs):
        bm.faces.new((inner[k], inner[(k+1) % segs], outer[(k+1) % segs], outer[k]))
    return bm

def ribbon(path, w, t, segs=8):
    """A stream along a polyline: an elliptic tube, w wide (sideways) and t thick, thinning as it falls."""
    bm = bmesh.new(); rings = []
    for i, p in enumerate(path):
        f = 1 - 0.45*i/(len(path) - 1)
        tg = (path[min(i+1, len(path)-1)] - path[max(i-1, 0)]).normalized()
        side = tg.cross(Vector((0, 0, 1))).normalized(); up = side.cross(tg)
        rings.append([bm.verts.new(p + f*(w*math.cos(a)*side + t*math.sin(a)*up)) for a in (math.tau*k/segs for k in range(segs))])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k+1) % segs], r1[(k+1) % segs], r1[k]))
    return bm

def arc(a, r0, z0, r1, z1, n=12):
    """Falling water from (r0, z0) out to (r1, z1) at angle a: level start, a parabola down."""
    d = Vector((math.cos(a), math.sin(a), 0))
    return [d*(r0 + (r1 - r0)*s) + Vector((0, 0, z0 - (z0 - z1)*s*s)) for s in (i/n for i in range(n + 1))]

# the bowls, inside (from the axis out): water level, inner edge (stem), outer edge (wall); the lip it spills from
POOLS = [  # level,     r0,      r1,       lip r, lip z
    (Z(34.0),  R(6.8),  R(15.3),  R(19.8), Z(36.3)),    # top bowl
    (Z(-4.0),  R(13.4), R(34.4),  R(41.4), Z(0.0)),     # middle bowl
    (Z(-44.0), R(33.7), R(56.2),  R(66.5), Z(-39.1)),   # lower bowl (the plinth under it stays dry)
]
FLOORS = [(Z(24.2), 0, R(13.3)), (Z(-24.0), 0, R(29.7)), (Z(-75.0), R(33.7), R(56.2)), (Z(-75.0), R(66.5), R(119.0))]

if not P["dry"]:
    water, wb = mat("Water", P["water"], Roughness=0.12, IOR=1.33)
    wb.inputs["Specular IOR Level"].default_value = 0.3
    nt = water.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord")
    rip = N("ShaderNodeTexWave"); rip.wave_type = 'RINGS'; rip.inputs["Scale"].default_value = 9
    rip.inputs["Distortion"].default_value = 4; Lk(tc.outputs["Object"], rip.inputs["Vector"])
    nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 40; Lk(tc.outputs["Object"], nz.inputs["Vector"])
    mx = N("ShaderNodeMath"); mx.operation = 'ADD'; Lk(rip.outputs["Fac"], mx.inputs[0]); Lk(nz.outputs["Fac"], mx.inputs[1])
    bp = N("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.25; bp.inputs["Distance"].default_value = 0.004
    Lk(mx.outputs["Value"], bp.inputs["Height"]); Lk(bp.outputs["Normal"], wb.inputs["Normal"])
    fall, fb = mat("Fall", (0.3, 0.5, 0.55), Roughness=0.05, Alpha=0.55)   # lighter than the pools so the streams read
    fb.inputs["Emission Color"].default_value = (0.5, 0.8, 0.9, 1); fb.inputs["Emission Strength"].default_value = 0.08
    foam, _ = mat("Foam", (0.7, 0.8, 0.82), Roughness=0.5, Alpha=0.5)
    ripple, _ = mat("Ripple", (0.5, 0.65, 0.7), Roughness=0.2, Alpha=0.25)
    for m in (water, fall, foam, ripple): m.cycles.emission_sampling = 'NONE'   # (keeps the shadow catcher clean)
    for lvl, r0, r1, _, _ in POOLS:
        obj("Water", ring(r0, r1 + R(0.6), lvl), water)   # a little under the walls

    def stream(a, r0, z0, r1, z1, w, t, n=12):
        obj("Fall", ribbon(arc(a, r0, z0, r1, z1, n), w, t), fall)
        p = Vector((math.cos(a), math.sin(a), 0))*r1   # foam where it lands and a ripple ring round it
        obj("Foam", ring(0, w*1.1, z1 + 0.002, 20), foam).location = (p.x, p.y, 0)
        obj("Ripple", ring(w*2.0, w*2.4, z1 + 0.002, 24), ripple).location = (p.x, p.y, 0)

    for k in range(4):                              # spouts from the spire's bulb into the top bowl
        stream(math.tau*(k + 0.125)/4, R(11.5), Z(66.0), R(14.2), POOLS[0][0], 0.006, 0.005, 8)
    for i, n in ((0, 6), (1, 8)):                   # the upper bowls spill over their lips into the bowl below
        _, _, _, lr, lz = POOLS[i]; below, b0, b1 = POOLS[i+1][:3]
        for k in range(n):
            stream(math.tau*(k + 0.5*(i % 2))/n, lr - R(1.5), lz + R(1.0), b0 + (b1 - b0)*0.35, below, 0.014, 0.006)
else:
    grime, _ = mat("Grime", (0.06, 0.055, 0.045), Roughness=0.95, Alpha=0.5)   # dark stain where the water stood
    for z, r0, r1 in FLOORS:
        obj("Silt", ring(r0, r1, z + 0.002), grime)
    tex = bpy.data.materials["GardenFountainBase"]
    for k in range(11):                             # fallen bits of the lips: rubble in the lower bowl and on the plinth
        lower = k < 4
        a = rnd.uniform(0, math.tau); d = rnd.uniform(0.33, 0.52) if lower else rnd.uniform(0.6, 0.9)
        s = rnd.uniform(0.03, 0.06)
        bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1)
        for v in bm.verts:
            v.co = Vector((v.co.x*s, v.co.y*s*rnd.uniform(0.7, 1.1), v.co.z*s*0.6))*rnd.uniform(0.8, 1.15)
        z = FLOORS[2][0] if lower else FLOORS[3][0]
        bm.transform(Matrix.Translation((d*math.cos(a), d*math.sin(a), z + s*0.35)) @ Matrix.Rotation(rnd.uniform(0, math.tau), 4, 'Z'))
        obj("Rubble", bm, tex, smooth=False)

gp = bmesh.new(); bmesh.ops.create_grid(gp, x_segments=1, y_segments=1, size=10)
gm = bpy.data.meshes.new("Ground"); gp.to_mesh(gm); gp.free()
link(sc, "Ground", gm).is_shadow_catcher = True

rig(sc, tgt=Vector((0, 0, 0.6)), elev=P["elev"])
sc.camera.data.lens = 68                          # same scale as the stairs
studio_world(sc, 0.5)
spot(sc, (-3, -4, 4), 150, (1, 0.95, 0.85), tgt=Vector((0, 0, 0.5))); spot(sc, (3, -3, 3), 80, (1, 1, 1), tgt=Vector((0, 0, 0.5)))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 5; sun.angle = math.radians(6)
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(32), 0, math.radians(-40))
for l in bpy.data.lights:                          # only the sun darkens the ground (see build_throne.py)
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False
render(sc, OUT, P["save_blend"], samples=128)
