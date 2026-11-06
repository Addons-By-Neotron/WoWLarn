"""Build + render the great marble statue standing on the ground (with a shadow).  Usage:
blender -b -P build_statue.py -- out.png '{"elev":20, "yaw":0, ...}'
The model is Poly Haven's Gothic Statue by Benny Weimer (CC0, models/gothic_statue, see CREDITS.md): a robed,
veiled, crowned figure with chains, a book and a sword.  Its own carving (the normal map) is kept, but it is
re-surfaced as polished white marble (ambientCG Marble012, CC0), with the model's weathering only darkening the
deep folds a little.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "statue.png"
P = dict(tint=(0.9, 0.87, 0.8), marble_scale=0.6, height=3.0, grime=0.4, yaw=-20, elev=20, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "models", "gothic_statue")

# ---- the model: linked in from its .blend (only the object: nothing in the file runs)
with bpy.data.libraries.load(os.path.join(MODEL, "gothic_statue_1k.blend")) as (src, dst):
    dst.objects = ["gothic_statue"]
statue = dst.objects[0]; sc.collection.objects.link(statue)
root = bpy.data.objects.new("Statue", None); sc.collection.objects.link(root)
bpy.context.view_layer.update()
bb = [statue.matrix_world @ Vector(c) for c in statue.bound_box]
lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
k = P["height"]/(hi.z - lo.z)                      # its base on the ground at the middle, P["height"] tall
statue.location = (statue.location - Vector(((lo.x + hi.x)/2, (lo.y + hi.y)/2, lo.z)))*k
statue.scale = (k, k, k); statue.parent = root
for poly in statue.data.polygons: poly.use_smooth = True

# ---- marble over its own carving
stone, sb = mat("Marble", (1, 1, 1))
nt = stone.node_tree; N = nt.nodes.new; Lk = nt.links.new
def image(name, colour=True):
    img = bpy.data.images.load(os.path.join(MODEL, "textures", name))
    if not colour: img.colorspace_settings.name = "Non-Color"
    return img
uv = N("ShaderNodeTexCoord")
tc = N("ShaderNodeMapping"); tc.inputs["Scale"].default_value = (P["marble_scale"],)*3
Lk(uv.outputs["Object"], tc.inputs["Vector"])
TEX = os.path.join(HERE, "textures", "Marble012_2K-JPG_")
def marble(kind, colour=True):                     # box-projected in object space (the veins run through the stone)
    t = N("ShaderNodeTexImage"); t.image = bpy.data.images.load(TEX + kind + ".jpg")
    if not colour: t.image.colorspace_settings.name = "Non-Color"
    t.projection = 'BOX'; t.projection_blend = 0.25; Lk(tc.outputs["Vector"], t.inputs["Vector"])
    return t
def own(name, colour=True):                        # the model's own maps, on its UVs
    t = N("ShaderNodeTexImage"); t.image = image(name, colour); Lk(uv.outputs["UV"], t.inputs["Vector"])
    return t
col = marble("Color")
dirt = own("gothic_statue_diff_1k.jpg")           # (its moss and grime, as light and dark only)
bw = N("ShaderNodeRGBToBW"); Lk(dirt.outputs["Color"], bw.inputs["Color"])
lift = N("ShaderNodeMapRange"); lift.inputs["From Min"].default_value = 0.05; lift.inputs["From Max"].default_value = 0.45
lift.inputs["To Min"].default_value = 1 - P["grime"]; Lk(bw.outputs["Val"], lift.inputs["Value"])
grime = N("ShaderNodeMix"); grime.data_type = 'RGBA'; grime.blend_type = 'MULTIPLY'; grime.inputs["Factor"].default_value = 1.0
Lk(col.outputs["Color"], grime.inputs["A"]); Lk(lift.outputs["Result"], grime.inputs["B"])
tint = N("ShaderNodeMix"); tint.data_type = 'RGBA'; tint.blend_type = 'MULTIPLY'; tint.inputs["Factor"].default_value = 1.0
tint.inputs["B"].default_value = (*P["tint"], 1); Lk(grime.outputs["Result"], tint.inputs["A"])
Lk(tint.outputs["Result"], sb.inputs["Base Color"])
rgh = marble("Roughness", False)
rr = N("ShaderNodeMapRange"); rr.inputs["To Min"].default_value = 0.5; rr.inputs["To Max"].default_value = 0.75    # honed, not glassy (or it reads as metal)
Lk(rgh.outputs["Color"], rr.inputs["Value"]); Lk(rr.outputs["Result"], sb.inputs["Roughness"])
nrm = own("gothic_statue_nor_gl_1k.exr", False)
nm = N("ShaderNodeNormalMap"); nm.uv_map = "UVMap"; nm.inputs["Strength"].default_value = 0.8
Lk(nrm.outputs["Color"], nm.inputs["Color"]); Lk(nm.outputs["Normal"], sb.inputs["Normal"])
sb.inputs["Subsurface Weight"].default_value = 0.3   # (marble lets a little light in)
sb.inputs["Specular IOR Level"].default_value = 0.2
sb.inputs["Subsurface Radius"].default_value = (0.08, 0.07, 0.06)
statue.data.materials.clear(); statue.data.materials.append(stone)

# ---- ground: shadow catcher
gp = bmesh.new(); bmesh.ops.create_grid(gp, x_segments=1, y_segments=1, size=10)
gme = bpy.data.meshes.new("Ground"); gp.to_mesh(gme); gp.free()
ground = link(sc, "Ground", gme); ground.data.materials.append(mat("Matte", (0.5, 0.5, 0.5), Roughness=1.0, **{"Specular IOR Level": 0.0})[0]); ground.is_shadow_catcher = True   # (matte: a glossy catcher records reflections as a haze)

root.rotation_euler = (0, 0, math.radians(P["yaw"]))
rig(sc, elev=P["elev"])                             # camera angle above the horizon
studio_world(sc, 0.4)
spot(sc, (-3, -4, 4), 110, (1, 0.95, 0.85)); spot(sc, (3, -3, 3), 50, (1, 1, 1))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 4; sun.angle = math.radians(6)   # crisp ground shadow
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(30), 0, math.radians(-40))
# only the sun darkens the ground (as for the throne: the soft lights would leave a faint wide shadow the crop cuts)
for l in bpy.data.lights:
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False
sc.cycles.diffuse_bounces = 0
render(sc, OUT, P["save_blend"], samples=128)
