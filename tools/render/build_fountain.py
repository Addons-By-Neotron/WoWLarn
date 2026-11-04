"""Build + render a stone fountain standing on the ground (with a shadow).  Usage:
blender -b -P build_fountain.py -- out.png '{"dry":false, "elev":45, ...}'
A round basin with a pedestal carrying an upper bowl.  Running: both bowls hold water and streams fall from the
upper bowl's lip into the basin.  Dry: no water, rubble and grime in the basin.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, rock_material, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "fountain.png"
P = dict(dry=False, stone=(0.3, 0.3, 0.31), rock_scale=0.8, water=(0.02, 0.07, 0.08), elev=90, seed=2, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rnd = random.Random(P["seed"])

root = bpy.data.objects.new("Fountain", None); sc.collection.objects.link(root)

def obj(name, bm, material, smooth=True):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = root; o.data.materials.append(material)
    return o

def lathe(profile, segs=64):
    """Revolve an (r, z) profile, from the axis round to the axis, about Z."""
    bm = bmesh.new()
    rings = [[bm.verts.new((r*math.cos(a), r*math.sin(a), z)) for a in (math.tau*k/segs for k in range(segs))] for r, z in profile]
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k+1) % segs], r1[(k+1) % segs], r1[k]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)   # collapse the rings on the axis
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def disk(r, z, segs=64):
    bm = bmesh.new()
    bm.faces.new([bm.verts.new((r*math.cos(a), r*math.sin(a), z)) for a in (math.tau*k/segs for k in range(segs))])
    return bm

def tube(path, r, segs=8):
    """Round tube along a polyline of Vectors."""
    bm = bmesh.new(); rings = []
    for i, p in enumerate(path):
        t = (path[min(i+1, len(path)-1)] - path[max(i-1, 0)]).normalized()
        u = t.orthogonal().normalized(); v = t.cross(u)
        rings.append([bm.verts.new(p + r*(math.cos(a)*u + math.sin(a)*v)) for a in (math.tau*k/segs for k in range(segs))])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k+1) % segs], r1[(k+1) % segs], r1[k]))
    return bm

stone, tint = rock_material("Stone", P["stone"], P["rock_scale"])
WL, WU = 0.27, 0.815                                # water levels: basin, upper bowl
# basin: plinth ring, outer wall with a moulded lip, inner wall, floor
obj("Basin", lathe([(0, 0.0), (1.1, 0.0), (1.12, 0.04), (1.08, 0.07), (1.02, 0.09), (1.0, 0.3), (1.05, 0.32), (1.06, 0.36),
                    (1.02, 0.38), (0.9, 0.38), (0.87, 0.36), (0.86, 0.33), (0.86, 0.1), (0.0, 0.1)]), stone)
# pedestal with a turned shaft and the upper bowl, a finial in the middle
obj("Pedestal", lathe([(0, 0.1), (0.22, 0.1), (0.2, 0.16), (0.14, 0.2), (0.12, 0.26), (0.13, 0.45), (0.11, 0.6), (0.14, 0.66),
                       (0.2, 0.7), (0.36, 0.76), (0.44, 0.8), (0.45, 0.84), (0.42, 0.85), (0.39, 0.83), (0.3, 0.79), (0.0, 0.78)]), stone)
obj("Finial", lathe([(0, 0.78), (0.06, 0.78), (0.05, 0.86), (0.035, 0.9), (0.05, 0.95), (0.03, 1.0), (0.0, 1.02)], segs=24), stone)

if not P["dry"]:
    water, wb = mat("Water", P["water"], Roughness=0.35)   # rough enough not to mirror the studio bands
    wb.inputs["Specular IOR Level"].default_value = 0.4
    nt = water.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord")
    rip = N("ShaderNodeTexWave"); rip.wave_type = 'RINGS'; rip.inputs["Scale"].default_value = 6
    rip.inputs["Distortion"].default_value = 3; Lk(tc.outputs["Object"], rip.inputs["Vector"])
    bp = N("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.15; bp.inputs["Distance"].default_value = 0.01
    Lk(rip.outputs["Fac"], bp.inputs["Height"]); Lk(bp.outputs["Normal"], wb.inputs["Normal"])
    obj("Water", disk(0.865, WL), water)
    obj("WaterUp", disk(0.4, WU, 32), water)
    fall, _ = mat("Fall", (0.22, 0.36, 0.4), Roughness=0.2)   # lighter than the pool so the streams read
    for k in range(8):                              # streams over the upper lip, arcing out into the basin
        a = math.tau*(k + 0.5)/8
        d = Vector((math.cos(a), math.sin(a), 0))
        path = [d*(0.45 + 0.17*t**0.7) + Vector((0, 0, 0.83 - (0.83 - WL)*t*t)) for t in (i/10 for i in range(11))]
        obj("Fall", tube(path, 0.01), fall)
        sp = obj("Splash", disk(0.03, WL + 0.003, 12), fall); sp.location = path[-1].xy.to_3d()
else:
    grime = stone.copy()                            # dark stain where the water stood
    grime.node_tree.nodes[tint.name].inputs["B"].default_value = (*[c*0.4 for c in P["stone"]], 1)
    obj("Silt", disk(0.865, 0.105), grime)
    obj("SiltUp", disk(0.4, 0.785, 32), grime)
    for k in range(9):                              # fallen bits of the lip and rubble in the dry basin
        a = rnd.uniform(0, math.tau); d = rnd.uniform(0.3, 0.8); s = rnd.uniform(0.04, 0.09)
        bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1)
        for v in bm.verts:
            v.co = Vector((v.co.x*s, v.co.y*s*rnd.uniform(0.7, 1.1), v.co.z*s*0.6))*rnd.uniform(0.8, 1.15)
        bm.transform(Matrix.Translation((d*math.cos(a), d*math.sin(a), 0.1 + s*0.4)) @ Matrix.Rotation(rnd.uniform(0, math.tau), 4, 'Z'))
        obj("Rubble", bm, stone, smooth=False)

gp = bmesh.new(); bmesh.ops.create_grid(gp, x_segments=1, y_segments=1, size=10)
gm = bpy.data.meshes.new("Ground"); gp.to_mesh(gm); gp.free()
link(sc, "Ground", gm).is_shadow_catcher = True

rig(sc, tgt=Vector((0, 0, 0.4)), elev=P["elev"])
sc.camera.data.lens = 68                          # same scale as the stairs
studio_world(sc, 0.4)
spot(sc, (-3, -4, 4), 150, (1, 0.95, 0.85), tgt=Vector((0, 0, 0))); spot(sc, (3, -3, 3), 80, (1, 1, 1), tgt=Vector((0, 0, 0)))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 5; sun.angle = math.radians(6)
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(32), 0, math.radians(-40))
for l in bpy.data.lights:                          # only the sun darkens the ground (see build_throne.py)
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False
render(sc, OUT, P["save_blend"], samples=128)
