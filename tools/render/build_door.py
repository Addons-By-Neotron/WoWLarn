"""Build + render a massive double door in a stone frame, head on.  Usage:
blender -b -P build_door.py -- out.png '{"style":"wood", "open":false, ...}'
The frame: stacked stone blocks for the jambs, a lintel with a keystone and a threshold, darkness behind the opening;
it is
square (as wide as it is tall) and casts no shadow: the icon is a piece of wall, filled edge to edge.
style: wood  - dark planks, iron bands with studs, ring pulls
       stone - heavy slabs carved with raised panels, iron ring pulls
       iron  - rusty riveted plates with straps, ring pulls
open: the two leaves swung in, away from the viewer.
leaves: only the two leaves, no frame (the game's 3D view draws the frame as geometry); writes OUT.box, the
        opening's corners in px of the render, for runner's fill="box" crop.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, rock_material, studio_world, spot, wood_material

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "door.png"
P = dict(style="wood", open=False, swing=72, stone=(0.12, 0.12, 0.125), rock_scale=0.6, wood=(0.05, 0.028, 0.015),
         elev=5, leaves=False, seed=4, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rnd = random.Random(P["seed"])

root = bpy.data.objects.new("Door", None); sc.collection.objects.link(root)

def obj(name, bm, material, parent=root, bevel=0.0, smooth=False):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = parent; o.data.materials.append(material)
    if bevel:
        m = o.modifiers.new("Bevel", 'BEVEL'); m.width = bevel; m.segments = 2; m.limit_method = 'ANGLE'
    return o

def box(x0, x1, y0, y1, z0, z1):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1)
    bm.transform(Matrix.Translation(((x0 + x1)/2, (y0 + y1)/2, (z0 + z1)/2)) @ Matrix.Diagonal((x1 - x0, y1 - y0, z1 - z0, 1)))
    return bm

def stud(x, y, z, r=0.022):
    """A domed nail head / rivet on a front face (facing -y)."""
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=10, v_segments=6, radius=r)
    bm.transform(Matrix.Translation((x, y, z)) @ Matrix.Diagonal((1, 0.5, 1, 1)))
    return bm

def ring(x, y, z, R=0.09, r=0.014):
    """A ring pull hanging from a boss on a front face."""
    bm = bmesh.new(); segs, tseg = 24, 8
    vs = [[bm.verts.new((x + (R + r*math.cos(v))*math.cos(u), y - 0.03 + r*math.sin(v), z - R + (R + r*math.cos(v))*math.sin(u)))
           for v in (math.tau*j/tseg for j in range(tseg))] for u in (math.tau*i/segs for i in range(segs))]
    for i in range(segs):
        for j in range(tseg):
            bm.faces.new((vs[i][j], vs[(i+1) % segs][j], vs[(i+1) % segs][(j+1) % tseg], vs[i][(j+1) % tseg]))
    boss = bmesh.new(); bmesh.ops.create_cone(boss, cap_ends=True, segments=16, radius1=0.045, radius2=0.035, depth=0.03)
    boss.transform(Matrix.Translation((x, y - 0.015, z)) @ Matrix.Rotation(math.pi/2, 4, 'X'))
    return bm, boss

# ---- materials
stone, _ = rock_material("Stone", P["stone"], P["rock_scale"])
iron, _ = mat("Iron", (0.05, 0.05, 0.055), Metallic=0.7, Roughness=0.55)
if P["style"] == "wood":
    leaf_mat = wood_material("Wood", P["wood"], axis="Z", roughness=0.85)
    leaf_mat.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.2
elif P["style"] == "stone":
    leaf_mat, _ = rock_material("Slab", (0.09, 0.085, 0.08), P["rock_scale"])   # darker, warmer than the frame
else:                                              # rusty iron: dark metal with patches of rust
    leaf_mat, lb = mat("Rust", (0.06, 0.055, 0.05), Roughness=0.6)
    nt = leaf_mat.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 5; nz.inputs["Detail"].default_value = 12; nz.inputs["Roughness"].default_value = 0.65
    Lk(tc.outputs["Object"], nz.inputs["Vector"])
    cr = N("ShaderNodeValToRGB"); Lk(nz.outputs["Fac"], cr.inputs[0]); el = cr.color_ramp.elements
    el[0].position, el[0].color = 0.35, (0.035, 0.033, 0.032, 1); el[1].position, el[1].color = 0.75, (0.07, 0.03, 0.013, 1)
    Lk(cr.outputs["Color"], lb.inputs["Base Color"])
    mr = N("ShaderNodeMapRange"); mr.inputs["From Min"].default_value = 0.4; mr.inputs["From Max"].default_value = 0.6
    mr.inputs["To Min"].default_value = 0.35; mr.inputs["To Max"].default_value = 0.0; Lk(nz.outputs["Fac"], mr.inputs["Value"])
    Lk(mr.outputs["Result"], lb.inputs["Metallic"])
    rr = N("ShaderNodeMapRange"); rr.inputs["From Min"].default_value = 0.4; rr.inputs["From Max"].default_value = 0.6
    rr.inputs["To Min"].default_value = 0.5; rr.inputs["To Max"].default_value = 0.9; Lk(nz.outputs["Fac"], rr.inputs["Value"])
    Lk(rr.outputs["Result"], lb.inputs["Roughness"])
    gr = N("ShaderNodeTexNoise"); gr.inputs["Scale"].default_value = 40; Lk(tc.outputs["Object"], gr.inputs["Vector"])
    bp = N("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.3; Lk(gr.outputs["Fac"], bp.inputs["Height"])
    Lk(bp.outputs["Normal"], lb.inputs["Normal"])
    iron, _ = mat("Strap", (0.025, 0.024, 0.023), Metallic=0.6, Roughness=0.6)   # straps and rivets: darker, less rusted

# ---- the frame round an opening 2W wide and H high
W, H, T = 1.0, 2.8, 0.14                           # leaf width (half the opening), height, thickness
J, FD = 0.65, 0.3                                  # jamb width (frame as wide as it is tall), frame half-depth
if not P["leaves"]:                                # leaves only: the game draws the frame itself
    for s in (-1, 1):                                  # jambs: four stacked blocks each
        z = 0.0
        for k, hk in enumerate((0.75, 0.65, 0.75, 0.65)):
            x0, x1 = sorted((s*W, s*(W + J)))
            obj("Jamb", box(x0, x1, -FD, FD, z + 0.006, z + hk - 0.006), stone, bevel=0.025); z += hk
    lw = (2*(W + J))/3
    for k in range(3):                                 # lintel; the middle block is the keystone, taller and proud
        x0 = -(W + J) + k*lw
        if k == 1:
            obj("Key", box(x0 + 0.006, x0 + lw - 0.006, -FD - 0.05, FD, H + 0.006, H + 0.5), stone, bevel=0.03)
        else:
            obj("Lintel", box(x0 + 0.006, x0 + lw - 0.006, -FD, FD, H + 0.006, H + 0.5), stone, bevel=0.025)
    obj("Sill", box(-W - 0.02, W + 0.02, -FD - 0.06, FD, 0.0, 0.05), stone, bevel=0.015)
    black, bb = mat("Black", (0, 0, 0), Roughness=1.0); bb.inputs["Specular IOR Level"].default_value = 0.0
    obj("Void", box(-W - 0.05, W + 0.05, 1.2, 1.25, 0.0, H + 0.05), black)   # darkness beyond the open leaves

# ---- the leaves, each built hinge-at-origin spanning x 0..W, front face at y = -T/2
def leaf():
    F = -T/2
    if P["style"] == "wood":
        n = 5; pw = W/n
        for k in range(n):
            yield box(k*pw + 0.005, (k + 1)*pw - 0.005, -T/2, T/2, 0.05, H - 0.005), leaf_mat, 0.008
        for zb in (0.45, 1.4, 2.35):               # iron bands with a row of studs
            yield box(0.0, W - 0.03, F - 0.018, F, zb - 0.065, zb + 0.065), iron, 0.006
            for k in range(6):
                yield stud(0.08 + k*(W - 0.2)/5, F - 0.018, zb), iron, 0
    elif P["style"] == "stone":
        yield box(0.005, W - 0.005, -T/2, T/2, 0.05, H - 0.005), leaf_mat, 0.012
        for z0, z1 in ((0.25, 1.3), (1.5, 2.6)):   # raised carved panels: a frame and a raised centre
            for x0, x1, a, b in ((0.12, W - 0.12, z0, z0 + 0.07), (0.12, W - 0.12, z1 - 0.07, z1),
                                 (0.12, 0.19, z0, z1), (W - 0.19, W - 0.12, z0, z1)):
                yield box(x0, x1, F - 0.035, F, a, b), leaf_mat, 0.01
            yield box(0.26, W - 0.26, F - 0.02, F, z0 + 0.14, z1 - 0.14), leaf_mat, 0.012
    else:
        yield box(0.005, W - 0.005, -T/2, T/2, 0.05, H - 0.005), leaf_mat, 0.006
        bars = [(0.0, 0.1, 0.05, H - 0.005), (W - 0.1, W - 0.005, 0.05, H - 0.005)] + \
               [(0.0, W - 0.005, z - 0.06, z + 0.06) for z in (0.25, 1.4, 2.6)]
        for x0, x1, z0, z1 in bars:                # riveted straps: stiles at the edges, three rails
            yield box(x0, x1, F - 0.025, F, z0, z1), iron, 0.006
        for x in (0.05, W - 0.055):
            for k in range(12):
                yield stud(x, F - 0.025, 0.12 + k*(H - 0.25)/11, 0.016), iron, 0
        for z in (0.25, 1.4, 2.6):
            for k in range(6):
                yield stud(0.16 + k*(W - 0.32)/5, F - 0.025, z, 0.016), iron, 0
    rb, boss = ring(W - 0.17, F - (0.02 if P["style"] != "stone" else 0.0), 1.45)
    yield rb, iron, 0
    yield boss, iron, 0

for s in (-1, 1):                                  # hinges at the jambs; the right leaf is the left one mirrored
    hinge = bpy.data.objects.new("Hinge", None); sc.collection.objects.link(hinge); hinge.parent = root
    hinge.location = (s*W, 0, 0); hinge.scale = (-s, 1, 1)
    if P["open"]:
        hinge.rotation_euler = (0, 0, math.radians(-s*P["swing"]))   # both swing in, away from the viewer
    for bm, m, bev in leaf():
        obj("Leaf", bm, m, parent=hinge, bevel=bev, smooth=(bev == 0))

rig(sc, tgt=Vector((0, 0, 1.65)), elev=P["elev"])
sc.camera.data.lens = 62                          # wide enough for the whole frame
if P["leaves"]:                                    # the opening in px of the render: the crop
    from bpy_extras.object_utils import world_to_camera_view
    sc.render.resolution_x = sc.render.resolution_y = 512; bpy.context.view_layer.update()   # (the camera's matrix)
    pts = [world_to_camera_view(sc, sc.camera, Vector((x, -T/2, z))) for x in (-W, W) for z in (0.0, H)]
    xs = [p.x*512 for p in pts]; ys = [(1 - p.y)*512 for p in pts]
    with open(OUT + ".box", "w") as f: json.dump([round(min(xs)), round(min(ys)), round(max(xs)), round(max(ys))], f)
studio_world(sc, 0.4)
spot(sc, (-3, -4, 4), 150, (1, 0.95, 0.85), tgt=Vector((0, 0, 1.4))); spot(sc, (3, -3, 3), 80, (1, 1, 1), tgt=Vector((0, 0, 1.4)))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 4; sun.angle = math.radians(6)
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(40), 0, math.radians(-30))
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False
render(sc, OUT, P["save_blend"], samples=128)
