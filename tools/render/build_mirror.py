"""Build + render a standing (cheval) mirror on the ground (with a shadow).  Usage:
blender -b -P build_mirror.py -- out.png '{"yaw":45, "elev":20, ...}'
An oval mirror in a wooden frame, tilted back a little on pivots between two turned posts; the posts stand on
cross feet joined by a stretcher, with gilt finials.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, studio_world, spot, wood_material

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "mirror.png"
P = dict(wood=(0.06, 0.028, 0.013), gold=(0.95, 0.68, 0.25), tilt=8, yaw=45, elev=20, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

root = bpy.data.objects.new("Mirror", None); sc.collection.objects.link(root)

def obj(name, bm, material, parent=root, bevel=0.0, smooth=True):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = parent; o.data.materials.append(material)
    if bevel:
        m = o.modifiers.new("Bevel", 'BEVEL'); m.width = bevel; m.segments = 2; m.limit_method = 'ANGLE'
    return o

def lathe(profile, segs=24, m=Matrix()):
    """Revolve an (r, z) profile, from the axis round to the axis, about Z; then transform by m."""
    bm = bmesh.new()
    rings = [[bm.verts.new((r*math.cos(a), r*math.sin(a), z)) for a in (math.tau*k/segs for k in range(segs))] for r, z in profile]
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k+1) % segs], r1[(k+1) % segs], r1[k]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.transform(m)
    return bm

def rod(p0, p1, r, segs=16):
    """Plain cylinder from p0 to p1."""
    d = p1 - p0
    return lathe([(0, 0), (r, 0), (r, d.length), (0, d.length)], segs, Matrix.Translation(p0) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4())

def ring_tube(pts, r, segs=10):
    """Closed round tube through a loop of Vectors."""
    bm = bmesh.new(); n = len(pts); rings = []
    for i, p in enumerate(pts):
        t = (pts[(i+1) % n] - pts[i-1]).normalized(); u = Vector((0, 1, 0)); v = t.cross(u)
        rings.append([bm.verts.new(p + r*(math.cos(a)*u + math.sin(a)*v)) for a in (math.tau*k/segs for k in range(segs))])
    for i in range(n):
        r0, r1 = rings[i], rings[(i+1) % n]
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k+1) % segs], r1[(k+1) % segs], r1[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def oval(a, b, n=64):
    return [Vector((a*math.cos(t), 0, b*math.sin(t))) for t in (math.tau*k/n for k in range(n))]

def slab(pts, y0, y1):
    """Extrude a loop of XZ points from y0 back to y1."""
    bm = bmesh.new()
    fr = [bm.verts.new((p.x, y0, p.z)) for p in pts]; bk = [bm.verts.new((p.x, y1, p.z)) for p in pts]
    bm.faces.new(fr); bm.faces.new(bk[::-1])
    for k in range(len(pts)):
        bm.faces.new((fr[k], bk[k], bk[(k+1) % len(pts)], fr[(k+1) % len(pts)]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

wood = wood_material("Wood", P["wood"], axis="Z", roughness=0.45)       # polished
woodx = wood_material("WoodX", P["wood"], axis="X", roughness=0.45)
gold, _ = mat("Gold", P["gold"], Metallic=1.0, Roughness=0.3)
# a true mirror only shows the studio bands at icon size: fake it with a diagonal blue-silver sheen under a soft gloss
glass, gb = mat("Glass", (0.6, 0.7, 0.78), Roughness=0.15)
nt = glass.node_tree; N = nt.nodes.new; Lk = nt.links.new
tc = N("ShaderNodeTexCoord"); sk = N("ShaderNodeMapping"); sk.inputs["Rotation"].default_value = (0, math.radians(-35), 0)
sk.inputs["Scale"].default_value = (1.4, 1, 1.4); Lk(tc.outputs["Object"], sk.inputs["Vector"])
gr = N("ShaderNodeTexGradient"); Lk(sk.outputs["Vector"], gr.inputs["Vector"])
sr = N("ShaderNodeValToRGB"); Lk(gr.outputs["Fac"], sr.inputs[0]); el = sr.color_ramp.elements
el[0].position, el[0].color = 0.25, (0.16, 0.22, 0.3, 1); el[1].position, el[1].color = 0.75, (0.16, 0.22, 0.3, 1)
for pos, c in ((0.42, (0.7, 0.8, 0.88, 1)), (0.5, (0.85, 0.92, 0.97, 1)), (0.56, (0.45, 0.55, 0.65, 1))):
    e = el.new(pos); e.color = c                    # a bright streak across the middle
Lk(sr.outputs["Color"], gb.inputs["Base Color"])

# ---- the swinging mirror, built round its pivot and tilted back
A, B, ZC, X = 0.36, 0.58, 1.1, 0.5                 # oval half-width/-height, pivot height, post x
swing = bpy.data.objects.new("Swing", None); sc.collection.objects.link(swing); swing.parent = root
swing.location = (0, 0, ZC); swing.rotation_euler = (math.radians(-P["tilt"]), 0, 0)
obj("Glass", slab(oval(A, B), -0.012, 0.0), glass, swing)
obj("Back", slab(oval(A + 0.03, B + 0.03), 0.0, 0.035), woodx, swing)
obj("Frame", ring_tube(oval(A + 0.025, B + 0.025), 0.04), wood, swing)
obj("Crest", lathe([(0, 0), (0.05, 0.02), (0.035, 0.06), (0.05, 0.09), (0, 0.13)], 16, Matrix.Translation((0, 0, B + 0.05))), gold, swing)
for s in (-1, 1):                                   # pivot pins into the posts
    obj("Pin", rod(Vector((s*(A + 0.05), 0, 0)), Vector((s*(X - 0.02), 0, 0)), 0.018), gold, swing)

# ---- posts on cross feet, a stretcher between them, finials on top
post = [(0, 0.08), (0.055, 0.08), (0.05, 0.18), (0.032, 0.24), (0.034, 0.85), (0.05, 0.92), (0.034, 0.98), (0.032, 1.55),
        (0.05, 1.62), (0.04, 1.68), (0, 1.7)]
for s in (-1, 1):
    obj("Post", lathe(post, 20, Matrix.Translation((s*X, 0, 0))), wood)
    obj("Finial", lathe([(0, 0), (0.03, 0.01), (0.045, 0.05), (0.03, 0.09), (0.012, 0.12), (0, 0.13)], 16, Matrix.Translation((s*X, 0, 1.69))), gold)
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    bm.transform(Matrix.Translation((s*X, 0, 0.045)) @ Matrix.Diagonal((0.08, 0.7, 0.09, 1)))
    obj("Foot", bm, woodx, bevel=0.02, smooth=False)
    for y in (-0.33, 0.33):
        obj("Toe", lathe([(0, 0), (0.04, 0), (0.045, 0.02), (0.03, 0.04), (0, 0.04)], 12, Matrix.Translation((s*X, y, -0.005))), gold)
obj("Stretcher", rod(Vector((-X, 0, 0.3)), Vector((X, 0, 0.3)), 0.022), woodx)

gp = bmesh.new(); bmesh.ops.create_grid(gp, x_segments=1, y_segments=1, size=10)
gm = bpy.data.meshes.new("Ground"); gp.to_mesh(gm); gp.free()
link(sc, "Ground", gm).is_shadow_catcher = True

root.rotation_euler = (0, 0, math.radians(P["yaw"]))
rig(sc, tgt=Vector((0, 0, 0.9)), elev=P["elev"])
studio_world(sc, 0.5)
spot(sc, (-3, -4, 4), 150, (1, 0.95, 0.85), tgt=Vector((0, 0, 0.9))); spot(sc, (3, -3, 3), 80, (1, 1, 1), tgt=Vector((0, 0, 0.9)))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 4; sun.angle = math.radians(6)
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(30), 0, math.radians(-40))
for l in bpy.data.lights:                          # only the sun darkens the ground (see build_throne.py)
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False
render(sc, OUT, P["save_blend"], samples=128)
