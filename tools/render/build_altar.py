"""Build + render the holy altar standing on the ground (with a shadow).  Usage:
blender -b -P build_altar.py -- out.png '{"elev":20, "holy":true, ...}'
The model is "Altar - Low Poly Medieval" by Avramania (CC0, models/altar, see CREDITS.md): a stone altar with
cross panels, gold candlesticks, a chalice and an open book.  It is coloured from a palette texture; here its
faces are sorted by that colour into marble (ambientCG Marble012, CC0, in the model's three shades), gold, wax
and cloth, its hard low-poly edges are bevelled, and the candles get flames.  holy: the book's pages glow and a
faint shaft of golden light comes down on it.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "altar.png"
P = dict(height=1.9, tint=(0.72, 0.7, 0.66), marble_scale=0.8, gold=(0.95, 0.68, 0.25), cloth=(0.1, 0.18, 0.45),
         holy=True, pages=1.2, shaft=0.35, flame=6.0, yaw=-20, elev=20, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, "models", "altar")

# ---- the model (a glTF: only meshes, materials and images)
bpy.ops.import_scene.gltf(filepath=os.path.join(MODEL, "scene.gltf"))
altar = next(o for o in sc.objects if o.type == 'MESH')
bpy.context.view_layer.update()
mw = altar.matrix_world.copy()
altar.parent = None; altar.matrix_world = mw                    # off the importer's empties, which then go
for o in [o for o in sc.objects if o.type == 'EMPTY']: bpy.data.objects.remove(o)
me = altar.data
# bake the import's rotation into the mesh, so its local Z is up (the palette lookup and the flames use it)
me.transform(mw); altar.matrix_world = Matrix.Identity(4)
lo = Vector([min(v.co[i] for v in me.vertices) for i in range(3)]); hi = Vector([max(v.co[i] for v in me.vertices) for i in range(3)])
k = P["height"]/(hi.z - lo.z)                      # its base on the ground at the middle, P["height"] tall
me.transform(Matrix.Scale(k, 4) @ Matrix.Translation(-Vector(((lo.x + hi.x)/2, (lo.y + hi.y)/2, lo.z))))

# ---- sort the faces by their palette colour
img = next(i for i in bpy.data.images if "baseColor" in i.name); W, H = img.size; px = img.pixels[:]
uv = me.uv_layers.active.data
def colour(p):
    u = sum(uv[i].uv.x for i in p.loop_indices)/p.loop_total; v = sum(uv[i].uv.y for i in p.loop_indices)/p.loop_total
    j = (min(H - 1, int(v*H))*W + min(W - 1, int(u*W)))*4
    return tuple(round(px[j + c]*255) for c in range(3))
KIND = {(143, 149, 154): "stone", (110, 116, 121): "trim", (86, 92, 99): "recess", (217, 166, 46): "gold",
        (232, 222, 198): "wax", (36, 33, 30): "wick", (34, 57, 98): "cloth"}
PAGE_Z = 1.04*k                                    # wax-white faces this low are the book's pages, not candles
kinds = []
for p in me.polygons:
    kd = KIND.get(colour(p), "stone")
    if kd == "wax" and p.center.z < PAGE_Z: kd = "pages"
    kinds.append(kd)

# ---- materials
def marble(name, shade):                           # box-projected in object space (the veins run through the stone)
    m, b = mat(name, (1, 1, 1)); nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); mp = N("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (P["marble_scale"],)*3
    Lk(tc.outputs["Object"], mp.inputs["Vector"])
    def tex(kind, colour=True):
        t = N("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(HERE, "textures", "Marble012_2K-JPG_" + kind + ".jpg"))
        if not colour: t.image.colorspace_settings.name = "Non-Color"
        t.projection = 'BOX'; t.projection_blend = 0.25; Lk(mp.outputs["Vector"], t.inputs["Vector"])
        return t
    tint = N("ShaderNodeMix"); tint.data_type = 'RGBA'; tint.blend_type = 'MULTIPLY'; tint.inputs["Factor"].default_value = 1.0
    tint.inputs["B"].default_value = (*[c*shade for c in P["tint"]], 1)
    Lk(tex("Color").outputs["Color"], tint.inputs["A"]); Lk(tint.outputs["Result"], b.inputs["Base Color"])
    rr = N("ShaderNodeMapRange"); rr.inputs["To Min"].default_value = 0.35; rr.inputs["To Max"].default_value = 0.6
    Lk(tex("Roughness", False).outputs["Color"], rr.inputs["Value"]); Lk(rr.outputs["Result"], b.inputs["Roughness"])
    nm = N("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = 0.5
    Lk(tex("NormalGL", False).outputs["Color"], nm.inputs["Color"]); Lk(nm.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Specular IOR Level"].default_value = 0.3
    return m
pages, pb = mat("Pages", (0.95, 0.9, 0.78), Roughness=0.7)
if P["holy"]:
    pb.inputs["Emission Color"].default_value = (1.0, 0.7, 0.25, 1); pb.inputs["Emission Strength"].default_value = P["pages"]
    pages.cycles.emission_sampling = 'NONE'        # (not a light: it would haze the shadow catcher)
MATS = {"stone": marble("Marble", 1.0), "trim": marble("Trim", 0.82), "recess": marble("Recess", 0.6),
        "gold": mat("Gold", P["gold"], Metallic=1.0, Roughness=0.28)[0],
        "wax": mat("Wax", (0.95, 0.9, 0.8), Roughness=0.5, **{"Subsurface Weight": 0.5})[0],
        "wick": mat("Wick", (0.03, 0.025, 0.02), Roughness=0.9)[0],
        "cloth": mat("Cloth", P["cloth"], Roughness=0.85, **{"Sheen Weight": 0.6})[0], "pages": pages}
order = list(MATS); me.materials.clear()
for n in order: me.materials.append(MATS[n])
for p, kd in zip(me.polygons, kinds): p.material_index = order.index(kd); p.use_smooth = False
bv = altar.modifiers.new("Bevel", 'BEVEL'); bv.width = 0.012*k; bv.segments = 2; bv.limit_method = 'ANGLE'
bv.angle_limit = math.radians(40); bv.harden_normals = False
root = bpy.data.objects.new("Altar", None); sc.collection.objects.link(root); altar.parent = root

# ---- candle flames: one over each wick (the wick faces, grouped by side)
wicks = {}
for p, kd in zip(me.polygons, kinds):
    if kd == "wick": wicks.setdefault(p.center.x > 0, []).append(p.center.copy())
flame, fb = mat("Flame", (1, 0.6, 0.2))
fn = flame.node_tree; N = fn.nodes.new; Lk = fn.links.new
em = N("ShaderNodeEmission"); em.inputs["Strength"].default_value = P["flame"]
geo = N("ShaderNodeNewGeometry"); lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.6
ramp = N("ShaderNodeValToRGB")                     # white-yellow core, orange edge (seen edge-on)
ramp.color_ramp.elements[0].color = (1, 0.95, 0.75, 1); ramp.color_ramp.elements[1].color = (1, 0.45, 0.08, 1)
Lk(lw.outputs["Facing"], ramp.inputs["Fac"]); Lk(ramp.outputs["Color"], em.inputs["Color"])
fn.links.new(em.outputs[0], fn.nodes["Material Output"].inputs["Surface"])
flame.cycles.emission_sampling = 'NONE'
for side, pts in wicks.items():
    c = sum(pts, Vector())/len(pts); top = max(p.z for p in pts)
    bm = bmesh.new(); segs = 12; rings = []
    for r, z in ((0.0, 0.0), (0.022, 0.02), (0.03, 0.05), (0.022, 0.09), (0.008, 0.13), (0.0, 0.15)):
        rings.append([bm.verts.new((c.x + r*k*math.cos(math.tau*i/segs), c.y + r*k*math.sin(math.tau*i/segs), top + z*k))
                      for i in range(segs)])
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(segs): bm.faces.new((r0[i], r0[(i+1) % segs], r1[(i+1) % segs], r1[i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    fm = bpy.data.meshes.new("Flame"); bm.to_mesh(fm); bm.free()
    for f in fm.polygons: f.use_smooth = True
    fo = link(sc, "Flame", fm); fo.data.materials.append(flame); fo.parent = root; fo.visible_shadow = False
    l = bpy.data.lights.new("Candle", 'POINT'); l.energy = 25; l.color = (1, 0.7, 0.35); l.shadow_soft_size = 0.05
    l.use_shadow = False
    lo_ = link(sc, "Candle", l); lo_.location = (c.x, c.y - 0.05*k, top + 0.08*k); lo_.parent = root

# ---- holy: a faint shaft of golden light coming down on the book, see-through at its middle
if P["holy"]:
    top_z = P["height"]*1.45; bot_z = 1.0*k              # (from the altar's top up)
    bm = bmesh.new(); segs = 32; rings = []
    for r, z in ((0.5, bot_z), (0.3, top_z)):
        rings.append([bm.verts.new((r*k*math.cos(math.tau*i/segs), r*k*math.sin(math.tau*i/segs), z)) for i in range(segs)])
    for i in range(segs): bm.faces.new((rings[0][i], rings[0][(i+1) % segs], rings[1][(i+1) % segs], rings[1][i]))
    sm = bpy.data.meshes.new("Shaft"); bm.to_mesh(sm); bm.free()
    for f in sm.polygons: f.use_smooth = True
    m = bpy.data.materials.new("Shaft"); nt = m.node_tree; nt.nodes.clear(); N = nt.nodes.new; Lk = nt.links.new
    def math_(op, a, b):
        n = N("ShaderNodeMath"); n.operation = op
        for i, v in enumerate((a, b)):
            if isinstance(v, (int, float)): n.inputs[i].default_value = v
            else: Lk(v, n.inputs[i])
        return n.outputs[0]
    lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.5
    edge = math_('POWER', math_('SUBTRACT', 1.0, lw.outputs["Facing"]), 2.0)            # its sides, not its face
    tc = N("ShaderNodeTexCoord"); sep = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sep.inputs[0])
    h = math_('DIVIDE', math_('SUBTRACT', sep.outputs["Z"], bot_z), top_z - bot_z)       # 0 at the foot, 1 at the top
    fade = math_('MULTIPLY', math_('MINIMUM', math_('MULTIPLY', h, 8.0), 1.0), math_('POWER', math_('SUBTRACT', 1.0, h), 3.0))
    a = math_('MULTIPLY', math_('MULTIPLY', edge, fade), P["shaft"])
    e = N("ShaderNodeEmission"); e.inputs["Color"].default_value = (1, 0.85, 0.5, 1); e.inputs["Strength"].default_value = 2.0
    tr = N("ShaderNodeBsdfTransparent"); mx = N("ShaderNodeMixShader"); Lk(a, mx.inputs[0])
    Lk(tr.outputs[0], mx.inputs[1]); Lk(e.outputs[0], mx.inputs[2])
    out = N("ShaderNodeOutputMaterial"); Lk(mx.outputs[0], out.inputs["Surface"])
    m.cycles.emission_sampling = 'NONE'
    so_ = link(sc, "Shaft", sm); so_.data.materials.append(m); so_.parent = root
    so_.visible_shadow = False; so_.visible_diffuse = False; so_.visible_glossy = False
    pz = [p.center for p, kd in zip(me.polygons, kinds) if kd == "pages"]
    c = sum(pz, Vector())/len(pz)                    # a warm pool of light from the book over the altar's top
    l = bpy.data.lights.new("Book", 'POINT'); l.energy = 10; l.color = (1, 0.75, 0.35); l.shadow_soft_size = 0.3
    bo = link(sc, "Book", l); bo.location = (c.x, c.y, c.z + 0.4*k); bo.parent = root

# ---- ground: shadow catcher
gp = bmesh.new(); bmesh.ops.create_grid(gp, x_segments=1, y_segments=1, size=10)
gme = bpy.data.meshes.new("Ground"); gp.to_mesh(gme); gp.free()
ground = link(sc, "Ground", gme); ground.data.materials.append(mat("Matte", (0.5, 0.5, 0.5), Roughness=1.0, **{"Specular IOR Level": 0.0})[0]); ground.is_shadow_catcher = True   # (matte: a glossy catcher records reflections as a haze)

root.rotation_euler = (0, 0, math.radians(P["yaw"]))
rig(sc, elev=P["elev"])                             # camera angle above the horizon
studio_world(sc, 0.5)
spot(sc, (-3, -4, 4), 110, (1, 0.95, 0.85)); spot(sc, (3, -3, 3), 50, (1, 1, 1))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 4; sun.angle = math.radians(6)   # crisp ground shadow
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(30), 0, math.radians(-40))
# only the sun darkens the ground (as for the throne: the soft lights would leave a faint wide shadow the crop cuts)
for l in bpy.data.lights:
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False
sc.cycles.diffuse_bounces = 0
sc.cycles.transparent_max_bounces = 32
render(sc, OUT, P["save_blend"], samples=128)
