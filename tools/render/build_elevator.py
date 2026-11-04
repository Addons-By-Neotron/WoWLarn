"""Build + render an express elevator: a wooden lift platform (with a shadow).  Usage:
blender -b -P build_elevator.py -- out.png '{"down":false, "elev":45, ...}'
The lift: a plank deck on bearers, a post at each corner and a railing with V braces on the left and right.
up:   the lift stands on a stone platform: the same frame as the down shaft, paved inside; a chain from each post top runs to a ring overhead, one chain rises from the ring
      and fades into the dark above.
down: the lift hangs over a square shaft in a stone frame (the dark shaft shows round it) from a simple gantry at
      the back: chains to a pulley on its arms and back to a winch drum with a gear and a crank.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, rock_material, studio_world, spot, wood_material

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "elevator.png"
P = dict(down=False, stone=(0.2, 0.2, 0.21), rock_scale=0.6, wood=(0.03, 0.017, 0.009), elev=90, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

root = bpy.data.objects.new("Elevator", None); sc.collection.objects.link(root)

def obj(name, bm, material, bevel=0.0, smooth=False):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = root; o.data.materials.append(material)
    if bevel:
        m = o.modifiers.new("Bevel", 'BEVEL'); m.width = bevel; m.segments = 2; m.limit_method = 'ANGLE'
    return o

def beam(p0, p1, w, h):
    """Box of cross-section w x h from p0 to p1."""
    p0, p1 = Vector(p0), Vector(p1); d = p1 - p0
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    bm.transform(Matrix.Translation((p0 + p1)/2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4() @ Matrix.Diagonal((w, h, d.length, 1)))
    return bm

def prism(outline, z0, z1):
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, z0)) for x, y in outline]; hi = [bm.verts.new((x, y, z1)) for x, y in outline]
    n = len(outline)
    bm.faces.new(lo[::-1]); bm.faces.new(hi)
    for k in range(n):
        bm.faces.new((lo[k], lo[(k+1) % n], hi[(k+1) % n], hi[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def rect(x0, x1, y0, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]

def loop(bm, pts, nrm, rw, segs=6):
    """Closed round tube through pts (a link or ring lying in the plane with normal nrm)."""
    n = len(pts); rings = []
    for i, p in enumerate(pts):
        t = (pts[(i+1) % n] - pts[i-1]).normalized(); b = t.cross(nrm)
        rings.append([bm.verts.new(p + rw*(math.cos(f)*nrm + math.sin(f)*b)) for f in (math.tau*k/segs for k in range(segs))])
    for i in range(n):
        r0, r1 = rings[i], rings[(i+1) % n]
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k+1) % segs], r1[(k+1) % segs], r1[k]))

def chain(bm, a, b, L=0.18, W=0.11, rw=0.025):
    """Interlocking oval links from a to b, each turned 90 degrees to the last."""
    a, b = Vector(a), Vector(b); d = b - a; pitch = L - 4*rw
    n = max(1, round(d.length/pitch)); d.normalize()
    u = d.orthogonal().normalized(); v = d.cross(u)
    R = W/2 - rw; hs = L/2 - rw - R                 # end radius, half the straight part (centre line)
    arc = [(R*math.cos(t), hs + R*math.sin(t)) for t in (math.pi*k/8 for k in range(9))] + \
          [(R*math.cos(t), -hs + R*math.sin(t)) for t in (math.pi + math.pi*k/8 for k in range(9))]
    for i in range(n):
        c = a + d*pitch*(i + 0.5); side = u if i % 2 == 0 else v
        loop(bm, [c + side*x + d*y for x, y in arc], side.cross(d), rw)

def cyl(p0, p1, r, segs=20):
    """Cylinder of radius r from p0 to p1."""
    p0, p1 = Vector(p0), Vector(p1); d = p1 - p0
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=d.length)
    bm.transform(Matrix.Translation((p0 + p1)/2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4())
    return bm

# ---- materials
wx, wy, wz = (wood_material("Wood" + k, P["wood"], axis=k, roughness=0.9) for k in "XYZ")
for m in (wx, wy, wz):                            # weathered, not varnished: no grey studio sheen
    m.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.2
iron, ib = mat("Iron", (0.07, 0.045, 0.03), Metallic=0.6, Roughness=0.7)       # rusty
nt = iron.node_tree; N = nt.nodes.new; Lk = nt.links.new
tc = N("ShaderNodeTexCoord"); sz = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sz.inputs[0])
fd = N("ShaderNodeMapRange"); fd.inputs["From Min"].default_value, fd.inputs["From Max"].default_value = (98, 99) if P["down"] else (1.5, 2.8)
Lk(sz.outputs["Z"], fd.inputs["Value"])            # up: the chain fades into the dark above, like the up stairs
ms = N("ShaderNodeMixShader"); em = N("ShaderNodeEmission"); em.inputs["Color"].default_value = (0, 0, 0, 1)
Lk(fd.outputs["Result"], ms.inputs[0]); Lk(ib.outputs[0], ms.inputs[1]); Lk(em.outputs[0], ms.inputs[2])
Lk(ms.outputs[0], nt.nodes["Material Output"].inputs["Surface"])

# ---- the lift, its deck bottom at z0
Q, PH = 0.62, 0.62                                 # post centres at (+-Q, +-Q), post height
def lift(z0):
    for y in (-0.5, 0.0, 0.5):                     # bearers under the deck
        obj("Bearer", beam((-Q, y, z0 + 0.03), (Q, y, z0 + 0.03), 0.08, 0.06), wx, bevel=0.008)
    NP = 7; pw = 1.2/NP
    for k in range(NP):                            # planks running front to back
        x0 = -0.6 + k*pw
        obj("Plank", prism(rect(x0 + 0.006, x0 + pw - 0.006, -0.6, 0.6), z0 + 0.06, z0 + 0.1), wy, bevel=0.008)
    for x in (-Q, Q):
        for y in (-Q, Q):
            obj("Post", beam((x, y, z0), (x, y, z0 + PH), 0.1, 0.1), wz, bevel=0.012)
            bm = bmesh.new(); loop(bm, [Vector((x + 0.04*math.cos(t), y, z0 + PH + 0.05 + 0.04*math.sin(t))) for t in (math.tau*k/12 for k in range(12))],
                                   Vector((0, 1, 0)), 0.014)
            obj("Eye", bm, iron, smooth=True)
        obj("Rail", beam((x, -Q, z0 + 0.5), (x, Q, z0 + 0.5), 0.045, 0.1), wy, bevel=0.008)
        for y in (-Q + 0.06, Q - 0.06):            # V braces under the rail
            obj("Brace", beam((x, y, z0 + 0.12), (x, 0, z0 + 0.46), 0.035, 0.07), wz, bevel=0.006)
    return z0 + PH + 0.05                          # height of the chain eyes

def hang(bm, top, rz):
    """A chain from each post's eye up to a ring at height rz."""
    for x in (-Q, Q):
        for y in (-Q, Q):
            chain(bm, (x, y, top + 0.03), (0.07*math.copysign(1, x), 0.07*math.copysign(1, y), rz - 0.02))
    loop(bm, [Vector((0.09*math.cos(t), 0.09*math.sin(t), rz)) for t in (math.tau*k/16 for k in range(16))], Vector((0, 0, 1)), 0.028)

# ---- square stone frame round the lift (the same for both, so the pair match)
frame, ftint = rock_material("Frame", P["stone"], P["rock_scale"], fade=(0.0, -0.8))
D, F = 0.85, 1.1
for outline in (rect(-F, F, -F, -D), rect(-F, F, D, F), rect(-F, -D, -D, D), rect(D, F, -D, D)):
    obj("Frame", prism(outline, -1.2, 0.05), frame, bevel=0.02)

ground = bmesh.new()
if not P["down"]:
    floor = frame.copy()                           # paved floor inside the frame, a little darker
    floor.node_tree.nodes[ftint.name].inputs["B"].default_value = (*[c*0.7 for c in P["stone"]], 1)
    obj("Floor", prism(rect(-D, D, -D, D), -0.05, 0.02), floor, bevel=0.01)
    top = lift(0.02)
    RZ = 1.9                                       # the ring the four chains meet at
    bm = bmesh.new(); hang(bm, top, RZ)
    chain(bm, (0, 0, RZ + 0.11), (0, 0, 4.0))
    obj("Chains", bm, iron, smooth=True)
    bmesh.ops.create_grid(ground, x_segments=1, y_segments=1, size=10)
    tgt = Vector((0, 0, 0.6))
else:
    # the shaft inside the frame: its walls fade to black with depth
    black, _ = mat("Black", (0, 0, 0), Roughness=1.0)
    obj("Shaft", prism(rect(-D, D, -D, D), -1.22, -1.2), black)
    top = lift(0.02)                               # hanging over the shaft at floor level
    # a simple gantry at the back: two posts on the frame, arms reaching over the shaft to a pulley,
    # braces under the arms, and a winch drum with a gear and a crank between the posts
    YB, GX, GZ = (D + F)/2, 0.42, 1.85
    for x in (-GX, GX):
        obj("Gantry", beam((x, YB, 0.05), (x, YB, GZ + 0.06), 0.13, 0.13), wz, bevel=0.012)
        obj("Arm", beam((x, YB + 0.12, GZ), (x, -0.2, GZ), 0.11, 0.13), wy, bevel=0.012)
        obj("Brace", beam((x, YB - 0.03, 1.2), (x, 0.35, GZ - 0.04), 0.07, 0.09), wz, bevel=0.008)
    obj("Tie", beam((-GX - 0.08, -0.15, GZ + 0.05), (GX + 0.08, -0.15, GZ + 0.05), 0.08, 0.08), wx, bevel=0.008)
    obj("Pulley", cyl((-0.04, -0.05, GZ - 0.08), (0.04, -0.05, GZ - 0.08), 0.1), iron)
    obj("Axle", cyl((-GX, -0.05, GZ - 0.08), (GX, -0.05, GZ - 0.08), 0.02, 10), iron)
    obj("Drum", cyl((-GX + 0.07, YB, 0.75), (GX - 0.07, YB, 0.75), 0.1), wx)
    obj("Axle", cyl((-GX - 0.16, YB, 0.75), (GX + 0.12, YB, 0.75), 0.025, 10), iron)
    obj("Gear", cyl((GX + 0.08, YB, 0.75), (GX + 0.12, YB, 0.75), 0.2, 28), iron)
    for k in range(14):                            # the gear's teeth
        a = math.tau*k/14; c = Vector((GX + 0.1, YB + 0.22*math.cos(a), 0.75 + 0.22*math.sin(a)))
        obj("Tooth", beam(c - Vector((0.02, 0, 0)), c + Vector((0.02, 0, 0)), 0.05, 0.05), iron)
    obj("Crank", beam((-GX - 0.16, YB, 0.75), (-GX - 0.16, YB - 0.18, 0.63), 0.03, 0.03), iron)
    obj("Handle", cyl((-GX - 0.16, YB - 0.18, 0.63), (-GX - 0.3, YB - 0.18, 0.63), 0.02, 10), wx)
    RZ = 1.3
    bm = bmesh.new(); hang(bm, top, RZ)
    chain(bm, (0, 0, RZ + 0.11), (0, 0, GZ - 0.2))                  # up to the pulley...
    chain(bm, (0, -0.02, GZ + 0.04), (0, YB - 0.05, 0.85))             # ...and back over it to the drum
    obj("Chains", bm, iron, smooth=True)
    verts = [ground.verts.new(p) for p in ((-10, -10, 0), (10, -10, 0), (10, 10, 0), (-10, 10, 0))]
    hole = [ground.verts.new((x, y, 0)) for x, y in rect(-F, F, -F, F)]
    for k in range(4):
        ground.faces.new((verts[k], verts[(k+1) % 4], hole[(k+1) % 4], hole[k]))
    tgt = Vector((0, 0, 0.3))

gm = bpy.data.meshes.new("Ground"); ground.to_mesh(gm); ground.free()
link(sc, "Ground", gm).is_shadow_catcher = True

rig(sc, tgt=tgt, elev=P["elev"])
sc.camera.data.lens = 68                          # same scale as the stairs and traps
studio_world(sc, 0.4)
spot(sc, (-3, -4, 4), 150, (1, 0.95, 0.85), tgt=Vector((0, 0, 0))); spot(sc, (3, -3, 3), 80, (1, 1, 1), tgt=Vector((0, 0, 0)))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 5; sun.angle = math.radians(6)
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(32), 0, math.radians(-40))
for l in bpy.data.lights:                          # only the sun darkens the ground (see build_throne.py)
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False                                # also keeps the shaft dark
render(sc, OUT, P["save_blend"], samples=128)
